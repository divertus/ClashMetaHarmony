/*
 * Log message model and the log-file codec.
 *
 * Ported from ClashMetaForAndroid:
 *   core/src/main/java/com/github/kr328/clash/core/model/LogMessage.kt
 *     -> `LogLevel`, `LogMessage`
 *   app/src/main/java/com/github/kr328/clash/log/LogcatReader.kt
 *     -> `parseLogFileContent` (file -> messages)
 *   app/src/main/java/com/github/kr328/clash/log/LogcatFilter.kt
 *     -> `formatLogFileContent` (messages -> file, used by the export action)
 *
 * File format written by LogcatFilter:
 *   # Capture on 2026-10-16 12:00:00.000
 *       12:00:01.000    Info: <message>
 * The reader skips `#` lines, then treats a line whose first `:`-separated
 * field parses as a number as `<epochMillis>:<Level>:<message>`; anything else
 * becomes a Warning carrying the previous timestamp.
 */

import { formatLogDate } from './LogFileModels';

export enum LogLevel {
  Debug = 'Debug',
  Info = 'Info',
  Warning = 'Warning',
  Error = 'Error',
  Silent = 'Silent',
  Unknown = 'Unknown'
}

export class LogMessage {
  level: LogLevel;
  message: string;

  /** Epoch milliseconds. */
  time: number;

  constructor(level: LogLevel, message: string, time: number) {
    this.level = level;
    this.message = message;
    this.time = time;
  }
}

/** `LogMessage.Level.valueOf(name)` -- throws on an unknown constant. */
function levelFromName(name: string): LogLevel {
  if (name === 'Debug') {
    return LogLevel.Debug;
  }
  if (name === 'Info') {
    return LogLevel.Info;
  }
  if (name === 'Warning') {
    return LogLevel.Warning;
  }
  if (name === 'Error') {
    return LogLevel.Error;
  }
  if (name === 'Silent') {
    return LogLevel.Silent;
  }
  if (name === 'Unknown') {
    return LogLevel.Unknown;
  }
  throw new Error(`unknown log level: ${name}`);
}

/** `String.toLongOrNull()` -- null when the text is not an integer. */
function parseEpochMillis(raw: string): number | null {
  if (!new RegExp('^[+-]?\\d+$').test(raw)) {
    return null;
  }
  const value: number = Number.parseInt(raw, 10);
  return Number.isNaN(value) ? null : value;
}

/** `String.split(delimiter, limit = 3)`. */
function splitLimited(line: string, limit: number): string[] {
  const parts: string[] = [];
  let rest: string = line;

  while (parts.length < limit - 1) {
    const index: number = rest.indexOf(':');
    if (index < 0) {
      break;
    }
    parts.push(rest.substring(0, index));
    rest = rest.substring(index + 1);
  }
  parts.push(rest);

  return parts;
}

/**
 * `BufferedReader.lineSequence()` -- splits on either line ending and does not
 * yield an extra empty line for a trailing newline.
 */
function splitLines(content: string): string[] {
  const lines: string[] = content.split(new RegExp('\\r?\\n'));
  if (lines.length > 0 && lines[lines.length - 1] === '') {
    lines.pop();
  }
  return lines;
}

/**
 * Mirrors `LogcatReader.readAll()`.
 *
 * Android indexes fields 1 and 2 without checking, so a line that starts with
 * a number but has no level is an IndexOutOfBoundsException; an unknown level
 * name is an IllegalArgumentException. Both surface to the caller as "this
 * file is not a log file", which is why they are rethrown here rather than
 * skipped.
 */
export function parseLogFileContent(content: string): LogMessage[] {
  const messages: LogMessage[] = [];
  let lastTime: number = 0;

  for (const rawLine of splitLines(content)) {
    const line: string = rawLine.trim();
    if (line.startsWith('#')) {
      continue;
    }

    const parts: string[] = splitLimited(line, 3);
    const parsedTime: number | null = parseEpochMillis(parts[0]);

    if (parsedTime !== null) {
      if (parts.length < 3) {
        throw new Error(`malformed log line: ${line}`);
      }
      lastTime = parsedTime;
      messages.push(new LogMessage(levelFromName(parts[1]), parts[2], parsedTime));
    } else {
      messages.push(new LogMessage(LogLevel.Warning, parts.join(':'), lastTime));
    }
  }

  return messages;
}

function pad(value: number, width: number): string {
  return value.toString().padStart(width, '0');
}

/** `Date.format(context, includeDate = false)` -- `HH:mm:ss.SSS`. */
export function formatLogTime(epochMillis: number): string {
  const date: Date = new Date(epochMillis);
  return `${pad(date.getHours(), 2)}:${pad(date.getMinutes(), 2)}:${pad(date.getSeconds(), 2)}` +
    `.${pad(date.getMilliseconds(), 3)}`;
}

/**
 * Mirrors `LogcatFilter.writeHeader` + `writeMessage`, i.e. the exact text the
 * export action hands to the document picker.
 */
export function formatLogFileContent(messages: LogMessage[], captureTime: number): string {
  let content: string = `# Capture on ${formatLogDate(captureTime)}\n`;
  for (const message of messages) {
    // "%12s %7s: %s" -- both fields are right-aligned.
    const time: string = formatLogTime(message.time).padStart(12, ' ');
    const level: string = message.level.toString().padStart(7, ' ');
    content += `${time} ${level}: ${message.message}\n`;
  }
  return content;
}
