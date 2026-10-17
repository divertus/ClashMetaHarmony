/*
 * Logs screen -- port of ClashMetaForAndroid `design_logs.xml` +
 * `LogsActivity.kt` + `LogsDesign.kt` + `adapter/LogFileAdapter.kt`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- LinearLayout(vertical)
 *      +- ActivityBarLayout
 *         +- RelativeLayout [ common_activity_bar | ImageView#delete_view ]
 *      +- ActionLabel  clash_logcat  (icon adb, subtext tap_to_start)
 *      +- View         (1dp divider, colorControlHighlight)
 *      +- TextView     history       (colorControlActivated)
 *      +- RecyclerView#recycler_list (one ActionLabel per LogFile)
 *
 * `LogsDesign.requestDeleteAll()` shows a MaterialAlertDialog before deleting;
 * the HarmonyOS equivalent is `promptAction.showDialog`. Its buttons keep
 * Android's order -- cancel on the left, OK on the right.
 *
 * A file row opens `LogcatPage` in local-file mode. The "Clash Logcat" row
 * starts the streaming session on Android, which needs the foreground
 * `LogcatService`; that is not ported (see
 * `outputs/logcat-streaming-harmonyos-feasibility.md`), so the row is drawn
 * disabled and explains itself when tapped. A controller `/logs` replacement
 * was built and reverted: see that file's note and PORT-STATUS.
 *
 * The port has no log *writer* either -- Android fills `cacheDir/logs` from
 * that same service -- so the history list is always empty. The empty state
 * below says so instead of leaving a blank list that reads as a broken page,
 * and no fake producer was added: the feasibility review concluded the
 * streaming half has no honest HarmonyOS equivalent, so a local writer would
 * only move the lie one step earlier.
 */

import { router, promptAction } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';
import { LogFile, formatLogDate } from '../model/LogFileModels';
import { LogsViewModel } from '../viewmodel/LogsViewModel';
import { ActionLabel } from '../view/ActionLabel';
import { PreferenceCategory } from '../view/PreferenceCategory';
import { showToast } from '../util/Platform';

@Entry
@ComponentV2
struct LogsPage {
  @Local vm: LogsViewModel = new LogsViewModel();

  aboutToAppear(): void {
    this.vm.useCacheDir(getContext(this).cacheDir);
    this.vm.reload();
  }

  /**
   * Mirrors `LogsActivity`'s `Event.ActivityStart` reload: returning from the
   * logcat screen may have deleted the file that was just opened.
   */
  onPageShow(): void {
    this.vm.reload();
  }

  /** Mirrors `LogsDesign.requestDeleteAll()`. */
  private confirmDeleteAll(): void {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    promptAction.showDialog({
      title: manager.getStringSync($r('app.string.delete_all_logs').id),
      message: manager.getStringSync($r('app.string.delete_all_logs_warn').id),
      buttons: [
        {
          text: manager.getStringSync($r('app.string.cancel').id),
          // MaterialAlertDialogBuilder colours both buttons with
          // ?attr/colorPrimary; the neutral control colour here keeps the
          // port's own hierarchy while still following the theme.
          color: $r('app.color.color_control_normal')
        },
        {
          text: manager.getStringSync($r('app.string.ok').id),
          color: $r('app.color.color_primary')
        }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.vm.deleteAll();
      }
    }).catch(() => {
      // Dismissed without a choice: Android resumes false, i.e. no delete.
    });
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

        Text($r('app.string.logs'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: $r('app.float.item_text_margin') })

        // Mirrors ImageView#delete_view -> Request.DeleteAll.
        Image($r('app.media.ic_baseline_clear_all'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .onClick(() => {
            this.confirmDeleteAll();
          })
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      // Mirrors the "Clash Logcat" ActionLabel -> Request.StartLogcat.
      //
      // Android starts `LogcatService`, which subscribes to the in-process
      // core's log stream and writes `cacheDir/logs`. Neither the service nor
      // the core subscription exists here, so the row is drawn disabled --
      // Android's `Preference.enabled = false`, i.e. 33% and no `onAction` --
      // and reports why through `onDisabledTap`. It is kept rather than deleted
      // so the reason stays visible; the subtext is no longer `tap_to_start`,
      // which would promise a session that cannot start.
      ActionLabel({
        text: $r('app.string.clash_logcat'),
        subtext: $r('app.string.unavailable'),
        icon: $r('app.media.ic_baseline_adb'),
        rowEnabled: false,
        onDisabledTap: () => {
          showToast($r('app.string.not_ported'));
        }
      })

      Divider()
        .strokeWidth(1)
        // `design_logs.xml` draws this separator as a View with
        // `android:background="?attr/colorControlHighlight"`; the colour
        // already carries its own alpha, so no extra opacity.
        .color($r('app.color.color_control_highlight'))

      PreferenceCategory({ text: $r('app.string.history') })

      // `design_logs.xml` has no empty view, so Android renders a blank list
      // when the directory is empty. A blank list is indistinguishable from a
      // broken page here, so the port states the reason instead.
      if (this.vm.files.length === 0) {
        Column() {
          Text($r('app.string.empty'))
            .fontSize(16)
            .textAlign(TextAlign.Center)

          Text($r('app.string.logs_empty_tip'))
            .fontSize(14)
            .opacity(0.6)
            .textAlign(TextAlign.Center)
            .margin({ top: $r('app.float.item_text_margin') })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 24, right: 24, top: 24 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Start)
      } else {
        List() {
          ForEach(this.vm.files, (item: LogFile) => {
            ListItem() {
              ActionLabel({
                text: item.fileName,
                subtext: formatLogDate(item.date),
                showIcon: false,
                onAction: () => {
                  // Mirrors Request.OpenFile -> LogcatActivity with the file name.
                  router.pushUrl({
                    url: 'pages/LogcatPage',
                    params: { fileName: item.fileName }
                  });
                }
              })
            }
          }, (item: LogFile) => item.fileName)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
  }
}
