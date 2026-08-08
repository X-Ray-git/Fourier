import { BinaryReader, WireType } from '@bufbuild/protobuf/wire';

const segmentDurationSeconds = 6 * 60;
const maxActiveDanmaku = 80;
const maxSegmentEntries = 20000;

type DanmakuMode = 'scroll' | 'top' | 'bottom';

interface DanmakuEntry {
  progressMs: number;
  mode: DanmakuMode;
  fontSize: number;
  color: number;
  content: string;
}

interface SegmentState {
  entries: DanmakuEntry[];
  cursor: number;
}

interface ActiveDanmaku extends DanmakuEntry {
  lane: number;
  startSeconds: number;
  durationSeconds: number;
  width: number;
}

export class BilibiliDanmaku {
  private readonly canvas = document.createElement('canvas');
  private readonly context: CanvasRenderingContext2D;
  private readonly segments = new Map<number, SegmentState>();
  private readonly loadingSegments = new Set<number>();
  private readonly failedSegments = new Set<number>();
  private readonly rollingLaneReadyAt: number[] = [];
  private readonly topLaneReadyAt: number[] = [];
  private readonly bottomLaneReadyAt: number[] = [];
  private readonly resizeObserver: ResizeObserver;
  private readonly toggleButton: HTMLButtonElement;
  private active: ActiveDanmaku[] = [];
  private enabled = true;
  private frameId = 0;
  private lastMediaTime = -1;
  private width = 0;
  private height = 0;
  private pixelRatio = 1;

  constructor(
    private readonly video: HTMLVideoElement,
    private readonly container: HTMLDivElement,
    private readonly segmentBaseUrl: string
  ) {
    const context = this.canvas.getContext('2d');
    if (!context) throw new Error('Canvas 2D is unavailable.');
    this.context = context;
    this.canvas.className = 'fourier-danmaku-canvas';
    this.container.append(this.canvas);

    this.toggleButton = this.createToggleButton();
    this.installToggleButton();
    this.updateToggleButton();

    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(this.container);
    this.resize();

    this.video.addEventListener('seeking', this.handleSeek);
    this.video.addEventListener('seeked', this.handleSeek);
    this.video.addEventListener('loadedmetadata', this.preloadNearbySegments);
    this.video.addEventListener('durationchange', this.preloadNearbySegments);
    this.video.addEventListener('ended', this.clear);
    this.frameId = requestAnimationFrame(this.render);
    this.preloadNearbySegments();
  }

  dispose() {
    cancelAnimationFrame(this.frameId);
    this.resizeObserver.disconnect();
    this.video.removeEventListener('seeking', this.handleSeek);
    this.video.removeEventListener('seeked', this.handleSeek);
    this.video.removeEventListener(
      'loadedmetadata',
      this.preloadNearbySegments
    );
    this.video.removeEventListener(
      'durationchange',
      this.preloadNearbySegments
    );
    this.video.removeEventListener('ended', this.clear);
    this.toggleButton.remove();
    this.canvas.remove();
  }

  private createToggleButton() {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'fourier-danmaku-button';
    button.textContent = '弹';
    button.addEventListener('click', (event) => {
      event.preventDefault();
      event.stopPropagation();
      this.enabled = !this.enabled;
      this.clear();
      this.resetCursors(this.video.currentTime);
      this.updateToggleButton();
      if (this.enabled) this.preloadNearbySegments();
    });
    return button;
  }

  private installToggleButton() {
    const panel = this.container.querySelector(
      '.shaka-controls-button-panel'
    );
    if (!panel) return;
    const overflowButton = panel.querySelector('.shaka-overflow-menu-button');
    panel.insertBefore(this.toggleButton, overflowButton);
  }

  private updateToggleButton() {
    this.toggleButton.classList.toggle('is-active', this.enabled);
    this.toggleButton.setAttribute('aria-pressed', String(this.enabled));
    this.toggleButton.setAttribute(
      'aria-label',
      this.enabled ? '关闭弹幕' : '开启弹幕'
    );
    this.toggleButton.title = this.enabled ? '关闭弹幕' : '开启弹幕';
  }

  private readonly handleSeek = () => {
    this.clear();
    this.resetCursors(this.video.currentTime);
    this.lastMediaTime = this.video.currentTime;
    this.preloadNearbySegments();
  };

  private readonly preloadNearbySegments = () => {
    if (!this.enabled || !Number.isFinite(this.video.currentTime)) return;
    const segment = Math.floor(
      Math.max(0, this.video.currentTime) / segmentDurationSeconds
    );
    void this.loadSegment(segment);
    const segmentCount = Number.isFinite(this.video.duration)
      ? Math.ceil(this.video.duration / segmentDurationSeconds)
      : Number.POSITIVE_INFINITY;
    if (segment + 1 < segmentCount) void this.loadSegment(segment + 1);
  };

  private async loadSegment(segment: number) {
    if (
      segment < 0 ||
      this.segments.has(segment) ||
      this.loadingSegments.has(segment) ||
      this.failedSegments.has(segment)
    ) {
      return;
    }
    this.loadingSegments.add(segment);
    try {
      const response = await fetch(`${this.segmentBaseUrl}${segment + 1}`);
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const entries = parseDanmakuSegment(
        new Uint8Array(await response.arrayBuffer())
      );
      this.segments.set(segment, {
        entries,
        cursor: lowerBound(entries, this.video.currentTime * 1000 - 100)
      });
    } catch (error) {
      this.failedSegments.add(segment);
      console.warn(
        '[BilibiliDanmaku]',
        `Skipping segment ${segment + 1}:`,
        error
      );
    } finally {
      this.loadingSegments.delete(segment);
    }
  }

  private readonly render = () => {
    const currentTime = this.video.currentTime;
    if (this.enabled && Number.isFinite(currentTime)) {
      if (
        this.lastMediaTime < 0 ||
        currentTime < this.lastMediaTime - 0.2 ||
        currentTime > this.lastMediaTime + 1
      ) {
        this.clear();
        this.resetCursors(currentTime);
      }
      this.preloadNearbySegments();
      if (!this.video.paused && !this.video.seeking) {
        this.dispatchEntries(currentTime);
      }
      this.draw(currentTime);
      this.lastMediaTime = currentTime;
    } else {
      this.context.clearRect(0, 0, this.width, this.height);
    }
    this.frameId = requestAnimationFrame(this.render);
  };

  private dispatchEntries(currentTime: number) {
    const segment = Math.floor(
      Math.max(0, currentTime) / segmentDurationSeconds
    );
    const state = this.segments.get(segment);
    if (!state) return;
    const deadlineMs = currentTime * 1000 + 60;
    while (
      state.cursor < state.entries.length &&
      state.entries[state.cursor].progressMs <= deadlineMs
    ) {
      const entry = state.entries[state.cursor++];
      if (entry.progressMs >= currentTime * 1000 - 180) {
        this.activate(entry);
      }
    }
  }

  private activate(entry: DanmakuEntry) {
    if (this.active.length >= maxActiveDanmaku) return;
    const fontSize = this.displayFontSize(entry.fontSize);
    this.context.font = `600 ${fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`;
    const width = this.context.measureText(entry.content).width;
    const startSeconds = entry.progressMs / 1000;
    const durationSeconds = entry.mode === 'scroll' ? 8 : 4;
    const lane = this.claimLane(entry.mode, startSeconds, durationSeconds);
    if (lane < 0) return;
    this.active.push({
      ...entry,
      lane,
      startSeconds,
      durationSeconds,
      width
    });
  }

  private claimLane(
    mode: DanmakuMode,
    startSeconds: number,
    durationSeconds: number
  ) {
    const lineHeight = this.lineHeight;
    const laneCount = Math.max(1, Math.floor((this.height * 0.72) / lineHeight));
    const readyAt = mode === 'scroll'
      ? this.rollingLaneReadyAt
      : mode === 'top'
        ? this.topLaneReadyAt
        : this.bottomLaneReadyAt;
    for (let lane = 0; lane < laneCount; lane++) {
      if ((readyAt[lane] ?? 0) <= startSeconds) {
        readyAt[lane] = startSeconds +
          (mode === 'scroll' ? durationSeconds * 0.42 : durationSeconds);
        return lane;
      }
    }
    return -1;
  }

  private draw(currentTime: number) {
    this.context.clearRect(0, 0, this.width, this.height);
    this.active = this.active.filter(
      (item) => currentTime <= item.startSeconds + item.durationSeconds
    );
    this.context.textAlign = 'left';
    this.context.textBaseline = 'middle';
    this.context.lineJoin = 'round';
    this.context.globalAlpha = 0.9;

    for (const item of this.active) {
      const elapsed = Math.max(0, currentTime - item.startSeconds);
      const progress = Math.min(1, elapsed / item.durationSeconds);
      const fontSize = this.displayFontSize(item.fontSize);
      const lineHeight = this.lineHeight;
      this.context.font = `600 ${fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif`;
      let x: number;
      let y: number;
      if (item.mode === 'scroll') {
        x = this.width - progress * (this.width + item.width);
        y = lineHeight * (item.lane + 0.65);
      } else {
        x = (this.width - item.width) / 2;
        y = item.mode === 'top'
          ? lineHeight * (item.lane + 0.65)
          : this.height - lineHeight * (item.lane + 1.25);
      }
      this.context.strokeStyle = contrastStroke(item.color);
      this.context.lineWidth = Math.max(2, fontSize * 0.14);
      this.context.strokeText(item.content, x, y);
      this.context.fillStyle = decimalColor(item.color);
      this.context.fillText(item.content, x, y);
    }
    this.context.globalAlpha = 1;
  }

  private resetCursors(currentTime: number) {
    const progressMs = Math.max(0, currentTime * 1000 - 100);
    for (const state of this.segments.values()) {
      state.cursor = lowerBound(state.entries, progressMs);
    }
    this.rollingLaneReadyAt.length = 0;
    this.topLaneReadyAt.length = 0;
    this.bottomLaneReadyAt.length = 0;
  }

  private readonly clear = () => {
    this.active = [];
    this.context.clearRect(0, 0, this.width, this.height);
    this.rollingLaneReadyAt.length = 0;
    this.topLaneReadyAt.length = 0;
    this.bottomLaneReadyAt.length = 0;
  };

  private resize() {
    const bounds = this.container.getBoundingClientRect();
    this.width = Math.max(1, bounds.width);
    this.height = Math.max(1, bounds.height);
    this.pixelRatio = Math.min(globalThis.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(this.width * this.pixelRatio);
    this.canvas.height = Math.round(this.height * this.pixelRatio);
    this.canvas.style.width = `${this.width}px`;
    this.canvas.style.height = `${this.height}px`;
    this.context.setTransform(
      this.pixelRatio,
      0,
      0,
      this.pixelRatio,
      0,
      0
    );
    this.clear();
    this.resetCursors(this.video.currentTime);
  }

  private displayFontSize(sourceSize: number) {
    const base = Math.max(15, Math.min(25, this.height / 18));
    return Math.max(13, Math.min(30, base * (sourceSize > 0 ? sourceSize / 25 : 1)));
  }

  private get lineHeight() {
    return Math.max(22, Math.min(34, this.height / 13));
  }
}

export function parseDanmakuSegment(bytes: Uint8Array): DanmakuEntry[] {
  const reader = new BinaryReader(bytes);
  const entries: DanmakuEntry[] = [];
  while (reader.pos < reader.len && entries.length < maxSegmentEntries) {
    const [fieldNumber, wireType] = reader.tag();
    if (fieldNumber === 1 && wireType === WireType.LengthDelimited) {
      const entry = parseDanmakuEntry(reader.bytes());
      if (entry) entries.push(entry);
    } else {
      reader.skip(wireType, fieldNumber);
    }
  }
  entries.sort((left, right) => left.progressMs - right.progressMs);
  return entries;
}

function parseDanmakuEntry(bytes: Uint8Array): DanmakuEntry | null {
  const reader = new BinaryReader(bytes);
  let progressMs = 0;
  let rawMode = 1;
  let fontSize = 25;
  let color = 0xffffff;
  let content = '';

  while (reader.pos < reader.len) {
    const [fieldNumber, wireType] = reader.tag();
    switch (fieldNumber) {
      case 2:
        progressMs = reader.int32();
        break;
      case 3:
        rawMode = reader.int32();
        break;
      case 4:
        fontSize = reader.int32();
        break;
      case 5:
        color = reader.uint32();
        break;
      case 7:
        content = reader.string().trim();
        break;
      default:
        reader.skip(wireType, fieldNumber);
    }
  }
  if (!content || progressMs < 0 || rawMode === 7) return null;
  const mode: DanmakuMode = rawMode === 4
    ? 'bottom'
    : rawMode === 5
      ? 'top'
      : 'scroll';
  return { progressMs, mode, fontSize, color, content };
}

function lowerBound(entries: DanmakuEntry[], progressMs: number) {
  let low = 0;
  let high = entries.length;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (entries[middle].progressMs < progressMs) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }
  return low;
}

function decimalColor(value: number) {
  const normalized = Number.isFinite(value) ? value & 0xffffff : 0xffffff;
  return `#${normalized.toString(16).padStart(6, '0')}`;
}

function contrastStroke(value: number) {
  const normalized = Number.isFinite(value) ? value & 0xffffff : 0xffffff;
  const red = (normalized >> 16) & 0xff;
  const green = (normalized >> 8) & 0xff;
  const blue = normalized & 0xff;
  const luminance = (red * 299 + green * 587 + blue * 114) / 255000;
  return luminance < 0.35
    ? 'rgba(255, 255, 255, 0.9)'
    : 'rgba(0, 0, 0, 0.88)';
}
