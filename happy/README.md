# Self-hosted Happy (Claude Code remote control) — macOS

Run [Happy](https://github.com/slopus/happy) entirely on your own machine so you can drive
Claude Code from your phone over Tailscale, with no dependency on the vendor's cloud.

```
Phone (Happy app)
   │  HTTPS/WSS over Tailscale
   ▼
tailscale serve  ──►  happy-server (127.0.0.1:3005)  ──►  postgres:17 (127.0.0.1:5433, docker)
                              │
                              ▼
                      happy daemon ──► claude
```

## Install

```bash
./setup.sh          # idempotent; safe to re-run
```

Then, once:

1. **Phone** — install Happy, set **Settings → Server Configuration** to the `https://<host>.ts.net`
   URL that `setup.sh` prints, then **Create account**.
2. **Mac** — `happy auth login`, choose **`1. Mobile App`**, scan the QR.
3. `happy claude`

## Requirements

- colima (or any Docker daemon) — `brew install colima docker && brew services start colima`
- Tailscale, with **HTTPS Certificates enabled** at `login.tailscale.com/admin/dns`
- `npm i -g happy happy-server-self-host` (setup.sh installs these if missing)

## Why it is built this way — four traps

These are not preferences. Each one produces a confusing failure that looks like something else.

### 1. PGlite is unusable — you must use Postgres

Upstream bugs [#686](https://github.com/slopus/happy/issues/686) /
[#612](https://github.com/slopus/happy/issues/612), both open.

PGlite returns `bytea` as a `Uint8Array`; `pglite-prisma-adapter@0.7.2` assumes a hex string
and does `.slice(2)`. Prisma then receives `{"0":0,"1":1,...}` and throws:

```
PrismaClientKnownRequestError P2023
Inconsistent column data: Conversion failed: expected a string or an array
in column 'dataEncryptionKey', found {"0":0,...}
```

`dataEncryptionKey` sits on both `Machine` and `Session` and is selected by default, so auth
and the daemon connect fine and it only detonates when a session or machine registers.

### 2. `DATABASE_URL` alone does nothing — set `DB_PROVIDER=postgres`

The standalone entrypoint hard-forces PGlite:

```js
async function serve() {
  process.env.DB_PROVIDER = process.env.DB_PROVIDER || "pglite";
```

`happy-server --help` claims `DATABASE_URL` "uses external Postgres instead of PGlite".
**That is wrong.** Without `DB_PROVIDER=postgres` you silently stay on PGlite and hit trap 1.

Verify you are actually on Postgres — the failure mode is invisible from outside:

```bash
docker exec -e PGPASSWORD="$(cat ~/.happy/pgpass)" happy-postgres \
  psql -U happy -d happy -tAc 'SELECT count(*) FROM "Machine";'      # must be >0 after pairing
```

### 3. Serve the API only — the bundled web UI breaks phone validation

The mobile app validates a server by requiring the body of `GET <url>` to contain the literal
string `Welcome to Happy Server!`. That route only exists when no static dir is mounted:

```js
if (!opts.staticDir) {
  app2.get("/", (request, reply) => reply.send("Welcome to Happy Server!"));
}
```

`happy server` mounts the bundled web UI at `/`, so the phone reports **"Not a valid Happy
Server"**. It cannot be fixed with an env var: the `happy-server` bin wrapper force-sets
`HAPPY_STATIC_DIR` and spawns with `cwd` = its own package dir (which contains `webapp/`), so
`findStaticDir()` always finds one.

Hence `run-server.sh` invokes `dist/standalone.mjs` directly from an **empty** working
directory (`~/.happy/server-run`). Keep that directory empty. Cost: no browser web UI.

### 4. Plain HTTP breaks pairing — TLS is mandatory

Over `http://<tailnet-ip>:3005`, pairing fails with "Failed to connect terminal" and a
completely clean server log (every request 200). The web bundle does its E2EE with
`crypto.subtle.importKey / deriveBits / encrypt / decrypt`, and browsers expose `crypto.subtle`
**only in a secure context**. On a plain-HTTP non-localhost origin it is `undefined`, so the
crypto dies client-side *before any request is sent*.

`tailscale serve` gives a real Let's Encrypt cert and also removes the Android cleartext-HTTP
question (`usesCleartextTraffic`) entirely.

## Operating notes

- **Server binds loopback only.** Tailscale's listener is the sole tailnet-facing surface, under
  tailnet ACLs. Do not bind `0.0.0.0`: the API would be reachable in plaintext on the LAN, and
  self-host mode has no single-user enforcement — "first client auto-pairs, rest rejected" is
  explicitly out of scope upstream, so anything that can reach the port can create an account.
- **`Machine.lastActiveAt` is not a liveness probe.** It updates on registration only; keep-alive
  rides the WebSocket and logs no HTTP requests. Use the daemon log instead.
- **Never `happy server --reset`.** It wipes local server data including pairing state and the
  master secret. It does not merely clear the settings pointer.
- **Deleting `~/.happy/server-data/master-secret` makes all server data unreadable.**
- **A daemon started before credentials exist** holds `~/.happy/daemon.state.json.lock` forever;
  every later start then fails with "Failed to acquire daemon lock". `run-daemon.sh` clears a
  lock whose PID is dead; for a live one use `happy doctor clean`.
- **Changing databases invalidates credentials.** Log out on the phone, create the account again,
  then `happy auth login`. Stale credentials produce a burst of `account.findUniqueOrThrow()` 500s.

## Boot chain

```
login → homebrew.mxcl.colima (RunAtLoad, installed by `brew services start colima`)
      → colima VM + dockerd
      → happy-postgres (restart: unless-stopped)
      → dev.happy.server (waits up to 300s for 127.0.0.1:5433)
      → dev.happy.daemon
```

launchd starts the server in parallel with the colima VM boot, hence the wait. If it times out,
`KeepAlive` restarts it and it waits again, so the chain self-heals.

## Troubleshooting

```bash
launchctl list | grep dev.happy                      # both should have live PIDs
tail -f ~/.happy/logs/launchd-server.log
tail -f "$(ls -t ~/.happy/logs/*-daemon.log | head -1)"
curl -s https://$(tailscale status --json | jq -r .Self.DNSName | sed 's/\.$//')/   # expect the welcome string
happy doctor
```

Restart everything:

```bash
launchctl kickstart -k gui/$(id -u)/dev.happy.server
launchctl kickstart -k gui/$(id -u)/dev.happy.daemon
```

## Files

| Path | Purpose |
|---|---|
| `setup.sh` | Idempotent installer |
| `common.sh` | Runtime resolvers (node / tailscale / MagicDNS name) |
| `run-server.sh` | Server launcher — resolves node at runtime so nvm upgrades don't break boot |
| `run-daemon.sh` | Daemon launcher — same, plus stale-lock cleanup |
| `launchd/*.template` | Plists rendered by `setup.sh` (`__HAPPY_DIR__`, `__HOME__`) |

Secrets live **outside** this repo: `~/.happy/pgpass` and `~/.happy/server-data/master-secret`,
both mode 600, generated by `setup.sh`.
