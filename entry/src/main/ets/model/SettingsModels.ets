/*
 * Domain model for the settings hub.
 *
 * Ported from ClashMetaForAndroid:
 *   design/src/main/java/com/github/kr328/clash/design/SettingsDesign.kt
 */

/**
 * Navigation targets raised by the settings hub.
 * Mirrors `SettingsDesign.Request`.
 */
export enum SettingsRequest {
  StartApp,
  StartNetwork,
  StartOverride,
  StartMetaFeature
}
