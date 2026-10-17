/*
 * The geofile import target.
 *
 * Ported from ClashMetaForAndroid:
 *   app/src/main/java/com/github/kr328/clash/util/Files.kt  (`Context.clashDir`)
 *   app/src/main/java/com/github/kr328/clash/MetaFeatureSettingsActivity.kt
 *     (`importGeoFile`)
 *
 * Android copies the picked document into `filesDir/clash/<name><ext>` and
 * checks the extension first. HarmonyOS has no `OpenableColumns`, so the
 * display name comes from the document URI's last path segment, and the copy is
 * `fileIo.copyFileSync`, which accepts a picker URI as the source.
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

/** Android's `Context.clashDir`: `filesDir.resolve("clash")`. */
export function clashDir(context: common.Context): string {
  return `${context.filesDir}/clash`;
}

/** `MetaFeatureSettingsActivity.validDatabaseExtensions`. */
const VALID_EXTENSIONS: string[] = ['.metadb', '.db', '.dat', '.mmdb'];

/** Mirrors `MetaFeatureSettingsDesign.Request.Import*`. */
export enum GeoFileKind {
  GeoIp,
  GeoSite,
  Country,
  Asn
}

/** The `validDatabaseExtensions.joinToString("/")` the message interpolates. */
export function validGeoExtensions(): string {
  return VALID_EXTENSIONS.join('/');
}

/** `validDatabaseExtensions.contains(ext)`. */
export function isSupportedGeoExtension(ext: string): boolean {
  return VALID_EXTENSIONS.includes(ext);
}

/**
 * SAF's `OpenableColumns.DISPLAY_NAME` has no HarmonyOS equivalent; a picker
 * URI ends in the file name, which is the same string the file browser shows.
 */
export function displayNameOf(uri: string): string {
  const slash: number = uri.lastIndexOf('/');
  return slash >= 0 ? uri.substring(slash + 1) : uri;
}

/**
 * `"." + displayName.substringAfterLast(".")`. A name with no dot yields the
 * whole name prefixed with a dot, exactly as Android's `substringAfterLast`
 * does -- which then fails the extension check.
 */
export function extensionOf(displayName: string): string {
  return `.${displayName.substring(displayName.lastIndexOf('.') + 1)}`;
}

/** The `outputFileName` of `importGeoFile`. */
export function geoFileName(kind: GeoFileKind, ext: string): string {
  if (kind === GeoFileKind.GeoIp) {
    return `geoip${ext}`;
  }
  if (kind === GeoFileKind.GeoSite) {
    return `geosite${ext}`;
  }
  if (kind === GeoFileKind.Country) {
    return `country${ext}`;
  }
  return `ASN${ext}`;
}

/**
 * The `contentResolver.openInputStream(uri).copyTo(FileOutputStream(...))`
 * step. `mkdirSync(path, true)` throws when the directory already exists, so
 * existence is checked first -- an uncaught throw here would take the page
 * down (see `ProfileFiles.ensureDir`).
 */
export function importGeoFile(context: common.Context, uri: string,
  kind: GeoFileKind, ext: string): void {
  const dir: string = clashDir(context);
  if (!fs.accessSync(dir)) {
    fs.mkdirSync(dir, true);
  }
  fs.copyFileSync(uri, `${dir}/${geoFileName(kind, ext)}`);
}
