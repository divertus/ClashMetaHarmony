/*
 * Domain model for the app-settings screen.
 *
 * Ported from ClashMetaForAndroid:
 *   design/src/main/java/com/github/kr328/clash/design/model/DarkMode.kt
 *   design/src/main/java/com/github/kr328/clash/design/AppSettingsDesign.kt
 */

/**
 * Mirrors `DarkMode`. `Auto` follows the system, which is Android's default
 * and the behaviour HarmonyOS gives an app that never calls
 * `setColorMode()`.
 */
export enum DarkMode {
  Auto,
  ForceLight,
  ForceDark
}

/**
 * Requests raised by the app-settings screen.
 * Mirrors `AppSettingsDesign.Request`.
 */
export enum AppSettingsRequest {
  /** `Request.ReCreateAllActivities` -- Android recreates every open screen. */
  ReCreateAllActivities
}
