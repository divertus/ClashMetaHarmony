/*
 * Domain model for the main screen.
 *
 * Ported from ClashMetaForAndroid:
 *   design/src/main/java/com/github/kr328/clash/design/MainDesign.kt   (Request enum)
 *   core/src/main/java/com/github/kr328/clash/core/model/TunnelState.kt (Mode enum)
 */

/** Tunnel mode. Mirrors `TunnelState.Mode`. */
export enum TunnelMode {
  Direct = 'direct',
  Global = 'global',
  Rule = 'rule'
}

/** Requests raised by the main screen. Mirrors `MainDesign.Request`. */
export enum MainRequest {
  ToggleStatus,
  OpenProxy,
  OpenProfiles,
  OpenProviders,
  OpenLogs,
  OpenSettings,
  OpenHelp,
  OpenAbout
}

/**
 * Snapshot of the tunnel state the main screen renders.
 *
 * On Android this is assembled from `queryTunnelState()`, `queryProviders()`
 * and `queryActive()` calls into the native core. On HarmonyOS those calls
 * have no implementation yet -- see `MainViewModel` / `ClashBackend`.
 */
@ObservedV2
export class MainState {
  @Trace running: boolean = false;
  @Trace uploadPacked: number = 0;
  @Trace downloadPacked: number = 0;
  @Trace mode: TunnelMode = TunnelMode.Rule;
  @Trace profileName: string = '';
  @Trace hasProfile: boolean = false;
  @Trace hasProviders: boolean = false;
}
