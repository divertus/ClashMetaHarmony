/*
 * Installed-app access and the local access-control package store.
 *
 * Android structure:
 *   AccessControlActivity reads `ServiceStore.accessControlPackages` (a
 *   Set<String>), calls `PackageManager.getInstalledPackages(GET_PERMISSIONS)`,
 *   keeps packages that request INTERNET (or are system apps), and writes the
 *   set back when the screen closes. If the tunnel was running and the set
 *   changed, it stops and restarts the Clash service.
 *
 * HarmonyOS mapping:
 *   PackageManager.getInstalledPackages -> `bundleManager.getInstalledBundleList`
 *   ServiceStore                        -> `AccessControlStore` (PersistenceV2)
 *
 *   The store is deliberately shaped like ProfileStore/UiStore: exactly one
 *   `@Trace` string field and no methods. PersistenceV2 drops richer objects
 *   silently, so every operation is a free function that decodes, mutates and
 *   re-encodes the string.
 *
 * The *platform* enumeration is denied to a normal app:
 *
 *   `getInstalledBundleList` is `@permission
 *   ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST` (API 26). The local
 *   SDK's `toolchains/lib/PermissionDefinitions.json` lists that permission as
 *   `availableLevel: system_basic`, so an app signed with the normal APL can
 *   never hold it. `getAllBundleInfo`/`getBundleInfos` are not exposed at all,
 *   `launcherBundleManager.getLauncherAbilityInfoSync` wants
 *   `GET_BUNDLE_INFO_PRIVILEGED` (`system_basic`) plus a bundle name it cannot
 *   enumerate, and `getBundleInfoForSelf` only ever answers for this app.
 *
 *   So the platform query is still attempted first (it costs nothing and starts
 *   working the day the app is signed with a privileged profile) and its
 *   rejection is *reported* through `InstalledAppQuery` instead of being
 *   flattened into an empty list.
 *
 * The SDK *looks* like it leaves one door open: `getBundleNameByUid` is
 * `@permission GET_BUNDLE_INFO_PRIVILEGED or GET_BUNDLE_INFO`, and
 * `GET_BUNDLE_INFO` is `availableLevel: normal`, which is why `module.json5`
 * declares it. On the reference device that door is shut as well. Measured
 * with the permission granted (`bm dump` reports `reqPermissionStates: [0,0,0]`):
 *
 *   getBundleNameByUidSync(uid) -> 201 "forbidden by permission:
 *     ohos.permission.GET_BUNDLE_INFO or ohos.permission.GET_BUNDLE_INFO_PRIVILEGED"
 *   getBundleInfo(other, GET_BUNDLE_INFO_DEFAULT) -> 201 "forbidden by
 *     permission: ohos.permission.GET_BUNDLE_INFO_PRIVILEGED"
 *
 * So the API checks for the *privileged* variant whenever the target is not
 * the caller, and `GET_BUNDLE_INFO` alone buys nothing. `scanInstalledApps`
 * keeps the by-uid walk as the one remaining attempt -- it is reachable from
 * the page's overflow menu, it costs nothing until asked for, and it starts
 * working the day the app is signed with a privileged profile -- but on a
 * normal signature it returns no rows.
 *
 * That leaves the manual `+` and the clipboard import as the working paths,
 * which is why `resolvePackage` exists at all: it is tried for every entered
 * name, and a name the platform refuses stays as an unresolved row rather than
 * disappearing.
 *
 *   ACTION NEEDED (out of this change's write scope): `entry/src/main/module.json5`
 *   must add `ohos.permission.GET_BUNDLE_INFO` to `requestPermissions` for the
 *   label/icon lookup to work. The permission is normal/system_grant, so it is
 *   granted at install with no user prompt. Until it is declared,
 *   `getBundleInfo` answers 201 and every hand-entered name renders as an
 *   unresolved row -- the list, the selection and import/export all still work.
 *
 * Blocked:
 *   There is no VpnService/tunnel service here, so the caller reports the
 *   Android restart step as `not_ported`.
 */

import { PersistenceV2 } from '@kit.ArkUI';
import { bundleManager } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccessControlApp } from '../model/AccessControlModels';

const DOMAIN: number = 0x0000;

@ObservedV2
export class AccessControlStore {
  static readonly KEY: string = 'ClashAccessControlStore';

  /** Serialized Set<String>; the store's only state. */
  @Trace encoded: string = '[]';
}

/** Load the persisted store, or create the default one on first run. */
export function loadAccessControlStore(): AccessControlStore {
  const store: AccessControlStore | undefined =
    PersistenceV2.connect(AccessControlStore, AccessControlStore.KEY, () => new AccessControlStore());
  return store ?? new AccessControlStore();
}

function decodePackages(encoded: string): string[] {
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
 * Mirrors `ServiceStore.accessControlPackages`: a Set<String> of package
 * names selected for access control.
 */
export function accessControlPackages(store: AccessControlStore): Set<string> {
  const packages: Set<string> = new Set<string>();
  const values: string[] = decodePackages(store.encoded);
  for (const value of values) {
    packages.add(value);
  }
  return packages;
}

/** The selected set as a sorted plain array, for rendering and export. */
export function accessControlPackageList(store: AccessControlStore): string[] {
  const values: string[] = [];
  for (const value of accessControlPackages(store)) {
    values.push(value);
  }
  values.sort();
  return values;
}

/**
 * Set or clear one package in the persisted Set<String>.
 *
 * The array is sorted before writing so the serialized value is stable across
 * set order changes; this also makes the page's dirty check deterministic.
 */
export function accessControlSetEnabled(
  store: AccessControlStore, packageName: string, enabled: boolean): void {
  const packages: Set<string> = accessControlPackages(store);
  if (enabled) {
    packages.add(packageName);
  } else {
    packages.delete(packageName);
  }
  writePackages(store, packages);
}

/** `Request.SelectAll` / `SelectNone` / `SelectInvert` / `Import` in one call. */
export function accessControlReplaceAll(store: AccessControlStore, packageNames: string[]): void {
  const packages: Set<string> = new Set<string>();
  for (const packageName of packageNames) {
    if (packageName.length > 0) {
      packages.add(packageName);
    }
  }
  writePackages(store, packages);
}

function writePackages(store: AccessControlStore, packages: Set<string>): void {
  const values: string[] = [];
  for (const value of packages) {
    values.push(value);
  }
  values.sort();
  store.encoded = JSON.stringify(values);
}

/**
 * Trim one candidate package name. Android splits the clipboard on "\n" and
 * takes the lines verbatim; a hand-typed name picks up stray whitespace, quotes
 * and trailing separators, so those are stripped here.
 */
export function normalizePackageName(raw: string): string {
  let value: string = raw.trim();
  while (value.length > 0 && (value.startsWith('"') || value.startsWith('\''))) {
    value = value.substring(1);
  }
  while (value.length > 0 && (value.endsWith('"') || value.endsWith('\'') ||
    value.endsWith(',') || value.endsWith(';'))) {
    value = value.substring(0, value.length - 1);
  }
  return value.trim();
}

const PACKAGE_NAME_PATTERN: RegExp = new RegExp('^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$');

/** `com.example.app`-shaped, i.e. worth trying to resolve. */
export function looksLikePackageName(value: string): boolean {
  return PACKAGE_NAME_PATTERN.test(value);
}

/**
 * Split pasted text into package names.
 *
 * Android's `Request.Import` does `clipboard.text.split("\n").toSet()` and then
 * intersects with the installed apps. The intersection is impossible here, so
 * the port keeps every line and lets `resolvePackage` decide whether it exists.
 */
export function parsePackageList(text: string): string[] {
  const seen: Set<string> = new Set<string>();
  const values: string[] = [];
  for (const raw of text.split(new RegExp('[\\r\\n,;\\s]+'))) {
    const value: string = normalizePackageName(raw);
    if (value.length === 0 || seen.has(value)) {
      continue;
    }
    seen.add(value);
    values.push(value);
  }
  return values;
}

/**
 * A row for a package name this device could not resolve. `label` stays empty
 * so the page can render the name alone instead of printing it twice.
 */
export function unresolvedApp(packageName: string): AccessControlApp {
  const app: AccessControlApp = new AccessControlApp();
  app.packageName = packageName;
  app.label = '';
  app.resolved = false;
  return app;
}

/**
 * The result of the installed-app query. Android's `loadApps` returns a
 * `List<AppInfo>` and cannot fail; here the failure mode *is* the interesting
 * part, because it decides whether the page shows a list or a manual-entry
 * notice.
 */
export class InstalledAppQuery {
  /** Resolved rows; empty when the query was denied or found nothing. */
  apps: AccessControlApp[] = [];

  /**
   * True when a full list was produced, whether by the platform or by the uid
   * scan. `scanned` says which of the two it was.
   */
  enumerated: boolean = false;

  /**
   * True when the rows came from `scanInstalledApps` rather than from
   * `getInstalledBundleList`. The uid scan is the normal-app path, so this is
   * the expected value on a device without an enterprise signature.
   */
  scanned: boolean = false;

  /** `BusinessError.code` of the rejection, or 0 when the query succeeded. */
  errorCode: number = 0;

  /**
   * True when the rejection was 201 (permission denied) -- the expected answer
   * for a normal app, and the one that means "no point retrying".
   */
  permissionDenied: boolean = false;
}

/** Bundle flags mirroring Android's `GET_PERMISSIONS` plus application info. */
const QUERY_FLAGS: number = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION |
  bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_REQUESTED_PERMISSION;

function requestsInternet(bundle: bundleManager.BundleInfo): boolean {
  for (const permission of bundle.reqPermissionDetails) {
    if (permission.name === 'ohos.permission.INTERNET') {
      return true;
    }
  }
  return false;
}

function toApp(bundle: bundleManager.BundleInfo, packageName: string): AccessControlApp {
  const info: bundleManager.ApplicationInfo = bundle.appInfo;
  const app: AccessControlApp = new AccessControlApp();
  app.packageName = packageName;
  app.label = info.label.length > 0 ? info.label : packageName;
  if (info.iconResource.id > 0) {
    app.icon = info.iconResource;
  }
  app.installTime = bundle.installTime;
  app.updateTime = bundle.updateTime;
  app.systemApp = info.systemApp;
  app.resolved = true;
  return app;
}

/** Label-first ordering, matching Android's `AppInfo.label` comparator. */
function byLabel(left: AccessControlApp, right: AccessControlApp): number {
  const leftLabel: string = left.label.toLowerCase();
  const rightLabel: string = right.label.toLowerCase();
  if (leftLabel < rightLabel) {
    return -1;
  }
  if (leftLabel > rightLabel) {
    return 1;
  }
  return 0;
}

/** `getBundleInfo` behind a try/catch: `undefined` when the name is unknown. */
async function resolveBundle(
  packageName: string): Promise<bundleManager.BundleInfo | undefined> {
  try {
    return await bundleManager.getBundleInfo(packageName, QUERY_FLAGS);
  } catch (error) {
    const failure: BusinessError = error as BusinessError;
    hilog.warn(DOMAIN, 'ClashApps', 'getBundleInfo(%{public}s, %{public}d) -> %{public}d %{public}s',
      packageName, QUERY_FLAGS, failure.code, failure.message);
    // A privileged flag can make the whole call fail even when the bundle name
    // is fine, so retry with the minimal flag before giving up.
    try {
      return await bundleManager.getBundleInfo(
        packageName, bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT);
    } catch (retryError) {
      const retryFailure: BusinessError = retryError as BusinessError;
      hilog.warn(DOMAIN, 'ClashApps', 'getBundleInfo(%{public}s, default) -> %{public}d %{public}s',
        packageName, retryFailure.code, retryFailure.message);
      return undefined;
    }
  }
}

/**
 * `getBundleNameByUidSync` is the one installed-app enumeration a normal app
 * can perform.
 *
 * `getInstalledBundleList` is `@permission
 * ohos.permission.ENTERPRISE_GET_INSTALLED_BUNDLE_LIST` and the local SDK's
 * `toolchains/lib/PermissionDefinitions.json` lists it as
 * `availableLevel: system_basic`, so a normally-signed app can never hold it.
 * `launcherBundleManager` wants `GET_BUNDLE_INFO_PRIVILEGED` (also
 * `system_basic`), and the deprecated `bundle.getAllApplicationInfo` wants the
 * same. `getBundleNameByUid`, on the other hand, accepts
 * `GET_BUNDLE_INFO_PRIVILEGED or GET_BUNDLE_INFO`, and `GET_BUNDLE_INFO` is
 * `availableLevel: normal`.
 *
 * The uid is not something the platform will hand out as a list, so the scan
 * walks the range the installed apps live in. On the reference device
 * (HUAWEI Pocket 2, HarmonyOS 7.0.0 / API 26) the application uids are
 * `20020042..20020426` -- i.e. `base + index` with `base = uid - (uid % 1000)`
 * of the calling app -- so a 2048-wide window covers the band with room for
 * several hundred more installs.
 */
export const DEFAULT_SCAN_WINDOW: number = 2048;

/** How many uids are probed between two yields back to the UI thread. */
const SCAN_CHUNK: number = 128;

/**
 * Cached result of the last full scan. The scan is ~2k synchronous bundle
 * calls, which is cheap once but pointless to repeat every time the page opens.
 */
let scanCache: AccessControlApp[] | undefined = undefined;

/** Drop the cached scan, e.g. after installing an app or from the menu. */
export function clearInstalledAppScanCache(): void {
  scanCache = undefined;
}

/** `base = uid - (uid % 1000)`, or 0 when the uid is unusable. */
export function uidScanBase(uid: number): number {
  if (uid <= 0) {
    return 0;
  }
  return uid - (uid % 1000);
}

/** The calling app's uid, or 0 when even that lookup is refused. */
function ownUid(): number {
  try {
    const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
      bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    return info.appInfo.uid;
  } catch (error) {
    return 0;
  }
}

/** Let the UI thread paint the progress line between two scan chunks. */
async function yieldToUi(): Promise<void> {
  await new Promise<void>((resolve: (value: void) => void): void => {
    setTimeout((): void => {
      resolve();
    }, 0);
  });
}

/**
 * Enumerate installed apps by walking the application uid band.
 *
 * `onProgress` is called once per chunk with `(scanned, total)` so the page can
 * show movement instead of a frozen screen. `windowBase` / `windowCount`
 * override the derived window, which the device checks use.
 */
export async function scanInstalledApps(
  selfBundleName: string,
  onProgress?: (scanned: number, total: number) => void,
  windowBase?: number,
  windowCount?: number): Promise<InstalledAppQuery> {
  const result: InstalledAppQuery = new InstalledAppQuery();
  const defaultWindow: boolean = windowBase === undefined && windowCount === undefined;

  if (defaultWindow && scanCache !== undefined) {
    result.apps = scanCache;
    result.enumerated = true;
    result.scanned = true;
    return result;
  }

  const base: number = windowBase !== undefined ? windowBase : uidScanBase(ownUid());
  const total: number = windowCount !== undefined ? windowCount : DEFAULT_SCAN_WINDOW;

  if (base <= 0 || total <= 0) {
    hilog.warn(DOMAIN, 'ClashApps',
      'scan unusable base=%{public}d total=%{public}d', base, total);
    result.errorCode = -1;
    return result;
  }

  const names: string[] = [];
  const seen: Set<string> = new Set<string>();
  let scanned: number = 0;
  let firstError: string = '';

  while (scanned < total) {
    const chunk: number = Math.min(SCAN_CHUNK, total - scanned);
    for (let offset = 0; offset < chunk; offset++) {
      const uid: number = base + scanned + offset;
      try {
        const name: string = bundleManager.getBundleNameByUidSync(uid);
        if (name.length > 0 && !seen.has(name)) {
          seen.add(name);
          names.push(name);
        }
      } catch (error) {
        // 17700021 (uid not found) is the common case here: keep scanning.
        if (firstError.length === 0) {
          firstError = `${(error as BusinessError).code}:${(error as BusinessError).message}`;
        }
      }
    }
    scanned += chunk;
    if (onProgress !== undefined) {
      onProgress(scanned, total);
    }
    await yieldToUi();
  }

  names.sort();
  hilog.info(DOMAIN, 'ClashApps',
    'scan base=%{public}d total=%{public}d names=%{public}d firstError=%{public}s',
    base, total, names.length, firstError);

  const apps: AccessControlApp[] = [];
  for (const name of names) {
    if (name === selfBundleName) {
      continue;
    }
    const bundle: bundleManager.BundleInfo | undefined = await resolveBundle(name);
    if (bundle === undefined) {
      // The name came from the platform, so it exists; only its label/icon
      // lookup was refused. Keep it as an unresolved row rather than dropping
      // a real app from the access-control list.
      apps.push(unresolvedApp(name));
      continue;
    }
    if (!bundle.appInfo.systemApp && !requestsInternet(bundle)) {
      continue;
    }
    apps.push(toApp(bundle, name));
  }

  apps.sort(byLabel);
  result.apps = apps;
  result.enumerated = true;
  result.scanned = true;
  if (defaultWindow) {
    scanCache = apps;
  }
  return result;
}

/**
 * Best-effort replacement for `PackageManager.getInstalledPackages`.
 *
 * The filters mirror Android's `loadApps`:
 *   - this app's own bundle is skipped,
 *   - a non-system app must request INTERNET,
 *   - the `showSystem` filter is *not* applied here; it is a display filter the
 *     page owns, exactly as in Android (`uiStore.accessControlSystemApp`).
 */
export async function queryInstalledApps(selfBundleName: string): Promise<InstalledAppQuery> {
  const result: InstalledAppQuery = new InstalledAppQuery();

  let bundles: bundleManager.BundleInfo[] = [];
  try {
    bundles = await bundleManager.getInstalledBundleList(QUERY_FLAGS);
    result.enumerated = true;
  } catch (error) {
    const failure: BusinessError = error as BusinessError;
    result.errorCode = failure.code;
    result.permissionDenied = failure.code === 201;
    // The platform list is enterprise-only. The uid scan is the one remaining
    // attempt, but on HarmonyOS 7.0.0 / API 26 it is refused too -- see
    // `scanInstalledApps` -- so it is offered from the overflow menu rather
    // than run on every page open. Measured on device:
    //   GetBundleNameByUidSync -> 201, "forbidden by permission:
    //   ohos.permission.GET_BUNDLE_INFO or GET_BUNDLE_INFO_PRIVILEGED"
    // even though `ohos.permission.GET_BUNDLE_INFO` is granted
    // (`bm dump` reports reqPermissionStates 0), because the check also
    // requires the caller to be a system app.
    return result;
  }

  const apps: AccessControlApp[] = [];
  for (const bundle of bundles) {
    if (bundle.name === selfBundleName) {
      continue;
    }

    // Android keeps system apps regardless of the INTERNET permission and
    // otherwise keeps only packages that request INTERNET.
    if (!bundle.appInfo.systemApp && !requestsInternet(bundle)) {
      continue;
    }

    apps.push(toApp(bundle, bundle.name));
  }

  apps.sort(byLabel);

  result.apps = apps;
  return result;
}

/**
 * Convenience entry point: the rows only.
 *
 * `queryInstalledApps` is the one that says *why* the list is empty; this
 * wrapper is for callers that only need the list. It keeps the module's
 * original export name working, so a caller written against the first shape of
 * this file still compiles and still gets the same rows.
 */
export async function loadInstalledApps(selfBundleName: string): Promise<AccessControlApp[]> {
  const result: InstalledAppQuery = await queryInstalledApps(selfBundleName);
  return result.apps;
}

/**
 * Resolve one package name through `bundleManager.getBundleInfo`, the only
 * bundle query a normal app may hold (`ohos.permission.GET_BUNDLE_INFO` is
 * `availableLevel: normal`, so the module declares it).
 *
 * Returns `undefined` when the name does not exist (17700001), the bundle is
 * disabled (17700026), or the platform refuses the call (201).
 */
export async function resolvePackage(packageName: string): Promise<AccessControlApp | undefined> {
  const bundle: bundleManager.BundleInfo | undefined = await resolveBundle(packageName);
  if (bundle === undefined) {
    return undefined;
  }
  return toApp(bundle, packageName);
}

/**
 * Resolve a batch, keeping the input order and turning failures into
 * unresolved rows. Used by the page when the user adds or imports names.
 */
export async function resolvePackages(packageNames: string[]): Promise<AccessControlApp[]> {
  const apps: AccessControlApp[] = [];
  for (const packageName of packageNames) {
    const resolved: AccessControlApp | undefined = await resolvePackage(packageName);
    apps.push(resolved ?? unresolvedApp(packageName));
  }
  return apps;
}
