import shaka from 'shaka-player/dist/shaka-player.ui';

interface FourierEmbedConfig {
  proxyBase: string;
  videoId: string;
  diagnosticsEnabled?: boolean;
}

export function getEmbedConfig(): FourierEmbedConfig | undefined {
  return (globalThis as typeof globalThis & { __FOURIER_EMBED__?: FourierEmbedConfig })
    .__FOURIER_EMBED__;
}

interface TrustedTypesPolicyLike {
  createHTML(source: string): unknown;
  createScript(source: string): unknown;
}

let trustedTypesPolicy: TrustedTypesPolicyLike | null | undefined;

/**
 * 真实 embed 页面通过 CSP `require-trusted-types-for 'script'` 强制
 * Trusted Types。WebKit 允许在未声明 `trusted-types` 白名单时创建策略，
 * 这里懒创建一个直通策略，供 HTML/脚本 sink 包装字符串输入。
 */
export function getTrustedTypesPolicy(): TrustedTypesPolicyLike | null {
  if (trustedTypesPolicy !== undefined) return trustedTypesPolicy;
  trustedTypesPolicy = null;
  try {
    const trustedTypes = (
      globalThis as typeof globalThis & {
        trustedTypes?: { createPolicy(name: string, options: object): unknown };
      }
    ).trustedTypes;
    if (trustedTypes?.createPolicy) {
      trustedTypesPolicy = trustedTypes.createPolicy('fourier#runtime', {
        createHTML: (source: string) => source,
        createScript: (source: string) => source,
      }) as TrustedTypesPolicyLike;
    }
  } catch {
    // 页面 CSP 显式禁止创建任何策略时保持 null，由调用方走降级路径。
  }
  return trustedTypesPolicy;
}

export function trustedScriptSource(code: string): unknown {
  return getTrustedTypesPolicy()?.createScript(code) ?? code;
}

export function buildProxyURL(target: string | URL): string {
  const embedConfig = getEmbedConfig();
  if (embedConfig?.proxyBase) {
    const base = embedConfig.proxyBase.endsWith('/')
      ? embedConfig.proxyBase
      : `${embedConfig.proxyBase}/`;
    const proxyURL = new URL('proxy', base);
    proxyURL.searchParams.set('target', target.toString());
    return proxyURL.toString();
  }
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
