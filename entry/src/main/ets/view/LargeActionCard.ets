/*
 * LargeActionCard -- port of ClashMetaForAndroid's
 * `design/src/main/java/com/github/kr328/clash/design/view/LargeActionCard.kt`
 * which inflates `design/src/main/res/layout/component_large_action_label.xml`.
 *
 * Android: MaterialCardView + a horizontal LinearLayout of [icon 30dp]
 * [vertical LinearLayout: text (Body1) / subtext (Body2)].
 * HarmonyOS: Row + borderRadius/shadow (CardView maps to a styled container,
 * per the atomic component mapping reference), min height 85vp, radius 8vp.
 *
 * `LargeActionCard` itself sets no text colour, so the icon and both lines
 * inherit `android:textColor` = `?attr/colorControlNormal` from whichever
 * theme is in scope. `design_main.xml` pins the status card to
 * `android:theme="@style/AppThemeDark"` (white content in both app themes)
 * while the proxy and profile cards follow the app theme, so the content
 * colour is a parameter rather than a constant.
 */
@ComponentV2
export struct LargeActionCard {
  @Require @Param text: ResourceStr = '';
  @Require @Param subtext: ResourceStr = '';
  @Require @Param icon: Resource = $r('app.media.startIcon');
  @Param cardColor: ResourceColor = $r('app.color.color_clash_stopped');
  @Param contentColor: ResourceColor = $r('app.color.color_control_normal');
  @Event onAction: () => void = () => {
  };

  build() {
    Row() {
      Image(this.icon)
        .width($r('app.float.large_item_header_component_size'))
        .height($r('app.float.large_item_header_component_size'))
        .margin({
          left: $r('app.float.large_item_header_margin_horizontal'),
          right: $r('app.float.large_item_header_margin_horizontal')
        })
        .objectFit(ImageFit.Contain)
        .fillColor(this.contentColor)

      Column() {
        Text(this.text)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.contentColor)
          .width('100%')
          .textAlign(TextAlign.Start)

        Text(this.subtext)
          .fontSize(14)
          .fontColor(this.contentColor)
          .opacity(0.72)
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ top: $r('app.float.large_item_text_margin') })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ right: $r('app.float.large_item_tailing_margin_horizontal') })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .constraintSize({ minHeight: $r('app.float.large_action_card_min_height') })
    .padding({
      top: $r('app.float.large_item_padding_vertical'),
      bottom: $r('app.float.large_item_padding_vertical')
    })
    .backgroundColor(this.cardColor)
    .borderRadius($r('app.float.large_action_card_radius'))
    .shadow({ radius: 5, color: '#33000000', offsetX: 0, offsetY: 2 })
    .onClick(() => {
      this.onAction();
    })
  }
}
