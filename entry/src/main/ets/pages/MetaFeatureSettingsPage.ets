/*
 * Meta feature settings screen -- port of ClashMetaForAndroid
 * `design_settings_meta_feature.xml` + `MetaFeatureSettingsActivity.kt` +
 * `MetaFeatureSettingsDesign.kt`.
 *
 * The tree is `OverrideModels.overrideMetaSections()`: four categories
 * (`age_key_category`, `settings`, `sniffer_setting`, `geox_files`) and 25 rows,
 * in the order the Kotlin `preferenceScreen` block builds them. Android also
 * carries a commented-out `geox_url_setting` category, so the port has no
 * `geox-url` rows either. The scaffold, the row kinds and the editors all come
 * from `view/PreferenceScreen.ets`, shared with `OverrideSettingsPage` -- both
 * screens read and write the *same* `Clash.OverrideSlot.Persist` record.
 *
 * Two things are genuinely this page's:
 *
 *   - The two age-key rows open `requestAgeKeyHelper`, which is built entirely
 *     on JNI (`Clash.genX25519KeyPair` / `genHybridKeyPair` / `veritySecretKeys`
 *     / `verityPublicKeys` / `toPublicKeys`). Those five calls are core
 *     primitives, so the port forwards them to the same mihomo functions over
 *     NAPI -- see `backend/AgeKeyHelper.ets` -- and the dialog below is the
 *     `dialog_age_key_helper.xml` layout. Caveat worth keeping in view: a
 *     generated key is still only *stored* here. Android feeds it to
 *     `ProfileProcessor` when fetching an age-encrypted subscription; this port
 *     downloads profiles (`backend/ProfileFetch.ets`) but has no age decryption
 *     step, so the key has nothing to unlock yet.
 *   - The four geofile rows (`Request.ImportGeoIp` / `GeoSite` / `Country` /
 *     `ASN`) pick a document with `DocumentViewPicker` in place of SAF's
 *     `GetContent`, check the extension, and copy it into `filesDir/clash/`.
 *
 * The `sniffer_setting` rows are registered in `snifferDependencies` on
 * Android, so they are disabled while the strategy row is `false`; that is the
 * `dependsOn` field of the row table.
 */

import { router, promptAction } from '@kit.ArkUI';
import { resourceManager } from '@kit.LocalizationKit';

import { picker } from '@kit.CoreFileKit';
import { PreferenceSection, overrideMetaSections, overridePatchBody } from '../model/OverrideModels';
import {
  OverrideStore,
  loadOverrideStore,
  overrideClear,
  overrideLoad,
  overrideSave
} from '../backend/OverrideStore';
import {
  GeoFileKind,
  displayNameOf,
  extensionOf,
  importGeoFile,
  isSupportedGeoExtension,
  validGeoExtensions
} from '../backend/GeoFiles';
import {
  AgeKeyKind,
  AgeKeyPair,
  copyToClipboard,
  deriveFirstPublicKey,
  generateKeyPair,
  verifyPublicKey,
  verifySecretKey
} from '../backend/AgeKeyHelper';
import { loadControllerStore } from '../backend/ControllerStore';
import { ExternalControllerBackend } from '../backend/ExternalControllerBackend';
import { PreferenceScreen } from '../view/PreferenceScreen';
import { showToast } from '../util/Platform';

@Entry
@ComponentV2
struct MetaFeatureSettingsPage {
  @Local store: OverrideStore = loadOverrideStore();

  /** The override record; absent keys are "do not modify". */
  @Local data: Record<string, string> = {};

  /** The four categories; built once, they never change. */
  private sections: PreferenceSection[] = [];

  private backend: ExternalControllerBackend | null = null;

  /** The override as it was when the screen opened, for the dirty check. */
  private initialEncoded: string = '{}';

  /** Set while leaving on purpose, so `onBackPress` lets the pop through. */
  private leaving: boolean = false;

  // ---- Age key helper (Android: `requestAgeKeyHelper`) -------------------

  /** Set while the helper modal is up. */
  @Local ageDialogOpen: boolean = false;

  /** Which row opened it; only the "Generate" button reads this. */
  @Local ageKind: AgeKeyKind = AgeKeyKind.X25519;

  @Local ageSecretKey: string = '';
  @Local agePublicKey: string = '';

  /**
   * `binding.secretKeyLayout.error != null` / `publicKeyLayout.error != null`.
   * Android shows a message under the field; the flag is what decides whether
   * the message is drawn.
   */
  @Local ageSecretError: boolean = false;
  @Local agePublicError: boolean = false;

  aboutToAppear(): void {
    this.sections = overrideMetaSections();
    this.data = overrideLoad(this.store);
    this.initialEncoded = JSON.stringify(this.data);
    this.backend = new ExternalControllerBackend(loadControllerStore());
  }

  /** The `clickable` rows: two age-key helpers and four geofile imports. */
  private action(key: string): void {
    if (key === 'age_key.x25519') {
      this.openAgeKeyHelper(AgeKeyKind.X25519);
      return;
    }
    if (key === 'age_key.hybrid') {
      this.openAgeKeyHelper(AgeKeyKind.Hybrid);
      return;
    }
    if (key === 'geofile.geoip') {
      this.pickGeoFile(GeoFileKind.GeoIp);
      return;
    }
    if (key === 'geofile.geosite') {
      this.pickGeoFile(GeoFileKind.GeoSite);
      return;
    }
    if (key === 'geofile.country') {
      this.pickGeoFile(GeoFileKind.Country);
      return;
    }
    this.pickGeoFile(GeoFileKind.Asn);
  }

  /**
   * `requestAgeKeyHelper(hybrid)`: a dialog over the core's age helpers.
   *
   * Android builds a fresh dialog every time with both fields empty and
   * neither marked as an error; the state below is that dialog, and closing it
   * simply drops the state.
   */
  private openAgeKeyHelper(kind: AgeKeyKind): void {
    this.ageKind = kind;
    this.ageSecretKey = '';
    this.agePublicKey = '';
    this.ageSecretError = false;
    this.agePublicError = false;
    this.ageDialogOpen = true;
  }

  private closeAgeKeyHelper(): void {
    this.ageDialogOpen = false;
  }

  /** `setTitle(if (hybrid) age_key_type_hybrid else age_key_type_x25519)`. */
  private ageDialogTitle(): ResourceStr {
    return this.ageKind === AgeKeyKind.Hybrid
      ? $r('app.string.age_key_type_hybrid')
      : $r('app.string.age_key_type_x25519');
  }

  /**
   * `binding.generateView.setOnClickListener`: fill both fields at once.
   *
   * Android would dereference a null `keyPair` here; a failure reports why
   * instead, and leaves whatever was typed alone.
   */
  private generateAgeKey(): void {
    const pair: AgeKeyPair = generateKeyPair(this.ageKind);
    if (!pair.ok) {
      showToast(pair.error);
      return;
    }

    this.ageSecretKey = pair.secretKey;
    this.agePublicKey = pair.publicKey;
    this.patchAgeSecretError();
    this.patchAgePublicError();
  }

  /**
   * `binding.toPublicKeyView.setOnClickListener`: derive the public key from
   * the secret field. `deriveFirstPublicKey` returns `''` when the secret does
   * not parse, which is Android's `?: ""` -- the field is cleared rather than
   * filled with something wrong.
   */
  private ageToPublicKey(): void {
    this.agePublicKey = deriveFirstPublicKey(this.ageSecretKey);
    this.patchAgePublicError();
  }

  /**
   * `copy(label, value)`: blank values are not copied, and a rejected write is
   * reported rather than announced as success.
   */
  private copyAgeKey(value: string): void {
    if (value.trim().length === 0) {
      return;
    }
    if (!copyToClipboard(value)) {
      showToast($r('app.string.not_ported'));
      return;
    }
    showToast($r('app.string.copied'));
  }

  /**
   * `patchSecretKeyState`: `secretKey.isBlank() || Clash.veritySecretKeys(...)`.
   * The blank-is-valid half is why the dialog opens clean, so it stays here
   * next to the message rather than inside the helper.
   */
  private patchAgeSecretError(): void {
    this.ageSecretError =
      this.ageSecretKey.trim().length > 0 && !verifySecretKey(this.ageSecretKey);
  }

  /** `patchPublicKeyState`, the same shape as the secret field's. */
  private patchAgePublicError(): void {
    this.agePublicError =
      this.agePublicKey.trim().length > 0 && !verifyPublicKey(this.agePublicKey);
  }

  /**
   * `MetaFeatureSettingsActivity.importGeoFile`, split in two: the picker half
   * (SAF's `ActivityResultContracts.GetContent`) and the copy half
   * (`backend/GeoFiles.importGeoFile`).
   */
  private async pickGeoFile(kind: GeoFileKind): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        // `uri == null`: Android falls through to `geofile_import_failed`.
        return;
      }

      const uri: string = uris[0];
      const displayName: string = displayNameOf(uri);
      const ext: string = extensionOf(displayName);
      if (!isSupportedGeoExtension(ext)) {
        this.warnUnknownFormat();
        return;
      }

      importGeoFile(getContext(this), uri, kind, ext);
      showToast($r('app.string.geofile_imported', displayName));
    } catch (error) {
      showToast($r('app.string.geofile_import_failed'));
    }
  }

  /** `MaterialAlertDialogBuilder` with the supported extension list. */
  private warnUnknownFormat(): void {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    promptAction.showDialog({
      title: manager.getStringSync($r('app.string.geofile_unknown_db_format').id),
      message: manager.getStringSync($r('app.string.geofile_unknown_db_format_message').id,
        validGeoExtensions()),
      buttons: [
        {
          text: manager.getStringSync($r('app.string.ok').id),
          color: $r('app.color.color_primary')
        }
      ]
    }).catch(() => {
      // Dismissed without pressing OK; Android's dialog has nothing to do
      // either way.
    });
  }

  /** The `defer` block both activities share; see `OverrideSettingsPage`. */
  private commit(): void {
    overrideSave(this.store, this.data);

    const body: string = overridePatchBody(this.data);
    const backend: ExternalControllerBackend | null = this.backend;
    if (body === '{}' || backend === null) {
      return;
    }
    backend.patchConfigs(body).then((applied: boolean) => {
      if (!applied) {
        showToast($r('app.string.override_apply_failed'));
      }
    });
  }

  private dirty(): boolean {
    return JSON.stringify(this.data) !== this.initialEncoded;
  }

  private requestBack(): void {
    if (this.dirty()) {
      this.commit();
    }
    this.leaving = true;
    router.back();
  }

  onBackPress(): boolean {
    if (this.leaving) {
      return false;
    }
    // The helper dialog is a Material `AlertDialog` on Android, so back
    // dismisses the dialog rather than the screen.
    if (this.ageDialogOpen) {
      this.closeAgeKeyHelper();
      return true;
    }
    if (this.dirty()) {
      this.commit();
    }
    this.leaving = true;
    return false;
  }

  private clearAndLeave(): void {
    overrideClear(this.store);
    this.data = {};
    this.leaving = true;
    router.back();
  }

  /**
   * `dialog_age_key_helper.xml`: a secret-key field, the Generate/Copy pair,
   * a public-key field, the From Secret/Copy pair.
   *
   * It is a `bindContentCover` modal for the same reason `view/
   * TextInputDialog.ets` is one -- `promptAction` dialogs cannot host inputs,
   * and a `Stack` sibling or `.overlay()` above the page's `Scroll` makes every
   * gesture inside that `Scroll` stop firing.
   *
   * One deliberate deviation: Android's dialog has no button row and is
   * dismissed by tapping outside it or pressing back. A `bindContentCover`
   * cover does not close on an outside tap, so a Cancel button is added --
   * every other dialog in this port has one, and a modal with no visible way
   * out is worse than a faithful absence.
   */
  @Builder
  ageKeyDialog() {
    Column() {
      Column() {
        Text(this.ageDialogTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        // `TextInputLayout(hint = age_secret_key)`
        TextInput({ text: this.ageSecretKey, placeholder: $r('app.string.age_secret_key') })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .onChange((value: string) => {
            this.ageSecretKey = value;
            this.patchAgeSecretError();
          })

        if (this.ageSecretError) {
          Text($r('app.string.age_secret_key_error'))
            .fontSize(12)
            .fontColor($r('app.color.color_error'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 4 })
        }

        Row() {
          Button($r('app.string.age_key_generate'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .onClick(() => {
              this.generateAgeKey();
            })

          Button($r('app.string.age_key_copy'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .margin({ left: 8 })
            .onClick(() => {
              this.copyAgeKey(this.ageSecretKey);
            })
        }
        .width('100%')
        .margin({ top: 8 })

        // `TextInputLayout(hint = age_public_key)`
        TextInput({ text: this.agePublicKey, placeholder: $r('app.string.age_public_key') })
          .width('100%')
          .height(44)
          .margin({ top: 8 })
          .onChange((value: string) => {
            this.agePublicKey = value;
            this.patchAgePublicError();
          })

        if (this.agePublicError) {
          Text($r('app.string.age_public_key_error'))
            .fontSize(12)
            .fontColor($r('app.color.color_error'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 4 })
        }

        Row() {
          Button($r('app.string.age_key_to_public'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .onClick(() => {
              this.ageToPublicKey();
            })

          Button($r('app.string.age_key_copy'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .margin({ left: 8 })
            .onClick(() => {
              this.copyAgeKey(this.agePublicKey);
            })
        }
        .width('100%')
        .margin({ top: 8 })

        Button($r('app.string.cancel'))
          .width('100%')
          .height(40)
          .fontSize(15)
          .fontColor($r('app.color.color_control_normal'))
          .backgroundColor($r('app.color.color_surface'))
          .margin({ top: 16 })
          .onClick(() => {
            this.closeAgeKeyHelper();
          })
      }
      .width('85%')
      .padding(20)
      .backgroundColor($r('app.color.color_surface'))
      .borderRadius(8)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#80000000')
  }

  build() {
    // An `@Entry` page's `build` must have a single container as its root, and
    // a custom component does not count -- hence the wrapping `Column`.
    Column() {
      PreferenceScreen({
        pageTitle: $r('app.string.meta_features'),
        sections: this.sections,
        data: this.data,
        onDataChange: (data: Record<string, string>) => {
          this.data = data;
        },
        onRowAction: (key: string) => {
          this.action(key);
        },
        onClear: () => {
          this.clearAndLeave();
        },
        onBack: () => {
          this.requestBack();
        }
      })
    }
    .width('100%')
    .height('100%')
    .bindContentCover(
      this.ageDialogOpen,
      this.ageKeyDialog(),
      { modalTransition: ModalTransition.NONE }
    )
  }
}
