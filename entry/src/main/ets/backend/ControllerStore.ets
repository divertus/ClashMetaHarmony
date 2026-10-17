/*
 * Connection settings for a mihomo external controller.
 *
 * CMFA on Android talks to an in-process mihomo core over JNI and takes over
 * traffic through VpnService. HarmonyOS *does* have a public equivalent --
 * `VpnExtensionAbility` + `@ohos.net.vpnExtension` (API 11+), and this port has
 * already created a `vpn-tun` with it (see `vpnextension/ClashVpnExtension.ets`
 * and PORT-STATUS §21) -- but there is no mihomo build for HarmonyOS to feed
 * that interface, so the form this app actually takes today is a *controller*
 * for a mihomo instance running elsewhere (router / desktop / NAS) over its
 * external-controller API. That is also how CMFA's own ExternalControlActivity
 * is shaped.
 *
 * Persisted with PersistenceV2 so it survives restarts without needing a
 * Context here.
 */

import { PersistenceV2 } from '@kit.ArkUI';

@ObservedV2
export class ControllerStore {
  static readonly KEY: string = 'ClashControllerStore';

  /** mihomo external-controller base URL, e.g. http://192.168.1.1:9090 */
  @Trace baseUrl: string = 'http://127.0.0.1:9090';

  /** `secret` from the mihomo config; empty when the controller has none. */
  @Trace secret: string = '';
}

/** Load the persisted store, or create the default one on first run. */
export function loadControllerStore(): ControllerStore {
  const store: ControllerStore | undefined =
    PersistenceV2.connect(ControllerStore, ControllerStore.KEY, () => new ControllerStore());
  return store ?? new ControllerStore();
}
