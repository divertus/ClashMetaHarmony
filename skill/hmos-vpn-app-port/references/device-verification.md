# Verifying on a device

The app's own UI is the least reliable source of truth about the tunnel. Confirm
every claim from outside the app first, then corroborate with the UI.

## Ground truth, in order

```bash
# 1. is the extension process alive
hdc shell "ps -ef | grep '<pkg>:vpn'"

# 2. did the platform actually install the interface
hdc shell "ifconfig <tun-name>"

# 3. is the control channel listening
hdc shell "netstat -an | grep <port>"

# 4. what did the platform do to us
hdc shell "hilog -x -T <YourVpnTag>"
hdc shell "hilog -x -e 'FdLeak'"

# 5. does traffic actually flow
hdc shell "ifconfig <tun-name> | grep -E 'RX packets|TX packets'"   # sample twice
```

`netstat` may still show a listener after the tunnel is gone, so it corroborates
rather than proves. `ifconfig` and `ps` are the decisive pair.

## The checks that catch real defects

**Liveness over time, not at one instant.** Sample `ps` and `ifconfig` every 30
seconds for several minutes. A tunnel that dies at 90 seconds passes every
single-shot check.

**The stop/start round trip.** After stopping: the interface must be gone *and*
direct networking must work. After starting again: all of the above must hold
again. Skipping the "direct networking works" half hides a tunnel that never
really released its routes.

**The interaction diff.** For each interactive row or control: capture the page
tree, tap, capture again, compare. A screen whose controls are inert looks
perfect in a screenshot. On a ported app this is worth doing mechanically across
every screen.

**Log diff across a restart.** Clear the log, restart, read it. Lines that are
new compared to a known-good baseline are where the cause of a symptom lives.

## Reading the failure signals

| Signal | Means |
|---|---|
| `FdLeakInfo ... fdcnt:<large>` with `Kill Reason: ResourceLeak:Fd Leak` | sockets are escaping per-socket protection |
| `onTerminateScene ... terminateReason: 2` then `exit with code:0` | the UI process was ended; anything holding the tunnel dies with it |
| `TUNGETIFF failed: Permission denied` in a probe | expected; it does not stop a working tunnel |
| a UI showing "running" with no interface in `ifconfig` | the UI is inferring state instead of reading it |

## What not to trust

- The app's status text.
- A control API answering on loopback; it can be a stale socket.
- A build succeeding.
- A screenshot looking right.
- A single green check at t=0.
