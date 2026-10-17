/*
 * Logcat screen, local-file mode -- port of ClashMetaForAndroid
 * `design_logcat.xml` + `LogcatActivity.kt` (the `fileName != null` branch) +
 * `LogcatDesign.kt` + `adapter/LogMessageAdapter.kt` + `adapter_log_message.xml`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- AppRecyclerView#recycler_list (one row per LogMessage)
 *   +- ActivityBarLayout
 *      +- RelativeLayout
 *         +- common_activity_bar
 *         +- [ delete | export ]   (VISIBLE when not streaming)
 *         +- stop                  (VISIBLE when streaming)
 *
 * Row (`adapter_log_message.xml`): padding 12dp/12dp, level name (Caption) on
 * the left and `HH:mm:ss.SSS` (Caption) on the right, both in
 * colorControlActivated, then the message body (Body2) below. Long-pressing a
 * row copies the message text (`LogMessageAdapter.onBindViewHolder`).
 *
 * Streaming mode is the other branch of the activity: it starts the foreground
 * `LogcatService`, binds it and polls a snapshot every 500ms with a reversed
 * list. That service and the core's log subscription are not ported, so only
 * the local-file branch exists here and the stop action is absent.
 *
 * The external controller's `/logs` route was implemented and tried as a
 * replacement producer; it connects, but holding that socket open was measured
 * to end the app process (and with it the tunnel) within ~60s, twice out of
 * two runs, while the same app survived 150s without it. See
 * `outputs/ClashMetaHarmony-PORT-STATUS.md` for the numbers. It is therefore
 * not wired in: a live log view is not worth the VPN.
 */

import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogMessage, formatLogTime } from '../model/LogMessageModels';
import { LogcatViewModel } from '../viewmodel/LogcatViewModel';
import { showToast } from '../util/Platform';

interface LogcatParams {
  fileName?: string;
}

@Entry
@ComponentV2
struct LogcatPage {
  @Local vm: LogcatViewModel = new LogcatViewModel();

  aboutToAppear(): void {
    const params: object | undefined = router.getParams();
    const fileName: string =
      params === undefined ? '' : ((params as LogcatParams).fileName ?? '');

    // `LogFile.parseFromFileName(fileName) ?: return showInvalid()`.
    if (!this.vm.resolveFile(fileName)) {
      showToast($r('app.string.invalid_log_file'));
      router.back();
      return;
    }

    this.vm.load(this.logsDir());
    if (this.vm.invalid) {
      // `LogcatReader(...).readAll()` threw: Android shows the same toast.
      showToast($r('app.string.invalid_log_file'));
    }
  }

  /** `context.logsDir` = `cacheDir/logs`. */
  private logsDir(): string {
    return `${getContext(this).cacheDir}/logs`;
  }

  /** Mirrors the adapter's long-click: copy the message to the clipboard. */
  private copyMessage(message: LogMessage): void {
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, message.message);
    pasteboard.getSystemPasteboard().setDataSync(data);
    showToast($r('app.string.copied'));
  }

  /** Mirrors `LogcatDesign.Request.Delete` -> delete the file, then finish. */
  private deleteFile(): void {
    this.vm.deleteFile();
    router.back();
  }

  /**
   * Mirrors `LogcatDesign.Request.Export` -> `CreateDocument("text/plain")`
   * followed by `writeLogTo`. The HarmonyOS equivalent of SAF's
   * `CreateDocument` is the document picker's `save()`.
   */
  private exportFile(): void {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const documentPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(context);

    documentPicker.save({ newFileNames: [this.vm.fileName()] })
      .then((uris: string[]) => {
        if (uris.length === 0) {
          return;
        }

        const file: fs.File = fs.openSync(uris[0], fs.OpenMode.READ_WRITE);
        try {
          fs.writeSync(file.fd, this.vm.exportContent());
        } finally {
          fs.closeSync(file);
        }

        showToast($r('app.string.file_exported'));
      })
      .catch((error: BusinessError) => {
        showToast(error.message);
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

        Text($r('app.string.logcat'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: $r('app.float.item_text_margin') })

        // The delete / export pair is VISIBLE whenever streaming is false,
        // which is always the case for this page.
        Image($r('app.media.ic_baseline_delete'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .margin({ right: $r('app.float.item_tailing_margin') })
          .onClick(() => {
            this.deleteFile();
          })

        Image($r('app.media.ic_baseline_publish'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .onClick(() => {
            this.exportFile();
          })
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      List() {
        ForEach(this.vm.messages, (item: LogMessage, index: number) => {
          ListItem() {
            Column() {
              Row() {
                Text(item.level.toString())
                  .fontSize(12)
                  .fontColor($r('app.color.color_primary'))

                Text(formatLogTime(item.time))
                  .fontSize(12)
                  .fontColor($r('app.color.color_primary'))
                  .layoutWeight(1)
                  .textAlign(TextAlign.End)
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              Text(item.message)
                .fontSize(14)
                .width('100%')
                .textAlign(TextAlign.Start)
                .margin({ top: $r('app.float.item_text_margin') })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding({
              left: $r('app.float.logcat_padding_horizontal'),
              right: $r('app.float.logcat_padding_horizontal'),
              top: $r('app.float.logcat_padding_vertical'),
              bottom: $r('app.float.logcat_padding_vertical')
            })
            // Mirrors `AdapterLogMessageBinding.root.setOnLongClickListener`,
            // i.e. the gesture sits on the row content, not on the ListItem.
            .gesture(LongPressGesture().onAction(() => {
              this.copyMessage(item);
            }))
          }
        }, (item: LogMessage, index: number) => `${index}:${item.time}:${item.message}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
  }
}
