/*
 * The VPN extension ability -- HarmonyOS's answer to Android's `VpnService`.
 *
 * Android's ClashMetaForAndroid carries mihomo in-process (gomobile + JNI) and
 * takes over traffic through `VpnService.Builder.establish()`, which hands back
 * a TUN file descriptor that the core pumps.
 *
 * HarmonyOS exposes the same shape, for third-party apps, since API 11:
 *
 *   `VpnExtensionAbility`  (extensionAbility `"type": "vpn"`)
 *   `vpnExtension.createVpnConnection(context).create(config)` -> TUN fd
 *   `VpnConnection.protect(socketFd)`  == `VpnService.protect()`
 *   `VpnConfig` addresses / routes / dnsAddresses / mtu / isBlocking /
 *   trustedApplications / blockedApplications == `Builder.addAddress` /
 *   `addRoute` / `addDnsServer` / `setMtu` / `addAllowedApplication` / ...
 *
 * The platform creates the virtual NIC and installs the routes; the tunnel
 * itself is the app's job -- exactly like Android. The system also shows a
 * trust dialog the first time a VPN app connects, and draws the key icon in
 * the status bar.
 *
 * The embedded mihomo core is `libclash.so`, built for OHOS arm64 from the
 * Android port's `cfa` Go module (`work/clashmeta/core/src/main/golang/ohos`)
 * and reached through `libclashcore.so`. This file owns the platform half:
 * create the TUN, protect the process's sockets, load the active profile, and
 * hand the descriptor to the core.
 *
 * THE MAPPING
 * -----------
 * Every value below comes from the `Want` that `Index.ets` built out of
 * `backend/VpnSettingsStore.ets`, and each one mirrors a line of Android's
 * `TunService.open()`:
 *
 *   bypassPrivateNetwork -> the route set: Android's `bypass_private_route`
 *                           (the complement of the private ranges, so private
 *                           networks keep the underlying route) plus the
 *                           virtual-DNS route; otherwise a single default route.
 *   dnsHijacking         -> the core's DNS hijack list: `0.0.0.0` (everything)
 *                           or the virtual DNS address only.
 *   allowIpv6            -> `isIPv6Accepted`, the `fdfe:dcba:9876::/` addresses
 *                           and their routes.
 *   tunStackMode         -> the sing-tun stack name.
 *   accessControlMode + selected packages -> `trustedApplications` /
 *                           `blockedApplications`, including Android's
 *                           "the VPN app itself is never inside its own tunnel".
 *
 * `systemProxy` and `allowBypass` are stored but not applied: `VpnConfig` has
 * no proxy field and no allow-bypass flag. See `pages/NetworkSettingsPage.ets`.
 */

import { connection, http, VpnExtensionAbility, vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  coreAttach,
  coreMarkSocketDone,
  corePrepare,
  coreSetAgeSecretKey,
  coreSetMarkSocket,
  coreStop,
  tunAttach
} from 'libclashcore.so';
import { Profile, ProfileType } from '../model/ProfileModels';
import {
  AccessControlMode,
  VpnSettings,
  accessControlModeName
} from '../model/NetworkSettingsModels';
import { VpnTunnelParameters, readVpnTunnelParameters } from '../backend/VpnSettingsStore';
import { ProfileFetchStatus, fetchProfileConfig } from '../backend/ProfileFetch';
import { ensureProfileDir, profileRootDir, readTextFile, writeTextFile } from '../backend/ProfileFiles';
import { markVpnRunning } from '../backend/VpnRuntime';

const DOMAIN: number = 0x0000;
const TAG: string = 'ClashVpnExt';

/** Package name used when the context cannot report it. Matches `module.json5`. */
const FALLBACK_BUNDLE_NAME: string = 'com.example.clashmeta';

/*
 * Android's `TunService.Companion` constants, verbatim. The gateway is the
 * address the interface carries, the portal is the address the core rewrites
 * outbound packets to (and answers DNS on), and the prefix is the subnet the
 * platform installs.
 */
const TUN_GATEWAY: string = '172.19.0.1';
const TUN_SUBNET_PREFIX: number = 30;
const TUN_GATEWAY6: string = 'fdfe:dcba:9876::1';
const TUN_SUBNET_PREFIX6: number = 126;
const TUN_PORTAL: string = '172.19.0.2';
const TUN_PORTAL6: string = 'fdfe:dcba:9876::2';
const TUN_MTU: number = 9000;
const NET_ANY: string = '0.0.0.0';
const NET_ANY6: string = '::';

/**
 * `R.array.bypass_private_route`: every IPv4 route except the private ranges
 * (`127/8`, `169.254/16`, `10/8`, `192.168/16`, `172.16/12`), so a private
 * destination keeps using the underlying network instead of entering the
 * tunnel. Spelled out rather than computed because this is the exact list
 * Android ships.
 */
const BYPASS_PRIVATE_ROUTES: string[] = [
  '1.0.0.0/8', '2.0.0.0/7', '4.0.0.0/6', '8.0.0.0/7', '11.0.0.0/8',
  '12.0.0.0/6', '16.0.0.0/4', '32.0.0.0/3', '64.0.0.0/3', '96.0.0.0/4',
  '112.0.0.0/5', '120.0.0.0/6', '124.0.0.0/7', '126.0.0.0/8', '128.0.0.0/3',
  '160.0.0.0/5', '168.0.0.0/8', '169.0.0.0/9', '169.128.0.0/10', '169.192.0.0/11',
  '169.224.0.0/12', '169.240.0.0/13', '169.248.0.0/14', '169.252.0.0/15',
  '169.255.0.0/16', '170.0.0.0/7', '172.0.0.0/12', '172.32.0.0/11',
  '172.64.0.0/10', '172.128.0.0/9', '173.0.0.0/8', '174.0.0.0/7', '176.0.0.0/4',
  '192.0.0.0/9', '192.128.0.0/11', '192.160.0.0/13', '192.169.0.0/16',
  '192.170.0.0/15', '192.172.0.0/14', '192.176.0.0/12', '192.192.0.0/10',
  '193.0.0.0/8', '194.0.0.0/7', '196.0.0.0/6', '200.0.0.0/5', '208.0.0.0/4',
  '240.0.0.0/5', '248.0.0.0/6', '252.0.0.0/7', '254.0.0.0/8', '255.0.0.0/9',
  '255.128.0.0/10', '255.192.0.0/11', '255.224.0.0/12', '255.240.0.0/13',
  '255.248.0.0/14', '255.252.0.0/15', '255.254.0.0/16', '255.255.0.0/17',
  '255.255.128.0/18', '255.255.192.0/19', '255.255.224.0/20', '255.255.240.0/21',
  '255.255.248.0/22', '255.255.252.0/23', '255.255.254.0/24', '255.255.255.0/25',
  '255.255.255.128/26', '255.255.255.192/27', '255.255.255.224/28',
  '255.255.255.240/29', '255.255.255.248/30', '255.255.255.252/31',
  '255.255.255.254/32'
];

/** `R.array.bypass_private_route6`, the same idea for IPv6. */
const BYPASS_PRIVATE_ROUTES6: string[] = [
  '::/1', '8000::/2', 'c000::/3', 'e000::/4', 'f000::/5', 'f800::/6',
  'fe00::/9', 'fec0::/10'
];

/** `TunService`'s debug profile, kept for the `vpnDebug` entry point. */
const DEBUG_PROFILE_UUID: string = 'ohos-debug';
const DEBUG_SUBSCRIPTION_URL: string =
  'https://sub.bwbwbw.cc/496615/3FDAEF37-47CD-341C-8BF6-32DF395C7663';

/** `parseCIDR`: `172.19.0.1/30` -> address + prefix length. */
function routeFromCidr(cidr: string, ipv6: boolean): vpnExtension.RouteInfo {
  const slash: number = cidr.indexOf('/');
  const address: string = cidr.substring(0, slash);
  const prefixLength: number = Number.parseInt(cidr.substring(slash + 1), 10);
  return {
    interface: '',
    destination: {
      address: { address: address, family: ipv6 ? 2 : 1 },
      prefixLength: prefixLength
    },
    gateway: { address: ipv6 ? NET_ANY6 : NET_ANY, family: ipv6 ? 2 : 1 },
    hasGateway: false,
    isDefaultRoute: false
  };
}

/** `Builder.addRoute(NET_ANY, 0)` / `Builder.addRoute(NET_ANY6, 0)`. */
function defaultRoute(ipv6: boolean): vpnExtension.RouteInfo {
  return {
    interface: '',
    destination: {
      address: { address: ipv6 ? NET_ANY6 : NET_ANY, family: ipv6 ? 2 : 1 },
      prefixLength: 0
    },
    gateway: { address: ipv6 ? NET_ANY6 : NET_ANY, family: ipv6 ? 2 : 1 },
    hasGateway: false,
    isDefaultRoute: true
  };
}

/**
 * Minimal IPv4 CIDR arithmetic used to keep the proxy and DNS servers out of
 * the TUN route set.
 *
 * `protectProcessNet()` is the first line of defence, but the OHOS VPN fd is
 * created by a different network namespace and the core's raw Go sockets are
 * not always covered by the process-wide protection. Keeping the servers the
 * core dials outside the VPN routes is the belt-and-braces fix: those sockets
 * then use the underlying network directly, so they cannot feed packets back
 * into the core's own TUN.
 */
class Cidr4 {
  base: number = 0;
  prefix: number = 0;
}

function ipv4ToNumber(address: string): number {
  const parts: string[] = address.split('.');
  let value: number = 0;
  for (const part of parts) {
    value = ((value * 256) + Number.parseInt(part, 10)) >>> 0;
  }
  return value;
}

function ipv4Mask(prefix: number): number {
  if (prefix <= 0) {
    return 0;
  }
  if (prefix >= 32) {
    return 0xFFFFFFFF;
  }
  return (0xFFFFFFFF << (32 - prefix)) >>> 0;
}

function parseCidr4(cidr: string): Cidr4 | null {
  const slash: number = cidr.indexOf('/');
  if (slash <= 0) {
    return null;
  }
  const prefix: number = Number.parseInt(cidr.substring(slash + 1), 10);
  if (!Number.isInteger(prefix) || prefix < 0 || prefix > 32) {
    return null;
  }
  const result: Cidr4 = new Cidr4();
  result.prefix = prefix;
  result.base = (ipv4ToNumber(cidr.substring(0, slash)) & ipv4Mask(prefix)) >>> 0;
  return result;
}

function cidr4ToString(cidr: Cidr4): string {
  const value: number = (cidr.base & ipv4Mask(cidr.prefix)) >>> 0;
  const a: number = (value >>> 24) & 0xFF;
  const b: number = (value >>> 16) & 0xFF;
  const c: number = (value >>> 8) & 0xFF;
  const d: number = value & 0xFF;
  return `${a}.${b}.${c}.${d}/${cidr.prefix}`;
}

function cidr4Contains(cidr: Cidr4, ip: number): boolean {
  const mask: number = ipv4Mask(cidr.prefix);
  return ((ip & mask) >>> 0) === ((cidr.base & mask) >>> 0);
}

function subtractIpv4(cidrs: Cidr4[], ip: number): Cidr4[] {
  const result: Cidr4[] = [];
  for (const cidr of cidrs) {
    if (!cidr4Contains(cidr, ip)) {
      result.push(cidr);
      continue;
    }
    if (cidr.prefix >= 32) {
      continue;
    }
    const left: Cidr4 = new Cidr4();
    left.base = cidr.base;
    left.prefix = cidr.prefix + 1;
    const right: Cidr4 = new Cidr4();
    right.base = (cidr.base + Math.pow(2, 31 - cidr.prefix)) >>> 0;
    right.prefix = cidr.prefix + 1;
    result.push(left);
    result.push(right);
  }
  return result;
}

function leadingSpaces(line: string): number {
  let count: number = 0;
  while (count < line.length && line.charAt(count) === ' ') {
    count++;
  }
  return count;
}

export default class ClashVpnExtension extends VpnExtensionAbility {
  private connection: vpnExtension.VpnConnection | null = null;
  private profileUuid: string = DEBUG_PROFILE_UUID;
  private profileSource: string = DEBUG_SUBSCRIPTION_URL;

  /** Everything the `Want` carried, or the Android defaults. */
  private tunnel: VpnTunnelParameters = new VpnTunnelParameters();

  /** Resolved proxy/DNS server IPv4 addresses kept outside the TUN routes. */
  private bypassIpv4: number[] = [];

  /**
   * The system calls this only after the user has accepted the VPN trust
   * dialog (or, on later runs, because the app already holds it).
   */
  onCreate(want: Want): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onCreate');
    this.tunnel = readVpnTunnelParameters(want);

    // `EntryAbility`'s `vpnDebug` entry point starts the extension with only
    // `vpnRoutes`; it predates the settings hand-off and asked for a full
    // default route, which is what `bypassPrivateNetwork = false` means.
    if (this.parameterValue(want, 'vpnRoutes') === '1' &&
      this.parameterValue(want, 'vpnSettings') === undefined) {
      this.tunnel.settings.bypassPrivateNetwork = false;
    }

    const uuid: string | undefined = this.parameterValue(want, 'profileUuid');
    if (uuid !== undefined && uuid.length > 0) {
      this.profileUuid = uuid;
      this.profileSource = '';
    }
    const source: string | undefined = this.parameterValue(want, 'profileSource');
    if (source !== undefined) {
      this.profileSource = source;
    }
    if (this.profileUuid === DEBUG_PROFILE_UUID && this.profileSource.length === 0) {
      this.profileSource = DEBUG_SUBSCRIPTION_URL;
    }

    hilog.info(DOMAIN, TAG,
      'settings: bypassPrivate=%{public}s dnsHijack=%{public}s allowBypass=%{public}s ' +
      'ipv6=%{public}s systemProxy=%{public}s stack=%{public}s accessControl=%{public}s ' +
      'selectedPackages=%{public}d',
      `${this.tunnel.settings.bypassPrivateNetwork}`,
      `${this.tunnel.settings.dnsHijacking}`,
      `${this.tunnel.settings.allowBypass}`,
      `${this.tunnel.settings.allowIpv6}`,
      `${this.tunnel.settings.systemProxy}`,
      this.tunnel.settings.tunStackMode,
      accessControlModeName(this.tunnel.accessControlMode),
      this.tunnel.accessControlPackages.length);

    // Protect the VPN process before the core creates any outbound socket.
    // `protectProcessNet()` only protects sockets created *after* the call;
    // calling it after `corePrepare()` leaves the core's startup DNS/provider
    // sockets unprotected, and their traffic is then routed back into the
    // TUN. On OHOS that feedback loop produced tens of thousands of fds and
    // the system's FdLeakDetector killed the VPN process.
    try {
      const connection: vpnExtension.VpnConnection =
        vpnExtension.createVpnConnection(this.context);
      this.connection = connection;
      coreSetMarkSocket((fd: number) => {
        connection.protect(fd).then(() => {
          coreMarkSocketDone(fd);
        }).catch((error: Object) => {
          coreMarkSocketDone(fd);
          hilog.error(DOMAIN, TAG, 'protect socket %{public}d failed: %{public}s',
            fd, JSON.stringify(error));
        });
      });
      connection.protectProcessNet().then(() => {
        this.prepareTunnel();
      }).catch((error: Object) => {
        hilog.error(DOMAIN, TAG, 'protectProcessNet failed: %{public}s',
          JSON.stringify(error));
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'createVpnConnection failed: %{public}s',
        JSON.stringify(error));
    }
  }

  private parameterValue(want: Want, name: string): string | undefined {
    try {
      const parameters: Record<string, Object> | undefined = want.parameters;
      if (parameters === undefined) {
        return undefined;
      }
      const value: Object = parameters[name];
      if (typeof value === 'string') {
        return value;
      }
    } catch (error) {
      // Malformed parameters are ignored.
    }
    return undefined;
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'onDestroy');
    markVpnRunning(this.context, false);
    coreStop();
    const connection: vpnExtension.VpnConnection | null = this.connection;
    this.connection = null;
    if (connection !== null) {
      connection.destroy().then(() => {
        hilog.info(DOMAIN, TAG, '%{public}s', 'tunnel destroyed');
      }).catch((error: Object) => {
        hilog.error(DOMAIN, TAG, 'destroy failed: %{public}s', JSON.stringify(error));
      });
    }
  }

  /** The bundle name, for Android's "never route the VPN app into itself" rule. */
  private bundleName(): string {
    try {
      const name: string = this.context.applicationInfo.name;
      if (name.length > 0) {
        return name;
      }
    } catch (error) {
      // Fall through to the constant.
    }
    return FALLBACK_BUNDLE_NAME;
  }

  /**
   * Fetch the profile before installing routes. That ordering keeps a failed
   * fetch from black-holing the phone while the core is not running.
   */
  private async prepareTunnel(): Promise<void> {
    try {
      const homeDir: string = this.context.filesDir;
      ensureProfileDir(this.context, this.profileUuid);
      const profileDir: string = profileRootDir(this.context, this.profileUuid);
      const configPath: string = `${profileDir}/config.yaml`;

      // Android's ProfileProcessor sets the age identity before it asks the
      // core to fetch/validate the profile. The port's fetch only downloads
      // bytes, but corePrepare still needs the key before it parses an age
      // armored config.
      const ageSecretKey: string = this.tunnel.ageSecretKey.trim().length === 0
        ? '' : this.tunnel.ageSecretKey;
      coreSetAgeSecretKey(ageSecretKey);
      hilog.info(DOMAIN, TAG, 'age secret key configured=%{public}s',
        `${ageSecretKey.length > 0}`);

      let haveConfig: boolean = false;
      if (fs.accessSync(configPath) && fs.statSync(configPath).size > 4096) {
        haveConfig = true;
      }
      if (!haveConfig) {
        const debugProfile: Profile = new Profile();
        debugProfile.uuid = this.profileUuid;
        debugProfile.name = this.profileUuid === DEBUG_PROFILE_UUID ? 'ohos-debug' : this.profileUuid;
        debugProfile.type = ProfileType.Url;
        debugProfile.source = this.profileSource;
        const fetched = await fetchProfileConfig(this.context, debugProfile);
        hilog.info(DOMAIN, TAG, 'debug profile fetch status=%{public}d bytes=%{public}d',
          fetched.status, fetched.bytes);
        if (fetched.status !== ProfileFetchStatus.Ok) {
          hilog.error(DOMAIN, TAG, 'debug profile fetch failed: %{public}s', fetched.message);
          if (this.profileUuid === DEBUG_PROFILE_UUID) {
            this.writeDummyProfile(configPath);
          } else {
            return;
          }
        }
      }
      const prepareError: string = corePrepare(homeDir, profileDir, '2.11.35');
      if (prepareError.length !== 0) {
        hilog.error(DOMAIN, TAG, 'mihomo core prepare failed: %{public}s', prepareError);
        return;
      }
      hilog.info(DOMAIN, TAG, '%{public}s', 'mihomo core prepared');
      this.bypassIpv4 = await this.resolveBypassIpv4(configPath);
      hilog.info(DOMAIN, TAG, 'resolved bypass IPv4 addresses=%{public}d',
        this.bypassIpv4.length);
      this.createTunnel(homeDir, profileDir);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'prepareTunnel failed: %{public}s', JSON.stringify(error));
    }
  }

  /** `Builder.addAddress` for the interface, IPv4 always and IPv6 on request. */
  private buildAddresses(settings: VpnSettings): vpnExtension.LinkAddress[] {
    const addresses: vpnExtension.LinkAddress[] = [
      {
        address: { address: TUN_GATEWAY, family: 1 },
        prefixLength: TUN_SUBNET_PREFIX
      }
    ];
    if (settings.allowIpv6) {
      addresses.push({
        address: { address: TUN_GATEWAY6, family: 2 },
        prefixLength: TUN_SUBNET_PREFIX6
      });
    }
    return addresses;
  }

  /**
   * Resolve the proxy servers and DNS servers out of `config.yaml` and return
   * their IPv4 addresses. These are the destinations the core itself dials;
   * they must stay outside the TUN routes.
   */
  private async resolveBypassIpv4(configPath: string): Promise<number[]> {
    const hosts: Set<string> = new Set<string>();
    let text: string = '';
    try {
      text = readTextFile(configPath);
    } catch (error) {
      return [];
    }

    const lines: string[] = text.split('\n');
    let dnsListIndent: number = -1;
    for (const rawLine of lines) {
      const line: string = rawLine.replace(/\r$/, '');
      const trimmed: string = line.trim();

      const serverMatch: RegExpMatchArray | null = trimmed.match(/^server:\s*([^\s#]+)/);
      if (serverMatch !== null) {
        hosts.add(serverMatch[1].replace(/["']/g, ''));
      }

      if (trimmed === 'nameserver:' || trimmed === 'default-nameserver:') {
        dnsListIndent = leadingSpaces(line);
        continue;
      }
      if (dnsListIndent >= 0) {
        const indent: number = leadingSpaces(line);
        if (trimmed.length > 0 && indent <= dnsListIndent && !trimmed.startsWith('-')) {
          dnsListIndent = -1;
        } else if (trimmed.startsWith('-')) {
          const value: string = trimmed.substring(1).trim();
          const host: string = value.replace(/^https?:\/\//, '').split('/')[0]
            .split(':')[0].replace(/["']/g, '');
          if (host.length > 0) {
            hosts.add(host);
          }
        }
      }
    }

    const result: Set<number> = new Set<number>();
    for (const host of hosts) {
      if (/^\d+\.\d+\.\d+\.\d+$/.test(host)) {
        result.add(ipv4ToNumber(host));
        continue;
      }
      let resolved: boolean = false;
      try {
        // Ask the core's own DNS resolver. The proxy servers are resolved by
        // this resolver inside the core, so these are the exact addresses the
        // dialer will use (and they are already in its DNS cache).
        const request: http.HttpRequest = http.createHttp();
        try {
          const response: http.HttpResponse = await request.request(
            `http://127.0.0.1:9090/dns/query?name=${encodeURIComponent(host)}&type=A`,
            {
              method: http.RequestMethod.GET,
              connectTimeout: 3000,
              readTimeout: 5000,
              expectDataType: http.HttpDataType.STRING,
              usingCache: false
            });
          if (typeof response.result === 'string') {
            const parsed: Record<string, Object> = JSON.parse(response.result) as Record<string, Object>;
            const answers: Object[] = parsed['Answer'] as Object[];
            if (answers !== undefined) {
              for (const answer of answers) {
                const item: Record<string, Object> = answer as Record<string, Object>;
                const data: Object = item['data'];
                const type: Object = item['type'];
                if (type === 1 && typeof data === 'string' &&
                  /^\d+\.\d+\.\d+\.\d+$/.test(data as string)) {
                  result.add(ipv4ToNumber(data as string));
                  resolved = true;
                }
              }
            }
          }
        } finally {
          request.destroy();
        }
      } catch (error) {
        // Fall through to the platform resolver.
      }
      if (resolved) {
        continue;
      }
      try {
        const addresses: connection.NetAddress[] =
          await connection.getAddressesByName(host);
        for (const address of addresses) {
          if (address.family === 1 && /^\d+\.\d+\.\d+\.\d+$/.test(address.address)) {
            result.add(ipv4ToNumber(address.address));
          }
        }
      } catch (error) {
        // A host that cannot be resolved is skipped; the core will report the
        // dial failure itself.
      }
    }
    const values: number[] = [];
    for (const value of result) {
      values.push(value);
    }
    return values;
  }

  /**
   * `Builder.addRoute` for both branches.
   *
   * With `bypassPrivateNetwork` the routes are the complement of the private
   * ranges plus the virtual DNS address; without it, one default route swallows
   * everything. Both branches mirror `TunService.open()`.
   */
  private buildRoutes(settings: VpnSettings): vpnExtension.RouteInfo[] {
    const routes: vpnExtension.RouteInfo[] = [];
    let base: Cidr4[] = [];
    if (settings.bypassPrivateNetwork) {
      for (const cidr of BYPASS_PRIVATE_ROUTES) {
        const parsed: Cidr4 | null = parseCidr4(cidr);
        if (parsed !== null) {
          base.push(parsed);
        }
      }
    } else {
      const all: Cidr4 = new Cidr4();
      all.base = 0;
      all.prefix = 0;
      base.push(all);
    }
    for (const ip of this.bypassIpv4) {
      base = subtractIpv4(base, ip);
    }
    for (const cidr of base) {
      routes.push(routeFromCidr(cidr4ToString(cidr), false));
    }
    // "Route of virtual DNS": `Builder.addRoute(TUN_DNS, 32)`.
    routes.push(routeFromCidr(`${TUN_PORTAL}/32`, false));
    if (settings.allowIpv6) {
      if (settings.bypassPrivateNetwork) {
        for (const cidr of BYPASS_PRIVATE_ROUTES6) {
          routes.push(routeFromCidr(cidr, true));
        }
      } else {
        routes.push(defaultRoute(true));
      }
      routes.push(routeFromCidr(`${TUN_PORTAL6}/128`, true));
    }
    return routes;
  }

  /**
   * `when (store.accessControlMode)`.
   *
   * `AcceptSelected` adds the VPN app itself to the trust list, which is
   * Android's way of keeping the tunnel from carrying its own traffic;
   * `DenySelected` removes it from the block list for the same reason.
   */
  private buildTrustedApplications(): string[] {
    if (this.tunnel.accessControlMode !== AccessControlMode.AcceptSelected) {
      return [];
    }
    const trusted: string[] = [];
    for (const packageName of this.tunnel.accessControlPackages) {
      trusted.push(packageName);
    }
    const self: string = this.bundleName();
    if (!trusted.includes(self)) {
      trusted.push(self);
    }
    return trusted;
  }

  private buildBlockedApplications(): string[] {
    // HarmonyOS has no "an app may opt itself out of the tunnel" API. The
    // closest supported equivalent is a user-managed bypass list expressed as
    // `blockedApplications`: the `allowBypass` master switch enables it, and
    // the access-control page's DenySelected set supplies the packages.
    if (!this.tunnel.settings.allowBypass ||
      this.tunnel.accessControlMode !== AccessControlMode.DenySelected) {
      return [];
    }
    const self: string = this.bundleName();
    const blocked: string[] = [];
    for (const packageName of this.tunnel.accessControlPackages) {
      if (packageName !== self) {
        blocked.push(packageName);
      }
    }
    return blocked;
  }

  /** `TunService`'s `gateway` argument: comma-separated interface prefixes. */
  private coreGateway(settings: VpnSettings): string {
    const v4: string = `${TUN_GATEWAY}/${TUN_SUBNET_PREFIX}`;
    if (!settings.allowIpv6) {
      return v4;
    }
    return `${v4},${TUN_GATEWAY6}/${TUN_SUBNET_PREFIX6}`;
  }

  /** `TunService`'s `portal` argument. */
  private corePortal(settings: VpnSettings): string {
    if (!settings.allowIpv6) {
      return TUN_PORTAL;
    }
    return `${TUN_PORTAL},${TUN_PORTAL6}`;
  }

  /**
   * `TunService`'s `dns` argument: which destinations the core treats as DNS.
   * `0.0.0.0` means "every DNS query on the tunnel"; otherwise only the virtual
   * DNS address is hijacked and everything else resolves normally.
   */
  private coreDns(settings: VpnSettings): string {
    if (settings.dnsHijacking) {
      return NET_ANY;
    }
    if (!settings.allowIpv6) {
      return TUN_PORTAL;
    }
    return `${TUN_PORTAL},${TUN_PORTAL6}`;
  }

  /** `create()` resolves with the TUN file descriptor. */
  private createTunnel(homeDir: string, profileDir: string): void {
    try {
      const settings: VpnSettings = this.tunnel.settings;
      const connection: vpnExtension.VpnConnection | null = this.connection;
      if (connection === null) {
        hilog.error(DOMAIN, TAG, '%{public}s', 'vpn connection is not initialized');
        return;
      }

      const config: vpnExtension.VpnConfig = {
        addresses: this.buildAddresses(settings),
        mtu: TUN_MTU,
        routes: this.buildRoutes(settings),
        // `Builder.addDnsServer(TUN_DNS)`, unconditional on Android: the DNS
        // server is the virtual portal, and `dnsHijacking` decides what the
        // *core* does with the packets, not what the system is told to use.
        dnsAddresses: settings.allowIpv6 ? [TUN_PORTAL, TUN_PORTAL6] : [TUN_PORTAL],
        isIPv4Accepted: true,
        isIPv6Accepted: settings.allowIpv6,
        isBlocking: false,
        trustedApplications: this.buildTrustedApplications(),
        blockedApplications: this.buildBlockedApplications()
      };

      hilog.info(DOMAIN, TAG,
        'VpnConfig: addresses=%{public}d routes=%{public}d dns=%{public}d ipv6=%{public}s ' +
        'trusted=%{public}d blocked=%{public}d',
        config.addresses.length, config.routes === undefined ? 0 : config.routes.length,
        config.dnsAddresses === undefined ? 0 : config.dnsAddresses.length,
        `${settings.allowIpv6}`,
        config.trustedApplications === undefined ? 0 : config.trustedApplications.length,
        config.blockedApplications === undefined ? 0 : config.blockedApplications.length);

      connection.create(config).then((tunFd: number) => {
        hilog.info(DOMAIN, TAG, 'tun fd = %{public}d', tunFd);
        try {
          hilog.info(DOMAIN, TAG, 'native probe: %{public}s', tunAttach(tunFd));
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'tunAttach failed: %{public}s', JSON.stringify(error));
        }
        this.startCore(connection, tunFd, settings);
      }).catch((error: Object) => {
        hilog.error(DOMAIN, TAG, 'create failed: %{public}s', JSON.stringify(error));
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'createVpnConnection threw: %{public}s', JSON.stringify(error));
    }
  }

  private startCore(
    connection: vpnExtension.VpnConnection, tunFd: number, settings: VpnSettings): void {
    const stack: string = settings.tunStackMode;
    const gateway: string = this.coreGateway(settings);
    const portal: string = this.corePortal(settings);
    const dns: string = this.coreDns(settings);
    hilog.info(DOMAIN, TAG,
      'coreAttach(fd=%{public}d, stack=%{public}s, gateway=%{public}s, portal=%{public}s, dns=%{public}s)',
      tunFd, stack, gateway, portal, dns);
    const error: string = coreAttach(tunFd, stack, gateway, portal, dns);
    if (error.length === 0) {
      hilog.info(DOMAIN, TAG, '%{public}s', 'mihomo core attached');
      // The tunnel is up: publish it for `isVpnRunning()`, which is what the
      // toggle shortcut and `ExternalControl` read. See `VpnRuntime.ets`.
      markVpnRunning(this.context, true);
    } else {
      hilog.error(DOMAIN, TAG, 'mihomo core attach failed: %{public}s', error);
      markVpnRunning(this.context, false);
      connection.destroy().catch((destroyError: Object) => {
        hilog.error(DOMAIN, TAG, 'destroy after core failure failed: %{public}s',
          JSON.stringify(destroyError));
      });
    }
  }

  private writeDummyProfile(configPath: string): void {
    const config: string = [
      'mixed-port: 7890',
      'external-controller: 127.0.0.1:9090',
      'mode: rule',
      'proxies:',
      '  - name: dummy',
      '    type: socks5',
      '    server: 127.0.0.1',
      '    port: 1',
      'proxy-groups:',
      '  - name: PROXY',
      '    type: select',
      '    proxies:',
      '      - dummy',
      '      - DIRECT',
      'rules:',
      '  - MATCH,PROXY',
      ''
    ].join('\n');
    writeTextFile(configPath, config);
  }
}
