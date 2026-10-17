/*
 * Log file model -- port of ClashMetaForAndroid
 * `design/src/main/java/com/github/kr328/clash/design/model/LogFile.kt`.
 *
 * Android stores one file per logcat session under `cacheDir/logs`, named
 * `clash-<epoch millis>.log`. The list screen parses the timestamp back out of
 * the file name and renders it as the row's summary.
 */

export class LogFile {
  fileName: string;

  /** Epoch milliseconds, parsed out of the file name. */
  date: number;

  constructor(fileName: string, date: number) {
    this.fileName = fileName;
    this.date = date;
  }
}

const FILE_NAME_PATTERN: RegExp = new RegExp('^clash-(\\d+)\\.log$');
const FILE_NAME_PREFIX: string = 'clash-';
const FILE_NAME_SUFFIX: string = '.log';

/** Mirrors `LogFile.parseFromFileName`: null when the name does not match. */
export function parseLogFileName(fileName: string): LogFile | null {
  const match: RegExpMatchArray | null = fileName.match(FILE_NAME_PATTERN);
  if (match === null) {
    return null;
  }
  return new LogFile(fileName, Number.parseInt(match[1], 10));
}

/** Mirrors `LogFile.generate()`: `clash-%d.log` for the given instant. */
export function generateLogFileName(epochMillis: number): string {
  return `${FILE_NAME_PREFIX}${epochMillis}${FILE_NAME_SUFFIX}`;
}

function pad(value: number, width: number): string {
  return value.toString().padStart(width, '0');
}

/**
 * Mirrors `Date.format(context)` with both flags on:
 * `SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", locale)`.
 *
 * The pattern has no locale-dependent fields, so the formatting is done
 * directly instead of going through the resource manager.
 */
export function formatLogDate(epochMillis: number): string {
  const date: Date = new Date(epochMillis);

  const day: string =
    `${date.getFullYear()}-${pad(date.getMonth() + 1, 2)}-${pad(date.getDate(), 2)}`;
  const time: string =
    `${pad(date.getHours(), 2)}:${pad(date.getMinutes(), 2)}:${pad(date.getSeconds(), 2)}` +
      `.${pad(date.getMilliseconds(), 3)}`;

  return `${day} ${time}`;
}
