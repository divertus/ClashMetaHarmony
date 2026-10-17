/*
 * Home-screen service card for the Clash tunnel.
 *
 * The three action buttons post `message` events to `EntryFormAbility`. The
 * extension translates those messages into the same
 * `startVpnExtensionAbility` / `stopVpnExtensionAbility` calls the main screen
 * and the static shortcuts use, then updates the card through
 * `formProvider.updateForm`.
 *
 * `@LocalStorageProp` is the card-data binding documented by FormKit: the
 * extension returns the values from `onAddForm`, and later refreshes replace
 * them without recreating the card UI.
 */

@Entry
@Component
struct ClashCard {
  @LocalStorageProp('running') running: string = 'false';
  @LocalStorageProp('statusText') statusText: string = 'Clash';
  @LocalStorageProp('profileText') profileText: string = '';

  private send(command: string): void {
    postCardAction(this, {
      action: 'message',
      params: {
        message: command
      }
    });
  }

  @Builder
  CardAction(icon: Resource, label: Resource, command: string) {
    Column() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor($r('app.color.color_primary'))
      Text(label)
        .fontSize(10)
        .fontColor($r('app.color.color_control_normal'))
        .margin({ top: 2 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(48)
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.color_background'))
    .borderRadius(8)
    .margin({ left: 2, right: 2 })
    .onClick(() => {
      this.send(command);
    })
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_clash'))
          .width(24)
          .height(24)
        Text($r('app.string.application_name'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 8 })
        Blank()
        Text(this.statusText)
          .fontSize(12)
          .fontColor(this.running === 'true'
            ? $r('app.color.color_clash_started')
            : $r('app.color.color_clash_stopped'))
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        postCardAction(this, {
          action: 'router',
          bundleName: 'com.example.clashmeta',
          moduleName: 'entry',
          abilityName: 'EntryAbility'
        });
      })

      Text(this.profileText)
        .fontSize(12)
        .fontColor($r('app.color.color_clash_stopped'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 4 })
        .width('100%')
        .textAlign(TextAlign.Start)

      Row() {
        this.CardAction(
          $r('app.media.ic_baseline_flash_on'),
          $r('app.string.shortcut_start_short'),
          'clash:start'
        )
        this.CardAction(
          $r('app.media.ic_baseline_swap_vert'),
          $r('app.string.shortcut_toggle_short'),
          'clash:toggle'
        )
        this.CardAction(
          $r('app.media.ic_baseline_stop'),
          $r('app.string.shortcut_stop_short'),
          'clash:stop'
        )
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
      .margin({ top: 10 })
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor($r('app.color.color_surface'))
    .borderRadius(8)
  }
}
