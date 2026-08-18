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

## Voice (ElevenLabs BYO agent)

Happy's built-in voice mints its ElevenLabs token through *their* server behind a paywall, so
it cannot work against a self-hosted server. The BYO path is the only self-host-compatible
one — and it is unlimited, needs no Happy subscription, and connects the phone straight to
ElevenLabs, bypassing the sync server entirely.

Create an agent at <https://elevenlabs.io/app/agents> (product is now "ElevenLabs Agents",
formerly "Conversational AI"), then add **two client tools**. The names are read from
`packages/happy-app/sources/realtime/realtimeClientTools.ts` and are **case-sensitive**:

| Tool | Parameters |
|---|---|
| `sendMessageToSession` | `sessionId` (string, required) · `message` (string, required) |
| `processPermissionRequest` | `requestId` (string, required) · `decision` (enum `allow`/`deny`) |

⚠️ Happy's own in-app help text calls the first tool `messageClaudeCode`. **That is wrong.**
Following the UI copy produces an agent that greets you and then silently does nothing.

Two details that matter more than they look:

- **Bind `sessionId` to the dynamic variable**, not the LLM: in the tool JSON set
  `"value_type": "dynamic_variable"` with `"dynamic_variable": "sessionId"`. Left as
  `llm_prompt`, the model has to recite the session id from memory and will eventually
  hallucinate one, producing silent no-ops.
- **`expects_response: true`** with `response_timeout_secs` around 30. The shipped default is
  `1` second, which fails every real round trip, and the form's "Wait for response" checkbox
  did not always persist — verify in JSON mode after saving.

Agent → **Settings → Security**:

- **Overrides ON** for *System prompt*, *First message*, *Agent language*. Happy sets all
  three at session start; if they are locked its injected prompt (carrying the live session
  context) is silently discarded.
- **Authentication OFF.** Counterintuitive but required: BYO mode connects with a bare
  `agentId` and no server-minted token.
- Consequently **the agent ID is a credential.** With auth off and no allowlist, anyone
  holding it can connect, spend your credits, and (because System prompt override is on)
  replace the prompt. An allowlist is host-based and may not apply to the native app —
  untested.

Finally, in the Happy app: **Settings → Voice** → paste the full agent ID **including the
`agent_` prefix** (the field's placeholder omits it; the placeholder is wrong) and enable the
bypass-token option. Billing is your own ElevenLabs account, ~$0.01/min.

Verify by side effect, never by the agent's reply: ask for something observable ("create a
file called voice-test.txt") and confirm `SessionMessage` rows increment in Postgres. A
pleasant conversational answer with no message row means the tool never fired.

## Orchestrator mode

Sessions started from the phone behave differently from sessions started at the keyboard. A
phone-driven session is a **conversation**: it discusses what to do, and once you agree it hands
the work to an [Orca](https://orca.computer) supervised worker, reads what comes back, and tells
you what happened in prose. It never pastes a diff at you, and it never edits a repo directly —
that is enforced, not merely requested.

Happy is the thinking half; Orca is the doing half. Code work is only part of it — notes,
research, and anything Claude's own tools reach get done directly in the conversation.

The only part of this that lives here is the activation signal, one line in `run-daemon.sh`:

```sh
export HAPPY_ORCHESTRATOR=1
```

Happy spawns Claude Code with the daemon's inherited environment, so that variable reaches every
session the daemon starts and no session you start yourself. Everything it activates lives in the
`claude-files` repo, under `~/.claude/orchestrator/`:

| File | Role |
|---|---|
| `gate.sh` | `PreToolUse` hook. Refuses `Edit`/`Write`/`MultiEdit`/`NotebookEdit` and mutating `Bash` in the main thread, while allowing `orca orchestration ...` and read-only inspection. |
| `brief.sh` | `SessionStart` hook. Injects `protocol.md` as additional context. |
| `protocol.md` | How the session converses, dispatches to Orca, and reports. |

**The two repos are a matched pair.** This variable does nothing without `claude-files` installed,
and the hooks there no-op without this variable. Neither half breaks anything on its own.

### Constraints worth knowing before changing any of it

- **A `PreToolUse` hook is the only mechanism that can restrict the main thread.**
  `permissions.deny` and `--disallowedTools` apply to subagents too, which would defeat the point.
  The hook distinguishes them because `PreToolUse` input carries `agent_id` only inside a
  subagent — its absence means main thread. Verified under `permission_mode: bypassPermissions`,
  which is what Happy's default `yolo` resolves to: hooks still fire, so the gate is real.
- **The conversational register cannot be an output style.** `outputStyle` is a global settings
  key with no CLI flag and no environment variable, so using one would impose this register at the
  keyboard too. It goes through `SessionStart` → `additionalContext` instead, capped at 10,000
  characters — `brief.sh` fails loudly rather than let a longer protocol be silently truncated.
- **A coordinator does not have to be an Orca terminal, but there is only one of them.** Orca
  assigns a single synthetic coordinator identity to every caller that isn't a live Orca terminal,
  and `run-create` binds it. A second session rebinds it, and the first then fails with
  `consumer_fenced: This coordinator terminal is bound to <other_run>`. `--run <run_id>` does not
  override the binding; `orca orchestration run-use --id <run_id>` re-takes it, so the protocol
  rebinds before each batch of calls. **Two concurrent phone sessions will fight over this.**
  Minting a distinct identity with `--from <handle>` is refused outright:
  `stable_pane_required: The coordinator terminal has no stable pane identity`.
  **This is an accepted limitation: one orchestrator session at a time.** Multiple Orca
  *projects* are fine; multiple simultaneous phone *sessions* are not. If that changes, the fix
  is to have the session drive an Orca-managed coordinator terminal rather than being the
  coordinator itself.
- **Never dispatch with `--worktree new-child` or `new-top-level`.** Both resolve relative to the
  caller's current worktree, which a non-terminal coordinator does not have, so they fail with
  `selector_not_found`. The failure is dangerous rather than loud: the obvious recovery is
  `--worktree current`, which puts the worker in the **live checkout** and lets it commit to the
  checked-out branch. Create the worktree explicitly with `orca worktree create --repo <selector>`
  and pass the exact `<repo_id>::<absolute_path>` selector. Orca puts worktrees under
  `~/orca/workspaces/<repo>/<name>`, outside the repo itself.
- **`check --wait` must stay at or under `--timeout-ms 500000`.** Orca's guide suggests 900000,
  but Claude Code's shell tool is capped at 600 seconds and kills a longer call. The orchestrator
  waits in slices instead.
- **The gate's metacharacter check is literal.** `;` `&` `|` `<` `>` and `$(` are rejected anywhere
  in a main-thread command, including inside quoted `--spec` and `--body` text, because parsing
  quoting reliably in `sh` is how allowlists get bypassed.
- **Orca must be running, and the repo must be registered.** `orca status` has to report a ready
  runtime, orchestration must be enabled under Settings → Experimental, and the repo needs
  `orca repo add`. Orca is not a KeepAlive launchd service like `dev.happy.server` — if it is
  down, the session says so and declines code work rather than falling back to editing anything
  itself.

Hook registration is not in git: `claude-files` gitignores `claude/settings.json` because it
carries Orca's generated hooks and machine-specific data. Its `install.sh` injects the two hook
groups idempotently instead — re-run it after pulling, and it reports `already registered` when
there is nothing to do.

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

### macOS TCC prompts (Downloads / Pictures / Desktop / Documents)

A launchd-run process has **no TCC grants of its own** — unlike one started from Terminal,
which borrows Terminal's. So if the daemon's `WorkingDirectory` is `$HOME`, anything that
enumerates the cwd walks into the protected folders and macOS prompts for each, attributed
to bare `node`.

The daemon therefore runs with `WorkingDirectory` = `~/.happy`. Sessions supply their own
working directory, so nothing is lost.

**Deny those prompts if they appear.** Nothing here needs those folders — repos live in
`~/git` and `~/orca`, neither of which is TCC-protected — and granting them would give
agents running with `--dangerously-skip-permissions` standing access to personal files.

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
| `run-daemon.sh` | Daemon launcher — same, plus stale-lock cleanup and the orchestrator-mode signal |
| `launchd/*.template` | Plists rendered by `setup.sh` (`__HAPPY_DIR__`, `__HOME__`) |

Secrets live **outside** this repo: `~/.happy/pgpass` and `~/.happy/server-data/master-secret`,
both mode 600, generated by `setup.sh`.
