/*
 * Domain model for the profile file browser.
 *
 * Ported from ClashMetaForAndroid:
 *   design/src/main/java/com/github/kr328/clash/design/model/File.kt
 *   design/src/main/java/com/github/kr328/clash/design/FilesDesign.kt
 *   design/src/main/java/com/github/kr328/clash/FilesActivity.kt
 */

/**
 * One row of the file list. Mirrors `File`, except that `id` is the absolute
 * path in the app sandbox rather than a DocumentsProvider document id.
 */
export class FileEntry {
  /** `File.id`. */
  id: string = '';

  /** `File.name`. */
  name: string = '';

  /** `File.size`, in bytes; 0 for directories. */
  size: number = 0;

  /** `File.lastModified`, in milliseconds since the epoch. */
  lastModified: number = 0;

  /** `File.isDirectory`. */
  directory: boolean = false;
}

/** Requests raised by the file browser. Mirrors `FilesDesign.Request`. */
export enum FilesRequest {
  OpenFile,
  OpenDirectory,
  RenameFile,
  DeleteFile,
  ImportFile,
  ExportFile,
  PopStack
}

/**
 * `PatternFileName` from `common/src/main/java/com/github/kr328/clash/common/
 * util/Patterns.kt`: `Regex("[^*&%\\n\\r/]+")`, plus the `isNotBlank()` that
 * `ValidatorFileName` adds on top.
 */
export function isValidFileName(name: string): boolean {
  if (name.trim() === '') {
    return false;
  }
  return !/[*&%\n\r/]/.test(name);
}
