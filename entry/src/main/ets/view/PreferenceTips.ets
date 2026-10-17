/*
 * PreferenceTips -- port of ClashMetaForAndroid's
 * `design/src/main/res/layout/preference_tips.xml` plus the `getHtml()` call
 * in `design/src/main/java/com/github/kr328/clash/design/preference/Tips.kt`.
 *
 * Android row: horizontal LinearLayout, gravity center_vertical,
 * paddingVertical item_padding_vertical:
 *   [ View(ic_outline_info) 25dp, marginHorizontal tips_icon_margin ]
 *   [ TextView(tips) Body2, marginEnd item_tailing_margin ]
 *
 * Android feeds the text through `Html.fromHtml` (`Context.getHtml`), so
 * `tips_help` arrives with `<strong>` emphasis. ArkUI's `Text` does not parse
 * markup, so the raw resource is split into styled `Span`s instead -- same
 * visible result, no HTML engine.
 */

/** One run of tip text plus whether Android would have bolded it. */
export class TipSegment {
  text: string;
  bold: boolean;

  constructor(text: string, bold: boolean) {
    this.text = text;
    this.bold = bold;
  }
}

const STRONG_OPEN: string = '<strong>';
const STRONG_CLOSE: string = '</strong>';

/**
 * Split `raw` on `<strong>`/`</strong>` pairs. Anything outside a pair is
 * emitted as plain text; an unterminated pair is emitted plainly rather than
 * dropped, so a malformed resource still renders its content.
 */
export function parseTipEmphasis(raw: string): TipSegment[] {
  const segments: TipSegment[] = [];
  let rest: string = raw;

  while (rest.length > 0) {
    const open: number = rest.indexOf(STRONG_OPEN);
    if (open < 0) {
      segments.push(new TipSegment(rest, false));
      break;
    }
    if (open > 0) {
      segments.push(new TipSegment(rest.substring(0, open), false));
    }

    const close: number = rest.indexOf(STRONG_CLOSE, open + STRONG_OPEN.length);
    if (close < 0) {
      segments.push(new TipSegment(rest.substring(open + STRONG_OPEN.length), false));
      break;
    }

    segments.push(new TipSegment(rest.substring(open + STRONG_OPEN.length, close), true));
    rest = rest.substring(close + STRONG_CLOSE.length);
  }

  return segments;
}

@ComponentV2
export struct PreferenceTips {
  /** Raw (markup-bearing) tip text, as it comes out of the resource. */
  @Require @Param raw: string = '';
  @Local segments: TipSegment[] = [];

  aboutToAppear(): void {
    this.segments = parseTipEmphasis(this.raw);
  }

  build() {
    Row() {
      Image($r('app.media.ic_outline_info'))
        .width($r('app.float.tips_icon_size'))
        .height($r('app.float.tips_icon_size'))
        .margin({
          left: $r('app.float.tips_icon_margin'),
          right: $r('app.float.tips_icon_margin')
        })
        .objectFit(ImageFit.Contain)
        .fillColor($r('app.color.color_control_normal'))

      Text() {
        ForEach(this.segments, (segment: TipSegment) => {
          Span(segment.text)
            .fontWeight(segment.bold ? FontWeight.Bold : FontWeight.Normal)
        }, (segment: TipSegment, index: number) => `${index}:${segment.text}`)
      }
      .fontSize(14)
      .layoutWeight(1)
      .margin({ right: $r('app.float.item_tailing_margin') })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      top: $r('app.float.item_padding_vertical'),
      bottom: $r('app.float.item_padding_vertical')
    })
  }
}
