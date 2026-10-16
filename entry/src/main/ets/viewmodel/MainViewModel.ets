/*
 * ViewModel for the main screen.
 *
 * Ported from ClashMetaForAndroid MainActivity / MainDesign. The Android
 * original drives this state from a 1-second ticker plus service events:
 *
 *   design.fetch()        -> queryTunnelState() / queryProviders() / queryActive()
 *   design.fetchTraffic() -> queryTrafficTotal()          (every 1s while running)
 *   ToggleStatus          -> stopClashService() | startClashService() (+ VPN consent)
 *
 * BACKEND SEAM -- READ THIS BEFORE RELYING ON THE UI
 * --------------------------------------------------
 * The Android app gets every value above from the native mihomo core (Go,
 * built with gomobile) over a JNI bridge, and it takes over traffic through
 * Android's `VpnService`. Neither exists on HarmonyOS:
 *
 *   - `VpnService` has no public HarmonyOS NEXT equivalent, so a Clash-style
 *     TUN-based traffic takeover cannot be reproduced by this app as written.
 *   - The mihomo core would have to be cross-compiled for HarmonyOS and
 *     bridged over NAPI, which is a separate project from this UI port.
 *
 * `ClashBackend` is therefore declared as an interface with a `NullClashBackend`
 * default that reports "stopped, no profile". The UI is real and complete; the
 * data behind it is not yet. Implement `ClashBackend` (external-controller
 * client is the realistic path -- see the note on `MainRequest.OpenProxy`) to
 * make the screen live.
 */

import { MainRequest, MainState, TunnelMode } from '../model/MainModels';
import { trafficTotal } from '../model/Traffic';

/** Snapshot returned by a backend poll. */
export interface BackendSnapshot {
  running: boolean;
  uploadPacked: number;
  downloadPacked: number;
  mode: TunnelMode;
  profileName: string;
  hasProfile: boolean;
  hasProviders: boolean;
}

/**
 * Data source for the main screen.
 *
 * Not implemented yet. See the file header: on Android this is the native
 * mihomo core plus VpnService; on HarmonyOS the realistic implementation is an
 * external-controller client talking to a mihomo instance running elsewhere
 * (router / desktop), which is also how ClashMetaForAndroid's own
 * `ExternalControlActivity` works.
 */
export interface ClashBackend {
  snapshot(): Promise<BackendSnapshot>;
  start(): Promise<boolean>;
  stop(): Promise<void>;
}

/** Reports "stopped, nothing configured". Placeholder until a backend exists. */
export class NullClashBackend implements ClashBackend {
  async snapshot(): Promise<BackendSnapshot> {
    const empty: BackendSnapshot = {
      running: false,
      uploadPacked: 0,
      downloadPacked: 0,
      mode: TunnelMode.Rule,
      profileName: '',
      hasProfile: false,
      hasProviders: false
    };
    return empty;
  }

  async start(): Promise<boolean> {
    return false;
  }

  async stop(): Promise<void> {
  }
}

@ObservedV2
export class MainViewModel {
  @Trace state: MainState = new MainState();

  private backend: ClashBackend = new NullClashBackend();

  /** Install a real backend. No-op until one exists. */
  setBackend(backend: ClashBackend): void {
    this.backend = backend;
  }

  /** Mirrors MainActivity.fetch(): tunnel state + providers + active profile. */
  async refresh(): Promise<void> {
    const snapshot: BackendSnapshot = await this.backend.snapshot();
    this.state.running = snapshot.running;
    this.state.uploadPacked = snapshot.uploadPacked;
    this.state.downloadPacked = snapshot.downloadPacked;
    this.state.mode = snapshot.mode;
    this.state.profileName = snapshot.profileName;
    this.state.hasProfile = snapshot.hasProfile;
    this.state.hasProviders = snapshot.hasProviders;
  }

  /** Mirrors MainActivity.fetchTraffic(). */
  async refreshTraffic(): Promise<void> {
    if (!this.state.running) {
      return;
    }
    const snapshot: BackendSnapshot = await this.backend.snapshot();
    this.state.uploadPacked = snapshot.uploadPacked;
    this.state.downloadPacked = snapshot.downloadPacked;
  }

  /** Mirrors MainDesign.Request.ToggleStatus. */
  async toggleStatus(): Promise<void> {
    if (this.state.running) {
      await this.backend.stop();
    } else {
      const started: boolean = await this.backend.start();
      if (!started) {
        return;
      }
    }
    await this.refresh();
  }

  /** "1.24 MiB Forwarded" -- mirrors MainDesign.setForwarded(). */
  @Computed
  get forwardedText(): string {
    return trafficTotal(this.state.uploadPacked, this.state.downloadPacked);
  }

  /** Mirrors MainDesign.setMode(). */
  @Computed
  get modeRes(): Resource {
    if (this.state.mode === TunnelMode.Direct) {
      return $r('app.string.direct_mode');
    }
    if (this.state.mode === TunnelMode.Global) {
      return $r('app.string.global_mode');
    }
    return $r('app.string.rule_mode');
  }

  /** Profile card subtext: activated profile name, or "Not selected". */
  @Computed
  get profileRes(): ResourceStr {
    if (this.state.hasProfile && this.state.profileName.length > 0) {
      return $r('app.string.format_profile_activated', this.state.profileName);
    }
    return $r('app.string.not_selected');
  }
}

export type MainRequestHandler = (request: MainRequest) => void;
