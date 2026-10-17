/*
 * Domain model for the network-settings screen.
 *
 * Ported from ClashMetaForAndroid:
 *   service/src/main/java/com/github/kr328/clash/service/model/AccessControlMode.kt
 *   design/src/main/java/com/github/kr328/clash/design/NetworkSettingsDesign.kt
 */

/** Mirrors `AccessControlMode`; the order is the order of `values()`. */
export enum AccessControlMode {
  AcceptAll,
  AcceptSelected,
  DenySelected
}

/**
 * `AccessControlMode.values()`, spelled out: ArkTS has no enum reflection, and
 * `NetworkSettingsDesign` passes `values()` straight into the selectable list.
 */
export const ACCESS_CONTROL_MODES: AccessControlMode[] = [
  AccessControlMode.AcceptAll,
  AccessControlMode.AcceptSelected,
  AccessControlMode.DenySelected
];

/**
 * `valuesText` of the `accessControlMode` selectableList, in `values()` order.
 * Shared by the network-settings row and the access-control page so the two
 * screens cannot drift apart.
 */
export function accessControlModeText(mode: AccessControlMode): Resource {
  if (mode === AccessControlMode.AcceptSelected) {
    return $r('app.string.allow_selected_apps');
  }
  if (mode === AccessControlMode.DenySelected) {
    return $r('app.string.deny_selected_apps');
  }
  return $r('app.string.allow_all_apps');
}

/**
 * Requests raised by the network-settings screen.
 * Mirrors `NetworkSettingsDesign.Request`.
 */
export enum NetworkSettingsRequest {
  StartAccessControlList
}

/**
 * `ServiceStore.tunStackMode`'s four legal values, in the order Android's
 * `selectableList(values = arrayOf("system", "gvisor", "mixed", "mips"))`
 * shows them. The string is handed to sing-tun verbatim, so these are the
 * wire values, not a UI enum.
 */
export const TUN_STACK_MODES: string[] = ['system', 'gvisor', 'mixed', 'mips'];

/** `ServiceStore.tunStackMode` default. */
export const DEFAULT_TUN_STACK_MODE: string = 'mips';

/** `valuesText` of the `tunStackMode` selectableList, in `TUN_STACK_MODES` order. */
export function tunStackModeText(mode: string): Resource {
  if (mode === 'system') {
    return $r('app.string.tun_stack_system');
  }
  if (mode === 'gvisor') {
    return $r('app.string.tun_stack_gvisor');
  }
  if (mode === 'mixed') {
    return $r('app.string.tun_stack_mixed');
  }
  return $r('app.string.tun_stack_mips');
}

/** True when `mode` is one of `TUN_STACK_MODES`. */
export function isTunStackMode(mode: string): boolean {
  for (const candidate of TUN_STACK_MODES) {
    if (candidate === mode) {
      return true;
    }
  }
  return false;
}

/**
 * The wire name of an `AccessControlMode`.
 *
 * The value has to survive a `Want` boundary, which carries no enums, so the
 * name is what travels; `accessControlModeFromName` is its inverse.
 */
export function accessControlModeName(mode: AccessControlMode): string {
  if (mode === AccessControlMode.AcceptSelected) {
    return 'AcceptSelected';
  }
  if (mode === AccessControlMode.DenySelected) {
    return 'DenySelected';
  }
  return 'AcceptAll';
}

/** Inverse of `accessControlModeName`; an unknown name reads as `AcceptAll`. */
export function accessControlModeFromName(name: string): AccessControlMode {
  if (name === 'AcceptSelected') {
    return AccessControlMode.AcceptSelected;
  }
  if (name === 'DenySelected') {
    return AccessControlMode.DenySelected;
  }
  return AccessControlMode.AcceptAll;
}

/**
 * Every knob the VPN-backed half of the network-settings screen owns, in the
 * shape the `VpnExtensionAbility` consumes.
 *
 * Android keeps these in two stores -- `UiStore.enableVpn` and six
 * `ServiceStore` fields -- because the UI process and the `VpnService` process
 * are separate. HarmonyOS's VPN extension is also a separate ability, but the
 * whole set travels as one `Want` parameter, so one record is the natural unit.
 *
 * Defaults are Android's, field for field (`ServiceStore.kt` /
 * `UiStore.kt`).
 */
export class VpnSettings {
  /** `UiStore.enableVpn`: the master switch, and the gate for every row below. */
  enableVpn: boolean = true;

  /** `ServiceStore.bypassPrivateNetwork`. */
  bypassPrivateNetwork: boolean = true;

  /** `ServiceStore.dnsHijacking`. */
  dnsHijacking: boolean = true;

  /** `ServiceStore.allowBypass`. */
  allowBypass: boolean = true;

  /** `ServiceStore.allowIpv6`. */
  allowIpv6: boolean = false;

  /** `ServiceStore.systemProxy`. */
  systemProxy: boolean = true;

  /** `ServiceStore.tunStackMode`; one of `TUN_STACK_MODES`. */
  tunStackMode: string = DEFAULT_TUN_STACK_MODE;
}
