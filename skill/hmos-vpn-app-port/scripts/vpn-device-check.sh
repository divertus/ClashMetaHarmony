#!/usr/bin/env bash
#
# Ground-truth check for a HarmonyOS VPN port.
#
# Answers, from outside the app: is the extension alive, is the tunnel
# interface up, is the control channel listening, and has the platform logged an
# fd leak. Samples over time, because a tunnel that dies at ~90s passes every
# single-shot check.
#
# Usage:
#   ./vpn-device-check.sh <bundle-name> <tun-name> [port] [minutes]
#   ./vpn-device-check.sh com.example.clashmeta vpn-tun 9090 3
#
set -uo pipefail

BUNDLE="${1:?usage: $0 <bundle-name> <tun-name> [port] [minutes]}"
TUN="${2:?usage: $0 <bundle-name> <tun-name> [port] [minutes]}"
PORT="${3:-}"
MINUTES="${4:-3}"

HDC="${HDC:-hdc}"
if ! command -v "$HDC" >/dev/null 2>&1; then
  echo "hdc not found; add the DevEco toolchains dir to PATH" >&2
  exit 2
fi

sh() { "$HDC" shell "$1" 2>/dev/null; }
num() { tr -d ' \r' <<<"${1:-0}"; }

echo "target: $BUNDLE   tun: $TUN   ${PORT:+port: $PORT   }window: ${MINUTES}m"
echo

fail=0
rounds=$(( MINUTES * 2 ))
for i in $(seq 1 "$rounds"); do
  vpn_proc="$(num "$(sh "ps -ef | grep '$BUNDLE:vpn' | grep -v grep | wc -l")")"
  ui_proc="$(num "$(sh "ps -ef | grep '$BUNDLE' | grep -v grep | wc -l")")"
  tun_up="$(num "$(sh "ifconfig $TUN 2>/dev/null | grep -c 'inet addr'")")"
  leak="$(num "$(sh "hilog -x -e 'FdLeak' 2>/dev/null | grep -c 'FdLeakInfo'")")"

  port_state="-"
  if [ -n "$PORT" ]; then
    port_state="$(num "$(sh "netstat -an 2>/dev/null | grep ':$PORT ' | grep -c LISTEN")")"
  fi

  printf 't=+%3ds  vpn_proc=%s ui_proc=%s tun=%s listen=%s fdleak=%s\n' \
    "$(( (i - 1) * 30 ))" "$vpn_proc" "$ui_proc" "$tun_up" "$port_state" "$leak"

  if [ "$vpn_proc" -eq 0 ]; then echo "  -> the VPN process is gone"; fail=1; fi
  if [ "$tun_up" -eq 0 ]; then echo "  -> $TUN has no address"; fail=1; fi
  if [ "$leak" -ne 0 ]; then echo "  -> FdLeakInfo present: sockets are escaping protection"; fail=1; fi

  [ "$i" -lt "$rounds" ] && sleep 30
done

echo
echo "--- last lines mentioning $BUNDLE ---"
sh "hilog -x 2>/dev/null | grep '$BUNDLE' | tail -12"

echo
if [ "$fail" -eq 0 ]; then
  echo "PASS: process, interface and fd count held for ${MINUTES}m"
  echo "Still to confirm by hand: a real request through the tunnel, and that"
  echo "stopping it removes the interface and restores direct networking."
else
  echo "FAIL: see the annotations above"
fi
exit "$fail"
