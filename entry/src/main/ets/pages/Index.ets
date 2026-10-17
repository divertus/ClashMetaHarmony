/*
 * Main screen -- port of ClashMetaForAndroid `design_main.xml` + `MainActivity.kt`.
 *
 * Android structure (design/src/main/res/layout/design_main.xml):
 *   CoordinatorLayout
 *   +- ScrollView
 *      +- LinearLayout(vertical, paddingH 30dp, insets top/bottom)
 *         +- LinearLayout(horizontal, minHeight 90dp)   [logo 50dp in 70dp frame | app name Headline6]
 *         +- LargeActionCard  status    (cardBg = running ? started : stopped)
 *         +- LargeActionCard  proxy     (GONE unless running)
 *         +- LargeActionCard  profile
 *         +- LargeActionLabel providers (GONE unless running && hasProviders)
 *         +- LargeActionLabel logs / settings / help / about
 *
 * HarmonyOS mapping applied (per hmos-batch-ui-align mapping references):
 *   CoordinatorLayout -> Column          ScrollView -> Scroll
 *   LinearLayout v/h  -> Column/Row      FrameLayout -> Stack
 *   MaterialCardView  -> styled Row (radius + shadow), not a stretched SVG
 *   View.GONE         -> omitted from build (if), not Visibility.Hidden
 *   dp/sp             -> vp/fp
 *
 * Navigation follows MainActivity's `design.requests.onReceive`: Proxy,
 * Profiles, Providers, Logs, Settings and Help push their pages. About opens
 * the same version dialog as Android; the native core half of that dialog's
 * version string has no HarmonyOS implementation.
 *
 * Paradigm: V2 (@ComponentV2 / @Local / @Param / @Event / @ObservedV2 / @Trace).
 */

import { router, promptAction } from '@kit.ArkUI';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { MainRequest } from '../model/MainModels';
import { MainViewModel } from '../viewmodel/MainViewModel';
import { ControllerStore, loadControllerStore } from '../backend/ControllerStore';
import { applyDarkMode, loadUiStore } from '../backend/UiStore';
import { loadProfileStore, profileActive } from '../backend/ProfileStore';
import { Profile } from '../model/ProfileModels';
import { isVpnRunning } from '../backend/VpnRuntime';
import { vpnTunnelParameters } from '../backend/VpnSettingsStore';
import { startVpnKeepAlive, stopVpnKeepAlive } from '../backend/VpnKeepAlive';
import { LargeActionCard } from '../view/LargeActionCard';
import { LargeActionLabel } from '../view/LargeActionLabel';

@Entry
@ComponentV2
struct Index {
  @Local vm: MainViewModel = new MainViewModel();
  @Local vpnBusy: boolean = false;
  private store: ControllerStore = loadControllerStore();

  aboutToAppear(): void {
    // Mirrors `BaseActivity`'s `queryDayNight()`: the stored DarkMode decides
    // whether the `base/` (light) or `dark/` resource qualifier applies. It is
    // applied here rather than in `EntryAbility.onCreate` because the store is
    // a PersistenceV2 object, and PersistenceV2 has to be connected from the UI
    // side or the value never reaches disk.
    applyDarkMode(getContext(this) as common.UIAbilityContext, loadUiStore().darkMode);
    this.vm.useExternalController(this.store);
    this.vm.useProfileStore(loadProfileStore());
    this.vm.refresh();
  }

  /**
   * The controller address is edited on the settings screen now, so the main
   * screen re-reads the store every time it comes back to the foreground.
   * `aboutToAppear` only fires once and would otherwise keep probing whatever
   * address the page was created with.
   */
  onPageShow(): void {
    this.vm.useExternalController(this.store);
    // Mirrors MainActivity's Event.ProfileChanged -> fetch(): the profile card
    // has to notice a profile activated on the profiles screen.
    this.vm.syncActiveProfile();
    // A force-stop or a failed extension start can leave the UI monitoring a
    // tunnel that no longer exists. The marker is advisory, but it is the only
    // cross-process signal HarmonyOS exposes here.
    if (this.vm.state.running && !isVpnRunning(getContext(this))) {
      this.vm.toggleStatus();
    }
    this.vm.refresh();
  }

  /** `PackageManager.getPackageInfo(...).versionName` equivalent. */
  private aboutVersionName(): string {
    try {
      const info: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      return info.versionName;
    } catch (error) {
      return '';
    }
  }

  /**
   * Mirrors `MainDesign.showAbout(queryAppVersionName())`.
   *
   * Android appends `Bridge.nativeCoreVersion()` after the app version. The
   * embedded core exists now, but `libclashcore.so` does not expose its version
   * yet, so only the app version is available here.
   */
  private showAbout(): void {
    promptAction.showDialog({
      title: $r('app.string.application_name'),
      message: this.aboutVersionName(),
      buttons: [
        {
          text: $r('app.string.close'),
          color: $r('app.color.color_primary')
        }
      ]
    }).catch(() => {
      // The dialog is best-effort; a missing UI surface must not crash.
    });
  }

  private request(request: MainRequest): void {
    // Mirrors MainActivity's `design.requests.onReceive`.
    if (request === MainRequest.ToggleStatus) {
      this.toggleVpn();
      return;
    }
    if (request === MainRequest.OpenSettings) {
      router.pushUrl({ url: 'pages/SettingsPage' });
      return;
    }
    if (request === MainRequest.OpenProxy) {
      // Mirrors MainActivity: Request.OpenProxy -> startActivity(ProxyActivity).
      router.pushUrl({ url: 'pages/ProxyPage' });
      return;
    }
    if (request === MainRequest.OpenProviders) {
      // Mirrors MainActivity: Request.OpenProviders ->
      // startActivity(ProvidersActivity).
      router.pushUrl({ url: 'pages/ProvidersPage' });
      return;
    }
    if (request === MainRequest.OpenProfiles) {
      // Mirrors MainActivity: Request.OpenProfiles ->
      // startActivity(ProfilesActivity).
      router.pushUrl({ url: 'pages/ProfilesPage' });
      return;
    }
    if (request === MainRequest.OpenHelp) {
      // Mirrors MainActivity: Request.OpenHelp -> startActivity(HelpActivity).
      router.pushUrl({ url: 'pages/HelpPage' });
      return;
    }
    if (request === MainRequest.OpenLogs) {
      // Mirrors MainActivity: Request.OpenLogs -> LogcatActivity when the
      // logcat service is running, LogsActivity otherwise. The service has no
      // HarmonyOS equivalent, so this always lands on the file list.
      router.pushUrl({ url: 'pages/LogsPage' });
      return;
    }
    if (request === MainRequest.OpenAbout) {
      this.showAbout();
      return;
    }
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private activeProfile(): Profile | undefined {
    return profileActive(loadProfileStore());
  }

  /**
   * Start the VpnExtensionAbility with the active profile. The system shows the
   * VPN trust dialog on first use; the loop below keeps probing the local
   * controller while the user answers it.
   */
  private async startVpn(): Promise<void> {
    const profile: Profile | undefined = this.activeProfile();
    if (profile === undefined) {
      promptAction.showToast({ message: $r('app.string.not_selected') });
      return;
    }

    // The extension builds its `VpnConfig` from these, so they are read at
    // start time rather than cached: the settings screen may have changed them
    // since the last run.
    const parameters: Record<string, Object> = vpnTunnelParameters();
    parameters['profileUuid'] = profile.uuid;
    parameters['profileSource'] = profile.source;
    parameters['ageSecretKey'] = profile.ageSecretKey;

    const want: Want = {
      bundleName: 'com.example.clashmeta',
      abilityName: 'ClashVpnExtension',
      parameters: parameters
    };
    try {
      await vpnExtension.startVpnExtensionAbility(want);
      startVpnKeepAlive(getContext(this) as common.UIAbilityContext);
    } catch (error) {
      // Already-running is not fatal; the controller probe below decides.
    }

    for (let attempt: number = 0; attempt < 60 && !this.vm.state.running; attempt++) {
      await this.delay(500);
      await this.vm.toggleStatus();
    }
    if (!this.vm.state.running) {
      const message: string = this.vm.lastError.length > 0
        ? this.vm.lastError : 'controller unreachable';
      promptAction.showToast({ message: message });
    }
  }

  private async stopVpn(): Promise<void> {
    if (this.vm.state.running) {
      await this.vm.toggleStatus();
    }
    try {
      await vpnExtension.stopVpnExtensionAbility({
        bundleName: 'com.example.clashmeta',
        abilityName: 'ClashVpnExtension'
      });
      stopVpnKeepAlive(getContext(this) as common.UIAbilityContext);
    } catch (error) {
      // Stopping an already-stopped extension is harmless.
    }
    // Let the platform finish tearing down the previous VpnConnection before a
    // later start can call `protectProcessNet` again.
    await this.delay(1500);
  }

  private async toggleVpn(): Promise<void> {
    if (this.vpnBusy) {
      return;
    }
    this.vpnBusy = true;
    try {
      if (this.vm.state.running) {
        await this.stopVpn();
      } else {
        await this.startVpn();
      }
    } catch (error) {
      promptAction.showToast({ message: `${error}` });
    } finally {
      this.vpnBusy = false;
    }
  }

  build() {
    Scroll() {
      Column() {
        // ---- header: logo + application name ----
        Row() {
          Stack() {
            Image($r('app.media.ic_clash'))
              .width($r('app.float.main_logo_size'))
              .height($r('app.float.main_logo_size'))
              .objectFit(ImageFit.Contain)
          }
          .width($r('app.float.large_item_header_layout_size'))
          .height($r('app.float.large_item_header_layout_size'))

          Text($r('app.string.application_name'))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .constraintSize({ minHeight: $r('app.float.main_top_banner_height') })

        // ---- status card (tap to connect / disconnect) ----
        LargeActionCard({
          text: this.vm.statusTextRes,
          subtext: this.vm.statusSubtextRes,
          icon: this.vm.state.running
            ? $r('app.media.ic_outline_check_circle')
            : $r('app.media.ic_outline_not_interested'),
          cardColor: this.vm.state.running
            ? $r('app.color.color_clash_started')
            : $r('app.color.color_clash_stopped'),
          // `design_main.xml` pins this card to `AppThemeDark`, so its icon
          // and both lines stay white whichever theme the app is in.
          contentColor: Color.White,
          onAction: () => {
            this.request(MainRequest.ToggleStatus);
          }
        })
          .margin({
            top: $r('app.float.main_card_margin_vertical'),
            bottom: $r('app.float.main_card_margin_vertical')
          })

        // ---- proxy card (GONE unless connected) ----
        if (this.vm.state.running) {
          LargeActionCard({
            text: $r('app.string.proxy'),
            subtext: this.vm.modeRes,
            icon: $r('app.media.ic_baseline_apps'),
            cardColor: $r('app.color.color_surface'),
            onAction: () => {
              this.request(MainRequest.OpenProxy);
            }
          })
            .margin({
              top: $r('app.float.main_card_margin_vertical'),
              bottom: $r('app.float.main_card_margin_vertical')
            })
        }

        // ---- profile card ----
        LargeActionCard({
          text: $r('app.string.profile'),
          subtext: this.vm.profileRes,
          icon: $r('app.media.ic_baseline_view_list'),
          cardColor: $r('app.color.color_surface'),
          onAction: () => {
            this.request(MainRequest.OpenProfiles);
          }
        })
          .margin({
            top: $r('app.float.main_card_margin_vertical'),
            bottom: $r('app.float.main_card_margin_vertical')
          })

        // ---- providers label (GONE unless connected && hasProviders) ----
        if (this.vm.state.running && this.vm.state.hasProviders) {
          LargeActionLabel({
            text: $r('app.string.providers'),
            icon: $r('app.media.ic_baseline_swap_vertical_circle'),
            onAction: () => {
              this.request(MainRequest.OpenProviders);
            }
          })
            .margin({
              top: $r('app.float.main_label_margin_vertical'),
              bottom: $r('app.float.main_label_margin_vertical')
            })
        }

        // ---- navigation labels ----
        LargeActionLabel({
          text: $r('app.string.logs'),
          icon: $r('app.media.ic_baseline_assignment'),
          onAction: () => {
            this.request(MainRequest.OpenLogs);
          }
        })
          .margin({
            top: $r('app.float.main_label_margin_vertical'),
            bottom: $r('app.float.main_label_margin_vertical')
          })

        LargeActionLabel({
          text: $r('app.string.settings'),
          icon: $r('app.media.ic_baseline_settings'),
          onAction: () => {
            this.request(MainRequest.OpenSettings);
          }
        })
          .margin({
            top: $r('app.float.main_label_margin_vertical'),
            bottom: $r('app.float.main_label_margin_vertical')
          })

        LargeActionLabel({
          text: $r('app.string.help'),
          icon: $r('app.media.ic_baseline_help_center'),
          onAction: () => {
            this.request(MainRequest.OpenHelp);
          }
        })
          .margin({
            top: $r('app.float.main_label_margin_vertical'),
            bottom: $r('app.float.main_label_margin_vertical')
          })

        LargeActionLabel({
          text: $r('app.string.about'),
          icon: $r('app.media.ic_baseline_info'),
          onAction: () => {
            this.request(MainRequest.OpenAbout);
          }
        })
          .margin({
            top: $r('app.float.main_label_margin_vertical'),
            bottom: $r('app.float.main_label_margin_vertical')
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({
        left: $r('app.float.main_padding_horizontal'),
        right: $r('app.float.main_padding_horizontal')
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    // Android paints `android:windowBackground` (color_light_background /
    // color_dark_background); the other ported screens set the same colour on
    // their root, so the main screen does too.
    .backgroundColor($r('app.color.color_background'))
  }
}
