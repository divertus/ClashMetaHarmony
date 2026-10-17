/*
 * Domain model for the override-settings screen.
 *
 * Ported from ClashMetaForAndroid:
 *   core/src/main/java/com/github/kr328/clash/core/model/ConfigurationOverride.kt
 *   design/src/main/java/com/github/kr328/clash/design/OverrideSettingsDesign.kt
 *   design/src/main/java/com/github/kr328/clash/design/preference/*.kt
 *   design/src/main/res/layout/preference_clickable.xml
 *
 * Android holds the override in a `ConfigurationOverride` whose every field is
 * nullable, and reads `null` as "do not modify": `NullableTextAdapter.Port`
 * turns that into an empty edit field and `EditableText` turns it into the
 * `placeholder` summary. Every row is therefore in one of three states:
 *
 *   unset        -> `placeholder`  ("Do not modify")
 *   set, empty   -> `empty`        ("Disabled" / "Default" / "Empty")
 *   set, a value -> the value
 *
 * This port keeps the same model in one flat `Record<string, string>`: a row is
 * *absent* from the record while it is unset and present -- possibly as the
 * empty string -- once it is set. Lists and maps are stored as their JSON text,
 * so a single record type covers all four row kinds and the whole override
 * survives `PersistenceV2` as one string.
 *
 * All four builders in `preference/` render the *same* row
 * (`preference_clickable.xml`: a 30dp icon slot, a Body1 title and a Body2
 * summary), so the screen is a table of `OverrideRow` values rather than the
 * `component_action_text_field.xml` shape that `PropertiesDesign` uses.
 *
 * Summaries are resolved to plain strings here rather than left as `Resource`s:
 * the page keys each row by its rendered content (see `OverrideSettingsPage`),
 * and a `Resource`'s identity does not change when its `format_elements`
 * argument does.
 */

import { resourceManager } from '@kit.LocalizationKit';

/** Which `preference/` builder produced a row. */
export enum OverrideKind {
  /** `editableText` -- one nullable string or port number. */
  Text,
  /** `editableTextList` -- a nullable list of strings. */
  List,
  /** `editableTextMap` -- a nullable string-to-string map. */
  Map,
  /** `selectableList` -- one of a fixed set of values. */
  Select,
  /**
   * `clickable(title, summary)` with no value at all: the row only raises a
   * request (`MetaFeatureSettingsDesign`'s age-key and geofile rows).
   */
  Action
}

/**
 * One entry of a `selectableList`. `value` is the wire value written into the
 * override; the empty string is the `null` entry, i.e. "do not modify".
 */
export interface OverrideOption {
  value: string;
  label: Resource;
}

/**
 * One row of the preference screen. `placeholder` / `emptyLabel` are `''` on
 * rows that do not use them; `options` is empty on every non-`Select` row.
 */
export interface OverrideRow {
  /** Stable identity, and the key this row uses in the override record. */
  key: string;
  kind: OverrideKind;
  title: Resource;
  /** `placeholder`: shown while the row is unset. */
  placeholder: Resource;
  /** `empty`: shown when the row is set to the empty string. */
  emptyLabel: Resource;
  /** `values` / `valuesText` of a `selectableList`. */
  options: OverrideOption[];
  /** `NullableTextAdapter.Port`: the row is edited as a port number. */
  port: boolean;
  /**
   * The key of the row that owns this one, or `''` for a top-level row.
   * `dnsDependencies` in `OverrideSettingsDesign` and `snifferDependencies` in
   * `MetaFeatureSettingsDesign` are both "disabled while <owner> is `false`",
   * so one field covers both.
   */
  dependsOn: string;
}

/** One `category(title) { ... }` block. */
export interface PreferenceSection {
  title: Resource;
  rows: OverrideRow[];
}

/**
 * The shared `booleanValues` / `booleanValuesText` pair from
 * `OverrideSettingsDesign`; nine rows use it.
 */
export function overrideBooleanOptions(): OverrideOption[] {
  return [
    { value: '', label: $r('app.string.dont_modify') },
    { value: 'true', label: $r('app.string.enabled') },
    { value: 'false', label: $r('app.string.disabled') }
  ];
}

/** `configuration::mode`: `TunnelState.Mode`'s three serial names. */
function overrideModeOptions(): OverrideOption[] {
  return [
    { value: '', label: $r('app.string.dont_modify') },
    { value: 'direct', label: $r('app.string.direct_mode') },
    { value: 'global', label: $r('app.string.global_mode') },
    { value: 'rule', label: $r('app.string.rule_mode') }
  ];
}

/** `configuration::logLevel`: `LogMessage.Level`'s five real serial names. */
function overrideLogLevelOptions(): OverrideOption[] {
  return [
    { value: '', label: $r('app.string.dont_modify') },
    { value: 'info', label: $r('app.string.info') },
    { value: 'warning', label: $r('app.string.warning') },
    { value: 'error', label: $r('app.string.error') },
    { value: 'debug', label: $r('app.string.debug') },
    { value: 'silent', label: $r('app.string.silent') }
  ];
}

/** `configuration.dns::enable`, titled `strategy`. */
function overrideDnsStrategyOptions(): OverrideOption[] {
  return [
    { value: '', label: $r('app.string.dont_modify') },
    { value: 'true', label: $r('app.string.force_enable') },
    { value: 'false', label: $r('app.string.use_built_in') }
  ];
}

/**
 * `configuration.dns::enhancedMode`. The enum's serial names are the mihomo
 * config values (`normal` / `fake-ip` / `redir-host`), while the labels are the
 * `disabled` / `fakeip` / `mapping` strings.
 */
function overrideDnsEnhancedModeOptions(): OverrideOption[] {
  return [
    { value: '', label: $r('app.string.dont_modify') },
    { value: 'normal', label: $r('app.string.disabled') },
    { value: 'fake-ip', label: $r('app.string.fakeip') },
    { value: 'redir-host', label: $r('app.string.mapping') }
  ];
}

/** `configuration.dns::fakeIPFilterMode`: `FilterMode`'s serial names. */
function overrideDnsFilterModeOptions(): OverrideOption[] {
  return [
    { value: '', label: $r('app.string.dont_modify') },
    { value: 'blacklist', label: $r('app.string.blacklist') },
    { value: 'whitelist', label: $r('app.string.whitelist') },
    { value: 'rule', label: $r('app.string.rule') }
  ];
}

/** A `Text` row. `owner` is `''` for a top-level row. */
function textRow(key: string, title: Resource, emptyLabel: Resource,
  port: boolean, owner: string): OverrideRow {
  return {
    key: key,
    kind: OverrideKind.Text,
    title: title,
    placeholder: $r('app.string.dont_modify'),
    emptyLabel: emptyLabel,
    options: [],
    port: port,
    dependsOn: owner
  };
}

/** A `List` row; `EditableTextListPreference` has no `empty` argument, so an
 * empty list reads as `R.string.empty`. */
function listRow(key: string, title: Resource, owner: string): OverrideRow {
  return {
    key: key,
    kind: OverrideKind.List,
    title: title,
    placeholder: $r('app.string.dont_modify'),
    emptyLabel: $r('app.string.empty'),
    options: [],
    port: false,
    dependsOn: owner
  };
}

/** A `Map` row; same empty state as a list. */
function mapRow(key: string, title: Resource, owner: string): OverrideRow {
  return {
    key: key,
    kind: OverrideKind.Map,
    title: title,
    placeholder: $r('app.string.dont_modify'),
    emptyLabel: $r('app.string.empty'),
    options: [],
    port: false,
    dependsOn: owner
  };
}

/** A `Select` row; its summary is always one of `options`, so `emptyLabel` is
 * unused and only kept so the row shape stays uniform. */
function selectRow(key: string, title: Resource, options: OverrideOption[],
  owner: string): OverrideRow {
  return {
    key: key,
    kind: OverrideKind.Select,
    title: title,
    placeholder: $r('app.string.dont_modify'),
    emptyLabel: $r('app.string.empty'),
    options: options,
    port: false,
    dependsOn: owner
  };
}

/**
 * A `clickable(title, summary)` row. `MetaFeatureSettingsDesign` uses it for
 * the two age-key rows and the four geofile imports; the summary is fixed text
 * rather than a value, so it rides in `placeholder`.
 */
function actionRow(key: string, title: Resource, summary: Resource,
  owner: string): OverrideRow {
  return {
    key: key,
    kind: OverrideKind.Action,
    title: title,
    placeholder: summary,
    emptyLabel: $r('app.string.empty'),
    options: [],
    port: false,
    dependsOn: owner
  };
}

/**
 * The rows under `category(R.string.general)`, in the order
 * `OverrideSettingsDesign`'s `preferenceScreen` block builds them.
 */
function overrideGeneralRows(): OverrideRow[] {
  const bools: OverrideOption[] = overrideBooleanOptions();
  const disabled: Resource = $r('app.string.disabled');
  const fallback: Resource = $r('app.string.default_');
  const none: string = '';

  return [
    textRow('http_port', $r('app.string.http_port'), disabled, true, none),
    textRow('socks_port', $r('app.string.socks_port'), disabled, true, none),
    textRow('redirect_port', $r('app.string.redirect_port'), disabled, true, none),
    textRow('tproxy_port', $r('app.string.tproxy_port'), disabled, true, none),
    textRow('mixed_port', $r('app.string.mixed_port'), disabled, true, none),
    listRow('authentication', $r('app.string.authentication'), none),
    selectRow('allow_lan', $r('app.string.allow_lan'), bools, none),
    selectRow('ipv6', $r('app.string.ipv6'), bools, none),
    textRow('bind_address', $r('app.string.bind_address'), fallback, false, none),
    textRow('external_controller', $r('app.string.external_controller'), fallback, false, none),
    textRow('external_controller_tls', $r('app.string.external_controller_tls'), fallback, false, none),
    listRow('allow_origins', $r('app.string.allow_origins'), none),
    selectRow('allow_private_network', $r('app.string.allow_private_network'), bools, none),
    textRow('secret', $r('app.string.secret'), fallback, false, none),
    selectRow('mode', $r('app.string.mode'), overrideModeOptions(), none),
    selectRow('log_level', $r('app.string.log_level'), overrideLogLevelOptions(), none),
    mapRow('hosts', $r('app.string.hosts'), none)
  ];
}

/**
 * The rows under `category(R.string.dns)`. Every one of them except the first
 * is registered in `dnsDependencies`, so they are disabled while the strategy
 * row is set to `false` ("use built-in").
 */
function overrideDnsRows(): OverrideRow[] {
  const bools: OverrideOption[] = overrideBooleanOptions();
  const disabled: Resource = $r('app.string.disabled');
  const dns: string = 'dns.enable';

  return [
    selectRow('dns.enable', $r('app.string.strategy'), overrideDnsStrategyOptions(), ''),
    selectRow('dns.prefer_h3', $r('app.string.prefer_h3'), bools, dns),
    textRow('dns.listen', $r('app.string.listen'), disabled, false, dns),
    selectRow('app.append_system_dns', $r('app.string.append_system_dns'), bools, dns),
    selectRow('dns.ipv6', $r('app.string.ipv6'), bools, dns),
    selectRow('dns.use_hosts', $r('app.string.use_hosts'), bools, dns),
    selectRow('dns.enhanced_mode', $r('app.string.enhanced_mode'),
      overrideDnsEnhancedModeOptions(), dns),
    listRow('dns.name_server', $r('app.string.name_server'), dns),
    listRow('dns.fallback', $r('app.string.fallback'), dns),
    listRow('dns.default_server', $r('app.string.default_name_server'), dns),
    listRow('dns.fakeip_filter', $r('app.string.fakeip_filter'), dns),
    selectRow('dns.fakeip_filter_mode', $r('app.string.fakeip_filter_mode'),
      overrideDnsFilterModeOptions(), dns),
    selectRow('dns.fallback_filter.geoip', $r('app.string.geoip_fallback'), bools, dns),
    textRow('dns.fallback_filter.geoip_code', $r('app.string.geoip_fallback_code'),
      $r('app.string.raw_cn'), false, dns),
    listRow('dns.fallback_filter.domain', $r('app.string.domain_fallback'), dns),
    listRow('dns.fallback_filter.ipcidr', $r('app.string.ipcidr_fallback'), dns),
    mapRow('dns.nameserver_policy', $r('app.string.name_server_policy'), dns)
  ];
}

/** `OverrideSettingsDesign`'s two categories. */
export function overrideSections(): PreferenceSection[] {
  return [
    { title: $r('app.string.general'), rows: overrideGeneralRows() },
    { title: $r('app.string.dns'), rows: overrideDnsRows() }
  ];
}

/** `ConfigurationOverride.FindProcessMode`'s three serial names. */
function overrideFindProcessOptions(): OverrideOption[] {
  return [
    { value: '', label: $r('app.string.dont_modify') },
    { value: 'off', label: $r('app.string.off') },
    { value: 'strict', label: $r('app.string.strict') },
    { value: 'always', label: $r('app.string.always') }
  ];
}

/** The three protocol blocks of `ConfigurationOverride.Sniffer.Sniff`. */
function snifferProtocolRows(protocol: string, title: Resource,
  overrideTitle: Resource): OverrideRow[] {
  const sniffer: string = 'sniffer.enable';
  return [
    listRow(`sniffer.sniff.${protocol}.ports`, title, sniffer),
    selectRow(`sniffer.sniff.${protocol}.override_destination`, overrideTitle,
      overrideBooleanOptions(), sniffer)
  ];
}

/**
 * The rows under `category(R.string.sniffer_setting)`. Every row except the
 * first is registered in `snifferDependencies`, so they are disabled while the
 * strategy row is set to `false`.
 */
function overrideSnifferRows(): OverrideRow[] {
  const bools: OverrideOption[] = overrideBooleanOptions();
  const sniffer: string = 'sniffer.enable';

  const rows: OverrideRow[] = [
    selectRow('sniffer.enable', $r('app.string.strategy'), overrideBooleanOptions(), '')
  ];
  for (const row of snifferProtocolRows('http', $r('app.string.sniff_http_ports'),
    $r('app.string.sniff_http_override_destination'))) {
    rows.push(row);
  }
  for (const row of snifferProtocolRows('tls', $r('app.string.sniff_tls_ports'),
    $r('app.string.sniff_tls_override_destination'))) {
    rows.push(row);
  }
  for (const row of snifferProtocolRows('quic', $r('app.string.sniff_quic_ports'),
    $r('app.string.sniff_quic_override_destination'))) {
    rows.push(row);
  }
  rows.push(selectRow('sniffer.force_dns_mapping', $r('app.string.force_dns_mapping'), bools, sniffer));
  rows.push(selectRow('sniffer.parse_pure_ip', $r('app.string.parse_pure_ip'), bools, sniffer));
  rows.push(selectRow('sniffer.override_destination', $r('app.string.override_destination'), bools, sniffer));
  rows.push(listRow('sniffer.force_domain', $r('app.string.force_domain'), sniffer));
  rows.push(listRow('sniffer.skip_domain', $r('app.string.skip_domain'), sniffer));
  rows.push(listRow('sniffer.skip_src_address', $r('app.string.skip_src_address'), sniffer));
  rows.push(listRow('sniffer.skip_dst_address', $r('app.string.skip_dst_address'), sniffer));
  return rows;
}

/**
 * `MetaFeatureSettingsDesign`'s four categories.
 *
 * The age-key rows and the geofile rows are `clickable` rows with no value:
 * their requests are handled by the page (`OverrideKind.Action`).
 *
 * Android also carries a commented-out `geox_url_setting` category, so the
 * port has no rows for `geox-url` either.
 */
export function overrideMetaSections(): PreferenceSection[] {
  const bools: OverrideOption[] = overrideBooleanOptions();
  const none: string = '';

  return [
    {
      title: $r('app.string.age_key_category'),
      rows: [
        actionRow('age_key.x25519', $r('app.string.age_key_type_x25519'),
          $r('app.string.age_key_generate_summary'), none),
        actionRow('age_key.hybrid', $r('app.string.age_key_type_hybrid'),
          $r('app.string.age_key_generate_summary'), none)
      ]
    },
    {
      title: $r('app.string.settings'),
      rows: [
        selectRow('unified_delay', $r('app.string.unified_delay'), bools, none),
        selectRow('geodata_mode', $r('app.string.geodata_mode'), bools, none),
        selectRow('tcp_concurrent', $r('app.string.tcp_concurrent'), bools, none),
        selectRow('find_process_mode', $r('app.string.find_process_mode'),
          overrideFindProcessOptions(), none)
      ]
    },
    {
      title: $r('app.string.sniffer_setting'),
      rows: overrideSnifferRows()
    },
    {
      title: $r('app.string.geox_files'),
      rows: [
        actionRow('geofile.geoip', $r('app.string.import_geoip_file'),
          $r('app.string.press_to_import'), none),
        actionRow('geofile.geosite', $r('app.string.import_geosite_file'),
          $r('app.string.press_to_import'), none),
        actionRow('geofile.country', $r('app.string.import_country_file'),
          $r('app.string.press_to_import'), none),
        actionRow('geofile.asn', $r('app.string.import_asn_file'),
          $r('app.string.press_to_import'), none)
      ]
    }
  ];
}

// ---------------------------------------------------------------------------
// The override record itself
// ---------------------------------------------------------------------------

/** `Object.keys` of a record, so absence can be tested without `undefined`. */
export function overrideHas(data: Record<string, string>, key: string): boolean {
  return Object.keys(data).includes(key);
}

/** The stored value, or `''` while the row is unset. */
export function overrideGet(data: Record<string, string>, key: string): string {
  return overrideHas(data, key) ? data[key] : '';
}

/** A copy with `key` set. Returns a new record so `@Local` re-renders. */
export function overridePut(data: Record<string, string>, key: string,
  value: string): Record<string, string> {
  const next: Record<string, string> = {};
  for (const name of Object.keys(data)) {
    next[name] = data[name];
  }
  next[key] = value;
  return next;
}

/** A copy with `key` back to "do not modify". */
export function overrideRemove(data: Record<string, string>, key: string): Record<string, string> {
  const next: Record<string, string> = {};
  for (const name of Object.keys(data)) {
    if (name !== key) {
      next[name] = data[name];
    }
  }
  return next;
}

/** Decode a persisted blob; a corrupt one reads as an empty override. */
export function overrideParse(encoded: string): Record<string, string> {
  try {
    const parsed: Record<string, string> = JSON.parse(encoded) as Record<string, string>;
    const next: Record<string, string> = {};
    for (const name of Object.keys(parsed)) {
      if (typeof parsed[name] === 'string') {
        next[name] = parsed[name];
      }
    }
    return next;
  } catch (error) {
    return {};
  }
}

/** `NullableTextAdapter.Port.to`: a blank or unparsable port is `0`. */
export function overridePortValue(text: string): number {
  if (text === '') {
    return 0;
  }
  const value: number = Number.parseInt(text, 10);
  return Number.isNaN(value) ? 0 : value;
}

/** `NullableTextAdapter.Port.from`: only a positive port has text. */
export function overridePortText(value: number): string {
  return value > 0 ? `${value}` : '';
}

/** A `List` row as an array; an unset or corrupt row reads as empty. */
export function overrideList(data: Record<string, string>, key: string): string[] {
  const raw: string = overrideGet(data, key);
  if (raw === '') {
    return [];
  }
  try {
    const parsed: string[] = JSON.parse(raw) as string[];
    return Array.isArray(parsed) ? parsed : [];
  } catch (error) {
    return [];
  }
}

/**
 * A `Map` row as `[key, value]` pairs. `JSON.parse` preserves the insertion
 * order of string keys, so the editor keeps whatever order the user created.
 */
export function overrideMap(data: Record<string, string>, key: string): string[][] {
  const raw: string = overrideGet(data, key);
  if (raw === '') {
    return [];
  }
  try {
    const parsed: Record<string, string> = JSON.parse(raw) as Record<string, string>;
    return Object.keys(parsed).map((name: string): string[] => [name, parsed[name]]);
  } catch (error) {
    return [];
  }
}

/** The stored text of a `List` row built from the editor's working copy. */
export function overrideEncodeList(items: string[]): string {
  return JSON.stringify(items);
}

/** The stored text of a `Map` row built from the editor's working copy. */
export function overrideEncodeMap(pairs: string[][]): string {
  const map: Record<string, string> = {};
  for (const pair of pairs) {
    map[pair[0]] = pair[1];
  }
  return JSON.stringify(map);
}

/**
 * The summary line of a row, mirroring `EditableText` / `EditableTextList` /
 * `EditableTextMap` / `SelectableList`'s summary setters.
 *
 * `manager` resolves the labels: the result is a plain string so the page can
 * use it as the row's `ForEach` key, and `format_elements` needs the resource
 * manager to substitute its count.
 */
export function overrideSummaryText(data: Record<string, string>, row: OverrideRow,
  manager: resourceManager.ResourceManager): string {
  // A `clickable` row has no value: its summary is the fixed `summary`
  // argument, which the row table carries in `placeholder`.
  if (row.kind === OverrideKind.Action) {
    return manager.getStringSync(row.placeholder.id);
  }

  if (row.kind === OverrideKind.Select) {
    const value: string = overrideGet(data, row.key);
    for (const option of row.options) {
      if (option.value === value) {
        return manager.getStringSync(option.label.id);
      }
    }
    return manager.getStringSync(row.placeholder.id);
  }

  if (!overrideHas(data, row.key)) {
    return manager.getStringSync(row.placeholder.id);
  }

  if (row.kind === OverrideKind.Text) {
    const text: string = overrideGet(data, row.key);
    return text === '' ? manager.getStringSync(row.emptyLabel.id) : text;
  }

  const count: number = row.kind === OverrideKind.List
    ? overrideList(data, row.key).length
    : overrideMap(data, row.key).length;
  if (count === 0) {
    return manager.getStringSync(row.emptyLabel.id);
  }
  return manager.getStringSync($r('app.string.format_elements').id, count);
}

/** Whether the row responds at all: `Preference.enabled`. */
export function overrideRowEnabled(data: Record<string, string>, row: OverrideRow): boolean {
  if (row.dependsOn === '') {
    return true;
  }
  // The listener only disables the group when the owner is explicitly `false`
  // ("use built-in" / "disabled"); `null` and `true` both leave it enabled.
  return overrideGet(data, row.dependsOn) !== 'false';
}

// ---------------------------------------------------------------------------
// The subset mihomo's external controller accepts
// ---------------------------------------------------------------------------

function appendText(parts: string[], data: Record<string, string>,
  key: string, wire: string): void {
  if (overrideHas(data, key)) {
    parts.push(`${JSON.stringify(wire)}:${JSON.stringify(overrideGet(data, key))}`);
  }
}

function appendPort(parts: string[], data: Record<string, string>,
  key: string, wire: string): void {
  if (overrideHas(data, key)) {
    const port: number = overridePortValue(overrideGet(data, key));
    parts.push(`${JSON.stringify(wire)}:${port}`);
  }
}

function appendFlag(parts: string[], data: Record<string, string>,
  key: string, wire: string): void {
  if (overrideHas(data, key)) {
    const value: string = overrideGet(data, key) === 'true' ? 'true' : 'false';
    parts.push(`${JSON.stringify(wire)}:${value}`);
  }
}

function appendList(parts: string[], data: Record<string, string>,
  key: string, wire: string): void {
  if (overrideHas(data, key)) {
    parts.push(`${JSON.stringify(wire)}:${overrideEncodeList(overrideList(data, key))}`);
  }
}

/**
 * The request body for `PATCH /configs`, built from the rows mihomo's
 * `config.General` actually carries.
 *
 * `OverrideSettingsDesign` writes the whole `ConfigurationOverride` into the
 * core's persist slot and lets the native side decide which fields it
 * understands. The port has no in-process core, so the override is handed to
 * the running core through the external controller instead, and only the
 * fields `PATCH /configs` accepts can make the trip:
 *
 *   port, socks-port, redir-port, tproxy-port, mixed-port, authentication,
 *   allow-lan, bind-address, mode, log-level, ipv6, unified-delay,
 *   geodata-mode, tcp-concurrent, find-process-mode, sniffing
 *
 * Everything else -- the controller's own address and secret, `hosts`, and the
 * whole DNS subtree -- lives in `RawConfig`, not in `General`, so `PATCH` drops
 * it. Those rows are stored and displayed but reach nothing; the page says so.
 *
 * The two screens share one record and therefore one body: whichever page
 * commits, every row that is set goes out together.
 */
export function overridePatchBody(data: Record<string, string>): string {
  const parts: string[] = [];
  appendPort(parts, data, 'http_port', 'port');
  appendPort(parts, data, 'socks_port', 'socks-port');
  appendPort(parts, data, 'redirect_port', 'redir-port');
  appendPort(parts, data, 'tproxy_port', 'tproxy-port');
  appendPort(parts, data, 'mixed_port', 'mixed-port');
  appendList(parts, data, 'authentication', 'authentication');
  appendFlag(parts, data, 'allow_lan', 'allow-lan');
  appendFlag(parts, data, 'ipv6', 'ipv6');
  appendText(parts, data, 'bind_address', 'bind-address');
  appendText(parts, data, 'mode', 'mode');
  appendText(parts, data, 'log_level', 'log-level');
  appendFlag(parts, data, 'unified_delay', 'unified-delay');
  appendFlag(parts, data, 'geodata_mode', 'geodata-mode');
  appendFlag(parts, data, 'tcp_concurrent', 'tcp-concurrent');
  appendText(parts, data, 'find_process_mode', 'find-process-mode');
  appendSniffer(parts, data);
  return `{${parts.join(',')}}`;
}

/**
 * One protocol block of `Sniffer.Sniff`. The wire names are upper case
 * (`HTTP` / `TLS` / `QUIC`), which is what mihomo's `RawSniffer.Sniff` map is
 * keyed by.
 */
function appendSniffProtocol(parts: string[], data: Record<string, string>,
  protocol: string): void {
  const fields: string[] = [];
  appendList(fields, data, `sniffer.sniff.${protocol}.ports`, 'ports');
  appendFlag(fields, data, `sniffer.sniff.${protocol}.override_destination`,
    'override-destination');
  if (fields.length > 0) {
    parts.push(`${JSON.stringify(protocol.toUpperCase())}:{${fields.join(',')}}`);
  }
}

/** The nested `sniffing` object, or nothing when none of its rows is set. */
function appendSniffer(parts: string[], data: Record<string, string>): void {
  const fields: string[] = [];
  appendFlag(fields, data, 'sniffer.enable', 'enable');
  appendFlag(fields, data, 'sniffer.force_dns_mapping', 'force-dns-mapping');
  appendFlag(fields, data, 'sniffer.parse_pure_ip', 'parse-pure-ip');
  appendFlag(fields, data, 'sniffer.override_destination', 'override-destination');
  appendList(fields, data, 'sniffer.force_domain', 'force-domain');
  appendList(fields, data, 'sniffer.skip_domain', 'skip-domain');
  appendList(fields, data, 'sniffer.skip_src_address', 'skip-src-address');
  appendList(fields, data, 'sniffer.skip_dst_address', 'skip-dst-address');

  const sniff: string[] = [];
  appendSniffProtocol(sniff, data, 'http');
  appendSniffProtocol(sniff, data, 'tls');
  appendSniffProtocol(sniff, data, 'quic');
  if (sniff.length > 0) {
    fields.push(`"sniff":{${sniff.join(',')}}`);
  }

  if (fields.length > 0) {
    parts.push(`"sniffing":{${fields.join(',')}}`);
  }
}
