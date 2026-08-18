#!/usr/bin/env bash
# Happy self-hosted API server (launchd: dev.happy.server).
#
# Two non-obvious requirements, both learned the hard way — see README.md:
#   1. DB_PROVIDER=postgres is REQUIRED. The standalone entrypoint does
#      `process.env.DB_PROVIDER = process.env.DB_PROVIDER || "pglite"`, so
#      DATABASE_URL alone is silently ignored and you land back on PGlite,
#      which corrupts Bytes columns (upstream slopus/happy#686, #612).
#   2. cwd must contain no ./webapp, or findStaticDir() mounts the web UI at /
#      and suppresses the "Welcome to Happy Server!" route that the mobile app
#      requires in order to accept the server as valid.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

PKG=happy-server-self-host
NODE="$(resolve_node_with_pkg "$PKG")" || { echo "no node found" >&2; exit 78; }
NM="$(global_node_modules "$NODE")"
STANDALONE="$NM/$PKG/dist/standalone.mjs"
[ -f "$STANDALONE" ] || { echo "missing $STANDALONE — run: npm i -g happy $PKG" >&2; exit 78; }

RUNDIR="$HOME/.happy/server-run"     # deliberately empty — see note 2 above
mkdir -p "$RUNDIR"; cd "$RUNDIR"

PGPASS_FILE="$HOME/.happy/pgpass"
MASTER_FILE="$HOME/.happy/server-data/master-secret"
[ -f "$PGPASS_FILE" ] || { echo "missing $PGPASS_FILE — run setup.sh" >&2; exit 78; }
[ -f "$MASTER_FILE" ] || { echo "missing $MASTER_FILE — run setup.sh" >&2; exit 78; }

# On a cold boot launchd starts us in parallel with the colima VM, which must
# boot dockerd before Postgres exists. If this still times out, KeepAlive
# restarts us and we wait again, so the chain self-heals.
for _ in $(seq 1 150); do
  /usr/bin/nc -z 127.0.0.1 5433 2>/dev/null && break
  sleep 2
done

DNS_NAME="$(tailnet_dns_name || true)"

export DB_PROVIDER=postgres
export DATABASE_URL="postgresql://happy:$(cat "$PGPASS_FILE")@127.0.0.1:5433/happy"
export HANDY_MASTER_SECRET="$(cat "$MASTER_FILE")"
export DATA_DIR="$HOME/.happy/server-data"
export PORT=3005
export HOST=127.0.0.1                # Tailscale serve is the only public listener
[ -n "$DNS_NAME" ] && export PUBLIC_URL="https://$DNS_NAME"
unset PGLITE_DIR

exec "$NODE" "$STANDALONE" serve
