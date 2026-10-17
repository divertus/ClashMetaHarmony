/*
 * The age key helpers behind the Meta-feature settings screen's two "Age Key"
 * rows.
 *
 * Android side (`MetaFeatureSettingsDesign.requestAgeKeyHelper`) is a dialog
 * over five `Clash` calls:
 *
 *   Clash.genX25519KeyPair()        the X25519 row's "Generate"
 *   Clash.genHybridKeyPair()        the MLKEM768-X25519 row's "Generate"
 *   Clash.toPublicKeys(secret)      "From Secret"
 *   Clash.veritySecretKeys(secret)  inline validation, on every keystroke
 *   Clash.verityPublicKeys(public)  inline validation, on every keystroke
 *
 * All five are core primitives -- the hybrid pair in particular exists only in
 * mihomo's `component/age`, so there is nothing to reimplement in ArkTS. This
 * module is the ArkTS half of the same calls: `libclashcore.so` forwards to the
 * `ohos_age_*` exports in
 * `work/clashmeta/core/src/main/golang/ohos/main.go`.
 *
 * The JSON envelopes are unwrapped here so the page never handles a raw
 * string. They exist because a key pair is *data*, not a success flag:
 * `{"ok":false,"error":"..."}` keeps the reason instead of collapsing into an
 * empty string the caller cannot explain to the user.
 *
 * These calls are pure crypto with no core state, so they work while the VPN
 * is stopped. `libclash.so` is loaded on demand when this module is first
 * imported, i.e. when the user opens the Meta-feature settings page.
 */

import {
  ageGenHybrid,
  ageGenX25519,
  ageToPublicKeys,
  ageVerifyPublicKeys,
  ageVerifySecretKeys
} from 'libclashcore.so';
import { pasteboard } from '@kit.BasicServicesKit';

/** Mirrors the Go `ageKeyPairResult` envelope. */
interface AgeKeyPairEnvelope {
  ok: boolean;
  secretKey?: string;
  publicKey?: string;
  error?: string;
}

/** Mirrors the Go `agePublicKeysResult` envelope. */
interface AgePublicKeysEnvelope {
  ok: boolean;
  publicKeys?: string[];
  error?: string;
}

/**
 * The two key types the dialog offers. Android passes a plain
 * `hybrid: Boolean`; an enum keeps the call sites readable.
 */
export enum AgeKeyKind {
  X25519,
  Hybrid
}

/** A generated identity, or the reason there is none. */
export class AgeKeyPair {
  ok: boolean = false;
  secretKey: string = '';
  publicKey: string = '';
  error: string = '';
}

function failure(message: string): AgeKeyPair {
  const result: AgeKeyPair = new AgeKeyPair();
  result.error = message;
  return result;
}

function parseKeyPair(encoded: string): AgeKeyPair {
  if (encoded.length === 0) {
    return failure('the native age helper returned nothing');
  }

  let envelope: AgeKeyPairEnvelope;
  try {
    envelope = JSON.parse(encoded) as AgeKeyPairEnvelope;
  } catch (error) {
    return failure('the native age helper returned malformed JSON');
  }

  if (!envelope.ok) {
    return failure(envelope.error ?? 'age key generation failed');
  }

  const result: AgeKeyPair = new AgeKeyPair();
  result.ok = true;
  result.secretKey = envelope.secretKey ?? '';
  result.publicKey = envelope.publicKey ?? '';
  return result;
}

/**
 * `Clash.genX25519KeyPair` / `Clash.genHybridKeyPair`. The pair comes back
 * together because the dialog fills both fields at once, as Android does.
 */
export function generateKeyPair(kind: AgeKeyKind): AgeKeyPair {
  try {
    const encoded: string = kind === AgeKeyKind.Hybrid ? ageGenHybrid() : ageGenX25519();
    return parseKeyPair(encoded);
  } catch (error) {
    return failure(`the native age helper threw: ${error}`);
  }
}

/**
 * `Clash.toPublicKeys(secret).firstOrNull() ?: ""` -- the "From Secret" button.
 *
 * A blank or unparseable secret yields `''`, which the page treats as "nothing
 * to fill in" exactly as Android's `?: ""` does. `Clash.toPublicKeys` accepts a
 * newline-separated list and returns one public key per identity, so a list
 * pasted into the field yields the first one rather than failing.
 */
export function deriveFirstPublicKey(secretKey: string): string {
  try {
    const encoded: string = ageToPublicKeys(secretKey);
    if (encoded.length === 0) {
      return '';
    }

    const envelope: AgePublicKeysEnvelope = JSON.parse(encoded) as AgePublicKeysEnvelope;
    if (!envelope.ok) {
      return '';
    }

    const publicKeys: string[] = envelope.publicKeys ?? [];
    return publicKeys.length > 0 ? publicKeys[0] : '';
  } catch (error) {
    return '';
  }
}

/**
 * `Clash.veritySecretKeys`.
 *
 * A blank field is *not* this function's business: Android's dialog reads
 * `secretKey.isBlank() || Clash.veritySecretKeys(secretKey)` so an empty field
 * is never an error, and that rule stays in the page next to the message it
 * shows.
 */
export function verifySecretKey(secretKey: string): boolean {
  try {
    return ageVerifySecretKeys(secretKey);
  } catch (error) {
    return false;
  }
}

/** `Clash.verityPublicKeys`, same blank-field rule as `verifySecretKey`. */
export function verifyPublicKey(publicKey: string): boolean {
  try {
    return ageVerifyPublicKeys(publicKey);
  } catch (error) {
    return false;
  }
}

/**
 * The dialog's two "Copy" buttons: `ClipboardManager.setPrimaryClip(
 * ClipData.newPlainText(label, value))`.
 *
 * Writing the clipboard needs no permission -- only *reading* it is
 * `system_basic` -- so this behaves exactly as it does on Android. Returns
 * false when the platform rejected the write, so the caller can say so instead
 * of claiming a copy that did not happen.
 */
export function copyToClipboard(text: string): boolean {
  try {
    const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
    board.setDataSync(pasteboard.createPlainTextData(text));
    return true;
  } catch (error) {
    return false;
  }
}
