# Per-app top talkers

## Current behavior

Inside the App Sandbox, NetworkMon ranks **network interfaces** by throughput (`InterfaceTopTalkersProvider`). That is a best-effort stand-in for “who is using the network.”

## Why per-app needs a helper

macOS does not expose per-process byte counters to sandboxed apps through public APIs. Useful approaches:

1. **Privileged XPC helper** installed with `SMJobBless` / `SMAppService` that reads `nettop`-style statistics or Network Statistics private SPI.
2. **Network Extension** (content filter / packet tunnel) that accounts flows by PID — App Store / Developer ID heavy.

## Scaffolding in this repo

- `TopTalkersProviding` protocol
- `InterfaceTopTalkersProvider` (sandbox-safe)
- `TopTalkersAvailability.perAppSupported == false`

A future helper should conform to `TopTalkersProviding` and be selected at runtime when the helper is installed and reachable.
