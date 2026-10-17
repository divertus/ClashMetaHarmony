/*
 * "Application Crashed" screen -- port of ClashMetaForAndroid
 * `design_app_crashed.xml` + `AppCrashedActivity.kt` + `AppCrashedDesign.kt`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- ObservableScrollView (clipToPadding=false,
 *      paddingTop = insets.top + toolbar_height)
 *      +- TextView#logs_view (lineSpacingMultiplier 1.5, padding 12dp/12dp,
 *                             textIsSelectable=true)
 *   +- ActivityBarLayout
 *      +- common_activity_bar
 *
 * The activity fills the TextView from `SystemLogcat.dumpCrash()`, which shells
 * out to Android's `logcat`. HarmonyOS has no equivalent command, and the port
 * has no crash handler, so the text arrives as a route parameter instead --
 * `router.pushUrl({ url: 'pages/AppCrashedPage', params: { logs } })`. With no
 * parameter the view stays empty, which is what Android renders when the dump
 * is empty.
 */

import { router } from '@kit.ArkUI';

interface AppCrashedParams {
  logs?: string;
}

@Entry
@ComponentV2
struct AppCrashedPage {
  @Local logs: string = '';

  aboutToAppear(): void {
    this.logs = this.readLogsParam();
  }

  /** Mirrors `AppCrashedDesign.setAppLogs(logs)`; the source is the route. */
  private readLogsParam(): string {
    const params: object | undefined = router.getParams();
    if (params === undefined) {
      return '';
    }
    const logs: string | undefined = (params as AppCrashedParams).logs;
    return logs ?? '';
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

        Text($r('app.string.application_crashed'))
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
        Text(this.logs)
          .fontSize(14)
          // lineSpacingMultiplier 1.5 on a 14sp text.
          .lineHeight(21)
          .width('100%')
          .textAlign(TextAlign.Start)
          .copyOption(CopyOptions.LocalDevice)
          .padding({
            left: $r('app.float.logcat_padding_horizontal'),
            right: $r('app.float.logcat_padding_horizontal'),
            top: $r('app.float.logcat_padding_vertical'),
            bottom: $r('app.float.logcat_padding_vertical')
          })
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
