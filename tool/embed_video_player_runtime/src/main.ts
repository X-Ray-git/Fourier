import shaka from 'shaka-player/dist/shaka-player.ui.js';
import type { Types } from 'youtubei.js/web';
import { Constants, Innertube, Platform, UniversalCache, Utils, YT } from 'youtubei.js/web';
import { SabrStreamingAdapter } from 'googlevideo/sabr-streaming-adapter';
import { buildSabrFormat } from 'googlevideo/utils';
import { ShakaPlayerAdapter } from './ShakaPlayerAdapter.js';
import { fetchFunction } from './helpers.js';
import { botguardService } from './BotguardService.js';
import { BilibiliDanmaku } from './bilibiliDanmaku.js';
import 'shaka-player/dist/controls.css';
import './player.css';

const videoElement = document.getElementById('video') as HTMLVideoElement;
const videoContainer = document.getElementById('video-container') as HTMLDivElement;

let player: shaka.Player;
let sabrAdapter: SabrStreamingAdapter;
let playerAdapter: ShakaPlayerAdapter;
let innertube: Innertube;
let playbackWebPoTokenContentBinding: string | undefined;
let playbackWebPoTokenCreationLock = false;
let playbackWebPoToken: string | undefined;
let coldStartToken: string | undefined;
let bilibiliDanmaku: BilibiliDanmaku | undefined;

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

  return new Function(code)();
};

async function main(provider: string) {
  shaka.polyfill.installAll();
  console.log('[Main]', 'Shaka polyfills installed');

  if (!shaka.Player.isBrowserSupported())
    throw new Error('Shaka Player is not supported on this browser.');
  console.log('[Main]', 'Browser support confirmed');

  if (provider === 'youtube') {
    innertube = await Innertube.create({
      cache: new UniversalCache(true),
      fetch: fetchFunction,
      generate_session_locally: true
    });

    botguardService.init()
      .then(() => console.info('[Main]', 'BotGuard client initialized'))
      .catch((error) => console.warn('[Main]', 'BotGuard initialization deferred:', error));

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

  playbackWebPoToken = undefined;
  playbackWebPoTokenContentBinding = videoId;

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

    // Initialize and attach SABR adapter.
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
      if (!playbackWebPoToken) {
        // For live streams, we must block and wait for the PO token as it's sometimes required for playback to start.
        // For VODs, we can mint the token in the background to avoid delaying playback, as it's not immediately required.
        // While BotGuard is pretty darn fast, it still makes a difference in user experience (from my own testing).
        if (isLive) {
          await mintContentWebPO();
        } else {
          mintContentWebPO().then();
        }
      }

      return playbackWebPoToken || coldStartToken || '';
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

    if (videoInfo.streaming_data && !isPostLiveDVR && !isLive) {
      console.log('[SABR]', 'Deciphering streaming URL');
      sabrAdapter.setStreamingURL(await innertube.session.player!.decipher(videoInfo.streaming_data?.server_abr_streaming_url));
      console.log('[SABR]', 'Streaming URL configured');
      sabrAdapter.setUstreamerConfig(videoInfo.player_config?.media_common_config.media_ustreamer_request_config?.video_playback_ustreamer_config);
      sabrAdapter.setServerAbrFormats(videoInfo.streaming_data.adaptive_formats.map(buildSabrFormat));
      console.log('[SABR]', 'Formats configured');
    }

    let manifestUri: string | undefined;
    if (videoInfo.streaming_data) {
      if (isLive) {
        manifestUri = videoInfo.streaming_data.dash_manifest_url ? `${videoInfo.streaming_data.dash_manifest_url}/mpd_version/7` : videoInfo.streaming_data.hls_manifest_url;
      } else if (isPostLiveDVR) {
        manifestUri = videoInfo.streaming_data.hls_manifest_url || `${videoInfo.streaming_data.dash_manifest_url}/mpd_version/7`;
      } else {
        console.log('[SABR]', 'Building DASH manifest');
        manifestUri = `data:application/dash+xml;base64,${btoa(await videoInfo.toDash({
          manifest_options: {
            is_sabr: true,
            captions_format: 'vtt',
            include_thumbnails: false
          }
        }))}`;
        console.log('[SABR]', 'DASH manifest built');
      }
    }

    if (!manifestUri)
      throw new Error('Could not find a valid manifest URI.');

    console.log('[Player]', 'Loading DASH manifest');
    try {
      await player.load(manifestUri);
      console.log('[Player]', 'SABR DASH manifest loaded');
    } catch (sabrError) {
      if (isLive || isPostLiveDVR) throw sabrError;

      console.warn(
        '[Player]',
        'SABR load failed; trying direct adaptive DASH:',
        describePlayerError(sabrError)
      );
      await player.unload();
      playerAdapter.disableSabrInterceptors();

      const directManifest = `data:application/dash+xml;base64,${btoa(await videoInfo.toDash({
        manifest_options: {
          is_sabr: false,
          captions_format: 'vtt',
          include_thumbnails: false
        }
      }))}`;
      await player.load(directManifest);
      console.log('[Player]', 'Direct adaptive DASH manifest loaded');
    }

    await videoElement.play();
    notify('playing', videoInfo.basic_info.title);
    console.log('[Player]', `Now playing: ${videoInfo.basic_info.title}`);
  } catch (e: any) {
    const detail = describePlayerError(e);
    console.error('[Player]', 'Error:', detail, e?.stack || '');
    notify('error', detail);
  }
}

async function mintContentWebPO() {
  if (!playbackWebPoTokenContentBinding || playbackWebPoTokenCreationLock) return;

  playbackWebPoTokenCreationLock = true;
  try {
    coldStartToken = botguardService.mintColdStartToken(playbackWebPoTokenContentBinding);
    console.info('[Player]', `Cold start token created (Content binding: ${decodeURIComponent(playbackWebPoTokenContentBinding)})`);

    if (!botguardService.isInitialized()) await botguardService.reinit();

    if (botguardService.integrityTokenBasedMinter) {
      playbackWebPoToken = await botguardService.integrityTokenBasedMinter.mintAsWebsafeString(decodeURIComponent(playbackWebPoTokenContentBinding));
      console.info('[Player]', `WebPO token created (Content binding: ${decodeURIComponent(playbackWebPoTokenContentBinding)})`);
    }
  } catch (err) {
    console.error('[Player]', 'Error minting WebPO token', err);
  } finally {
    playbackWebPoTokenCreationLock = false;
  }
}

document.addEventListener('DOMContentLoaded', () => {
  const query = new URL(globalThis.location.href).searchParams;
  const provider = query.get('provider') ?? 'youtube';
  const load = provider === 'bilibili'
    ? () => loadBilibili(query.get('session') ?? '')
    : () => loadVideo(query.get('videoId') ?? '');

  main(provider)
    .then(load)
    .catch((err) => {
      const detail = describePlayerError(err);
      console.error('Initialization failed:', detail);
      notify('error', detail);
    });
});
