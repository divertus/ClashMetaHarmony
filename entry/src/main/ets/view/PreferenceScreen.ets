/*
 * The shared shape of the two override screens.
 *
 * `OverrideSettingsDesign` and `MetaFeatureSettingsDesign` are two different
 * preference trees over the *same* `ConfigurationOverride` persist slot, and
 * both carry the identical scaffolding:
 *
 *   ActivityBarLayout
 *   +- common_activity_bar (back + title)
 *   +- ImageView#clear_view (ic_baseline_replay -> requestClear)
 *   +- preferenceScreen: category(title) { rows... }
 *
 * and the identical editors:
 *
 *   editableText      -> `requestModelTextInput` (with a neutral Reset)
 *   editableTextList  -> `requestEditableListOverlay`
 *   editableTextMap   -> `requestEditableListOverlay` + `requestModelInputEntry`
 *   selectableList    -> `popupSelectMenu`
 *   clickable         -> a request, no value
 *   requestClear      -> `requestResetConfirm`
 *
 * All of that lives here so the pages only own their row table and whatever
 * their `clickable` rows actually do. The component never touches the store or
 * the controller: it reports edits through `onDataChange` and the reset through
 * `onClear`, and the page decides what that means.
 *
 * Two ArkUI rules shape this file:
 *   - `ForEach` re-runs its item generator only for entries whose key changed,
 *     so the key carries the rendered summary (`rowKey`).
 *   - a `@Builder` whose parameters are passed by value is not re-executed when
 *     the parent's state changes, so the row markup is inlined in `ForEach`.
 *
 * Two parameter names are deliberately not the obvious ones. The precheck's
 * `regular-property-init` rule scans this file line by line, ignores nesting,
 * and treats every `name:` key it sees as a *member* of the enclosing struct --
 * so the `title:` and `onAction:` keys of the `TextInputDialog` / `ActionLabel`
 * calls below would register as members of `PreferenceScreen`, and then every
 * caller that passes `title` or `onAction` would be reported as initialising an
 * undecorated property. `pageTitle` / `onRowAction` dodge that, and they also
 * read better next to the row components' own `title` / `onAction`.
 */

import { resourceManager } from '@kit.LocalizationKit';
import {
  OverrideKind,
  OverrideOption,
  OverrideRow,
  PreferenceSection,
  overrideEncodeList,
  overrideEncodeMap,
  overrideGet,
  overrideList,
  overrideMap,
  overridePortText,
  overridePortValue,
  overridePut,
  overrideRemove,
  overrideRowEnabled,
  overrideSummaryText
} from '../model/OverrideModels';
import { ActionLabel } from './ActionLabel';
import { ElementInputDialog, ElementListDialog } from './ElementListDialog';
import { PreferenceCategory } from './PreferenceCategory';
import { PreferenceList } from './PreferenceList';
import { TextInputDialog } from './TextInputDialog';
import { showToast } from '../util/Platform';

/**
 * What the content cover is showing. Android runs one `select` loop over the
 * design's requests and raises each dialog as a coroutine, so at most one is
 * ever up; this is the same thing as an explicit state.
 */
enum PreferenceDialog {
  None,
  /** `requestModelTextInput` for one `editableText` row. */
  Text,
  /** `requestEditableListOverlay` for one list or map row. */
  Elements,
  /** The overlay's "new element" step. */
  Element,
  /** `requestResetConfirm`. */
  Reset
}

@ComponentV2
export struct PreferenceScreen {
  /** `android:label` on the two activities. */
  @Require @Param pageTitle: Resource = $r('app.string.override');

  /** The `category(...)` blocks, in order. */
  @Require @Param sections: PreferenceSection[] = [];

  /** The override record; absent keys are "do not modify". */
  @Require @Param data: Record<string, string> = {};

  /** Fired with a new record after any edit; the page owns the store. */
  @Event onDataChange: (data: Record<string, string>) => void = () => {
  };

  /** Fired by a `clickable` row, which has no value of its own. */
  @Event onRowAction: (key: string) => void = () => {
  };

  /** The user confirmed `requestResetConfirm`. */
  @Event onClear: () => void = () => {
  };

  /** The toolbar's back arrow. */
  @Event onBack: () => void = () => {
  };

  @Local dialog: PreferenceDialog = PreferenceDialog.None;

  /** The row the open dialog belongs to; `''` while none is open. */
  @Local editingKey: string = '';

  /** The text dialog's draft. */
  @Local draft: string = '';

  /** The list/map overlay's working copy: `[text]` or `[key, value]` rows. */
  @Local editingItems: string[][] = [];

  /** The "new element" step's two fields. */
  @Local draftKey: string = '';
  @Local draftValue: string = '';

  private manager(): resourceManager.ResourceManager {
    return getContext(this).resourceManager;
  }

  /** The row with `key`, across every section. */
  private rowByKey(key: string): OverrideRow | undefined {
    for (const section of this.sections) {
      for (const row of section.rows) {
        if (row.key === key) {
          return row;
        }
      }
    }
    return undefined;
  }

  /** The summary line, also used as the `ForEach` key. */
  private summaryText(row: OverrideRow): string {
    return overrideSummaryText(this.data, row, this.manager());
  }

  /**
   * `ForEach` re-runs its item generator only for entries whose key changed, so
   * the key has to carry everything the row draws -- otherwise a row whose
   * summary changed would keep rendering the old one.
   */
  private rowKey(row: OverrideRow): string {
    return `${row.key}|${this.summaryText(row)}`;
  }

  /** Mirrors `SelectableListPreference.popupSelectMenu`'s entries. */
  private selectMenu(row: OverrideRow): MenuElement[] {
    const manager: resourceManager.ResourceManager = this.manager();
    const entries: MenuElement[] = [];
    for (const option of row.options) {
      entries.push({
        value: manager.getStringSync(option.label.id),
        action: () => {
          this.select(row, option);
        }
      });
    }
    return entries;
  }

  /** `SelectableListPreference`'s item click: write the value, or `null`. */
  private select(row: OverrideRow, option: OverrideOption): void {
    if (option.value === '') {
      this.onDataChange(overrideRemove(this.data, row.key));
    } else {
      this.onDataChange(overridePut(this.data, row.key, option.value));
    }
  }

  /** `ClickablePreference.clicked` for an `editableText` row. */
  private openText(row: OverrideRow): void {
    this.draft = overrideGet(this.data, row.key);
    this.editingKey = row.key;
    this.dialog = PreferenceDialog.Text;
  }

  /** `ClickablePreference.clicked` for an `editableTextList`/`Map` row. */
  private openElements(row: OverrideRow): void {
    this.editingItems = row.kind === OverrideKind.List
      ? overrideList(this.data, row.key).map((item: string): string[] => [item])
      : overrideMap(this.data, row.key);
    this.editingKey = row.key;
    this.dialog = PreferenceDialog.Elements;
  }

  private openRow(row: OverrideRow): void {
    if (row.kind === OverrideKind.Action) {
      this.onRowAction(row.key);
      return;
    }
    if (row.kind === OverrideKind.List || row.kind === OverrideKind.Map) {
      this.openElements(row);
      return;
    }
    this.openText(row);
  }

  private closeDialog(): void {
    this.dialog = PreferenceDialog.None;
    this.editingKey = '';
  }

  /** `EditableTextPreference`'s OK: `adapter.to(text)` then `value.set`. */
  private acceptDraft(): void {
    const row: OverrideRow | undefined = this.rowByKey(this.editingKey);
    if (row === undefined) {
      this.closeDialog();
      return;
    }
    // `NullableTextAdapter.Port.to` / `.from`: the value is normalised through
    // the number, so `abc` and a blank both land on `0` -- "disabled".
    const text: string = row.port
      ? overridePortText(overridePortValue(this.draft))
      : this.draft;
    this.onDataChange(overridePut(this.data, row.key, text));
    this.closeDialog();
  }

  /** `EditableTextPreference`'s Reset: `value.set(null)`. */
  private resetDraft(): void {
    this.onDataChange(overrideRemove(this.data, this.editingKey));
    this.closeDialog();
  }

  /** `EditableListOverlayResult.Apply`. */
  private applyElements(): void {
    const row: OverrideRow | undefined = this.rowByKey(this.editingKey);
    if (row === undefined) {
      this.closeDialog();
      return;
    }
    const encoded: string = row.kind === OverrideKind.List
      ? overrideEncodeList(this.editingItems.map((item: string[]): string => item[0]))
      : overrideEncodeMap(this.editingItems);
    this.onDataChange(overridePut(this.data, row.key, encoded));
    this.closeDialog();
  }

  /** `EditableListOverlayResult.Reset`: the whole list goes back to `null`. */
  private resetElements(): void {
    this.onDataChange(overrideRemove(this.data, this.editingKey));
    this.closeDialog();
  }

  /** The overlay's `new_view`, which raises the "new element" dialog. */
  private openElementInput(): void {
    this.draftKey = '';
    this.draftValue = '';
    this.dialog = PreferenceDialog.Element;
  }

  /**
   * `EditableTextListAdapter.addElement` / `EditableTextMapAdapter.addElement`:
   * the new entry is appended, and the overlay comes back with it in the list.
   */
  private addElement(key: string, value: string): void {
    const row: OverrideRow | undefined = this.rowByKey(this.editingKey);
    const entry: string[] = row !== undefined && row.kind === OverrideKind.Map
      ? [key, value]
      : [key];
    const next: string[][] = [];
    for (const item of this.editingItems) {
      next.push(item);
    }
    next.push(entry);
    this.editingItems = next;
    this.dialog = PreferenceDialog.Elements;
  }

  /**
   * Android has no explanation for a disabled row here -- the dependent rows
   * simply stop responding while their owner is "disabled". The port keeps the
   * gesture and says why, the way `NetworkSettingsPage` does for its VPN rows.
   */
  private unavailable(): void {
    showToast($r('app.string.options_unavailable'));
  }

  /** The title of the row the open dialog belongs to. */
  private rowTitle(key: string): Resource {
    const row: OverrideRow | undefined = this.rowByKey(key);
    return row === undefined ? this.pageTitle : row.title;
  }

  private editingPairMode(): boolean {
    const row: OverrideRow | undefined = this.rowByKey(this.editingKey);
    return row !== undefined && row.kind === OverrideKind.Map;
  }

  /** The content cover's content: at most one dialog is ever up. */
  @Builder
  dialogContent() {
    if (this.dialog === PreferenceDialog.Text) {
      TextInputDialog({
        title: this.rowTitle(this.editingKey),
        initial: this.draft,
        hint: this.rowTitle(this.editingKey),
        showReset: true,
        onConfirm: (value: string) => {
          this.draft = value;
          this.acceptDraft();
        },
        onCancel: () => {
          this.closeDialog();
        },
        onReset: () => {
          this.resetDraft();
        }
      })
    }

    if (this.dialog === PreferenceDialog.Elements) {
      ElementListDialog({
        title: this.rowTitle(this.editingKey),
        pairMode: this.editingPairMode(),
        items: this.editingItems,
        onAdd: () => {
          this.openElementInput();
        },
        onDelete: (index: number) => {
          this.editingItems = this.editingItems.filter(
            (item: string[], position: number) => position !== index);
        },
        onReset: () => {
          this.resetElements();
        },
        onCancel: () => {
          this.closeDialog();
        },
        onApply: () => {
          this.applyElements();
        }
      })
    }

    if (this.dialog === PreferenceDialog.Element) {
      ElementInputDialog({
        title: this.rowTitle(this.editingKey),
        pairMode: this.editingPairMode(),
        onConfirm: (key: string, value: string) => {
          this.addElement(key, value);
        },
        onCancel: () => {
          this.dialog = PreferenceDialog.Elements;
        }
      })
    }

    if (this.dialog === PreferenceDialog.Reset) {
      this.resetDialog()
    }
  }

  /** `requestResetConfirm()` -- a Material dialog with two buttons. */
  @Builder
  resetDialog() {
    Column() {
      Column() {
        Text($r('app.string.reset_override_settings'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text($r('app.string.reset_override_settings_message'))
          .fontSize(15)
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: 12 })

        Row() {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .onClick(() => {
              this.closeDialog();
            })

          Button($r('app.string.ok'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .margin({ left: 8 })
            .onClick(() => {
              this.closeDialog();
              this.onClear();
            })
        }
        .width('100%')
        .margin({ top: 20 })
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
    Column() {
      // ---- ActivityBarLayout: back + title + clear_view ----
      Row() {
        Image($r('app.media.ic_baseline_arrow_back'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .onClick(() => {
            this.onBack();
          })

        Text(this.pageTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .margin({ left: $r('app.float.item_text_margin') })

        Image($r('app.media.ic_baseline_replay'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .onClick(() => {
            this.dialog = PreferenceDialog.Reset;
          })
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          ForEach(this.sections, (section: PreferenceSection) => {
            PreferenceCategory({ text: section.title })

            ForEach(section.rows, (row: OverrideRow) => {
              // The row markup is inlined rather than put in a `@Builder`: a
              // builder whose parameters are passed by value is not re-executed
              // when the parent's state changes.
              if (row.kind === OverrideKind.Select) {
                PreferenceList({
                  title: row.title,
                  summary: this.summaryText(row),
                  showIcon: false,
                  rowEnabled: overrideRowEnabled(this.data, row),
                  menuItems: this.selectMenu(row),
                  onDisabledTap: () => {
                    this.unavailable();
                  }
                })
              } else {
                ActionLabel({
                  text: row.title,
                  subtext: this.summaryText(row),
                  showIcon: false,
                  rowEnabled: overrideRowEnabled(this.data, row),
                  onAction: () => {
                    this.openRow(row);
                  },
                  onDisabledTap: () => {
                    this.unavailable();
                  }
                })
              }
            }, (row: OverrideRow) => this.rowKey(row))
          }, (section: PreferenceSection) => `${section.title.id}`)
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
    // `bindContentCover` rather than a `Stack` child or `.overlay()`: either of
    // those puts a full-size sibling above the `Scroll` and every gesture in it
    // stops firing.
    .bindContentCover(
      this.dialog !== PreferenceDialog.None,
      this.dialogContent(),
      { modalTransition: ModalTransition.NONE }
    )
  }
}
