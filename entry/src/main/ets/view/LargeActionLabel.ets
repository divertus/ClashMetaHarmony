/*
 * LargeActionLabel -- port of ClashMetaForAndroid's
 * `design/src/main/java/com/github/kr328/clash/design/view/LargeActionLabel.kt`
 * (FrameLayout + the same `component_large_action_label.xml` row the card uses).
 *
 * Difference from LargeActionCard: no card surface, no radius, no elevation --
 * just the tappable row. Subtext is optional; Android hides the view entirely
 * when subtext is null, so this renders it conditionally.
 */
@ComponentV2
export struct LargeActionLabel {
  @Require @Param text: ResourceStr = '';
  @Require @Param icon: Resource = $r('app.media.startIcon');
  @Param subtext: ResourceStr = '';
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
        .fillColor($r('app.color.color_light_control_disabled'))

      Column() {
        Text(this.text)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        if (this.subtext !== '') {
          Text(this.subtext)
            .fontSize(14)
            .opacity(0.6)
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: $r('app.float.large_item_text_margin') })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ right: $r('app.float.large_item_tailing_margin_horizontal') })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      top: $r('app.float.large_item_padding_vertical'),
      bottom: $r('app.float.large_item_padding_vertical')
    })
    .onClick(() => {
      this.onAction();
    })
  }
}
