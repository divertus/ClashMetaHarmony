# Profile QR share / scan on HarmonyOS

## Scope

This note covers the two Android ZXing/Quickie paths used by
ClashMetaForAndroid:

- `ProfilesActivity` / `ProfilesDesign.showProfileQrCode`: encode
  `profile.source` as a QR code and show it in a dialog.
- `NewProfileActivity` / `NewProfileDesign.Request.LaunchScanner`: open a
  scanner, then create a `Url` profile from the scanned payload.

## SDK evidence

### QR generation

The local ArkUI SDK has a public `QRCode` component:

- `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/ets/component/qrcode.d.ts`
- `QRCode(value: ResourceStr)`, plus `color`, `backgroundColor`, and
  `contentOpacity` attributes.
- `@syscap SystemCapability.ArkUI.ArkUI.Full`; available since API 7.

No ZXing or other QR encoder dependency is needed.

### QR scanning

The local HarmonyOS SDK contains the HMS Scan Kit declarations:

- `/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/kits/@kit.ScanKit.d.ts`
- `/Applications/DevEco-Studio.app/Contents/sdk/default/hms/ets/api/@hms.core.scan.scanBarcode.d.ts`
- `scanBarcode.startScanForResult(context, options?): Promise<ScanResult>`
  brings up the system default scanning UI.
- `ScanResult.originalValue` is the decoded string.
- `ScanOptions.scanTypes`, `enableMultiMode`, and `enableAlbum` are public.
- The official guide says the default Scan Kit UI pre-authorizes its camera
  access; no additional camera permission is requested by this app.

The project targets `HarmonyOS` API 26, so the API 11+/12+ Scan Kit surface is
available.

## Implementation

### Share QR code

`pages/ProfilesPage.ets` now:

1. Keeps the Android menu condition:
   `profile.imported && profile.type === Url && profile.source !== ''`.
2. Stores the URL in `shareSource` and opens a `bindContentCover` modal.
3. Renders `QRCode(this.shareSource)` at 240 x 240 with a white background.
4. Keeps the Android dialog shape: title, QR code, and a Close button.

`bindContentCover` is used for the same reason as the other ported dialogs:
a full-size `Stack` or `.overlay()` sibling above a `Scroll` can stop list
gestures from firing.

### Import from QR code

`pages/NewProfilePage.ets` now:

1. Calls `scanBarcode.startScanForResult(getContext(this), options)`.
2. Requests `scanCore.ScanType.QR_CODE` with multi-code and album scanning
   disabled, matching Android's camera-only Quickie scanner.
3. Uses `result.originalValue` as the profile source.
4. Creates a `Url` profile and pushes `PropertiesPage`, matching Android's
   `createProfileByQrCode`.

The documented error code `1000500002` (user canceled) is silent, matching
Android's `QRUserCanceled` branch. Other failures show
`import_from_qr_exception`.

## Known limits

- There is no Android-style `ACTION_PROVIDE_URL` provider list on HarmonyOS,
  so only the three built-in rows remain. This was already documented before
  this change.
- The Scan Kit default UI is a system-provided screen. The app does not render
  a custom camera preview or decode frames itself; that would require the
  separate `customScan`/`detectBarcode` APIs and a camera UI.
- The share dialog displays the QR code but does not invoke a system share
  sheet. Android's `showProfileQrCode` also only displays the QR code; the
  port matches that behavior. The profile URL itself remains visible in
  `PropertiesPage` and can be copied from there by the platform's normal text
  selection.
- Android catches ZXing's `WriterException` and shows
  `qr_code_generation_failed`. The declarative ArkUI `QRCode` component has no
  encoder call or error result, so that toast has no direct equivalent here.
- No device or full-build verification was run for this subtask. Static
  checking and a unified build are still required before claiming device
  behavior.
