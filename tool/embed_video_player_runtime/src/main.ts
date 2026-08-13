import shaka from 'shaka-player/dist/shaka-player.ui.js';
import type { Types } from 'youtubei.js/web';
import { Constants, Innertube, Platform, UniversalCache, Utils, YT } from 'youtubei.js/web';
import { SabrStreamingAdapter } from 'googlevideo/sabr-streaming-adapter';
import { buildSabrFormat } from 'googlevideo/utils';
import { ShakaPlayerAdapter } from './ShakaPlayerAdapter.js';
import {
  buildProxyURL,
  fetchFunction,
  getEmbedConfig,
  getTrustedTypesPolicy,
  trustedScriptSource,
} from './helpers.js';
import { botguardService, type BotguardChallenge } from './BotguardService.js';
import { BilibiliDanmaku } from './bilibiliDanmaku.js';
import 'shaka-player/dist/controls.css';
import './player.css';

let videoElement: HTMLVideoElement;
let videoContainer: HTMLDivElement;

let player: shaka.Player;
let sabrAdapter: SabrStreamingAdapter;
let playerAdapter: ShakaPlayerAdapter;
let innertube: Innertube;
let playbackPlayerPoTokenContentBinding: string | undefined;
let playbackPlayerPoTokenCreationPromise: Promise<void> | undefined;
let playbackPlayerPoToken: string | undefined;
let playbackGvsPoTokenContentBinding: string | undefined;
let playbackGvsPoTokenCreationPromise: Promise<void> | undefined;
let playbackGvsPoToken: string | undefined;
let coldStartToken: string | undefined;
let bilibiliDanmaku: BilibiliDanmaku | undefined;

const youtubeEmbedderUrl = 'https://github.com/X-Ray-git/Fourier/';

/**
 * 本地页面（Bilibili）由 index.html 提供 #video / #video-container。
 * 真实 YouTube embed 页面由注入的运行时自行构建播放表面，并接管页面 DOM。
 */
function ensurePlayerDom() {
  const existingVideo = document.getElementById('video') as HTMLVideoElement | null;
  const existingContainer = document.getElementById('video-container') as HTMLDivElement | null;
  if (existingVideo && existingContainer) {
    videoElement = existingVideo;
    videoContainer = existingContainer;
    return;
  }

  const host = document.createElement('div');
  host.id = 'fourier-player-host';
  host.style.cssText =
    'position:fixed;inset:0;width:100%;height:100%;background:#000;z-index:2147483647;';
  videoContainer = document.createElement('div');
  videoContainer.id = 'video-container';
  videoContainer.style.cssText =
    'position:relative;width:100%;height:100%;margin:0;padding:0;overflow:hidden;background:#000;';
  videoElement = document.createElement('video');
  videoElement.id = 'video';
  videoElement.setAttribute('autoplay', '');
  videoElement.setAttribute('playsinline', '');
  videoElement.style.cssText = 'width:100%;height:100%;object-fit:contain;';
  videoContainer.appendChild(videoElement);
  host.appendChild(videoContainer);
  document.body.appendChild(host);
}

function takeoverEmbedPageDom() {
  ensurePlayerDom();
  const style = document.createElement('style');
  style.id = 'fourier-embed-takeover';
  style.textContent = `
    html, body {
      width: 100% !important; height: 100% !important;
      margin: 0 !important; padding: 0 !important;
      overflow: hidden !important; background: #000 !important;
    }
    body > :not(#fourier-player-host):not(#fourier-embed-takeover) {
      display: none !important;
    }
  `;
  document.head.appendChild(style);

  const neutralize = () => {
    document.querySelectorAll('video').forEach((videoElement) => {
      if (videoElement.closest('#fourier-player-host')) return;
      try {
        videoElement.pause();
        videoElement.removeAttribute('src');
      } catch {
        // 官方播放器元素可能尚未初始化
      }
      videoElement.style.display = 'none';
    });
  };
  neutralize();
  new MutationObserver(neutralize).observe(document.body, {
    childList: true,
    subtree: true,
  });
}

function notify(
  type: 'ready' | 'playing' | 'error' | 'scroll' | 'activated' | 'togglePlayback',
  detail?: string | number
) {
  const channel = (globalThis as typeof globalThis & {
    FourierVideoPlayer?: { postMessage(message: string): void }
  }).FourierVideoPlayer;
  channel?.postMessage(JSON.stringify({ type, detail }));
}

function describePlayerError(error: any) {
  const message = error?.message || String(error);
  const reason = Array.isArray(error?.data) && typeof error.data[0] === 'string'
    ? error.data[0]
    : undefined;
  if (reason && !/^https?:/i.test(reason)) {
    return `${message}: ${reason}`;
  }
  const cause = Array.isArray(error?.data) ? error.data[1] : undefined;
  const causeMessage = cause instanceof Error
    ? cause.message
    : typeof cause === 'string'
      ? cause
      : undefined;
  return causeMessage ? `${message}: ${causeMessage}` : message;
}

let pendingArticleScroll = 0;
let articleScrollFrame: number | undefined;

function isPlayerMenuTarget(target: EventTarget | null) {
  return target instanceof Element &&
    target.closest('.shaka-overflow-menu, .shaka-settings-menu') !== null;
}

function bridgeArticleScroll(event: WheelEvent) {
  if (isPlayerMenuTarget(event.target)) return;

  const scale = event.deltaMode === WheelEvent.DOM_DELTA_LINE
    ? 16
    : event.deltaMode === WheelEvent.DOM_DELTA_PAGE
      ? globalThis.innerHeight
      : 1;
  pendingArticleScroll += event.deltaY * scale;
  event.preventDefault();

  if (articleScrollFrame !== undefined) return;
  articleScrollFrame = requestAnimationFrame(() => {
    const delta = pendingArticleScroll;
    pendingArticleScroll = 0;
    articleScrollFrame = undefined;
    if (delta !== 0) notify('scroll', delta);
  });
}

function handlePlaybackShortcut(event: KeyboardEvent) {
  if (
    event.code !== 'Space' ||
    event.repeat ||
    event.metaKey ||
    event.ctrlKey ||
    event.altKey
  ) {
    return;
  }
  const target = event.target instanceof Element ? event.target : null;
  if (
    target?.closest(
      'button, input, select, textarea, [contenteditable="true"]'
    )
  ) {
    return;
  }

  event.preventDefault();
  event.stopImmediatePropagation();
  notify('togglePlayback');
}

function togglePlayPause() {
  if (videoElement.paused) {
    if (
      Number.isFinite(videoElement.duration) &&
      videoElement.duration > 0 &&
      videoElement.currentTime >= videoElement.duration
    ) {
      videoElement.currentTime = 0;
    }
    videoElement.play().catch((error) => {
      console.warn('[Player]', 'Playback toggle failed:', error);
    });
    return;
  }
  videoElement.pause();
}

Platform.shim.eval = async (data: Types.BuildScriptResult, env: Record<string, Types.VMPrimative>) => {
  const properties = [];

  if (env.n) {
    properties.push(`n: exportedVars.nFunction("${env.n}")`);
  }

  if (env.sig) {
    properties.push(`sig: exportedVars.sigFunction("${env.sig}")`);
  }

  const code = `${data.output}\nreturn { ${properties.join(', ')} }`;

  return new Function(trustedScriptSource(code) as string)();
};

/**
 * 真实 embed 页面启用了 Trusted Types（CSP `require-trusted-types-for
 * 'script'`），字符串形式的 HTML 插入与 eval 都会被原生 sink 拒绝。Shaka
 * UI 使用 `insertAdjacentHTML`/`innerHTML` 注入静态模板；优先用直通策略把
 * 字符串包装为 TrustedHTML 走原生 sink，策略不可用时退回「blob URL + 同步
 * XHR 文档解析 + 节点搬移」路径。宿主页面自身的 TrustedHTML 值始终走原生
 * 路径，不受影响。
 */
function installTrustedTypesShim() {
  const policy = getTrustedTypesPolicy();
  const nativeInsertAdjacentHTML = Element.prototype.insertAdjacentHTML;

  const parseFragment = (html: string): DocumentFragment => {
    // Trusted Types 页面上所有 HTML sink（innerHTML / insertAdjacentHTML /
    // DOMParser / createContextualFragment / createHTMLDocument）都被强制，
    // 且无策略可用。唯一未被强制的是通过 blob URL + 同步 XHR
    // responseType=document 走网络解析器得到的文档。
    const blob = new Blob([html], { type: 'text/html' });
    const url = URL.createObjectURL(blob);
    try {
      const xhr = new XMLHttpRequest();
      xhr.open('GET', url, false);
      xhr.responseType = 'document';
      xhr.send();
      const doc = xhr.responseXML;
      if (!doc?.body) {
        throw new Error('XHR document parse failed');
      }
      const fragment = doc.createDocumentFragment();
      while (doc.body.firstChild) fragment.appendChild(doc.body.firstChild);
      return fragment;
    } finally {
      URL.revokeObjectURL(url);
    }
  };

  (Element.prototype as unknown as {
    insertAdjacentHTML: (position: string, html: unknown) => void;
  }).insertAdjacentHTML = function (
    this: Element,
    position: string,
    html: unknown,
  ) {
    const insertPosition = position as InsertPosition;
    if (typeof html === 'string' && policy) {
      nativeInsertAdjacentHTML.call(
        this,
        insertPosition,
        policy.createHTML(html) as string,
      );
      return;
    }
    try {
      nativeInsertAdjacentHTML.call(this, insertPosition, html as string);
      return;
    } catch (error) {
      if (
        typeof html !== 'string' ||
        !(error instanceof TypeError) ||
        !/TrustedHTML/.test(error.message)
      ) {
        throw error;
      }
    }
    const nodes = parseFragment(html);
    switch (position) {
      case 'beforebegin':
        this.parentNode?.insertBefore(nodes, this);
        return;
      case 'afterbegin':
        this.insertBefore(nodes, this.firstChild);
        return;
      case 'beforeend':
        this.appendChild(nodes);
        return;
      case 'afterend':
        this.parentNode?.insertBefore(nodes, this.nextSibling);
        return;
      default:
        nativeInsertAdjacentHTML.call(this, insertPosition, html);
    }
  };

  for (const target of [
    Element.prototype,
    typeof SVGElement !== 'undefined' ? SVGElement.prototype : undefined,
    typeof ShadowRoot !== 'undefined' ? ShadowRoot.prototype : undefined,
  ].filter((entry): entry is Element => entry != null)) {
    for (const property of ['innerHTML', 'outerHTML'] as const) {
      const descriptor = Object.getOwnPropertyDescriptor(target, property);
      if (!descriptor?.set) continue;
      Object.defineProperty(target, property, {
        configurable: true,
        enumerable: descriptor.enumerable,
        get: descriptor.get,
        set(this: Element, value: unknown) {
          if (typeof value === 'string' && policy) {
            descriptor.set!.call(this, policy.createHTML(value));
            return;
          }
          try {
            descriptor.set!.call(this, value);
            return;
          } catch (error) {
            if (
              typeof value !== 'string' ||
              !(error instanceof TypeError) ||
              !/TrustedHTML/.test(error.message)
            ) {
              throw error;
            }
          }
          const element = this;
          while (element.firstChild) element.removeChild(element.firstChild);
          element.appendChild(parseFragment(value));
        },
      });
    }
  }
}

async function main(provider: string) {
  installTrustedTypesShim();
  shaka.polyfill.installAll();
  console.log('[Main]', 'Shaka polyfills installed');

  if (!shaka.Player.isBrowserSupported())
    throw new Error('Shaka Player is not supported on this browser.');
  console.log('[Main]', 'Browser support confirmed');

  if (provider === 'youtube') {
    innertube = await Innertube.create({
      cache: new UniversalCache(true),
      fetch: fetchFunction,
      // Keep the Innertube context aligned with the browser environment used
      // to execute BotGuard. The native proxy forwards this same user agent.
      user_agent: navigator.userAgent,
      generate_session_locally: true
    });

    const embedConfig = getEmbedConfig();
    if (embedConfig) {
      await prepareYouTubeEmbedPage(embedConfig);
    } else {
      botguardService.configureChallengeLoader(async () => {
        const response = await innertube.actions.execute('/att/get', {
          engagementType: 'ENGAGEMENT_TYPE_UNBOUND'
        });
        const challenge = response.data.bgChallenge;
        if (!challenge) throw new Error('Innertube attestation response has no BotGuard challenge.');
        return challenge;
      });
    }

    console.log('[Main] Innertube initialized');
  }

  // Now init the player.
  player = new shaka.Player();
  console.log('[Main]', 'Shaka Player instance created');
  player.configure({
    abr: { enabled: true },
    streaming: {
      bufferingGoal: 120,
      rebufferingGoal: 2
    }
  });

  console.log('[Main]', 'Attaching media element');
  await player.attach(videoElement, false);
  console.log('[Main]', 'Media element attached');

  console.log('[Main]', 'Creating UI overlay');
  const ui = new shaka.ui.Overlay(player, videoContainer, videoElement);
  console.log('[Main]', 'UI overlay created');

  ui.configure({
    addBigPlayButton: false,
    addSeekBar: true,
    controlPanelElements: [
      'play_pause',
      'time_and_duration',
      'spacer',
      'mute',
      'volume',
      'overflow_menu',
      'fullscreen'
    ],
    overflowMenuButtons: [
      'captions',
      'quality',
      'language',
      'playback_rate'
    ],
    customContextMenu: false,
    doubleClickForFullscreen: false,
    enableKeyboardPlaybackControls: true,
    fadeDelay: 3,
    singleClickForPlayAndPause: false,
    seekBarColors: {
      base: 'rgba(255, 255, 255, 0.15)',
      buffered: 'rgba(255, 255, 255, 0.30)',
      played: '#FF5C00',
      adBreaks: '#FF5C00'
    },
    volumeBarColors: {
      base: 'rgba(255, 255, 255, 0.30)',
      level: '#FF5C00'
    }
  });

  document.addEventListener('wheel', bridgeArticleScroll, {
    capture: true,
    passive: false
  });
  document.addEventListener('pointerdown', () => notify('activated'), {
    capture: true
  });
  window.addEventListener('keydown', handlePlaybackShortcut, {
    capture: true
  });
  (globalThis as typeof globalThis & {
    FourierVideoControls?: { togglePlayPause(): void }
  }).FourierVideoControls = { togglePlayPause };

  console.log('[Main] Shaka Player initialized');
  notify('ready');
}

interface BilibiliSubtitle {
  url: string;
  language: string;
  label: string;
}

interface BilibiliBootstrap {
  danmakuBaseUrl?: string;
  manifestUrl: string;
  title: string;
  subtitles: BilibiliSubtitle[];
}

async function loadBilibili(session: string) {
  if (!session) throw new Error('Missing Bilibili playback session.');

  console.log('[Bilibili]', 'Requesting playback bootstrap');
  const bootstrapUrl = new URL(
    `./bilibili/bootstrap/${encodeURIComponent(session)}`,
    globalThis.location.href
  );
  const response = await fetch(bootstrapUrl);
  if (!response.ok) {
    throw new Error(`Bilibili bootstrap failed with HTTP ${response.status}`);
  }
  const bootstrap = await response.json() as BilibiliBootstrap;
  if (!bootstrap.manifestUrl) {
    throw new Error('Bilibili bootstrap has no DASH manifest.');
  }
  if (bootstrap.danmakuBaseUrl) {
    bilibiliDanmaku?.dispose();
    bilibiliDanmaku = new BilibiliDanmaku(
      videoElement,
      videoContainer,
      bootstrap.danmakuBaseUrl
    );
  }

  console.log('[Bilibili]', 'Loading DASH manifest');
  await player.load(bootstrap.manifestUrl);
  for (const subtitle of bootstrap.subtitles ?? []) {
    try {
      await player.addTextTrackAsync(
        subtitle.url,
        subtitle.language || 'und',
        'subtitles',
        'text/vtt',
        undefined,
        subtitle.label || subtitle.language || '字幕'
      );
    } catch (error) {
      console.warn(
        '[Bilibili]',
        `Skipping subtitle ${subtitle.label}:`,
        describePlayerError(error)
      );
    }
  }
  await videoElement.play();
  notify('playing', bootstrap.title || 'Bilibili');
  console.log('[Bilibili]', `Now playing: ${bootstrap.title || 'Bilibili'}`);
}

async function loadVideo(videoId: string) {
  if (!videoId) {
    alert('Please enter a video ID.');
    return;
  }

  playbackPlayerPoToken = undefined;
  playbackPlayerPoTokenContentBinding = videoId;
  coldStartToken = undefined;

  console.log('[Player]', `Loading video: ${videoId}`);

  try {
    if (sabrAdapter) {
      console.log('[Player]', 'Unloading previous content');
      await player.unload();
      console.log('[Player]', 'Previous content unloaded');
      sabrAdapter.dispose();
    }

    console.log('[Player]', 'Requesting video info');
    const videoInfo = await innertube.getInfo(videoId);
    console.log('[Player]', 'Video info received');
    const cpn = Utils.generateRandomString(16);

    if (videoInfo.playability_status?.status !== 'OK') {
      throw new Error(`Cannot play video: ${videoInfo.playability_status?.reason}`);
    }
    console.log('[Player]', 'Video is playable');

    const isLive = videoInfo.basic_info.is_live;
    const isPostLiveDVR = !!videoInfo.basic_info.is_post_live_dvr ||
      (videoInfo.basic_info.is_live_content && !!(videoInfo.streaming_data?.dash_manifest_url || videoInfo.streaming_data?.hls_manifest_url));

    // 播放主路径：WEB_EMBEDDED 直连、SABR、MWEB 普通 DASH；
    // 直播 / PostLiveDVR 走官方 manifest 直连，不进入回退链。
    let playbackSource: string;
    if (videoInfo.streaming_data && !isPostLiveDVR && !isLive) {
      playbackSource = await playVodWithSabrFallback(videoId, videoInfo, cpn);
    } else if (videoInfo.streaming_data) {
      const manifestUri = isLive
        ? videoInfo.streaming_data.dash_manifest_url ? `${videoInfo.streaming_data.dash_manifest_url}/mpd_version/7` : videoInfo.streaming_data.hls_manifest_url
        : videoInfo.streaming_data.hls_manifest_url || `${videoInfo.streaming_data.dash_manifest_url}/mpd_version/7`;
      if (!manifestUri)
        throw new Error('Could not find a valid manifest URI.');
      playbackSource = 'official-manifest';
      await player.load(manifestUri);
    } else {
      throw new Error('Could not find a valid manifest URI.');
    }

    await videoElement.play();
    notify('playing', videoInfo.basic_info.title);
    console.log('[Player]', `Now playing: ${videoInfo.basic_info.title} (${playbackSource})`);
  } catch (e: any) {
    const detail = describePlayerError(e);
    console.error('[Player]', 'Error:', detail, e?.stack || '');
    notify('error', detail);
  }
}

/**
 * VOD 首先使用无需 PO token 的 WEB_EMBEDDED 普通 DASH。它只覆盖允许
 * 嵌入的视频，但这正是文章内嵌视频的主要场景。失败后再尝试 SABR，
 * 最后仅在成功生成正式 GVS token 时使用 MWEB。不得把 GenerateIT 的
 * fallback token 当作正式 token，否则媒体服务器会在试用流量耗尽后返回 403。
 */
async function playVodWithSabrFallback(videoId: string, videoInfo: Awaited<ReturnType<typeof innertube.getInfo>>, cpn: string): Promise<string> {
  try {
    const embeddedManifest = await buildDirectDashForClient(videoId, 'WEB_EMBEDDED');
    console.log('[Player] Loading WEB_EMBEDDED direct adaptive DASH manifest');
    await player.load(embeddedManifest);
    console.log('[Player] WEB_EMBEDDED direct adaptive DASH manifest loaded');
    return 'WEB_EMBEDDED';
  } catch (embeddedError) {
    console.warn(
      '[Player]',
      'WEB_EMBEDDED direct playback failed; trying SABR:',
      describePlayerError(embeddedError)
    );
  }

  try {
    const sabrManifest = await setupSabrFlow(videoId, videoInfo, cpn);
    console.log('[Player]', 'Loading SABR DASH manifest');
    await player.load(sabrManifest);
    console.log('[Player]', 'SABR DASH manifest loaded');
    return 'sabr';
  } catch (sabrError) {
    console.warn(
      '[Player]',
      'SABR failed; falling back to MWEB:',
      describePlayerError(sabrError)
    );
    await teardownSabrFlow();
  }

  const directManifest = await buildDirectDashForClient(videoId, 'MWEB');
  console.log('[Player] Loading MWEB direct adaptive DASH manifest');
  await player.load(directManifest);
  console.log('[Player] MWEB direct adaptive DASH manifest loaded');
  return 'MWEB';
}

async function teardownSabrFlow() {
  try {
    await player.unload();
  } catch (_) {
    // SABR 设置阶段失败时可能尚无内容可卸载。
  }
  try {
    playerAdapter?.disableSabrInterceptors();
  } catch (_) {
    // 拦截器可能尚未安装。
  }
  // Do not dispose the SABR adapter here. Its Shaka adapter owns the custom
  // HTTP(S) scheme handler that the direct DASH fallback still needs. The
  // adapter is disposed before a later video load, or with this WebView.
}

/**
 * 用指定 client 重新获取视频信息并生成 is_sabr=false 的普通 DASH。
 * WEB 响应可能只含 SABR 信息（没有直接 URL），因此绝不复用该响应
 * 生成 direct DASH。
 */
async function buildDirectDashForClient(
  videoId: string,
  client: 'WEB_EMBEDDED' | 'MWEB'
): Promise<string> {
  console.log('[Player]', `Requesting video info with ${client} client`);
  let info: Awaited<ReturnType<typeof innertube.getInfo>>;
  if (client === 'MWEB') {
    await mintPlayerWebPO();
    await mintGvsWebPO();
    if (!playbackGvsPoToken) {
      throw new Error('MWEB GVS token is unavailable.');
    }
    if (innertube.session.player) {
      innertube.session.player.po_token = playbackGvsPoToken;
    }
    info = await innertube.getInfo(videoId, {
      client,
      po_token: playbackPlayerPoToken
    });
  } else {
    info = await getEmbeddedVideoInfo(videoId);
  }
  console.log('[Player]', `${client} video info received`);
  if (info.playability_status?.status !== 'OK') {
    throw new Error(`Cannot play video: ${info.playability_status?.reason}`);
  }
  if (!info.streaming_data) {
    throw new Error(`Cannot play video: ${client} response has no streaming data`);
  }
  // Some clients return caption paths relative to youtube.com. youtubei.js
  // constructs URL objects before invoking url_transformer, so normalize them
  // here instead of allowing one caption track to abort the whole manifest.
  for (const track of info.captions?.caption_tracks ?? []) {
    if (track.base_url.startsWith('/')) {
      track.base_url = new URL(track.base_url, 'https://www.youtube.com').toString();
    }
  }
  const dash = await info.toDash({
    // The page CSP only permits same-origin media. It also lets the native
    // proxy consistently apply the allowlist and request handling used by the
    // SABR path.
    url_transformer: (url) => new URL(buildProxyURL(url)),
    manifest_options: {
      is_sabr: false,
      captions_format: 'vtt',
      include_thumbnails: false
    }
  });
  return `data:application/dash+xml;base64,${btoa(dash)}`;
}

async function getEmbeddedVideoInfo(videoId: string) {
  const pageUrl = new URL(
    `/embed/${encodeURIComponent(videoId)}?html5=1&playsinline=1`,
    'https://www.youtube-nocookie.com'
  );
  const pageResponse = await fetchFunction(pageUrl);
  if (!pageResponse.ok) {
    throw new Error(`YouTube embed config request failed with HTTP ${pageResponse.status}`);
  }

  const config = parseYtcfg(await pageResponse.text());
  const rawContext = config.INNERTUBE_CONTEXT;
  if (!isRecord(rawContext) || !isRecord(rawContext.client)) {
    throw new Error('YouTube embed page has no Innertube context.');
  }

  const context = structuredClone(rawContext) as typeof innertube.session.context;
  const visitorData = typeof config.VISITOR_DATA === 'string'
    ? config.VISITOR_DATA
    : context.client.visitorData;
  if (visitorData) context.client.visitorData = visitorData;
  context.thirdParty = {
    ...(isRecord(context.thirdParty) ? context.thirdParty : {}),
    embedUrl: youtubeEmbedderUrl
  };

  // Player.decipher() reads this constant when appending cver to media URLs.
  // Keep it aligned with the dynamic embed page instead of youtubei.js's
  // potentially stale bundled value.
  const mutableConstants = Constants as unknown as {
    CLIENTS: { WEB_EMBEDDED: { VERSION: string } };
  };
  mutableConstants.CLIENTS.WEB_EMBEDDED.VERSION = context.client.clientVersion;

  console.info(
    '[Player]',
    `WEB_EMBEDDED dynamic context loaded (version=${context.client.clientVersion})`
  );

  const previousContext = innertube.session.context;
  innertube.session.context = context;
  try {
    // Omitting the client override is intentional: youtubei.js would replace
    // the page's encrypted embeddedPlayerContext with a static context.
    return await innertube.getInfo(videoId);
  } finally {
    innertube.session.context = previousContext;
  }
}

function parseYtcfg(html: string): Record<string, unknown> {
  const marker = 'ytcfg.set(';
  const merged: Record<string, unknown> = {};
  let searchFrom = 0;
  let found = false;

  while (true) {
    const markerIndex = html.indexOf(marker, searchFrom);
    if (markerIndex < 0) break;
    const jsonStart = markerIndex + marker.length;
    const jsonEnd = findJsonObjectEnd(html, jsonStart);
    if (jsonEnd < 0) break;
    searchFrom = jsonEnd;
    try {
      const value = JSON.parse(html.slice(jsonStart, jsonEnd));
      if (isRecord(value)) {
        Object.assign(merged, value);
        found = true;
      }
    } catch (_) {
      // A later ytcfg.set call may still contain the required context.
    }
  }

  if (!found) throw new Error('YouTube embed page has no readable ytcfg.');
  return merged;
}

function findJsonObjectEnd(source: string, start: number): number {
  let depth = 0;
  let inString = false;
  let escaped = false;

  for (let index = start; index < source.length; index++) {
    const char = source[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === '\\') {
        escaped = true;
      } else if (char === '"') {
        inString = false;
      }
      continue;
    }
    if (char === '"') {
      inString = true;
    } else if (char === '{') {
      depth++;
    } else if (char === '}' && --depth === 0) {
      return index + 1;
    }
  }
  return -1;
}

function isRecord(value: unknown): value is Record<string, any> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

/**
 * 真实 embed 页模式：接管页面 DOM，并通过 loopback 代理重新抓取 embed
 * 页面 HTML，从中提取 ytcfg（真实 visitor data）与 ytAtN(R/T) 认证数据。
 * BotGuard 必须运行在真实 YouTube 页面环境里，GenerateIT 才会签发真正的
 * integrity token；本地 127.0.0.1 裸页只会拿到 websafe fallback token。
 */
async function prepareYouTubeEmbedPage(config: { proxyBase: string; videoId: string }) {
  takeoverEmbedPageDom();

  const pageUrl = new URL(
    `/embed/${encodeURIComponent(config.videoId)}?html5=1&playsinline=1`,
    'https://www.youtube-nocookie.com'
  );
  const pageResponse = await fetchFunction(pageUrl);
  if (!pageResponse.ok) {
    throw new Error(`YouTube embed page request failed with HTTP ${pageResponse.status}`);
  }
  const pageHtml = await pageResponse.text();
  const pageConfig = parseYtcfg(pageHtml);

  let attestationData: { R?: Record<string, unknown>; T?: string } = {};
  try {
    attestationData = extractYtAtN(pageHtml);
  } catch (error) {
    console.warn('[Player]', 'Embed page has no readable ytAtN; using att/get fallback:', error);
  }

  // BotGuard reads EVENT_ID from yt.config_ (bgutils/FreeTube recipe).
  (globalThis as typeof globalThis & { yt?: unknown }).yt = { config_: pageConfig };
  console.info('[Player]', 'Embed page context and attestation data loaded');

  botguardService.configureChallengeLoader(async () => {
    if (attestationData.R?.bgChallenge) {
      console.info('[Player]', 'BotGuard challenge from embed page ytAtN');
      return attestationData.R.bgChallenge as BotguardChallenge;
    }
    // FreeTube-style fallback: att/get with eacrToken.
    const payload: Record<string, unknown> = {
      engagementType: 'ENGAGEMENT_TYPE_UNBOUND',
    };
    if (attestationData.T) payload['eacrToken'] = attestationData.T;
    const response = await innertube.actions.execute('/att/get', payload);
    const challenge = response.data.bgChallenge;
    if (!challenge) throw new Error('Innertube attestation response has no BotGuard challenge.');
    console.info('[Player]', 'BotGuard challenge from att/get fallback');
    return challenge;
  });
}

// Port of bgutils-js v4 parseLooseJSON (MIT, see THIRD_PARTY_NOTICES.md).
function parseLooseJSON(looseJson: string): Record<string, any> {
  let jsonStr = looseJson.replace(/,\s*([\]}])/g, '$1');
  jsonStr = jsonStr.replace(/'((?:[^'\\]|\\[\s\S])*)'/g, (_match, innerStr: string) => {
    const unescaped = innerStr.replace(/\\'/g, "'");
    return JSON.stringify(unescaped);
  });
  jsonStr = jsonStr.replace(/([{,]\s*)([a-zA-Z0-9_$]+)\s*:/g, '$1"$2":');
  const parsedData = JSON.parse(jsonStr);

  const decodeHexEscapes = (value: string): string =>
    value.replace(/\\x([0-9A-Fa-f]{2})/g, (_match, hex: string) =>
      String.fromCharCode(parseInt(hex, 16)));

  const normalizeValue = (value: any): any => {
    if (typeof value === 'string') {
      const decodedValue = decodeHexEscapes(value);
      const trimmed = decodedValue.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return normalizeValue(JSON.parse(decodedValue));
        } catch {
          return decodedValue;
        }
      }
      return decodedValue;
    }
    if (Array.isArray(value)) return value.map(normalizeValue);
    if (value && typeof value === 'object') {
      for (const key in value) value[key] = normalizeValue(value[key]);
    }
    return value;
  };
  return normalizeValue(parsedData);
}

function extractYtAtN(html: string): { R?: Record<string, unknown>; T?: string } {
  const match = html.match(/window\.ytAtN\(\s*({[\s\S]*?})\s*\)/);
  if (!match) throw new Error('Embed page has no ytAtN attestation data.');
  const parsed = parseLooseJSON(match[1]);
  return {
    R: parsed.R as Record<string, unknown> | undefined,
    T: typeof parsed.T === 'string' ? parsed.T : undefined,
  };
}

/**
 * SABR 设置与 DASH manifest 构建（VOD）。任何一步失败都会抛出，
 * 由调用方进入 MWEB 回退。
 */
async function setupSabrFlow(videoId: string, videoInfo: Awaited<ReturnType<typeof innertube.getInfo>>, cpn: string): Promise<string> {
  console.log('[SABR]', 'Creating adapter');
  playerAdapter = new ShakaPlayerAdapter();
  sabrAdapter = new SabrStreamingAdapter({
    playerAdapter,
    clientInfo: {
      osName: innertube.session.context.client.osName,
      osVersion: innertube.session.context.client.osVersion,
      clientName: parseInt(Constants.CLIENT_NAME_IDS[innertube.session.context.client.clientName as keyof typeof Constants.CLIENT_NAME_IDS]),
      clientVersion: innertube.session.context.client.clientVersion
    }
  });
  console.log('[SABR]', 'Adapter created');

  sabrAdapter.onMintPoToken(async () => {
    if (!playbackPlayerPoToken) {
      // For VODs we can mint the token in the background to avoid delaying playback,
      // as it's not immediately required. While BotGuard is pretty darn fast, it
      // still makes a difference in user experience (from my own testing).
      mintPlayerWebPO().then();
    }
    return playbackPlayerPoToken || coldStartToken || '';
  });

  sabrAdapter.onReloadPlayerResponse(async (reloadContext) => {
    console.log('[SABR]', 'Reloading player response...');

    const reloadedInfo = await innertube.actions.execute('/player', {
      videoId,
      contentCheckOk: true,
      racyCheckOk: true,
      playbackContext: {
        adPlaybackContext: {
          pyv: true
        },
        contentPlaybackContext: {
          signatureTimestamp: innertube.session.player?.signature_timestamp
        },
        reloadPlaybackContext: reloadContext
      }
    });

    const parsedInfo = new YT.VideoInfo([ reloadedInfo ], innertube.actions, cpn);
    sabrAdapter.setStreamingURL(await innertube.session.player!.decipher(parsedInfo.streaming_data?.server_abr_streaming_url));
    sabrAdapter.setUstreamerConfig(videoInfo.player_config?.media_common_config.media_ustreamer_request_config?.video_playback_ustreamer_config);
  });

  console.log('[SABR]', 'Attaching adapter');
  sabrAdapter.attach(player);
  console.log('[SABR]', 'Adapter attached');

  console.log('[SABR]', 'Deciphering streaming URL');
  sabrAdapter.setStreamingURL(await innertube.session.player!.decipher(videoInfo.streaming_data?.server_abr_streaming_url));
  console.log('[SABR]', 'Streaming URL configured');
  sabrAdapter.setUstreamerConfig(videoInfo.player_config?.media_common_config.media_ustreamer_request_config?.video_playback_ustreamer_config);
  sabrAdapter.setServerAbrFormats(videoInfo.streaming_data!.adaptive_formats.map(buildSabrFormat));
  console.log('[SABR]', 'Formats configured');

  console.log('[SABR]', 'Building DASH manifest');
  const manifestUri = `data:application/dash+xml;base64,${btoa(await videoInfo.toDash({
    manifest_options: {
      is_sabr: true,
      captions_format: 'vtt',
      include_thumbnails: false
    }
  }))}`;
  console.log('[SABR]', 'DASH manifest built');
  return manifestUri;
}

function mintPlayerWebPO(): Promise<void> {
  if (!playbackPlayerPoTokenContentBinding || playbackPlayerPoToken) {
    return Promise.resolve();
  }
  if (playbackPlayerPoTokenCreationPromise) {
    return playbackPlayerPoTokenCreationPromise;
  }

  const contentBinding = playbackPlayerPoTokenContentBinding;
  playbackPlayerPoTokenCreationPromise = (async () => {
    try {
      coldStartToken = botguardService.mintColdStartToken(contentBinding);
      console.info('[Player]', 'Cold start Player token created');

      playbackPlayerPoToken = await mintWebPoToken(contentBinding);
      if (playbackPlayerPoToken) console.info('[Player]', 'Player WebPO token created');
    } catch (err) {
      console.error(
        '[Player]',
        `Error minting Player WebPO token: ${describePlayerError(err)}`
      );
    }
  })().finally(() => {
    playbackPlayerPoTokenCreationPromise = undefined;
  });
  return playbackPlayerPoTokenCreationPromise;
}

function mintGvsWebPO(): Promise<void> {
  const contentBinding = getGvsContentBinding();
  if (!contentBinding) return Promise.resolve();

  if (playbackGvsPoTokenContentBinding !== contentBinding) {
    playbackGvsPoTokenContentBinding = contentBinding;
    playbackGvsPoToken = undefined;
  }
  if (playbackGvsPoToken) return Promise.resolve();
  if (playbackGvsPoTokenCreationPromise) {
    return playbackGvsPoTokenCreationPromise;
  }

  playbackGvsPoTokenCreationPromise = (async () => {
    try {
      playbackGvsPoToken = await mintWebPoToken(contentBinding);
      if (playbackGvsPoToken) console.info('[Player]', 'GVS WebPO token created');
    } catch (err) {
      console.error(
        '[Player]',
        `Error minting GVS WebPO token: ${describePlayerError(err)}`
      );
    }
  })().finally(() => {
    playbackGvsPoTokenCreationPromise = undefined;
  });
  return playbackGvsPoTokenCreationPromise;
}

function getGvsContentBinding(): string | undefined {
  const videoId = playbackPlayerPoTokenContentBinding;
  if (!videoId) {
    console.warn('[Player]', 'Cannot mint GVS WebPO token without a video ID');
    return undefined;
  }
  // Current web/MWEB enforcement binds both Player and GVS PO tokens to the
  // video ID. Keep the two token slots separate because YouTube still treats
  // them as different request contexts and may diverge their rules again.
  return videoId;
}

async function mintWebPoToken(contentBinding: string): Promise<string | undefined> {
  if (!botguardService.isInitialized()) await botguardService.reinit();
  return botguardService.mintWebsafeToken(contentBinding);
}

function bootstrapPlayer() {
  const embedConfig = getEmbedConfig();
  const query = new URL(globalThis.location.href).searchParams;
  const provider = embedConfig
    ? 'youtube'
    : query.get('provider') ?? 'youtube';
  const load = provider === 'bilibili'
    ? () => loadBilibili(query.get('session') ?? '')
    : () => loadVideo(embedConfig?.videoId ?? query.get('videoId') ?? '');

  ensurePlayerDom();
  main(provider)
    .then(load)
    .catch((err) => {
      const detail = describePlayerError(err);
      console.error('Initialization failed:', detail, err?.stack || '');
      notify('error', detail);
    });
}

// 本地页面在 DOMContentLoaded 时启动；真实 embed 页面的运行时是在
// onPageFinished 之后注入的，此时事件早已触发，必须直接启动。
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', bootstrapPlayer);
} else {
  bootstrapPlayer();
}
