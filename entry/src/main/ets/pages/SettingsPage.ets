/*
 * Settings screen -- port of ClashMetaForAndroid `design_settings.xml` +
 * `SettingsActivity.kt` + `SettingsDesign.kt`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- ObservableScrollView
 *      +- LinearLayout(vertical, paddingTop = insets.top + toolbar_height)
 *         +- ActionLabel  app            -> AppSettingsActivity
 *         +- ActionLabel  network        -> NetworkSettingsActivity
 *         +- ActionLabel  override       -> OverrideSettingsActivity
 *         +- ActionLabel  meta_features  -> MetaFeatureSettingsActivity
 *   +- ActivityBarLayout
 *      +- common_activity_bar (back + title)
 *
 * App, Network, Override and MetaFeature all have screens now. AppSettingsPage keeps
 * Android's four preference groups and makes dark mode work, while the three
 * preferences that need PackageManager, a launcher alias or the recents API
 * report `not_ported`. NetworkSettingsPage keeps Android's VPN form but every
 * VPN-backed control is disabled, since there is no VpnService to configure.
 * OverrideSettingsPage carries the whole override tree and forwards the subset
 * the external controller accepts; the rows it cannot forward are stored and
 * displayed but reach nothing. MetaFeatureSettingsPage writes the same persist
 * record (the sniffer block and the four `General` switches) and imports geofiles
 * into `filesDir/clash/`; only its two age-key rows still say `not_ported`,
 * because they are built entirely on JNI.
 *
 * The port adds one entry Android does not have -- External Controller --
 * because with no in-process mihomo core the controller address *is* this
 * app's primary setting. It was previously an inline panel on the main
 * screen; moving it here restores Android's "main screen navigates, settings
 * configures" split.
 *
 * That panel is the reason this page has a back handler: while it is open a
 * back tap (the toolbar arrow or the system gesture) cancels the edit and keeps
 * the page, matching the panel's own Cancel button. Leaving without that would
 * drop a half-typed address with no warning. `router.back()` bypasses
 * `onBackPress`, so the arrow calls `requestBack()` instead.
 *
 * HarmonyOS mapping (per hmos-batch-ui-align references):
 *   CoordinatorLayout -> Column          ObservableScrollView -> Scroll
 *   LinearLayout v    -> Column          View.GONE -> omitted from build (if)
 */

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { SettingsRequest } from '../model/SettingsModels';
import { ControllerStore, loadControllerStore } from '../backend/ControllerStore';
import { pinClashToggleShortcut } from '../backend/ShortcutPinner';
import { ActionLabel } from '../view/ActionLabel';

@Entry
@ComponentV2
struct SettingsPage {
  @Local store: ControllerStore = loadControllerStore();
  @Local editing: boolean = false;
  @Local draftUrl: string = '';
  @Local draftSecret: string = '';

  aboutToAppear(): void {
    this.draftUrl = this.store.baseUrl;
    this.draftSecret = this.store.secret;
  }

  /** Mirrors `SettingsDesign.Request`. */
  private request(request: SettingsRequest): void {
    if (request === SettingsRequest.StartApp) {
      // Mirrors SettingsDesign: Request.StartApp -> AppSettingsActivity.
      router.pushUrl({ url: 'pages/AppSettingsPage' });
      return;
    }
    if (request === SettingsRequest.StartNetwork) {
      // Mirrors SettingsDesign: Request.StartNetwork -> NetworkSettingsActivity.
      router.pushUrl({ url: 'pages/NetworkSettingsPage' });
      return;
    }
    if (request === SettingsRequest.StartOverride) {
      // Mirrors SettingsDesign: Request.StartOverride -> OverrideSettingsActivity.
      router.pushUrl({ url: 'pages/OverrideSettingsPage' });
      return;
    }
    // Mirrors SettingsDesign: Request.StartMetaFeature ->
    // MetaFeatureSettingsActivity.
    router.pushUrl({ url: 'pages/MetaFeatureSettingsPage' });
  }

  private beginEdit(): void {
    this.draftUrl = this.store.baseUrl;
    this.draftSecret = this.store.secret;
    this.editing = true;
  }

  private save(): void {
    this.store.baseUrl = this.draftUrl;
    this.store.secret = this.draftSecret;
    this.editing = false;
  }

  /**
   * The toolbar arrow; `router.back()` does not go through `onBackPress`, so
   * the arrow runs the same check rather than dropping the draft.
   */
  private requestBack(): void {
    if (this.editing) {
      // Same as the panel's Cancel button: drop the draft, stay on the page.
      this.editing = false;
      return;
    }
    router.back();
  }

  /** The system back gesture; mirrors `requestBack()`. */
  onBackPress(): boolean {
    if (this.editing) {
      this.editing = false;
      return true;
    }
    return false;
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
            this.requestBack();
          })

        Text($r('app.string.settings'))
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
          // ---- the port's own entry: mihomo external controller ----
          ActionLabel({
            text: $r('app.string.external_controller'),
            subtext: this.store.baseUrl,
            icon: $r('app.media.ic_baseline_domain'),
            onAction: () => {
              this.beginEdit();
            }
          })

          if (this.editing) {
            Column() {
              TextInput({ text: this.draftUrl, placeholder: 'http://192.168.1.1:9090' })
                .width('100%')
                .height(44)
                .fontSize(15)
                .onChange((value: string) => {
                  this.draftUrl = value;
                })

              TextInput({ text: this.draftSecret, placeholder: 'secret' })
                .width('100%')
                .height(44)
                .fontSize(15)
                .margin({ top: 8 })
                .onChange((value: string) => {
                  this.draftSecret = value;
                })

              Row() {
                Button($r('app.string.controller_cancel'))
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(15)
                  .backgroundColor($r('app.color.color_surface'))
                  .onClick(() => {
                    this.editing = false;
                  })

                Button($r('app.string.controller_save'))
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(15)
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.save();
                  })
              }
              .width('100%')
              .margin({ top: 12 })
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.color_surface'))
          }

          // ---- the four navigation targets from design_settings.xml ----
          ActionLabel({
            text: $r('app.string.app'),
            icon: $r('app.media.ic_baseline_settings'),
            onAction: () => {
              this.request(SettingsRequest.StartApp);
            }
          })

          ActionLabel({
            text: $r('app.string.network'),
            icon: $r('app.media.ic_baseline_dns'),
            onAction: () => {
              this.request(SettingsRequest.StartNetwork);
            }
          })

          ActionLabel({
            text: $r('app.string.override'),
            icon: $r('app.media.ic_baseline_extension'),
            onAction: () => {
              this.request(SettingsRequest.StartOverride);
            }
          })

          ActionLabel({
            text: $r('app.string.meta_features'),
            icon: $r('app.media.ic_baseline_meta'),
            onAction: () => {
              this.request(SettingsRequest.StartMetaFeature);
            }
          })

          ActionLabel({
            text: $r('app.string.desktop_shortcut'),
            subtext: $r('app.string.desktop_shortcut_summary'),
            icon: $r('app.media.ic_baseline_add'),
            onAction: () => {
              pinClashToggleShortcut(getContext(this) as common.UIAbilityContext);
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
