import shaka from 'shaka-player/dist/shaka-player.ui';

export function buildProxyURL(target: string | URL): string {
  const proxyURL = new URL('proxy', globalThis.location.href);
  proxyURL.searchParams.set('target', target.toString());
  return proxyURL.toString();
}

export async function fetchFunction(input: string | Request | URL, init?: RequestInit): Promise<Response> {
  const requestLike = typeof input === 'string' || input instanceof URL
    ? undefined
    : input;
  const url = input instanceof URL
    ? input
    : new URL(typeof input === 'string' ? input : input.url);
  const headers = new Headers(init?.headers ?? requestLike?.headers);

  if (url.pathname.includes('v1/player')) {
    url.searchParams.set('$fields', 'playerConfig,storyboards,captions,playabilityStatus,streamingData,responseContext.mainAppWebResponseContext.datasyncId,videoDetails.isLive,videoDetails.isLiveContent,videoDetails.title,videoDetails.author,videoDetails.thumbnail');
  }

  const body = init?.body ?? requestLike?.body;
  const method = (
    init?.method ??
    requestLike?.method ??
    (body == null ? 'GET' : 'POST')
  ).toUpperCase();
  const requestInit: RequestInit = {
    ...init,
    method,
    headers,
    credentials: 'same-origin'
  };
  if (method !== 'GET' && method !== 'HEAD' && body != null) {
    requestInit.body = body;
  } else {
    delete requestInit.body;
  }

  return fetch(buildProxyURL(url), requestInit);
}

export function asMap<K, V>(object: Record<string, V>): Map<K, V> {
  const map = new Map<K, V>();
  for (const key of Object.keys(object)) {
    map.set(key as K, object[key]);
  }
  return map;
}

export function createRecoverableError(message: string, info?: Record<string, any>) {
  return new shaka.util.Error(
    shaka.util.Error.Severity.RECOVERABLE,
    shaka.util.Error.Category.NETWORK,
    shaka.util.Error.Code.HTTP_ERROR,
    message,
    { info }
  );
}

export function headersToGenericObject(headers: Headers): Record<string, string> {
  const headersObj: Record<string, string> = {};
  headers.forEach((value, key) => {
    // Since Edge incorrectly returns the header with a leading new line
    // character ('\n'), we trim the header here.
    headersObj[key.trim()] = value;
  });
  return headersObj;
}

export function makeResponse(
  headers: Record<string, string>,
  data: BufferSource,
  status: number,
  uri: string,
  responseURL: string,
  request: shaka.extern.Request,
  requestType: shaka.net.NetworkingEngine.RequestType
): shaka.extern.Response & { originalRequest: shaka.extern.Request } {
  if (status >= 200 && status <= 299 && status !== 202) {
    return {
      uri: responseURL || uri,
      originalUri: uri,
      data,
      status,
      headers,
      originalRequest: request,
      fromCache: !!headers['x-shaka-from-cache']
    };
  }

  let responseText: string | null = null;
  try {
    responseText = shaka.util.StringUtils.fromBytesAutoDetect(data);
  } catch { /* no-op */ }

  const severity = status === 401 || status === 403
    ? shaka.util.Error.Severity.CRITICAL
    : shaka.util.Error.Severity.RECOVERABLE;

  throw new shaka.util.Error(
    severity,
    shaka.util.Error.Category.NETWORK,
    shaka.util.Error.Code.BAD_HTTP_STATUS,
    uri,
    status,
    responseText,
    headers,
    requestType,
    responseURL || uri
  );
}
