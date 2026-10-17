/*
 * "Application Broken" screen -- port of ClashMetaForAndroid
 * `design_settings_common.xml` + `ApkBrokenActivity.kt` + `ApkBrokenDesign.kt`.
 *
 * Android builds:
 *   tips(application_broken_tips)
 *   category(reinstall)
 *     clickable(github_releases, summary = meta_github_url)
 *
 * Tapping the row raises `ApkBrokenDesign.Request(url)` and the activity opens
 * it with `Intent.ACTION_VIEW`; here that is `openInBrowser()`.
 *
 * On Android this activity is the fallback shown when the packaged native
 * libraries cannot be loaded. The port keeps the screen, but nothing routes to
 * it yet -- there is no native core to fail loading.
 */

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { ActionLabel } from '../view/ActionLabel';
import { PreferenceCategory } from '../view/PreferenceCategory';
import { PreferenceTips } from '../view/PreferenceTips';
import { openInBrowser } from '../util/Platform';

@Entry
@ComponentV2
struct ApkBrokenPage {
  @Local tips: string = '';

  aboutToAppear(): void {
    this.tips = getContext(this).resourceManager.getStringSync($r('app.string.application_broken_tips').id);
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

        Text($r('app.string.application_broken'))
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
          PreferenceTips({ raw: this.tips })

          PreferenceCategory({ text: $r('app.string.reinstall') })

          ActionLabel({
            text: $r('app.string.github_releases'),
            subtext: $r('app.string.meta_github_url'),
            showIcon: false,
            onAction: () => {
              const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
              openInBrowser(
                getContext(this) as common.UIAbilityContext,
                manager.getStringSync($r('app.string.meta_github_url').id)
              );
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
