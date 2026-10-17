/*
 * The parts of CMFA's `UiStore` that drive the app-settings screen.
 *
 * Ported from ClashMetaForAndroid:
 *   design/src/main/java/com/github/kr328/clash/design/store/UiStore.kt
 *
 * Android keeps these in SharedPreferences under the "ui" preference file;
 * the port persists `darkMode` (Android's `dark_mode` key) with
 * PersistenceV2.
 *
 * Only `darkMode` maps onto a HarmonyOS API, so it is the only value kept
 * here. The other three preferences on that screen are Android platform
 * features with no counterpart on HarmonyOS and are not persisted:
 *   autoRestart     PackageManager.setComponentEnabledSetting(RestartReceiver)
 *                   -- enabling/disabling a manifest component.
 *   hideAppIcon     the same call against MainActivityAlias, i.e. a launcher
 *                   activity-alias. A HarmonyOS launcher icon is fixed by
 *                   module.json5 and has no runtime alias.
 *   hideFromRecents ActivityManager's recents-exclusion flag; HarmonyOS has no
 *                   public recents API.
 */

import { PersistenceV2 } from '@kit.ArkUI';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DarkMode } from '../model/AppSettingsModels';

const DOMAIN = 0x0000;

@ObservedV2
export class UiStore {
  static readonly KEY: string = 'ClashUiStore';

  /** `UiStore.darkMode`, default `DarkMode.Auto`. */
  @Trace darkMode: DarkMode = DarkMode.Auto;
}

/** Load the persisted store, or create the default one on first run. */
export function loadUiStore(): UiStore {
  const store: UiStore | undefined =
    PersistenceV2.connect(UiStore, UiStore.KEY, () => new UiStore());
  return store ?? new UiStore();
}

/**
 * Mirror of `BaseActivity.queryDayNight()`, which picks `AppThemeLight` or
 * `AppThemeDark` before `setContentView`. HarmonyOS resolves the `base/` and
 * `dark/` resource qualifiers from the application colour mode, so the same
 * decision is made once, here, instead of in every page.
 *
 * `COLOR_MODE_NOT_SET` is what `Auto` means: the app inherits the system mode,
 * and the platform keeps following it as the system setting changes.
 */
export function applyDarkMode(context: common.Context, mode: DarkMode): void {
  let colorMode: ConfigurationConstant.ColorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
  if (mode === DarkMode.ForceLight) {
    colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
  } else if (mode === DarkMode.ForceDark) {
    colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
  }

  hilog.info(DOMAIN, 'clashmeta', 'applyDarkMode: %{public}d', colorMode);
  context.getApplicationContext().setColorMode(colorMode);
}
