/*
 * ActionTextField -- port of ClashMetaForAndroid's
 * `design/src/main/java/com/github/kr328/clash/design/view/ActionTextField.kt`
 * which inflates `component_action_text_field.xml`.
 *
 * Android row: horizontal LinearLayout, gravity center_vertical,
 * minHeight item_min_height, paddingVertical item_padding_vertical:
 *   [ View(icon) 30dp, marginHorizontal item_header_margin ]
 *   [ FrameLayout:
 *       [ vertical: title (Caption) / text (Body1, marginTop item_text_margin,
 *                   ellipsize start, single line) / rule (divider_size,
 *                   colorControlNormal) ]
 *       [ ImageView edit 30dp, bottom|end ] ]
 *
 * Two behaviours come from `ActionTextField.setText`, not from the markup:
 *   - the value falls back to the hint (`app:placeholder`) while empty;
 *   - when the view is disabled the value is replaced with `unavailable` and
 *     the row drops to 33% alpha.
 *
 * This is a component rather than a `@Builder` on purpose: a `@Builder` whose
 * parameters are passed by value is not re-executed when the parent's state
 * changes, so the row would keep showing the value it was first built with.
 */

@ComponentV2
export struct ActionTextField {
  /** `app:title` -- the caption above the value. */
  @Require @Param title: ResourceStr = '';

  /** `app:text`; empty shows `placeholder` instead. */
  @Param value: string = '';

  /** `app:placeholder` -- the hint. */
  @Param placeholder: ResourceStr = '';

  /** `app:icon`. */
  @Param icon: Resource = $r('app.media.ic_outline_label');

  /** `app:enabled`. */
  @Param rowEnabled: boolean = true;

  @Event onAction: () => void = () => {
  };

  /**
   * `ActionTextField.text`'s setter: a disabled field shows `unavailable`
   * whatever its value is, and an empty enabled field shows the hint.
   */
  private displayValue(): ResourceStr {
    if (!this.rowEnabled) {
      return $r('app.string.unavailable');
    }
    return this.value !== '' ? this.value : this.placeholder;
  }

  build() {
    Row() {
      Image(this.icon)
        .width($r('app.float.item_header_component_size'))
        .height($r('app.float.item_header_component_size'))
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_control_normal'))
        .margin({
          left: $r('app.float.item_header_margin'),
          right: $r('app.float.item_header_margin')
        })

      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          Text(this.title)
            .fontSize(12)
            .opacity(0.6)
            .width('100%')
            .textAlign(TextAlign.Start)

          Text(this.displayValue())
            .fontSize(16)
            // The hint is muted; a real value -- and `unavailable` -- is not.
            .opacity(this.rowEnabled && this.value === '' ? 0.6 : 1)
            .width('100%')
            .textAlign(TextAlign.Start)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: $r('app.float.item_text_margin') })

          Divider()
            .strokeWidth(1)
            .color($r('app.color.color_control_normal'))
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Image($r('app.media.ic_baseline_edit'))
          .width($r('app.float.item_tailing_component_size'))
          .height($r('app.float.item_tailing_component_size'))
          .objectFit(ImageFit.Contain)
          .fillColor($r('app.color.color_control_normal'))
      }
      .layoutWeight(1)
      .margin({ right: $r('app.float.item_tailing_margin') })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: $r('app.float.item_min_height') })
    .padding({
      top: $r('app.float.item_padding_vertical'),
      bottom: $r('app.float.item_padding_vertical')
    })
    .opacity(this.rowEnabled ? 1 : 0.33)
    .onClick(() => {
      if (this.rowEnabled) {
        this.onAction();
      }
    })
  }
}
