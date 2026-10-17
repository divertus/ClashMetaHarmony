/*
 * PreferenceCategory -- port of ClashMetaForAndroid's
 * `design/src/main/res/layout/preference_category.xml`.
 *
 * Android: a single TextView, paddingVertical item_padding_vertical,
 * paddingStart = item_header_component_size + item_header_margin * 2 (so the
 * heading lines up with the text of the rows below it), paddingEnd
 * item_tailing_margin, textColor ?attr/colorControlActivated.
 *
 * `colorControlActivated` is `?attr/colorPrimary` in both themes
 * (`design/src/main/res/values/themes.xml`), so this maps to the semantic
 * `color_primary`: #1e4376 in light, #1976d2 in dark.
 */

/** item_header_component_size (30) + item_header_margin (17.5) * 2. */
const CATEGORY_INDENT: number = 65;

@ComponentV2
export struct PreferenceCategory {
  @Require @Param text: ResourceStr = '';

  build() {
    Text(this.text)
      .fontSize(14)
      .fontColor($r('app.color.color_primary'))
      .width('100%')
      .textAlign(TextAlign.Start)
      .padding({
        top: $r('app.float.item_padding_vertical'),
        bottom: $r('app.float.item_padding_vertical'),
        left: CATEGORY_INDENT,
        right: $r('app.float.item_tailing_margin')
      })
  }
}
