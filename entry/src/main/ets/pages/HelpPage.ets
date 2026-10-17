/*
 * Help screen -- port of ClashMetaForAndroid `design_settings_common.xml` +
 * `HelpActivity.kt` + `HelpDesign.kt`.
 *
 * Android builds a preference screen inside the common scaffold:
 *   tips(tips_help)
 *   category(document)
 *     clickable(clash_wiki,          summary = clash_wiki_url)
 *     clickable(clash_meta_wiki,     summary = clash_meta_wiki_url)
 *   category(sources)
 *     clickable(clash_meta_core,     summary = clash_meta_core_url)
 *     clickable(clash_meta_for_android, summary = meta_github_url)
 *
 * Every row opens its URL with `Intent.ACTION_VIEW`; here that is
 * `openInBrowser()`. The rows carry no icon, but Android leaves the icon
 * `View` in the tree (it is only hidden when `icon` is explicitly set to
 * null, which `clickable()` never does), so the text stays indented --
 * `showIcon: false` keeps that slot.
 *
 * HelpDesign holds no state, so this page has no ViewModel.
 */

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { ActionLabel } from '../view/ActionLabel';
import { PreferenceCategory } from '../view/PreferenceCategory';
import { PreferenceTips } from '../view/PreferenceTips';
import { openInBrowser } from '../util/Platform';

@Entry
@ComponentV2
struct HelpPage {
  @Local tips: string = '';

  aboutToAppear(): void {
    this.tips = this.stringOf($r('app.string.tips_help'));
  }

  /** Resolve a string resource, for values that are handed out as plain text. */
  private stringOf(resource: Resource): string {
    return getContext(this).resourceManager.getStringSync(resource.id);
  }

  /** Mirrors `HelpDesign`'s `openLink(Uri.parse(context.getString(...)))`. */
  private openLink(urlResource: Resource): void {
    openInBrowser(getContext(this) as common.UIAbilityContext, this.stringOf(urlResource));
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

        Text($r('app.string.help'))
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

          PreferenceCategory({ text: $r('app.string.document') })

          ActionLabel({
            text: $r('app.string.clash_wiki'),
            subtext: $r('app.string.clash_wiki_url'),
            showIcon: false,
            onAction: () => {
              this.openLink($r('app.string.clash_wiki_url'));
            }
          })

          ActionLabel({
            text: $r('app.string.clash_meta_wiki'),
            subtext: $r('app.string.clash_meta_wiki_url'),
            showIcon: false,
            onAction: () => {
              this.openLink($r('app.string.clash_meta_wiki_url'));
            }
          })

          PreferenceCategory({ text: $r('app.string.sources') })

          ActionLabel({
            text: $r('app.string.clash_meta_core'),
            subtext: $r('app.string.clash_meta_core_url'),
            showIcon: false,
            onAction: () => {
              this.openLink($r('app.string.clash_meta_core_url'));
            }
          })

          ActionLabel({
            text: $r('app.string.clash_meta_for_android'),
            subtext: $r('app.string.meta_github_url'),
            showIcon: false,
            onAction: () => {
              this.openLink($r('app.string.meta_github_url'));
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
