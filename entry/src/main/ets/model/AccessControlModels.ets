/*
 * Access-control screen models.
 *
 * Android structure:
 *   AppInfo(packageName, label, icon, installTime, updateDate)
 *   AccessControlDesign keeps a mutable Set<String> of selected package names
 *   and filters the list by a search keyword plus `accessControlSystemApp`.
 *
 * HarmonyOS mapping:
 *   BundleInfo/ApplicationInfo -> AccessControlApp
 *   Android Drawable -> Resource
 *   Android Set<String> -> the persisted JSON string owned by
 *   `backend/InstalledApps.ets`; the page keeps a plain string[] for rendering.
*
 * Blocked:
 *   There is no Android PackageManager and no VpnService. Bundle enumeration is
 *   best-effort only and may be denied to a third-party app; callers must
 *   tolerate an empty list. The Android service restart after a selection
 *   change is reported as `not_ported`.
 */

/** Mirrors `design/model/AppInfo.kt`. */
export class AccessControlApp {
  packageName: string = '';
  label: string = '';

  /**
   * `ApplicationInfo.iconResource`. The default is used when the bundle does
   * not expose a usable icon resource.
   */
  icon: Resource = $r('app.media.ic_baseline_apps');

  installTime: number = 0;
  updateTime: number = 0;

  /** Mirrors Android's `ApplicationInfo.FLAG_SYSTEM` check. */
  systemApp: boolean = false;

  /**
   * Whether this row came from the platform (`queryInstalledApps` /
   * `resolvePackage`), as opposed to a package name the user typed or imported
   * that this device could not resolve.
   *
   * Android never has to model this: every row is by construction a real
   * installed package. HarmonyOS denies a third-party app the bundle-list
   * permission, so an unresolved name is a legitimate row here and must be
   * distinguishable -- `resolved === false` rows render as a single dimmed
   * package-name line instead of a label plus package name.
   */
  resolved: boolean = true;
}

/**
 * Mirrors `design/model/AppInfoSort.kt`.
 *
 * `AccessControlMenu` offers all four as a single-choice group; the page keeps
 * the choice in `AccessControlUiStore` and sorts with it.
 */
export enum AccessControlSort {
  Label,
  PackageName,
  InstallTime,
  UpdateTime
}

/**
 * The three access-control values Android keeps in `UiStore`:
 *   accessControlSystemApp  -> showSystem  (`false` hides system apps)
 *   accessControlSort       -> sort
 *   accessControlReverse    -> reverse
 *
 * Persisted by `backend/AccessControlPrefs.ets` as one JSON blob inside a
 * single `@Trace` string, for the reason documented in `ProfileStore`.
 */
export interface AccessControlUi {
  showSystem: boolean;
  sort: AccessControlSort;
  reverse: boolean;
}
