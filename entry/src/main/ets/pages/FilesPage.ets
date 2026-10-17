/*
 * Profile file browser -- port of ClashMetaForAndroid `design_files.xml` +
 * `adapter_file.xml` + `dialog_files_menu.xml` + `FilesActivity.kt` +
 * `FilesDesign.kt`.
 *
 * Android structure:
 *   CoordinatorLayout
 *   +- common_recycler_list (file rows)
 *   +- ActivityBarLayout
 *      +- common_activity_bar (back + title)
 *      +- new_view (GONE while the root directory is showing)
 *
 * Row (`adapter_file.xml`): minHeight item_min_height, then
 * [ folder/article icon 30dp | name + size | elapsed | divider | more-vert ].
 * Size and elapsed are GONE for directories.
 *
 * The root rule is Android's: `FilesActivity.fetch` shows the whole listing
 * only when `config.yaml` is non-empty, otherwise it shows just that one file,
 * so `providers/` stays hidden until the configuration has content.
 *
 * Deviations:
 *   - Android opens a file with `Intent.ACTION_VIEW` and lets another app render
 *     it; the port makes the same hand-off with a file URI Want and falls back
 *     to `not_ported` when nothing accepts it. There is no in-app text editor on
 *     either side.
 *   - Import / Export use `DocumentViewPicker` in place of SAF's
 *     `GetContent` / `CreateDocument`.
 *   - Android's menu is an `AppBottomSheetDialog`; `bindMenu` is used here for
 *     the same reason as the other ported menus (`MenuElement[]` cannot nest, so
 *     the Delete row is not tinted with the error colour).
 *   - `configurationEditable` is `profile.type != Type.Url`, which is what gates
 *     importing over `config.yaml` at the root.
 */

import { router } from '@kit.ArkUI';
import { common, wantConstant, Want } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { resourceManager } from '@kit.LocalizationKit';
import { FileEntry, FilesRequest, isValidFileName } from '../model/FileModels';
import { ProfileType } from '../model/ProfileModels';
import { ProfileStore, loadProfileStore, profileByUUID } from '../backend/ProfileStore';
import {
  copyFile,
  copyFromUri,
  copyToUri,
  deleteEntry,
  ensureProfileDir,
  listEntries,
  profileRootDir,
  renameEntry
} from '../backend/ProfileFiles';
import { elapsedIntervalString } from '../model/ProviderModels';
import { TextInputDialog } from '../view/TextInputDialog';
import { showToast } from '../util/Platform';

interface FilesParams {
  uuid?: string;
}

@Entry
@ComponentV2
struct FilesPage {
  @Local store: ProfileStore = loadProfileStore();
  @Local uuid: string = '';
  /** `configurationEditable = profile.type != Type.Url`. */
  @Local configurationEditable: boolean = false;

  /**
   * `FilesActivity`'s `Stack<String>` of document ids. Empty means the root, and
   * `inBaseDir` is `stack.empty()`.
   */
  @Local stack: string[] = [];
  @Local entries: FileEntry[] = [];
  @Local now: number = Date.now();

  // ---- rename / new-file dialog ----
  @Local naming: boolean = false;
  @Local nameInitial: string = '';
  @Local nameError: ResourceStr = '';
  /** The entry being renamed; undefined while creating a new file. */
  private renaming: FileEntry | undefined = undefined;
  /** A picked source URI waiting for a name, for `Request.ImportFile(null)`. */
  private pendingImportUri: string = '';

  private ticker: number = -1;

  aboutToAppear(): void {
    const params: object | undefined = router.getParams();
    const uuid: string | undefined =
      params === undefined ? undefined : (params as FilesParams).uuid;
    if (uuid === undefined) {
      // Mirrors `intent.uuid ?: return finish()`.
      router.back();
      return;
    }

    const profile = profileByUUID(this.store, uuid);
    if (profile === undefined) {
      router.back();
      return;
    }

    this.uuid = uuid;
    this.configurationEditable = profile.type !== ProfileType.Url;
    // An uncaught throw in `aboutToAppear` takes the page (and the app) down, so
    // the filesystem work is guarded the way Android's `try { ... } catch` in
    // `FilesActivity.main` guards it.
    try {
      ensureProfileDir(getContext(this), uuid);
      this.refresh();
    } catch (error) {
      this.entries = [];
      showToast($r('app.string.not_ported'));
    }

    // `FilesActivity` runs a one-minute ticker for the elapsed labels.
    this.ticker = setInterval(() => {
      this.now = Date.now();
    }, 60000);
  }

  aboutToDisappear(): void {
    if (this.ticker >= 0) {
      clearInterval(this.ticker);
      this.ticker = -1;
    }
  }

  /** Mirrors `FilesActivity.onBackPressed` -> `Request.PopStack`. */
  onBackPress(): boolean {
    if (this.naming) {
      return false;
    }
    if (this.stack.length > 0) {
      this.stack.pop();
      this.refresh();
      return true;
    }
    return false;
  }

  /**
   * The toolbar arrow has to run the same logic as `onBackPress`: `router.back()`
   * does **not** go through `onBackPress`, so calling it directly would leave the
   * directory stack unpopped and close the page from a nested directory.
   */
  private requestBack(): void {
    if (this.naming) {
      return;
    }
    if (this.stack.length > 0) {
      this.stack.pop();
      this.refresh();
      return;
    }
    router.back();
  }

  /** `FilesActivity.fetch(client, stack, root)`. */
  private refresh(): void {
    const root: string = profileRootDir(getContext(this), this.uuid);
    const dir: string = this.stack.length === 0 ? root : this.stack[this.stack.length - 1];
    const entries: FileEntry[] = listEntries(dir);

    if (this.stack.length > 0) {
      this.entries = entries;
      return;
    }

    // At the root, an empty `config.yaml` hides everything else.
    const config: FileEntry | undefined =
      entries.find((entry: FileEntry) => entry.id.endsWith('config.yaml'));
    this.entries = (config === undefined || config.size > 0) ? entries : [config];
  }

  private inBaseDir(): boolean {
    return this.stack.length === 0;
  }

  /** Mirrors `elapsedIntervalString(currentTime - file.lastModified)`. */
  private elapsedLabel(entry: FileEntry): ResourceStr {
    return elapsedIntervalString(this.now - entry.lastModified);
  }

  /** Mirrors `I18nKt.toBytesString(file.size)`; only files reach this. */
  private sizeLabel(entry: FileEntry): string {
    if (entry.size > 1024 * 1024 * 1024) {
      return `${(entry.size / 1024 / 1024 / 1024).toFixed(2)} GiB`;
    }
    if (entry.size > 1024 * 1024) {
      return `${(entry.size / 1024 / 1024).toFixed(2)} MiB`;
    }
    if (entry.size > 1024) {
      return `${(entry.size / 1024).toFixed(2)} KiB`;
    }
    return `${entry.size} Bytes`;
  }

  /** Mirrors `dialog_files_menu.xml`'s four visibility expressions. */
  private itemMenu(entry: FileEntry): MenuElement[] {
    const manager: resourceManager.ResourceManager = getContext(this).resourceManager;
    const items: MenuElement[] = [];

    if (!entry.directory && (!this.inBaseDir() || this.configurationEditable)) {
      items.push({
        value: manager.getStringSync($r('app.string.import_').id),
        action: () => {
          this.request(FilesRequest.ImportFile, entry);
        }
      });
    }

    if (!entry.directory && entry.size > 0) {
      items.push({
        value: manager.getStringSync($r('app.string.export').id),
        action: () => {
          this.request(FilesRequest.ExportFile, entry);
        }
      });
    }

    if (!this.inBaseDir()) {
      items.push({
        value: manager.getStringSync($r('app.string.rename').id),
        action: () => {
          this.request(FilesRequest.RenameFile, entry);
        }
      });
      items.push({
        value: manager.getStringSync($r('app.string.delete').id),
        action: () => {
          this.request(FilesRequest.DeleteFile, entry);
        }
      });
    }

    return items;
  }

  /** Mirrors `FilesActivity`'s `design.requests.onReceive` switch. */
  private request(request: FilesRequest, entry: FileEntry): void {
    if (request === FilesRequest.OpenDirectory) {
      this.stack.push(entry.id);
      this.refresh();
      return;
    }
    if (request === FilesRequest.OpenFile) {
      this.openExternally(entry);
      return;
    }
    if (request === FilesRequest.RenameFile) {
      this.renaming = entry;
      this.pendingImportUri = '';
      this.nameInitial = entry.name;
      this.nameError = '';
      this.naming = true;
      return;
    }
    if (request === FilesRequest.DeleteFile) {
      deleteEntry(entry);
      this.refresh();
      return;
    }
    if (request === FilesRequest.ImportFile) {
      this.pickForImport(entry);
      return;
    }
    if (request === FilesRequest.ExportFile) {
      this.exportEntry(entry);
      return;
    }
    if (request === FilesRequest.PopStack) {
      if (this.stack.length === 0) {
        router.back();
      } else {
        this.stack.pop();
        this.refresh();
      }
    }
  }

  /**
   * Mirrors `Intent.ACTION_VIEW` with `text/plain`: the document is handed to
   * whatever app renders text, rather than rendered here.
   *
   * The Android intent carries `FLAG_GRANT_READ_URI_PERMISSION`; the port needs
   * the same thing, or the target ability receives a sandbox `file://` URI it
   * has no permission to read and the preview dies with "preview failed".
   * `wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION` is that grant on
   * HarmonyOS, and it is the one form a normal app may use -- the explicit
   * `uriPermissionManager.grantUriPermission` wants
   * `ohos.permission.PROVISIONING_GRANT_PERMISSION` (`system_basic`).
   *
   * The `entity.system.browsable` entity is deliberately gone: it matches
   * browsers, and this is a text document, not a URL.
   */
  private openExternally(entry: FileEntry): void {
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: fileUri.getUriFromPath(entry.id),
      type: 'text/plain',
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION
    };

    (getContext(this) as common.UIAbilityContext).startAbility(want)
      .catch((error: BusinessError) => {
        // Android fell back to a chooser when nothing handled the intent;
        // HarmonyOS has no chooser, so the failure is reported as-is.
        showToast(error.message);
      });
  }

  /** `Request.ImportFile` -- SAF's `GetContent`, then `importDocument`/`copyDocument`. */
  private async pickForImport(entry: FileEntry): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }

      // Copying onto an existing file needs no name; a new file does.
      copyFromUri(uris[0], entry.id);
      this.refresh();
    } catch (error) {
      // Mirrors `showExceptionToast(e)`: the message, not a generic failure.
      showToast((error as BusinessError).message ?? '');
    }
  }

  /** `Request.ImportFile(null)` -- "new": pick a file, then ask for its name. */
  private async pickForNew(): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: string[] = await documentPicker.select(options);
      if (uris.length === 0) {
        return;
      }

      const uri: string = uris[0];
      const slash: number = uri.lastIndexOf('/');
      this.renaming = undefined;
      this.pendingImportUri = uri;
      this.nameInitial = slash >= 0 ? uri.substring(slash + 1) : 'File';
      this.nameError = '';
      this.naming = true;
    } catch (error) {
      showToast((error as BusinessError).message ?? '');
    }
  }

  /** `Request.ExportFile` -- SAF's `CreateDocument`, then `copyDocument`. */
  private async exportEntry(entry: FileEntry): Promise<void> {
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [entry.name];
      const documentPicker = new picker.DocumentViewPicker(getContext(this));
      const uris: string[] = await documentPicker.save(options);
      if (uris.length === 0) {
        return;
      }

      copyToUri(entry.id, uris[0]);
      showToast($r('app.string.file_exported'));
    } catch (error) {
      showToast((error as BusinessError).message ?? '');
    }
  }

  /** `FilesDesign.requestFileName` + `ValidatorFileName`. */
  private confirmName(value: string): void {
    if (!isValidFileName(value)) {
      this.nameError = $r('app.string.invalid_file_name');
      return;
    }

    const entry: FileEntry | undefined = this.renaming;
    if (entry !== undefined) {
      renameEntry(entry, value);
    } else if (this.pendingImportUri !== '') {
      const dir: string = this.stack[this.stack.length - 1];
      copyFromUri(this.pendingImportUri, `${dir}/${value}`);
    }

    this.renaming = undefined;
    this.pendingImportUri = '';
    this.naming = false;
    this.refresh();
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

        // `android:label="@string/files"` on FilesActivity.
        Text($r('app.string.files'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: $r('app.float.item_text_margin') })

        // `new_view`: GONE at the root directory.
        if (!this.inBaseDir()) {
          Image($r('app.media.ic_baseline_add'))
            .width($r('app.float.item_tailing_component_size'))
            .height($r('app.float.item_tailing_component_size'))
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_control_normal'))
            .onClick(() => {
              this.pickForNew();
            })
        }
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      List() {
        ForEach(this.entries, (entry: FileEntry) => {
          ListItem() {
            Row() {
              Image(entry.directory
                ? $r('app.media.ic_outline_folder')
                : $r('app.media.ic_outline_article'))
                .width($r('app.float.item_tailing_component_size'))
                .height($r('app.float.item_tailing_component_size'))
                .objectFit(ImageFit.Contain)
                .fillColor($r('app.color.color_control_normal'))
                .margin({
                  left: $r('app.float.item_header_margin'),
                  right: $r('app.float.item_header_margin')
                })

              Column() {
                Text(entry.name)
                  .fontSize(16)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                // Size is GONE for directories.
                if (!entry.directory) {
                  Text(this.sizeLabel(entry))
                    .fontSize(14)
                    .opacity(0.6)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .margin({ top: $r('app.float.item_text_margin') })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .padding({
                top: $r('app.float.item_padding_vertical'),
                bottom: $r('app.float.item_padding_vertical')
              })

              // Elapsed is GONE for directories.
              if (!entry.directory) {
                Text(this.elapsedLabel(entry))
                  .fontSize(12)
                  .margin({ right: $r('app.float.item_midden_margin') })

                // `minHeight = item_tailing_component_size * 1.5`.
                Divider()
                  .vertical(true)
                  .strokeWidth(1)
                  .height(45)
                  .color($r('app.color.color_control_highlight'))
              }

              // `bindMenu` with an empty `MenuElement[]` does not draw an empty
              // menu -- it covers the page with a blank white surface. Android
              // keeps the icon even when every row of the sheet is GONE (a
              // `config.yaml` at the root of a Url profile has no actions at
              // all), so the icon stays and simply carries no menu.
              //
              // It is drawn at 33% in that case. With no menu attached the
              // glyph is not a button -- a tap on it falls through to the row
              // and opens the file, exactly as in Android -- but at full
              // opacity it read as a menu that never appeared. Dimming keeps
              // Android's layout (the slot is always there) while saying
              // "nothing here" before the tap instead of after it.
              if (this.itemMenu(entry).length > 0) {
                Image($r('app.media.ic_baseline_more_vert'))
                  .width($r('app.float.item_tailing_component_size'))
                  .height($r('app.float.item_tailing_component_size'))
                  .objectFit(ImageFit.Contain)
                  .fillColor($r('app.color.color_control_normal'))
                  .margin($r('app.float.item_tailing_margin'))
                  .bindMenu(this.itemMenu(entry))
              } else {
                Image($r('app.media.ic_baseline_more_vert'))
                  .width($r('app.float.item_tailing_component_size'))
                  .height($r('app.float.item_tailing_component_size'))
                  .objectFit(ImageFit.Contain)
                  .fillColor($r('app.color.color_control_normal'))
                  .margin($r('app.float.item_tailing_margin'))
                  .opacity(0.33)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .constraintSize({ minHeight: $r('app.float.item_min_height') })
            .onClick(() => {
              this.request(entry.directory
                ? FilesRequest.OpenDirectory
                : FilesRequest.OpenFile, entry);
            })
          }
        }, (entry: FileEntry) => `${entry.id}|${entry.size}|${entry.lastModified}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
    // `bindContentCover` rather than a `Stack` child: a full-size sibling above
    // the `Scroll` makes every gesture in the list stop firing.
    .bindContentCover(
      this.naming,
      this.nameDialog(),
      { modalTransition: ModalTransition.NONE }
    )
  }

  @Builder
  nameDialog() {
    TextInputDialog({
      title: $r('app.string.file_name'),
      initial: this.nameInitial,
      hint: $r('app.string.file_name'),
      errorText: this.nameError,
      onConfirm: (value: string) => {
        this.confirmName(value);
      },
      onCancel: () => {
        this.renaming = undefined;
        this.pendingImportUri = '';
        this.naming = false;
      }
    })
  }
}
