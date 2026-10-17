/*
 * The profile file tree.
 *
 * Ported from ClashMetaForAndroid:
 *   service/src/main/java/com/github/kr328/clash/service/ProfileManager.kt
 *     (`create()` lays out `<uuid>/config.yaml` + `<uuid>/providers/`)
 *   app/src/main/java/com/github/kr328/clash/remote/FilesClient.kt
 *   service/src/main/java/com/github/kr328/clash/service/ProfileProvider.kt
 *
 * Android stores each profile under `files/profiles/<uuid>/` and reaches it
 * through a `DocumentsProvider` (`FilesClient` talks to it over the service
 * connection). HarmonyOS has no DocumentsProvider in this project, so the same
 * tree lives in the app sandbox (`<filesDir>/profiles/<uuid>/`) and is read and
 * written directly with `@kit.CoreFileKit`'s `fileIo`.
 *
 * The layout is deliberately identical to Android's, because `FilesActivity`
 * has a rule that depends on it: at the root, a `config.yaml` of size 0 hides
 * every other entry (`FilesActivity.fetch` returns `listOf(config)` in that
 * case), i.e. providers only show up once the configuration has content.
 */

import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { FileEntry } from '../model/FileModels';

/** `<filesDir>/profiles/<uuid>` -- Android's `files/profiles/<uuid>/`. */
export function profileRootDir(context: common.Context, uuid: string): string {
  return `${context.filesDir}/profiles/${uuid}`;
}

/**
 * `mkdirSync(path, true)` still throws `File exists` when the directory is
 * already there, which is not what Android's `mkdirs()` does -- it returns
 * false and carries on. An uncaught throw here takes the whole page down, so
 * existence is checked first.
 */
function ensureDir(path: string): void {
  if (!fs.accessSync(path)) {
    fs.mkdirSync(path, true);
  }
}

/** Android's `ProfileManager.create()` directory setup. */
export function ensureProfileDir(context: common.Context, uuid: string): void {
  const root: string = profileRootDir(context, uuid);
  ensureDir(root);
  ensureDir(`${root}/providers`);

  const config: string = `${root}/config.yaml`;
  if (!fs.accessSync(config)) {
    writeTextFile(config, '');
  }
}

/** Mirrors `FilesClient.list(documentId)`. */
export function listEntries(dir: string): FileEntry[] {
  if (!fs.accessSync(dir)) {
    return [];
  }

  const entries: FileEntry[] = [];
  for (const name of fs.listFileSync(dir)) {
    const path: string = `${dir}/${name}`;
    const stat = fs.statSync(path);
    const entry: FileEntry = new FileEntry();
    entry.id = path;
    entry.name = name;
    entry.directory = stat.isDirectory();
    entry.size = entry.directory ? 0 : stat.size;
    // `Stat.mtime` is in seconds; Android's `lastModified` is in milliseconds.
    entry.lastModified = stat.mtime * 1000;
    entries.push(entry);
  }

  // Android renders whatever order the DocumentsProvider returns, which is the
  // filesystem's. Directories-first then by name is the convention every file
  // browser uses, so the port sorts instead of showing an arbitrary order.
  entries.sort((left: FileEntry, right: FileEntry) => {
    if (left.directory !== right.directory) {
      return left.directory ? -1 : 1;
    }
    return left.name.localeCompare(right.name);
  });
  return entries;
}

/** Mirrors `FilesClient.deleteDocument(file.id)`. */
export function deleteEntry(entry: FileEntry): void {
  if (entry.directory) {
    fs.rmdirSync(entry.id);
  } else {
    fs.unlinkSync(entry.id);
  }
}

/** Mirrors `FilesClient.renameDocument(file.id, newName)`. */
export function renameEntry(entry: FileEntry, newName: string): void {
  const parent: string = entry.id.substring(0, entry.id.lastIndexOf('/'));
  fs.renameSync(entry.id, `${parent}/${newName}`);
}

/** Read a whole file as UTF-8 text. */
export function readTextFile(path: string): string {
  const stat = fs.statSync(path);
  if (stat.size === 0) {
    return '';
  }

  const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
  try {
    const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
    const length: number = fs.readSync(file.fd, buffer);
    return util.TextDecoder.create('utf-8').decodeToString(new Uint8Array(buffer, 0, length));
  } finally {
    fs.closeSync(file);
  }
}

/** Replace a file's contents with `text`, creating it when missing. */
export function writeTextFile(path: string, text: string): void {
  const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    if (text.length === 0) {
      return;
    }
    const encoded: Uint8Array = util.TextEncoder.create('utf-8').encodeInto(text);
    fs.writeSync(file.fd, encoded.buffer);
  } finally {
    fs.closeSync(file);
  }
}

/** Mirrors `FilesClient.importDocument(dir, uri, name)` / `copyDocument`. */
export function copyFile(sourcePath: string, targetPath: string): void {
  fs.copyFileSync(sourcePath, targetPath);
}

/*
 * Mirror of `FilesClient.copyDocument(source, target)` for the directions where
 * one side is a picker URI rather than a sandbox path.
 *
 * `copyFileSync` takes paths, file descriptors or URIs on either side, which is
 * exactly the shape needed here. Reading the URI by hand (`openSync` +
 * `statSync(fd)` + `readSync` + `writeSync`) fails on a picker URI, so the
 * single call is also the correct one.
 */

/** Mirror of `FilesClient.copyDocument(source, target)` -- sandbox to picker. */
export function copyToUri(sourcePath: string, targetUri: string): void {
  fs.copyFileSync(sourcePath, targetUri);
}

/** Mirror of `FilesClient.copyDocument(uri, target)` -- picker to sandbox. */
export function copyFromUri(sourceUri: string, targetPath: string): void {
  fs.copyFileSync(sourceUri, targetPath);
}
