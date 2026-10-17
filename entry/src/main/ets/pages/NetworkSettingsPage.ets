/*
 * Network settings screen -- port of ClashMetaForAndroid `NetworkSettingsDesign.kt`
 * + `NetworkSettingsActivity.kt` inside the `design_settings_common.xml` scaffold.
 *
 * Android builds a preference screen:
 *   switch  uiStore::enableVpn             vpn_lock / route_system_traffic
 *   category(vpn_service_options)
 *     switch  srvStore::bypassPrivateNetwork
 *     switch  srvStore::dnsHijacking
 *     switch  srvStore::allowBypass
 *     switch  srvStore::allowIpv6
 *     switch  srvStore::systemProxy        (only when SDK_INT >= 29)
 *     selectableList srvStore::tunStackMode
 *     selectableList srvStore::accessControlMode
 *     clickable access_control_packages -> AccessControlActivity
 *
 * Every one of those rows is now real, including the VPN-backed ones: the port
 * carries a mihomo core (`libclash.so`, built for OHOS arm64) and a
 * `VpnExtensionAbility` that builds its `VpnConfig` from exactly these values.
 * See `vpnextension/ClashVpnExtension.ets` for the mapping and
 * `backend/VpnSettingsStore.ets` for how the values reach it.
 *
 * Three Android behaviours are deliberately not reproduced, and the reasons
 * are platform facts rather than unfinished work:
 *
 *   `systemProxy` -- Android's `Builder.setHttpProxy()` attaches an HTTP proxy
 *     to the VPN, and the *system* then uses it for every app. HarmonyOS's
 *     `VpnConfig` has no proxy field. `connection.setAppHttpProxy()` exists but
 *     is application-scoped: it would only proxy this app's own requests, which
 *     is not what the switch promises. The value is still stored and shown (it
 *     is part of the profile of settings the extension receives), and the row
 *     says so in its summary instead of pretending.
 *
 *   `allowBypass` -- Android's `Builder.allowBypass()` lets individual apps opt
 *     out of the tunnel. `VpnConfig` has `trustedApplications` /
 *     `blockedApplications`, which express "which apps are in the tunnel", not
 *     "which apps may leave it"; there is no allow-bypass equivalent. Same
 *     handling as `systemProxy`.
 *
 *   `running` -- Android disables the whole group while the tunnel is up and
 *     shows an indefinite `options_unavailable` toast. The port has no
 *     always-on status to read here (the VPN extension is started from the main
 *     screen), so the group stays editable.
 *
 * `access_control_packages` matches Android in one respect worth keeping: it is
 * *not* in `vpnDependencies`, so it stays enabled even when the master switch
 * is off. `access_control_mode` is in `vpnDependencies` on Android, but here it
 * is the same store `AccessControlPage` writes, and that page is reachable from
 * the main screen too, so the row is not gated.
 */

import { router } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import {
  ACCESS_CONTROL_MODES,
  AccessControlMode,
  TUN_STACK_MODES,
  VpnSettings,
  accessControlModeText,
  tunStackModeText
} from '../model/NetworkSettingsModels';
import { AccessControlModeStore, loadAccessControlModeStore } from '../backend/AccessControlPrefs';
import {
  VpnSettingsStore,
  loadVpnSettingsStore,
  saveVpnSettings,
  vpnSettings
} from '../backend/VpnSettingsStore';
import { ActionLabel } from '../view/ActionLabel';
import { PreferenceCategory } from '../view/PreferenceCategory';
import { PreferenceList } from '../view/PreferenceList';
import { PreferenceSwitch } from '../view/PreferenceSwitch';

@Entry
@ComponentV2
struct NetworkSettingsPage {
  /** `UiStore.enableVpn` + the six `ServiceStore` fields, persisted as one blob. */
  @Local vpnStore: VpnSettingsStore = loadVpnSettingsStore();
  @Local settings: VpnSettings = new VpnSettings();

  /** `ServiceStore.accessControlMode`, persisted by the port. */
  @Local modeStore: AccessControlModeStore = loadAccessControlModeStore();
  @Local accessControlMode: AccessControlMode = AccessControlMode.AcceptAll;

  aboutToAppear(): void {
    this.settings = vpnSettings(this.vpnStore);
    this.accessControlMode = this.modeStore.mode;
  }

  /**
   * The one write path: decode, mutate the copy, persist, and republish it so
   * every row that depends on `settings` re-renders.
   */
  private update(mutate: (settings: VpnSettings) => void): void {
    const next: VpnSettings = vpnSettings(this.vpnStore);
    mutate(next);
    saveVpnSettings(this.vpnStore, next);
    this.settings = next;
  }

  /**
   * A summary with the platform note appended, for the two switches whose
   * Android behaviour has no HarmonyOS equivalent. The value is still real and
   * still saved; the row just does not claim an effect it cannot have.
   */
  private annotatedSummary(summary: Resource): string {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const text: string = manager.getStringSync(summary.id);
    const note: string = manager.getStringSync($r('app.string.vpn_option_no_effect').id);
    return `${text} (${note})`;
  }

  /** Marks the active entry of a single-choice menu, as the popup list did. */
  private markActive(label: string, active: boolean): string {
    return active ? `${label} \u2713` : label;
  }

  /** Mirrors `selectableList(values = AccessControlMode.values())`. */
  private accessControlModeMenu(): MenuElement[] {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const items: MenuElement[] = [];

    for (const mode of ACCESS_CONTROL_MODES) {
      const label: string = manager.getStringSync(accessControlModeText(mode).id);
      items.push({
        value: this.markActive(label, this.accessControlMode === mode),
        action: () => {
          this.setAccessControlMode(mode);
        }
      });
    }
    return items;
  }

  /** Mirrors `SelectableList.kt`'s `value.set(...)` + `listener.onChanged()`. */
  private setAccessControlMode(mode: AccessControlMode): void {
    this.accessControlMode = mode;
    this.modeStore.mode = mode;
  }

  /** Mirrors `selectableList(values = arrayOf("system", "gvisor", "mixed", "mips"))`. */
  private tunStackMenu(): MenuElement[] {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const items: MenuElement[] = [];

    for (const mode of TUN_STACK_MODES) {
      const label: string = manager.getStringSync(tunStackModeText(mode).id);
      items.push({
        value: this.markActive(label, this.settings.tunStackMode === mode),
        action: () => {
          this.update((settings: VpnSettings) => {
            settings.tunStackMode = mode;
          });
        }
      });
    }
    return items;
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

        // `android:label="@string/network"` on NetworkSettingsActivity.
        Text($r('app.string.network'))
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
          // The master switch: `uiStore::enableVpn`, the only row with an icon.
          // Its listener is what enables the rows below, so `rowEnabled` on
          // every child reads this same value.
          PreferenceSwitch({
            title: $r('app.string.route_system_traffic'),
            summary: $r('app.string.routing_via_vpn_service'),
            icon: $r('app.media.ic_baseline_vpn_lock'),
            checked: this.settings.enableVpn,
            onAction: () => {
              this.update((settings: VpnSettings) => {
                settings.enableVpn = !settings.enableVpn;
              });
            }
          })

          PreferenceCategory({ text: $r('app.string.vpn_service_options') })

          PreferenceSwitch({
            title: $r('app.string.bypass_private_network'),
            summary: $r('app.string.bypass_private_network_summary'),
            showIcon: false,
            checked: this.settings.bypassPrivateNetwork,
            rowEnabled: this.settings.enableVpn,
            onAction: () => {
              this.update((settings: VpnSettings) => {
                settings.bypassPrivateNetwork = !settings.bypassPrivateNetwork;
              });
            }
          })

          PreferenceSwitch({
            title: $r('app.string.dns_hijacking'),
            summary: $r('app.string.dns_hijacking_summary'),
            showIcon: false,
            checked: this.settings.dnsHijacking,
            rowEnabled: this.settings.enableVpn,
            onAction: () => {
              this.update((settings: VpnSettings) => {
                settings.dnsHijacking = !settings.dnsHijacking;
              });
            }
          })

          // No HarmonyOS equivalent for `Builder.allowBypass()`; the summary
          // says so. See the file header.
          PreferenceSwitch({
            title: $r('app.string.allow_bypass'),
            summary: $r('app.string.allow_bypass_harmony_summary'),
            showIcon: false,
            checked: this.settings.allowBypass,
            rowEnabled: this.settings.enableVpn,
            onAction: () => {
              this.update((settings: VpnSettings) => {
                settings.allowBypass = !settings.allowBypass;
              });
            }
          })

          PreferenceSwitch({
            title: $r('app.string.allow_ipv6'),
            summary: $r('app.string.allow_ipv6_summary'),
            showIcon: false,
            checked: this.settings.allowIpv6,
            rowEnabled: this.settings.enableVpn,
            onAction: () => {
              this.update((settings: VpnSettings) => {
                settings.allowIpv6 = !settings.allowIpv6;
              });
            }
          })

          // Android adds this one only when `Build.VERSION.SDK_INT >= 29`.
          // `VpnConfig` has no proxy field, so the row is honest about it.
          PreferenceSwitch({
            title: $r('app.string.system_proxy'),
            summary: $r('app.string.system_proxy_harmony_summary'),
            showIcon: false,
            checked: this.settings.systemProxy,
            rowEnabled: this.settings.enableVpn,
            onAction: () => {
              this.update((settings: VpnSettings) => {
                settings.systemProxy = !settings.systemProxy;
              });
            }
          })

          PreferenceList({
            title: $r('app.string.tun_stack_mode'),
            summary: tunStackModeText(this.settings.tunStackMode),
            showIcon: false,
            rowEnabled: this.settings.enableVpn,
            menuItems: this.tunStackMenu()
          })

          PreferenceList({
            title: $r('app.string.access_control_mode'),
            summary: accessControlModeText(this.accessControlMode),
            showIcon: false,
            menuItems: this.accessControlModeMenu()
          })

          // Not in `vpnDependencies` on Android either, so it stays enabled.
          ActionLabel({
            text: $r('app.string.access_control_packages'),
            subtext: $r('app.string.access_control_packages_summary'),
            showIcon: false,
            onAction: () => {
              // Mirrors Request.StartAccessControlList -> AccessControlActivity.
              router.pushUrl({ url: 'pages/AccessControlPage' });
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
