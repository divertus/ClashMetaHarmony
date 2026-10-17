/*
 * A one-field modal, standing in for ClashMetaForAndroid's
 * `requestModelTextInput` (`design/src/main/java/com/github/kr328/clash/design/
 * dialog/TextInput.kt`), which is a Material `AlertDialog` around a single
 * `TextInputLayout`.
 *
 * ArkUI's `promptAction` dialogs cannot host an input, so the dialog is drawn
 * here as a scrim plus a card and presented with `bindContentCover` -- not as a
 * `Stack` child or `.overlay()`, because either of those makes every gesture
 * inside a `Scroll` on the page underneath stop firing.
 *
 * The parent owns the validation result and passes it back in as `errorText`;
 * this component only holds the draft while the user types.
 *
 * `showReset` reproduces the neutral button that `requestModelTextInput` adds
 * when it is called with a `reset` label -- `EditableText` passes `R.string.reset`
 * so a value can be put back to `null`, i.e. "do not modify". The button order
 * is the Material one: neutral, negative, positive.
 */

@ComponentV2
export struct TextInputDialog {
  /** Dialog title, e.g. `R.string.file_name`. */
  @Require @Param title: ResourceStr = '';

  /** `requestModelTextInput(initial = ...)`. */
  @Param initial: string = '';

  /** `requestModelTextInput(hint = ...)`. */
  @Param hint: ResourceStr = '';

  /** `requestModelTextInput(error = ...)`, shown once validation fails. */
  @Param errorText: ResourceStr = '';

  /** Adds the neutral button when the caller has a `null` state to go back to. */
  @Param showReset: boolean = false;

  @Event onConfirm: (value: string) => void = () => {
  };

  @Event onCancel: () => void = () => {
  };

  @Event onReset: () => void = () => {
  };

  @Local draft: string = '';

  aboutToAppear(): void {
    this.draft = this.initial;
  }

  build() {
    Column() {
      Column() {
        Text(this.title)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .width('100%')
          .textAlign(TextAlign.Start)

        TextInput({ text: this.draft, placeholder: this.hint })
          .width('100%')
          .height(44)
          .margin({ top: 16 })
          .onChange((value: string) => {
            this.draft = value;
          })

        if (this.errorText !== '') {
          Text(this.errorText)
            .fontSize(12)
            .fontColor($r('app.color.color_error'))
            .width('100%')
            .textAlign(TextAlign.Start)
            .margin({ top: 4 })
        }

        Row() {
          if (this.showReset) {
            Button($r('app.string.reset'))
              .layoutWeight(1)
              .height(40)
              .fontSize(15)
              .fontColor($r('app.color.color_control_normal'))
              .backgroundColor($r('app.color.color_surface'))
              .onClick(() => {
                this.onReset();
              })
          }

          Button($r('app.string.cancel'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .fontColor($r('app.color.color_control_normal'))
            .backgroundColor($r('app.color.color_surface'))
            .margin({ left: this.showReset ? 8 : 0 })
            .onClick(() => {
              this.onCancel();
            })

          Button($r('app.string.ok'))
            .layoutWeight(1)
            .height(40)
            .fontSize(15)
            .margin({ left: 8 })
            .onClick(() => {
              this.onConfirm(this.draft);
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
