/*
 * Create-profile screen -- port of ClashMetaForAndroid `design_new_profile.xml`
 * + `adapter_profile_provider.xml` + `NewProfileActivity.kt` +
 * `NewProfileDesign.kt`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- common_recycler_list (provider rows)
 *   +- ActivityBarLayout
 *      +- common_activity_bar (back + title)
 *
 * Each row is [icon 30dp | name (Body1) / summary (Body2)] with
 * paddingVertical item_padding_vertical.
 *
 * `NewProfileActivity.queryProfileProviders()` returns three built-ins --
 * File, Url, QR -- followed by one entry per installed handler of the
 * `com.github.kr328.clash.ACTION_PROVIDE_URL` intent. That intent contract does
 * not exist on HarmonyOS, so only the built-ins are listed.
 *
 * Deviations:
 *   - QR opens the platform's default scanning UI through
 *     `@kit.ScanKit`'s `scanBarcode.startScanForResult`. Android uses the
 *     third-party `ScanQRCode` Activity contract; HarmonyOS's system Scan Kit
 *     provides the equivalent default UI and pre-authorizes its camera use.
 *   - Android creates the record and then opens `PropertiesActivity` for the
 *     result, finishing itself when the editor saves. The port pushes
 *     `PropertiesPage` the same way but keeps this page on the stack; the back
 *     gesture from the editor therefore returns here rather than to the profile
 *     list. (`router.replaceUrl` would lose the profile list behind it.)
 *   - File and Url both create an *empty* record and let the editor fill it in,
 *     exactly as Android does; QR creates a Url record with the scanned payload
 *     as its source before opening the same editor.
 */

import { router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { ProfileProviderKind, ProfileType } from '../model/ProfileModels';
import { loadProfileStore, profileCreate } from '../backend/ProfileStore';
import { ensureProfileDir } from '../backend/ProfileFiles';
import { showToast } from '../util/Platform';

@Entry
@ComponentV2
struct NewProfilePage {
  /** Guards against opening two Scan Kit surfaces from a double tap. */
  private scanning: boolean = false;

  /** Mirrors `Request.Create(provider)` -> `create(type, getString(new_profile))`. */
  private create(type: ProfileType, source: string = ''): void {
    const store = loadProfileStore();
    const name: string =
      getContext(this).resourceManager.getStringSync($r('app.string.new_profile').id);

    const profile = profileCreate(store, type, name, source);

    // Mirrors `ProfileManager.create()`'s directory setup.
    ensureProfileDir(getContext(this), profile.uuid);

    // Mirrors `launchProperties(uuid)`.
    router.pushUrl({ url: 'pages/PropertiesPage', params: { uuid: profile.uuid } });
  }

  /**
   * Mirrors `NewProfileActivity.scanResultHandler` + `createProfileByQrCode`.
   * Scan Kit returns the raw QR payload in `originalValue`; Android creates a
   * Url profile with that string without additional validation, and so does
   * this port. The editor remains responsible for the final URL check.
   */
  private async scanQrCode(): Promise<void> {
    if (this.scanning) {
      return;
    }
    this.scanning = true;

    const options: scanBarcode.ScanOptions = {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableMultiMode: false,
      // Android's Quickie `ScanQRCode` contract is camera-only; Scan Kit's
      // album entry is a platform extra, so keep it off for parity.
      enableAlbum: false
    };

    try {
      const result: scanBarcode.ScanResult =
        await scanBarcode.startScanForResult(getContext(this), options);
      this.create(ProfileType.Url, result.originalValue);
    } catch (error) {
      const failure: BusinessError = error as BusinessError;
      // 1000500002 is the documented "user canceled" code. Android's
      // QRUserCanceled branch is silent; only real errors get a toast.
      if (failure.code !== 1000500002) {
        showToast($r('app.string.import_from_qr_exception'));
      }
    } finally {
      this.scanning = false;
    }
  }

  /** Mirrors `NewProfileDesign.requestCreate`. */
  private requestCreate(kind: ProfileProviderKind): void {
    if (kind === ProfileProviderKind.Qr) {
      // Mirrors Request.LaunchScanner -> ScanQRCode().
      this.scanQrCode();
      return;
    }
    this.create(kind === ProfileProviderKind.Url ? ProfileType.Url : ProfileType.File);
  }

  @Builder
  providerRow(name: ResourceStr, summary: ResourceStr, icon: Resource) {
    Row() {
      Image(icon)
        .width($r('app.float.item_header_component_size'))
        .height($r('app.float.item_header_component_size'))
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_control_normal'))
        .margin({
          left: $r('app.float.item_header_margin'),
          right: $r('app.float.item_header_margin')
        })

      Column() {
        Text(name)
          .fontSize(16)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(summary)
          .fontSize(14)
          .opacity(0.6)
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: $r('app.float.item_text_margin') })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      top: $r('app.float.item_padding_vertical'),
      bottom: $r('app.float.item_padding_vertical')
    })
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

        // `android:label="@string/create_profile"` on NewProfileActivity.
        Text($r('app.string.create_profile'))
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
          // A `@Builder` cannot take attributes at its call site, so each row is
          // wrapped in the container that carries the click.
          Column() {
            this.providerRow($r('app.string.file'), $r('app.string.import_from_file'),
              $r('app.media.ic_baseline_attach_file'))
          }
          .width('100%')
          .onClick(() => {
            this.requestCreate(ProfileProviderKind.File);
          })

          Column() {
            this.providerRow($r('app.string.url'), $r('app.string.import_from_url'),
              $r('app.media.ic_baseline_cloud_download'))
          }
          .width('100%')
          .onClick(() => {
            this.requestCreate(ProfileProviderKind.Url);
          })

          Column() {
            this.providerRow($r('app.string.qr'), $r('app.string.import_from_qr'),
              $r('app.media.baseline_qr_code_scanner'))
          }
          .width('100%')
          .onClick(() => {
            this.requestCreate(ProfileProviderKind.Qr);
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
