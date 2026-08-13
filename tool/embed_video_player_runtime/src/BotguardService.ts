import { fetchFunction, trustedScriptSource } from './helpers.js';
import type { WebPoSignalOutput } from 'bgutils-js';
import { BG, buildURL, GOOG_API_KEY } from 'bgutils-js';

export interface BotguardChallenge {  interpreterHash: string;
  program: string;
  globalName: string;
  // Innertube's /att/get response stores both the inline script and the
  // fallback URL in interpreterUrl despite the field's name.
  interpreterUrl: {
    privateDoNotAccessOrElseSafeScriptWrappedValue?: string | null;
    privateDoNotAccessOrElseTrustedResourceUrlWrappedValue?: string | null;
  };
  // Keep accepting the older shape used by the WAA challenge endpoint.
  interpreterJavascript?: {
    privateDoNotAccessOrElseSafeScriptWrappedValue?: string | null;
    privateDoNotAccessOrElseTrustedResourceUrlWrappedValue?: string | null;
  };
}

type ChallengeLoader = () => Promise<BotguardChallenge>;

export class BotguardService {
  private readonly waaRequestKey = 'O43z0dpjhgX20SCx4KAo';

  public botguardClient?: BG.BotGuardClient;
  public initializationPromise?: Promise<BG.BotGuardClient | undefined> | null = null;
  public integrityTokenBasedMinter?: BG.WebPoMinter;
  public bgChallenge?: BotguardChallenge;
  private challengeLoader?: ChallengeLoader;

  public configureChallengeLoader(loader: ChallengeLoader) {
    this.challengeLoader = loader;
  }

  async init() {
    if (this.initializationPromise) {
      return await this.initializationPromise;
    }

    return this.setup();
  }

  private async setup() {
    if (this.initializationPromise)
      return await this.initializationPromise;

    this.initializationPromise = this._initBotguard();

    try {
      this.botguardClient = await this.initializationPromise;
      return this.botguardClient;
    } finally {
      this.initializationPromise = null;
    }
  }

  private async _initBotguard() {
    if (!this.challengeLoader) {
      throw new Error('BotGuard challenge loader is not configured.');
    }
    this.bgChallenge = await this.challengeLoader();

    if (!this.bgChallenge)
      return;

    let interpreterJavascript = this.bgChallenge.interpreterUrl
      .privateDoNotAccessOrElseSafeScriptWrappedValue ??
      this.bgChallenge.interpreterJavascript
        ?.privateDoNotAccessOrElseSafeScriptWrappedValue;
    if (!interpreterJavascript) {
      const interpreterPath = this.bgChallenge.interpreterUrl
        .privateDoNotAccessOrElseTrustedResourceUrlWrappedValue ??
        this.bgChallenge.interpreterJavascript
          ?.privateDoNotAccessOrElseTrustedResourceUrlWrappedValue;
      if (!interpreterPath) {
        throw new Error(
          `BotGuard challenge ${this.bgChallenge.interpreterHash} has no interpreter.`
        );
      }
      const interpreterResponse = await fetchFunction(
        new URL(interpreterPath, 'https://www.youtube.com')
      );
      if (!interpreterResponse.ok) {
        throw new Error(`BotGuard interpreter request failed with HTTP ${interpreterResponse.status}`);
      }
      interpreterJavascript = await interpreterResponse.text();
    }

    if (!interpreterJavascript) {
      throw new Error(
        `BotGuard interpreter ${this.bgChallenge.interpreterHash} is empty.`
      );
    }

    // Match the current bgutil provider. The newer /att/get interpreter is a
    // self-contained program and must execute in the page's global realm
    // before BotGuardClient resolves globalName. Trusted Types 页面需要用
    // 直通策略包装脚本源。
    new Function(trustedScriptSource(interpreterJavascript) as string)();

    this.botguardClient = await BG.BotGuardClient.create({
      globalObj: globalThis,
      globalName: this.bgChallenge.globalName,
      program: this.bgChallenge.program
    });

    if (this.bgChallenge) {
      const webPoSignalOutput: WebPoSignalOutput = [];
      const botguardResponse = await this.botguardClient.snapshot({ webPoSignalOutput });

      // YouTube's attestation challenge must be completed through YouTube's
      // WAA endpoint. The generic Google endpoint can accept the payload but
      // return only a fallback token, which is unusable for GVS playback.
      const integrityTokenResponse = await fetchFunction(buildURL('GenerateIT', true), {
        method: 'POST',
        headers: {
          'content-type': 'application/json+protobuf',
          'x-goog-api-key': GOOG_API_KEY,
          'x-user-agent': 'grpc-web-javascript/0.1'
        },
        body: JSON.stringify([ this.waaRequestKey, botguardResponse ])
      });

      const integrityTokenResponseData = await integrityTokenResponse.json();
      const [
        integrityToken,
        estimatedTtlSecs,
        mintRefreshThreshold,
        websafeFallbackToken
      ] = integrityTokenResponseData as [string | undefined, number?, number?, string?];

      if (!integrityToken) {
        throw new Error(
          `BotGuard GenerateIT returned no integrity token for ${this.bgChallenge.interpreterHash} ` +
          `(${describeIntegrityResponse(integrityTokenResponseData)}).`
        );
      }

      this.integrityTokenBasedMinter = await BG.WebPoMinter.create({
        integrityToken,
        estimatedTtlSecs,
        mintRefreshThreshold,
        websafeFallbackToken
      }, webPoSignalOutput);
    }

    return this.botguardClient;
  }

  public mintColdStartToken(contentBinding: string) {
    return BG.PoToken.generateColdStartToken(contentBinding);
  }

  public isInitialized() {
    return !!this.botguardClient && !!this.integrityTokenBasedMinter;
  }

  public async mintWebsafeToken(contentBinding: string) {
    if (!this.integrityTokenBasedMinter) {
      throw new Error('BotGuard WebPO minter is unavailable.');
    }
    return this.integrityTokenBasedMinter.mintAsWebsafeString(contentBinding);
  }

  public dispose() {
    if (this.botguardClient && this.bgChallenge) {
      this.botguardClient.shutdown();
      this.botguardClient = undefined;
      this.integrityTokenBasedMinter = undefined;

    }
  }

  public async reinit() {
    if (this.initializationPromise)
      return this.initializationPromise;
    this.dispose();
    return this.setup();
  }
}

export const botguardService = new BotguardService();

function describeIntegrityResponse(value: unknown): string {
  if (Array.isArray(value)) {
    const types = value.slice(0, 6).map((entry) => {
      if (entry == null) return String(entry);
      if (typeof entry === 'string') return `string(${entry.length})`;
      if (Array.isArray(entry)) return `array(${entry.length})`;
      if (typeof entry === 'object') {
        return `object(${Object.keys(entry as Record<string, unknown>).slice(0, 6).join(',')})`;
      }
      return typeof entry;
    });
    return `array length=${value.length} types=[${types.join(',')}]`;
  }
  if (value && typeof value === 'object') {
    return `object keys=[${Object.keys(value as Record<string, unknown>).slice(0, 10).join(',')}]`;
  }
  return `${typeof value}:${String(value).slice(0, 80)}`;
}
