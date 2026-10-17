/*
 * PreferenceList -- ClashMetaForAndroid's `preference_clickable.xml` row whose
 * click opens a popup list instead of navigating.
 *
 * The row shape is identical to `ActionLabel` (Android builds both from the
 * same layout: icon slot 30dp, title Body1, summary Body2, minHeight
 * item_min_height), so this component is deliberately a copy of that markup
 * rather than a wrapper around it: `ActionLabel` registers `onClick`, and a row
 * that registers `onClick` swallows the `bindMenu` tap, so the menu never
 * opens. Keeping the gesture out of the row content is what makes the menu
 * work.
 *
 * Android's `selectableList` is `clickable(title, icon)` plus a
 * `ListPopupWindow`; the ArkUI equivalent is `bindMenu` with a `MenuElement[]`,
 * which has no nested form (see the proxy overflow menu for the same trade-off).
 *
 * `showIcon: false` drops the image but keeps the 30dp slot, matching Android:
 * `clickable()` only removes the icon View when `icon` is explicitly null, and
 * the switch rows leave it in the tree with no background.
 */

@ComponentV2
export struct PreferenceList {
  @Require @Param title: ResourceStr = '';
  @Require @Param summary: ResourceStr = '';
  @Param icon: Resource = $r('app.media.ic_baseline_settings');
  @Param showIcon: boolean = true;
  /** `Preference.enabled`; false dims the row to 33% and stops it opening. */
  @Param rowEnabled: boolean = true;
  @Require @Param menuItems: MenuElement[] = [];
  /** Fired instead of opening the menu when the row is disabled. */
  @Event onDisabledTap: () => void = () => {
  };

  @Builder
  rowContent() {
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
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: $r('app.float.item_min_height') })
    .padding({
      top: $r('app.float.item_padding_vertical'),
      bottom: $r('app.float.item_padding_vertical'),
      right: $r('app.float.item_tailing_margin')
    })
  }

  build() {
    Column() {
      if (this.rowEnabled) {
        Column() {
          this.rowContent()
        }
        .width('100%')
        .bindMenu(this.menuItems)
      } else {
        Column() {
          this.rowContent()
        }
        .width('100%')
        .opacity(0.33)
        .onClick(() => {
          this.onDisabledTap();
        })
      }
    }
    .width('100%')
  }
}
