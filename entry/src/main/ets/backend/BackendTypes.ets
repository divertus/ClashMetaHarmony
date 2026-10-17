/*
 * Shared contract between the main screen's ViewModel and any backend.
 *
 * Kept in its own module so `MainViewModel` and `ExternalControllerBackend` can
 * both depend on it without importing each other.
 */

import { TunnelMode } from '../model/MainModels';

/**
 * Snapshot returned by a backend poll.
 *
 * Traffic totals are raw bytes. The Android core returned a packed 64-bit value
 * instead (2 bits of unit type + 30 bits of data per direction); the external
 * controller reports plain byte deltas, so the packing step is skipped and the
 * only shared piece is the final formatting.
 */
export interface BackendSnapshot {
  connected: boolean;
  uploadBytes: number;
  downloadBytes: number;
  mode: TunnelMode;
  profileName: string;
  hasProfile: boolean;
  hasProviders: boolean;
}

/** Data source for the main screen. */
export interface ClashBackend {
  snapshot(): Promise<BackendSnapshot>;

  /** Returns whether the backend became usable. */
  start(): Promise<boolean>;

  stop(): Promise<void>;
}

/** Reports "not connected, nothing configured". */
export class NullClashBackend implements ClashBackend {
  async snapshot(): Promise<BackendSnapshot> {
    const empty: BackendSnapshot = {
      connected: false,
      uploadBytes: 0,
      downloadBytes: 0,
      mode: TunnelMode.Rule,
      profileName: '',
      hasProfile: false,
      hasProviders: false
    };
    return empty;
  }

  async start(): Promise<boolean> {
    return false;
  }

  async stop(): Promise<void> {
  }
}
