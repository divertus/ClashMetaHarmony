/*
 * ViewModel for the logcat screen, local-file mode.
 *
 * Ported from ClashMetaForAndroid `LogcatActivity.kt`:
 *
 *   LogFile.parseFromFileName(fileName) -> null ? showInvalid()
 *   LogcatReader(this, file).readAll()  -> read failure ? showInvalid()
 *   Request.Delete                      -> logsDir/file.delete(), finish
 *   Request.Export                      -> write the messages back out
 *
 * The streaming half of the activity (bind `LogcatService`, tick every 500ms)
 * is not ported: the service is a foreground Android service and the core's
 * log subscription has no HarmonyOS equivalent. `LogcatDesign(this, false)` --
 * the local-file branch -- is what this ViewModel covers.
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LogFile, parseLogFileName } from '../model/LogFileModels';
import {
  LogMessage,
  formatLogFileContent,
  parseLogFileContent
} from '../model/LogMessageModels';

@ObservedV2
export class LogcatViewModel {
  @Trace messages: LogMessage[] = [];

  /** Mirrors `showInvalid()`: the file is missing, unreadable or malformed. */
  @Trace invalid: boolean = false;
  @Trace lastError: string = '';

  private filePath: string = '';
  private file: LogFile = new LogFile('', 0);

  /** `LogFile.parseFromFileName(fileName)` -- false when the name is not one. */
  resolveFile(fileName: string): boolean {
    const file: LogFile | null = parseLogFileName(fileName);
    if (file === null) {
      return false;
    }
    this.file = file;
    return true;
  }

  /** Mirrors `LogcatReader(this, file).readAll()`. */
  load(logsDir: string): void {
    this.filePath = `${logsDir}/${this.file.fileName}`;
    try {
      const content: string = fs.readTextSync(this.filePath);
      this.messages = parseLogFileContent(content);
      this.invalid = false;
      this.lastError = '';
    } catch (error) {
      this.messages = [];
      this.invalid = true;
      this.lastError = (error as BusinessError).message;
    }
  }

  /** Mirrors `LogcatDesign.Request.Delete` -> `logsDir/file.delete()`. */
  deleteFile(): void {
    try {
      fs.unlinkSync(this.filePath);
      this.messages = [];
      this.lastError = '';
    } catch (error) {
      this.lastError = (error as BusinessError).message;
    }
  }

  /** Mirrors `writeLogTo` -> `LogcatFilter.writeHeader/writeMessage`. */
  exportContent(): string {
    return formatLogFileContent(this.messages, this.file.date);
  }

  fileName(): string {
    return this.file.fileName;
  }
}
