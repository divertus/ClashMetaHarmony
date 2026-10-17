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
 * BACKEND -- what changed on HarmonyOS
 * ------------------------------------
 * Android gets every value above from the native mihomo core (Go, built with
 * gomobile) over JNI, and takes over traffic through Android's `VpnService`.
 * This port now has the same shape: `VpnExtensionAbility` owns the TUN, and
 * `libclash.so` is the OHOS arm64 mihomo core behind `libclashcore.so`
 * (PORT-STATUS §23). `Index.ets` starts/stops that extension with the active
 * profile.
 *
 * The backend is still `ExternalControllerBackend`, but it now points at the
 * local core's `127.0.0.1:9090` external-controller by default. Consequences,
 * stated plainly (see ExternalControllerBackend's header for the full table):
 *
 *   - `connected` means "the controller answered"; the VPN start/stop state is
 *     owned by `Index.ets` / `VpnExtensionAbility`.
 *   - The profile name is not exposed by the controller API. The Profile card
 *     therefore reads the *local* profile store instead (`useProfileStore`), and
 *     `BackendSnapshot.profileName` is only a fallback for a backend that
 *     reports one.
 *   - `state.running` still means "this UI is actively monitoring", not
 *     "the controller is reachable".
 */

import { MainState, TunnelMode } from '../model/MainModels';
import { trafficFromBytes } from '../model/Traffic';
import { ControllerStore } from '../backend/ControllerStore';
import { ExternalControllerBackend } from '../backend/ExternalControllerBackend';
import { BackendSnapshot, ClashBackend, NullClashBackend } from '../backend/BackendTypes';
import { ProfileStore, profileActive } from '../backend/ProfileStore';
import { Profile } from '../model/ProfileModels';

@ObservedV2
export class MainViewModel {
  @Trace state: MainState = new MainState();
  @Trace connecting: boolean = false;
  @Trace lastError: string = '';

  private backend: ClashBackend = new NullClashBackend();
  private controller: ExternalControllerBackend | null = null;
  private profileStore: ProfileStore | null = null;

  /**
   * Name of the active *local* profile, mirroring `MainActivity`'s
   * `withProfile { queryActive() }`. The external-controller API has no profile
   * concept, so `BackendSnapshot.profileName` stays empty and this is what the
   * profile card actually shows.
   */
  @Trace activeProfileName: string = '';

  /** Handle for the 1-second traffic ticker; -1 when not monitoring. */
  private tickerId: number = -1;

  /** Point the ViewModel at a mihomo external controller. */
  useExternalController(store: ControllerStore): void {
    const backend: ExternalControllerBackend = new ExternalControllerBackend(store);
    this.controller = backend;
    this.backend = backend;
    this.lastError = '';
  }

  /** Point the ViewModel at the local profile store. */
  useProfileStore(store: ProfileStore): void {
    this.profileStore = store;
    this.syncActiveProfile();
  }

  /**
   * Re-read the active profile. `MainActivity` re-runs this on every
   * `Event.ProfileChanged`; the port calls it from `onPageShow`, which is the
   * equivalent "another page may have changed something".
   */
  syncActiveProfile(): void {
    const store: ProfileStore | null = this.profileStore;
    const active: Profile | undefined = store === null ? undefined : profileActive(store);
    this.activeProfileName = active === undefined ? '' : active.name;
  }

  /** Mirrors MainActivity.fetch(): tunnel state + providers + active profile. */
  async refresh(): Promise<void> {
    const snapshot: BackendSnapshot = await this.backend.snapshot();
    this.state.mode = snapshot.mode;
    this.state.profileName = snapshot.profileName;
    this.state.hasProfile = snapshot.hasProfile;
    this.state.hasProviders = snapshot.hasProviders;
    await this.refreshTraffic();
  }

  /** Mirrors MainActivity.fetchTraffic(). */
  async refreshTraffic(): Promise<void> {
    const controller: ExternalControllerBackend | null = this.controller;
    if (controller === null) {
      this.state.uploadPacked = 0;
      this.state.downloadPacked = 0;
      return;
    }
    const totals: [number, number] = controller.getTrafficTotals();
    this.state.uploadPacked = totals[0];
    this.state.downloadPacked = totals[1];
  }

  /**
   * Mirrors MainDesign.Request.ToggleStatus, adapted: with a remote controller
   * there is no local tunnel to switch, so this starts or stops monitoring.
   *
   * `state.running` means "this app is actively monitoring", not "the core's
   * tunnel is up" -- refresh() deliberately leaves it alone, because the
   * controller being reachable is a precondition for monitoring, not the
   * toggle state itself.
   */
  async toggleStatus(): Promise<void> {
    this.connecting = true;
    try {
      if (this.state.running) {
        this.stopTicker();
        await this.backend.stop();
        this.state.running = false;
        this.state.hasProviders = false;
        this.lastError = '';
      } else {
        const connected: boolean = await this.backend.start();
        if (connected) {
          this.state.running = true;
          this.lastError = '';
          this.startTicker();
        } else {
          this.lastError = 'controller unreachable';
        }
      }
    } catch (error) {
      this.lastError = 'controller unreachable';
    } finally {
      this.connecting = false;
    }
    await this.refresh();
  }

  /**
   * Android ticks traffic once a second while the tunnel runs:
   *   val ticker = ticker(TimeUnit.SECONDS.toMillis(1))
   *   ticker.onReceive { design.fetchTraffic() }
   * Same cadence here, active only while monitoring.
   */
  private startTicker(): void {
    if (this.tickerId !== -1) {
      return;
    }
    this.tickerId = setInterval(() => {
      this.refreshTraffic();
    }, 1000);
  }

  private stopTicker(): void {
    if (this.tickerId === -1) {
      return;
    }
    clearInterval(this.tickerId);
    this.tickerId = -1;
  }

  /** "1.24 MiB Forwarded" -- mirrors MainDesign.setForwarded(). */
  @Computed
  get forwardedText(): string {
    return trafficFromBytes(this.state.uploadPacked, this.state.downloadPacked);
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

  /**
   * Profile card subtext. The local store wins: the controller API never
   * supplies a profile name, so `state.profileName` is only a fallback for a
   * backend that does report one.
   */
  @Computed
  get profileRes(): ResourceStr {
    if (this.activeProfileName.length > 0) {
      return $r('app.string.format_profile_activated', this.activeProfileName);
    }
    if (this.state.hasProfile && this.state.profileName.length > 0) {
      return $r('app.string.format_profile_activated', this.state.profileName);
    }
    return $r('app.string.not_selected');
  }

  /** Status card title. "Running" is weaker than Android's tunnel state. */
  @Computed
  get statusTextRes(): Resource {
    return this.state.running ? $r('app.string.running') : $r('app.string.stopped');
  }

  /** Status card subtext. Error text wins so a failed probe is visible. */
  @Computed
  get statusSubtextRes(): ResourceStr {
    if (this.connecting) {
      return $r('app.string.tap_to_start');
    }
    if (this.lastError.length > 0) {
      return this.lastError;
    }
    if (this.state.running) {
      return $r('app.string.format_traffic_forwarded', this.forwardedText);
    }
    return $r('app.string.tap_to_start');
  }
}
