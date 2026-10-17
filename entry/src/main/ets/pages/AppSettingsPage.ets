/*
 * App settings screen -- port of ClashMetaForAndroid `AppSettingsDesign.kt` +
 * `AppSettingsActivity.kt` inside the `design_settings_common.xml` scaffold.
 *
 * Android builds a preference screen:
 *   category(behavior)
 *     switch  behavior::autoRestart      restore / auto_restart
 *   category(interface_)
 *     selectableList uiStore::darkMode   brightness_4 / dark_mode
 *     switch  uiStore::hideAppIcon       hide / hide_app_icon_title
 *     switch  uiStore::hideFromRecents   stack / hide_from_recents_title
 *   category(service)
 *     switch  srvStore::dynamicNotification  domain / show_traffic
 *                                        enabled = !running
 *
 * Only `darkMode` has a HarmonyOS counterpart (`ApplicationContext.
 * setColorMode`, which picks the `base/` or `dark/` resource qualifier).
 * The other rows keep Android's layout but are drawn in the disabled state
 * (`Preference.enabled = false` -> 33% opacity) and report `not_ported` when
 * tapped, instead of pretending to work -- a switch that never moves and only
 * answers with a toast reads as a broken control:
 *   autoRestart     PackageManager.setComponentEnabledSetting(RestartReceiver)
 *   hideAppIcon     the same call against the launcher activity-alias
 *   hideFromRecents ActivityManager's recents-exclusion flag
 * `dynamicNotification` drives the foreground-service notification of the
 * in-process mihomo core; this port has no such service, so it has nothing to
 * control either.
 *
 * `Request.ReCreateAllActivities` -- Android recreates every open activity so
 * they pick up the new `uiMode` -- has no counterpart here and needs none:
 * `setColorMode` makes ArkUI re-resolve the `base/` and `dark/` qualifiers in
 * every live page, so the whole stack restyles without being rebuilt.
 */

import { router } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { DarkMode } from '../model/AppSettingsModels';
import { UiStore, applyDarkMode, loadUiStore } from '../backend/UiStore';
import { PreferenceList } from '../view/PreferenceList';
import { PreferenceCategory } from '../view/PreferenceCategory';
import { PreferenceSwitch } from '../view/PreferenceSwitch';
import { showToast } from '../util/Platform';

@Entry
@ComponentV2
struct AppSettingsPage {
  @Local store: UiStore = loadUiStore();

  /** `valuesText` of the dark-mode `selectableList`. */
  private modeText(mode: DarkMode): Resource {
    if (mode === DarkMode.ForceLight) {
      return $r('app.string.always_light');
    }
    if (mode === DarkMode.ForceDark) {
      return $r('app.string.always_dark');
    }
    return $r('app.string.follow_system_android_10');
  }

  private markActive(label: string, active: boolean): string {
    return active ? `${label} \u2713` : label;
  }

  /** Mirrors `ListPopupWindow` + `PopupListAdapter` over `DarkMode.values()`. */
  private darkModeMenu(): MenuElement[] {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const auto: string = manager.getStringSync($r('app.string.follow_system_android_10').id);
    const light: string = manager.getStringSync($r('app.string.always_light').id);
    const dark: string = manager.getStringSync($r('app.string.always_dark').id);

    return [
      {
        value: this.markActive(auto, this.store.darkMode === DarkMode.Auto),
        action: () => {
          this.setDarkMode(DarkMode.Auto);
        }
      },
      {
        value: this.markActive(light, this.store.darkMode === DarkMode.ForceLight),
        action: () => {
          this.setDarkMode(DarkMode.ForceLight);
        }
      },
      {
        value: this.markActive(dark, this.store.darkMode === DarkMode.ForceDark),
        action: () => {
          this.setDarkMode(DarkMode.ForceDark);
        }
      }
    ];
  }

  /** Mirrors `SelectableList.kt`'s `value.set(...)` + `listener.onChanged()`. */
  private setDarkMode(mode: DarkMode): void {
    this.store.darkMode = mode;
    applyDarkMode(getContext(this), mode);
  }

  build() {
    Column() {
      // ---- navigation bar (ActivityBarLayout + common_activity_bar) ----
      Row() {
        Image($r('app.media.ic_baseline_arrow_back'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .onClick(() => {
            router.back();
          })

        // `android:label="@string/app"` on AppSettingsActivity.
        Text($r('app.string.app'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: $r('app.float.item_text_margin') })
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          PreferenceCategory({ text: $r('app.string.behavior') })

          PreferenceSwitch({
            title: $r('app.string.auto_restart'),
            summary: $r('app.string.allow_clash_auto_restart'),
            icon: $r('app.media.ic_baseline_restore'),
            rowEnabled: false,
            onDisabledTap: () => {
              showToast($r('app.string.not_ported'));
            }
          })

          PreferenceCategory({ text: $r('app.string.interface_') })

          // The one preference that is genuinely portable. Android's
          // `selectableList` draws the current value as the row summary and
          // opens a popup list on click; `bindMenu` is the ArkUI equivalent.
          PreferenceList({
            title: $r('app.string.dark_mode'),
            summary: this.modeText(this.store.darkMode),
            icon: $r('app.media.ic_baseline_brightness_4'),
            menuItems: this.darkModeMenu()
          })

          PreferenceSwitch({
            title: $r('app.string.hide_app_icon_title'),
            summary: $r('app.string.hide_app_icon_desc'),
            icon: $r('app.media.ic_baseline_hide'),
            rowEnabled: false,
            onDisabledTap: () => {
              showToast($r('app.string.not_ported'));
            }
          })

          PreferenceSwitch({
            title: $r('app.string.hide_from_recents_title'),
            summary: $r('app.string.hide_from_recents_desc'),
            icon: $r('app.media.ic_baseline_stack'),
            rowEnabled: false,
            onDisabledTap: () => {
              showToast($r('app.string.not_ported'));
            }
          })

          PreferenceCategory({ text: $r('app.string.service') })

          PreferenceSwitch({
            title: $r('app.string.show_traffic'),
            summary: $r('app.string.show_traffic_summary'),
            icon: $r('app.media.ic_baseline_domain'),
            rowEnabled: false,
            onDisabledTap: () => {
              showToast($r('app.string.not_ported'));
            }
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
  }
}
