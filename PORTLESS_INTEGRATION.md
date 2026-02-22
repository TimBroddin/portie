# Portless Integration Research

## What is Portless?

[Portless](https://github.com/vercel-labs/portless) is a Vercel Labs project that replaces port numbers with stable, named `.localhost` URLs for local development. Instead of `localhost:3000`, you get `myapp.localhost:1355`.

**Architecture:**
- A **proxy daemon** runs on port 1355 (configurable) and routes requests based on subdomain
- A **CLI wrapper** (`portless myapp next dev`) assigns a random port (4000-4999) to the app and registers it with the proxy
- Routes are stored as **JSON on disk** at `~/.portless/routes.json` (or `/tmp/portless/routes.json` for privileged ports)

**Route file format** (`~/.portless/routes.json`):
```json
[
  { "hostname": "myapp.localhost", "port": 4023, "pid": 12345 },
  { "hostname": "api.myapp.localhost", "port": 4156, "pid": 12346 }
]
```

**State files:**
- `~/.portless/routes.json` — route mappings (hostname -> port + pid)
- `~/.portless/proxy.pid` — PID of the running proxy daemon
- `~/.portless/proxy.port` — port the proxy listens on
- `~/.portless/proxy.tls` — marker file indicating HTTPS mode

## Why This Matters for Portie

Portie monitors localhost ports and shows what's running. Portless gives those ports human-readable names. The combination is natural: **Portie can become portless-aware and show the friendly URL names alongside port numbers.**

## Integration Ideas

### 1. Show Portless Route Names in the Menu Bar (High Value, Low Effort)

When portless is active, Portie could read `~/.portless/routes.json` and display the portless hostname alongside the port number.

**Current display:**
```text
● Port :4023
  node · My Next App
```

**With portless integration:**
```text
● myapp.localhost:1355
  node · My Next App
```

**Implementation:** In `PortMonitor.swift`, add a method that reads and parses `~/.portless/routes.json`. On each refresh cycle, load the routes and match them to monitored/discovered ports by port number. Store the portless hostname in `PortStatus` and use it in the display.

**Key code path:**
- Read `~/.portless/routes.json` (and `/tmp/portless/routes.json` as fallback)
- Parse JSON array of `{ hostname, port, pid }` objects
- Filter stale routes by checking if the PID is still alive (`kill(pid, 0)`)
- Match routes to ports and store the hostname

### 2. Open in Browser Using Portless URL (High Value, Low Effort)

When clicking "Open in browser" on a port that has a portless route, open `http://myapp.localhost:1355` instead of `http://localhost:4023`.

**Implementation:** In `PortMenuItem.openInBrowser()`, check if the port has an associated portless route. If so, construct the URL using the portless hostname and proxy port (read from `~/.portless/proxy.port`).

### 3. Copy Portless URL to Clipboard (Medium Value, Low Effort)

Add a "Copy URL" action that copies the portless URL. Useful for sharing with teammates or pasting into config files. The portless URL is stable (always `myapp.localhost:1355`) while the raw port changes every restart.

### 4. Show Portless Proxy Status (Medium Value, Low Effort)

Add a section in the menu showing whether the portless proxy is running:
```text
Portless: ● Running (port 1355, HTTPS)
```

**Implementation:** Check if `~/.portless/proxy.pid` exists and if that PID is alive. Read port from `~/.portless/proxy.port` and TLS status from `~/.portless/proxy.tls`.

### 5. Auto-discover Portless Routes as Monitored Ports (Medium Value, Medium Effort)

Instead of manually adding ports, Portie could auto-detect all portless routes and display them. This effectively makes Portie a GUI for `portless list`.

**Implementation:** On each refresh cycle, read the portless routes file and treat each route as a monitored port (in addition to manually added ports). Show them in a separate "Portless Routes" section.

### 6. Quick-add Portless Route from Portie (Lower Value, Higher Effort)

Allow users to assign a portless name to a discovered port from the Portie UI. This would require writing to the portless routes file (with proper file locking via `mkdir` for the lock directory, matching portless's locking protocol).

## Recommended Implementation Order

1. **Read portless routes** — Add a `PortlessIntegration` service that reads `routes.json`
2. **Show portless hostnames** — Enhance `PortStatus` with an optional `portlessHostname` field
3. **Open portless URLs** — Update `openInBrowser()` to prefer portless URLs
4. **Show proxy status** — Add a status indicator to the menu
5. **Auto-discover routes** — Surface portless routes in the discovered ports section

## Technical Notes

- Portless stores state at `~/.portless/` (unprivileged) or `/tmp/portless/` (privileged, port < 1024). Portie should check both locations.
- The routes file uses a file lock (`routes.lock` directory) for concurrent access. For **read-only** access, Portie can safely read without locking (portless writes are atomic via `writeFileSync`).
- Portless filters stale routes by checking `process.kill(pid, 0)` — Portie should do the same to avoid showing dead routes.
- The proxy port defaults to 1355 but can be overridden via `PORTLESS_PORT` env var or `~/.portless/proxy.port` file.
- TLS mode is indicated by the presence of `~/.portless/proxy.tls` marker file. When TLS is active, URLs should use `https://` scheme.
- Portless is macOS and Linux only, Node.js 20+ — same target as Portie (macOS 14+).
