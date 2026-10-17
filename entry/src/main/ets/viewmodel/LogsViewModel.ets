/*
 * ViewModel for the logs screen.
 *
 * Ported from ClashMetaForAndroid `LogsActivity.kt`:
 *
 *   Event.ActivityStart -> loadFiles()      = cacheDir/logs listing
 *   Request.DeleteAll   -> deleteAllLogs()  = logsDir.deleteRecursively()
 *   Request.OpenFile    -> LogcatActivity   (not ported)
 *   Request.StartLogcat -> LogcatActivity   (not ported)
 *
 * Android writes those files from the foreground `LogcatService`; that service
 * is not ported (see `outputs/logcat-streaming-harmonyos-feasibility.md`), so
 * nothing fills the directory and `files` is always empty on a device. The
 * listing, filtering and delete paths are the real ones, and `LogcatPage` can
 * still read, delete and export any file that does appear -- the port just has
 * no producer to hand it one.
 *
 * This is deliberately *not* papered over with a stub writer: the feasibility
 * review found no honest HarmonyOS equivalent of the core log subscription, so
 * the page reports an empty history and says why instead of inventing content.
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogFile, parseLogFileName } from '../model/LogFileModels';

@ObservedV2
export class LogsViewModel {
  @Trace files: LogFile[] = [];
  @Trace lastError: string = '';

  private cacheDir: string = '';

  /** `context.cacheDir` -- mirrors `cacheDir.resolve("logs")` on Android. */
  useCacheDir(cacheDir: string): void {
    this.cacheDir = cacheDir;
  }

  private logsDir(): string {
    return `${this.cacheDir}/logs`;
  }

  /** Mirrors `LogsActivity.loadFiles()`. */
  reload(): void {
    const dir: string = this.logsDir();
    try {
      if (!fs.accessSync(dir)) {
        this.files = [];
        this.lastError = '';
        return;
      }

      const parsed: LogFile[] = [];
      for (const name of fs.listFileSync(dir)) {
        const file: LogFile | null = parseLogFileName(name);
        if (file !== null) {
          parsed.push(file);
        }
      }

      this.files = parsed;
      this.lastError = '';
    } catch (error) {
      this.files = [];
      this.lastError = (error as BusinessError).message;
    }
  }

  /**
   * Mirrors `LogsActivity.deleteAllLogs()` = `logsDir.deleteRecursively()`.
   *
   * HarmonyOS `rmdirSync` refuses a non-empty directory (`13900032`), so the
   * files are unlinked first and the directory is removed after them.
   */
  deleteAll(): void {
    const dir: string = this.logsDir();
    try {
      if (fs.accessSync(dir)) {
        for (const name of fs.listFileSync(dir)) {
          fs.unlinkSync(`${dir}/${name}`);
        }
        fs.rmdirSync(dir);
      }

      this.files = [];
      this.lastError = '';
    } catch (error) {
      this.lastError = (error as BusinessError).message;
    }
  }
}
