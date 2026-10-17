# The VPN descriptor lifecycle

The failure this file exists to prevent is a tunnel that works and then
disappears, with the app still claiming it is up.

## Order matters

In the UI process:

1. `startVpnExtensionAbility(want)` with everything the extension needs
   (profile path, settings, secrets).

In the VpnExtension process:

2. `onCreate`
3. `protectProcessNet()` — **before** the descriptor exists
4. `connection.create(config)` → the tun descriptor
5. prepare the core (load config) — still without the descriptor
6. attach the core to the descriptor, with routes, DNS and gateway
7. publish "running" so the UI can read it

On stop: `onDestroy` → stop the core, close the connection, unpublish.

`protectProcessNet()` must come before `connection.create()`. Protecting after
the core has started leaves the sockets the core already opened unprotected,
and the fd count climbs until the detector ends the process.

## Why process-level protection is not enough

`protectProcessNet()` covers sockets created after the call, which is why the
ordering above matters. But the core's own dialer may create sockets through
paths the process-level protection does not cover on every build. The reliable
answer is the Android approach: let the core ask, per socket.

```text
core dialer, about to connect
  -> calls a registered hook with the fd
     -> native layer posts the fd to the ArkTS thread
        -> VpnConnection.protect(fd)
        -> signals "done"
  <- the hook returns, the dialer connects
```

The core must **wait** for the completion signal, with a timeout. A hook that
returns immediately re-creates the problem it was added to fix.

## Evidence that you fixed it

```console
$ hdc shell "hilog -x -e 'FdLeak'"        # expect no output
$ hdc shell "hilog -x -T <YourVpnTag>"    # expect the attach line, then nothing fatal
```

and, independently:

```console
$ hdc shell "ps -ef | grep <pkg>:vpn"
$ hdc shell "ifconfig <tun-name> | grep -E 'inet addr|RX packets'"
```

Run both at intervals for several minutes. A single check after start proves
nothing; this failure appears around the 90-second mark.

## A second, cheaper safety net

Resolve the core's actual upstream destinations (proxy servers, DNS), then
remove those `/32`s and `/128`s from the route set you hand to the platform.
Then even if a socket escapes protection, the core's own traffic does not loop
back into the tunnel. This is a fallback, not a substitute: it does not cover
anything the core dials that you did not predict.

## Two more lifecycle facts

**The extension is a separate process.** Anything cached in the UI process,
including `PersistenceV2` state, is invisible to it and vice versa. A file in
the app sandbox is the cheap shared channel.

**Stop-then-start can stall.** Give the platform a moment after
`stopVpnExtensionAbility` before starting again, and treat the "running" marker
as a hint that may be stale after a force-stop, because the extension gets no
`onDestroy` in that case.
