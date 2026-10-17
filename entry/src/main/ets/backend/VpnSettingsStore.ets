/*
 * The VPN-backed half of the network-settings screen, plus the `Want` payload
 * that carries it to the `VpnExtensionAbility`.
 *
 * Android structure:
 *   UiStore.enableVpn                 the master switch
 *   ServiceStore.bypassPrivateNetwork / dnsHijacking / allowBypass /
 *   allowIpv6 / systemProxy / tunStackMode
 *   ServiceStore.accessControlMode / accessControlPackages
 *
 * Android reads all of them inside `TunService.open()` -- the service process
 * reads the same `SharedPreferences` the UI wrote, and there is no hand-off
 * because there is one store. HarmonyOS splits the UI (`EntryAbility`) and the
 * tunnel (`VpnExtensionAbility`) the same way, but the extension is started
 * with a `Want`, so the values travel as parameters instead. That is why this
 * file owns both ends: `vpnTunnelParameters()` builds the payload,
 * `readVpnTunnelParameters()` decodes it.
 *
 * Persistence is the shape `ProfileStore` documents -- one `@Trace` string,
 * no methods, free functions for the CRUD. `VpnSettings` is plain data, so
 * JSON round-trips exactly, and a missing or corrupt value reads as the
 * Android defaults rather than throwing.
 *
 * The access-control half deliberately lives where it already lived:
 * `AccessControlModeStore` in `AccessControlPrefs.ets` and the selected package
 * set in `InstalledApps.ets`. This file only reads them at hand-off time, so
 * the network-settings screen and the access-control screen keep sharing one
 * copy of that state.
 */

import { PersistenceV2 } from '@kit.ArkUI';
import { Want } from '@kit.AbilityKit';
import {
  AccessControlMode,
  VpnSettings,
  accessControlModeFromName,
  accessControlModeName,
  isTunStackMode
} from '../model/NetworkSettingsModels';
import { loadAccessControlModeStore } from './AccessControlPrefs';
import { accessControlPackageList, loadAccessControlStore } from './InstalledApps';

@ObservedV2
export class VpnSettingsStore {
  static readonly KEY: string = 'ClashVpnSettingsStore';

  /** Serialized `VpnSettings`; the store's only state. */
  @Trace encoded: string = '';
}

/** Load the persisted settings, or create the default ones on first run. */
export function loadVpnSettingsStore(): VpnSettingsStore {
  const store: VpnSettingsStore | undefined =
    PersistenceV2.connect(VpnSettingsStore, VpnSettingsStore.KEY, () => new VpnSettingsStore());
  return store ?? new VpnSettingsStore();
}

/** A field that is not a boolean of the expected shape keeps its default. */
function readBoolean(source: Record<string, Object>, key: string, fallback: boolean): boolean {
  const value: Object = source[key];
  if (typeof value === 'boolean') {
    return value as boolean;
  }
  return fallback;
}

/**
 * Decode a `VpnSettings` blob. Every field falls back to its own default, so
 * a store written by an older build (or a hand-edited one) still loads.
 */
export function decodeVpnSettings(encoded: string): VpnSettings {
  const settings: VpnSettings = new VpnSettings();
  if (encoded.length === 0) {
    return settings;
  }
  try {
    const parsed: Record<string, Object> = JSON.parse(encoded) as Record<string, Object>;
    settings.enableVpn = readBoolean(parsed, 'enableVpn', settings.enableVpn);
    settings.bypassPrivateNetwork =
      readBoolean(parsed, 'bypassPrivateNetwork', settings.bypassPrivateNetwork);
    settings.dnsHijacking = readBoolean(parsed, 'dnsHijacking', settings.dnsHijacking);
    settings.allowBypass = readBoolean(parsed, 'allowBypass', settings.allowBypass);
    settings.allowIpv6 = readBoolean(parsed, 'allowIpv6', settings.allowIpv6);
    settings.systemProxy = readBoolean(parsed, 'systemProxy', settings.systemProxy);

    const stack: Object = parsed['tunStackMode'];
    if (typeof stack === 'string' && isTunStackMode(stack as string)) {
      settings.tunStackMode = stack as string;
    }
    return settings;
  } catch (error) {
    return new VpnSettings();
  }
}

/** The persisted settings as plain data. */
export function vpnSettings(store: VpnSettingsStore): VpnSettings {
  return decodeVpnSettings(store.encoded);
}

/** Persist the whole record; the page always writes a decoded-then-mutated copy. */
export function saveVpnSettings(store: VpnSettingsStore, settings: VpnSettings): void {
  store.encoded = JSON.stringify(settings);
}

/** Decode the package list that travels next to the settings. */
export function decodePackageList(encoded: string): string[] {
  try {
    const values: string[] = JSON.parse(encoded) as string[];
    const packages: string[] = [];
    for (const value of values) {
      if (typeof value === 'string' && value.length > 0) {
        packages.push(value);
      }
    }
    return packages;
  } catch (error) {
    return [];
  }
}

/**
 * Everything `ClashVpnExtension` needs, in the shape it needs it.
 *
 * This is the mirror of Android's "the service reads `ServiceStore` itself":
 * the extension cannot assume it shares a preferences file with the UI, so the
 * caller reads the stores and ships the values across the `Want`.
 */
export class VpnTunnelParameters {
  settings: VpnSettings = new VpnSettings();
  accessControlMode: AccessControlMode = AccessControlMode.AcceptAll;
  accessControlPackages: string[] = [];
  /** Active profile's `Profile.ageSecretKey`; empty when unset. */
  ageSecretKey: string = '';
}

/**
 * `Index.ets` builds the extension's `Want` from this.
 *
 * `parameters['vpnSettings']` is a JSON string rather than a nested object
 * because `Want` parameters are a flat `Record<string, Object>` on the way in
 * and are serialized across the ability boundary.
 */
export function vpnTunnelParameters(): Record<string, Object> {
  const parameters: Record<string, Object> = {};
  parameters['vpnSettings'] = JSON.stringify(vpnSettings(loadVpnSettingsStore()));
  parameters['accessControlMode'] =
    accessControlModeName(loadAccessControlModeStore().mode);
  parameters['accessControlPackages'] =
    JSON.stringify(accessControlPackageList(loadAccessControlStore()));
  return parameters;
}

/**
 * Read `vpnTunnelParameters()` back out of a `Want`.
 *
 * Missing or malformed parameters fall back to the Android defaults instead of
 * failing the tunnel: the debug entry point in `EntryAbility` starts the
 * extension with only `vpnRoutes`, and a TUN with default settings is still a
 * better answer than a refusal.
 */
export function readVpnTunnelParameters(want: Want): VpnTunnelParameters {
  const result: VpnTunnelParameters = new VpnTunnelParameters();
  const parameters: Record<string, Object> | undefined = want.parameters;
  if (parameters === undefined) {
    return result;
  }

  const encodedSettings: Object = parameters['vpnSettings'];
  if (typeof encodedSettings === 'string') {
    result.settings = decodeVpnSettings(encodedSettings as string);
  }

  const mode: Object = parameters['accessControlMode'];
  if (typeof mode === 'string') {
    result.accessControlMode = accessControlModeFromName(mode as string);
  }

  const packages: Object = parameters['accessControlPackages'];
  if (typeof packages === 'string') {
    result.accessControlPackages = decodePackageList(packages as string);
  }

  const ageSecretKey: Object = parameters['ageSecretKey'];
  if (typeof ageSecretKey === 'string') {
    result.ageSecretKey = ageSecretKey as string;
  }

  return result;
}
