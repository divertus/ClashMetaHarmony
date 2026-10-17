/*
 * ElementListDialog -- port of ClashMetaForAndroid's `requestEditableListOverlay`
 * (`design/src/main/java/com/github/kr328/clash/design/preference/Overlay.kt`),
 * which inflates `dialog_preference_list.xml` into a `FullScreenDialog`.
 *
 * Android structure:
 *   RelativeLayout
 *   +- title_view    (Headline6, aligned to the toolbar row)
 *   +- new_view      (ic_baseline_add, alignParentEnd)
 *   +- main_list     (RecyclerView, between the title and the buttons)
 *   +- reset_view / cancel_view / ok_view  (text buttons along the bottom)
 *
 * The list rows are `adapter_editable_text_list.xml` (text + a trailing
 * `ic_baseline_close` delete button) or `adapter_editable_text_map.xml`
 * (key on Body1, value on Body2, same delete button).
 *
 * The three results map onto `EditableListOverlayResult`:
 *   Reset  -> the caller drops the value back to `null` ("do not modify")
 *   Apply  -> the caller stores the working copy
 *   Cancel -> the caller keeps whatever it had
 *
 * The component is stateless on purpose: the working copy lives in the page, so
 * that opening the "new element" dialog and coming back does not lose it. That
 * is also why the rows are keyed by content as well as position -- the page
 * replaces the whole array on every edit.
 */

@ComponentV2
export struct ElementListDialog {
  /** `binding.titleView.text` -- the preference row's title. */
  @Require @Param title: ResourceStr = '';

  /** `true` for `editableTextMap`: rows carry a key and a value. */
  @Param pairMode: boolean = false;

  /** The working copy; one `[text]` or `[key, value]` entry per row. */
  @Require @Param items: string[][] = [];

  @Event onAdd: () => void = () => {
  };

  @Event onDelete: (index: number) => void = () => {
  };

  @Event onReset: () => void = () => {
  };

  @Event onCancel: () => void = () => {
  };

  @Event onApply: () => void = () => {
  };

  /** `ForEach` identity: position plus content, never the position alone. */
  private rowKey(index: number): string {
    return `${index}\u0001${this.items[index].join('\u0002')}`;
  }

  build() {
    Column() {
      // ---- title + `new_view` ----
      Row() {
        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: $r('app.float.item_header_margin') })

        Image($r('app.media.ic_baseline_add'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
          .margin({ right: $r('app.float.item_tailing_margin') })
          .onClick(() => {
            this.onAdd();
          })
      }
      .width('100%')
      .height($r('app.float.toolbar_height'))
      .alignItems(VerticalAlign.Center)

      // ---- `main_list` ----
      List() {
        ForEach(this.items, (item: string[], index: number) => {
          ListItem() {
            // The row markup is inlined rather than put in a `@Builder`: a
            // builder whose parameters are passed by value is not re-executed
            // when the parent's state changes.
            Row() {
              Column() {
                Text(item[0])
                  .fontSize(16)
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })

                if (this.pairMode) {
                  Text(item[1])
                    .fontSize(14)
                    .opacity(0.6)
                    .width('100%')
                    .textAlign(TextAlign.Start)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: $r('app.float.item_text_margin') })
                }
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Image($r('app.media.ic_baseline_close'))
                .width($r('app.float.item_tailing_component_size'))
                .height($r('app.float.item_tailing_component_size'))
                .objectFit(ImageFit.Contain)
                .fillColor($r('app.color.color_control_normal'))
                .onClick(() => {
                  this.onDelete(index);
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .constraintSize({ minHeight: $r('app.float.item_min_height') })
            .padding({
              top: $r('app.float.item_padding_vertical'),
              bottom: $r('app.float.item_padding_vertical'),
              left: $r('app.float.item_header_margin'),
              right: $r('app.float.item_tailing_margin')
            })
          }
        }, (item: string[], index: number) => this.rowKey(index))
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // ---- `reset_view` / `cancel_view` / `ok_view` ----
      Row() {
        Button($r('app.string.reset'))
          .height(40)
          .fontSize(15)
          .fontColor($r('app.color.color_primary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onReset();
          })

        Blank()

        Button($r('app.string.cancel'))
          .height(40)
          .fontSize(15)
          .fontColor($r('app.color.color_primary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onCancel();
          })

        Button($r('app.string.ok'))
          .height(40)
          .fontSize(15)
          .fontColor($r('app.color.color_primary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.onApply();
          })
      }
      .width('100%')
      .padding({
        left: 12,
        right: 12,
        top: 8,
        bottom: 8
      })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.color_background'))
  }
}

/*
 * ElementInputDialog -- the "add an element" step of the same overlay.
 *
 * Android reaches it two different ways: a list calls `requestModelTextInput`
 * (one field, no reset button) and a map calls `requestModelInputEntry`
 * (`dialog_editable_map_text_field.xml`: a `key` field over a `value` field).
 * Both are Material dialogs raised *over* the overlay; this port raises them as
 * a separate step of the same content cover, because nesting two covers is not
 * reliable and a `Stack` over the overlay's `List` would swallow its gestures.
 *
 * `requestModelInputEntry` only accepts an entry when both fields are non-blank,
 * so `onConfirm` is only reachable with a non-empty key here.
 */

@ComponentV2
export struct ElementInputDialog {
  /** `title` passed to the dialog; the preference row's title. */
  @Require @Param title: ResourceStr = '';

  /** `true` for `requestModelInputEntry`: two fields instead of one. */
  @Param pairMode: boolean = false;

  @Event onConfirm: (key: string, value: string) => void = () => {
  };

  @Event onCancel: () => void = () => {
  };

  @Local draftKey: string = '';
  @Local draftValue: string = '';

  build() {
    Column() {
      Column() {
        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        TextInput({ text: this.draftKey, placeholder: this.pairMode ? $r('app.string.key') : '' })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .onChange((value: string) => {
            this.draftKey = value;
          })

        if (this.pairMode) {
          TextInput({ text: this.draftValue, placeholder: $r('app.string.value') })
            .width('100%')
            .height(44)
            .margin({ top: 8 })
            .onChange((value: string) => {
              this.draftValue = value;
            })
        }

        Row() {
          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .onClick(() => {
              this.onCancel();
            })

          Button($r('app.string.ok'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .margin({ left: 8 })
            // `requestModelInputEntry` ignores an entry with a blank key, and a
            // blank value; a list only rejects a blank text.
            .enabled(this.draftKey.trim() !== ''
              && (!this.pairMode || this.draftValue.trim() !== ''))
            .onClick(() => {
              this.onConfirm(this.draftKey.trim(), this.draftValue.trim());
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
}
