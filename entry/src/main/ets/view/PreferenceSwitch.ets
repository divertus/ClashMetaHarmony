/*
 * PreferenceSwitch -- port of ClashMetaForAndroid's
 * `design/src/main/res/layout/preference_switch.xml` plus the `switch()`
 * builder in `design/src/main/java/com/github/kr328/clash/design/preference/
 * Switch.kt`.
 *
 * Android row: RelativeLayout, minHeight item_min_height, clickable,
 * paddingEnd item_tailing_margin:
 *   [ View(icon) 30dp, marginHorizontal item_header_margin ]
 *   [ vertical: title (Body1) / summary (Body2) ]
 *   [ SwitchMaterial, alignParentEnd ]
 *
 * Two details from `Switch.kt` that the markup alone does not show:
 *   - the switch itself is neither clickable nor focusable; the whole row
 *     toggles the value, so the switch must not swallow taps here either;
 *   - `enabled = false` dims the *row* to 33% and stops it responding, rather
 *     than drawing the switch in its own disabled state.
 *
 * `showIcon: false` drops the image but keeps the 30dp slot: `switch()` only
 * sets a background when an icon resource is passed, and `preference_switch.xml`
 * leaves the icon View in the tree either way.
 *
 * The row reports taps through `onAction` rather than owning the value: Android
 * flips the switch first and then hands the new value to the listener, but
 * every caller in this port is a stub that has to explain why the control does
 * nothing, so the parent stays in charge of `checked`.
 *
 * `rowEnabled` is `Preference.enabled`: false dims the whole row to 33% and
 * stops it responding. A disabled row reports its tap through `onDisabledTap`
 * instead of `onAction`, exactly like `ActionLabel` and `PreferenceList`, so a
 * caller with an explanation to give can still give it -- and a row the user
 * cannot use never fires the caller's real action.
 */

@ComponentV2
export struct PreferenceSwitch {
  @Require @Param title: ResourceStr = '';
  @Param summary: ResourceStr = '';
  @Param icon: Resource = $r('app.media.ic_baseline_settings');
  @Param showIcon: boolean = true;
  @Param checked: boolean = false;
  /** `enabled` is a built-in component attribute, so the flag is named here. */
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
        Text(this.title)
          .fontSize(16)
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.summary !== '') {
          Text(this.summary)
            .fontSize(14)
            .opacity(0.6)
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: $r('app.float.item_text_margin') })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .selectedColor($r('app.color.color_primary'))
        // The row owns the gesture, exactly as `binding.root.setOnClickListener`
        // does on Android; the switch stays visually enabled.
        .hitTestBehavior(HitTestMode.None)
        .margin({ right: $r('app.float.item_tailing_margin') })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: $r('app.float.item_min_height') })
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
