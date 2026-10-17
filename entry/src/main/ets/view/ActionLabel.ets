/*
 * ActionLabel -- port of ClashMetaForAndroid's
 * `design/src/main/java/com/github/kr328/clash/design/view/ActionLabel.kt`
 * (a FrameLayout) which inflates `component_action_label.xml`.
 *
 * Android row: horizontal LinearLayout, gravity center_vertical,
 * minHeight item_min_height, paddingVertical item_padding_vertical:
 *   [ View(icon) 30dp, marginHorizontal item_header_margin ]
 *   [ vertical: text (Body1) / subtext (Body2, GONE when null) ]
 *
 * The preference screens use the same row shape
 * (`preference_clickable.xml`), so Help / ApkBroken reuse this component.
 * Those two pass `showIcon: false`; Android keeps the icon View in the tree
 * with no background, so the space is still reserved and the text stays
 * indented by the same 65dp -- `showIcon: false` therefore only drops the
 * image, not the slot.
 *
 * `rowEnabled` is `Preference.enabled`: Android's setter dims the whole row to
 * 33% and clears `clickable` / `focusable`, which is how `OverrideSettingsDesign`
 * switches off its `dnsDependencies` while the DNS strategy is "use built-in".
 * A disabled row reports taps through `onDisabledTap` instead, so a caller that
 * has an explanation to give can still give it.
 */

@ComponentV2
export struct ActionLabel {
  @Require @Param text: ResourceStr = '';
  @Param subtext: ResourceStr = '';
  @Param icon: Resource = $r('app.media.ic_baseline_settings');
  @Param showIcon: boolean = true;
  /** `Preference.enabled`; false dims the row to 33% and stops it responding. */
  @Param rowEnabled: boolean = true;
  @Event onAction: () => void = () => {
  };
  /** Fired instead of `onAction` when the row is disabled. */
  @Event onDisabledTap: () => void = () => {
  };

  build() {
    Row() {
      Stack() {
        if (this.showIcon) {
          Image(this.icon)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.color_control_normal'))
        }
      }
      .width($r('app.float.item_header_component_size'))
      .height($r('app.float.item_header_component_size'))
      .margin({
        left: $r('app.float.item_header_margin'),
        right: $r('app.float.item_header_margin')
      })

      Column() {
        Text(this.text)
          .fontSize(16)
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.subtext !== '') {
          Text(this.subtext)
            .fontSize(14)
            .opacity(0.6)
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: $r('app.float.item_text_margin') })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: $r('app.float.item_min_height') })
    .padding({
      top: $r('app.float.item_padding_vertical'),
      bottom: $r('app.float.item_padding_vertical'),
      right: $r('app.float.item_tailing_margin')
    })
    .opacity(this.rowEnabled ? 1 : 0.33)
    .onClick(() => {
      if (this.rowEnabled) {
        this.onAction();
      } else {
        this.onDisabledTap();
      }
    })
  }
}
