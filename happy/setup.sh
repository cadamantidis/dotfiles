#!/usr/bin/env bash
# Idempotent installer for the self-hosted Happy stack on macOS.
#
#   colima/docker -> postgres:17 container -> happy-server -> happy daemon
#   Tailscale serve terminates TLS; the server itself binds loopback only.
#
# Safe to re-run. Creates nothing that already exists.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

PG_CONTAINER=happy-postgres
PG_PORT=5433
PGPASS_FILE="$HOME/.happy/pgpass"
say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

say "Checking prerequisites"
command -v docker >/dev/null || { echo "docker not found (brew install colima docker)"; exit 1; }
docker info >/dev/null 2>&1 || { echo "docker daemon not running — try: colima start"; exit 1; }
NODE="$(resolve_node_with_pkg happy-server-self-host)" || { echo "no node found"; exit 1; }
NM="$(global_node_modules "$NODE")"
if [ ! -d "$NM/happy-server-self-host" ] || [ ! -d "$NM/happy" ]; then
  echo "installing happy + happy-server-self-host globally"
  "$(dirname "$NODE")/npm" install -g happy happy-server-self-host
  NM="$(global_node_modules "$NODE")"
fi
echo "node: $NODE"

say "Secrets"
mkdir -p "$HOME/.happy/server-data" "$HOME/.happy/logs" "$HOME/.happy/server-run"
if [ ! -f "$PGPASS_FILE" ]; then
  openssl rand -hex 24 > "$PGPASS_FILE"; echo "generated $PGPASS_FILE"
fi
chmod 600 "$PGPASS_FILE"
if [ ! -f "$HOME/.happy/server-data/master-secret" ]; then
  openssl rand -hex 32 > "$HOME/.happy/server-data/master-secret"
  echo "generated master-secret (deleting it makes all server data unreadable)"
fi
chmod 600 "$HOME/.happy/server-data/master-secret"
PGPASS="$(cat "$PGPASS_FILE")"

say "Postgres container"
# PGlite is NOT usable — see README.md (upstream slopus/happy#686).
if docker ps -a --format '{{.Names}}' | grep -qx "$PG_CONTAINER"; then
  docker start "$PG_CONTAINER" >/dev/null 2>&1 || true
  echo "$PG_CONTAINER already exists"
else
  docker run -d --name "$PG_CONTAINER" --restart unless-stopped \
    -e POSTGRES_USER=happy -e POSTGRES_PASSWORD="$PGPASS" -e POSTGRES_DB=happy \
    -p "127.0.0.1:${PG_PORT}:5432" -v happy-pgdata:/var/lib/postgresql/data \
    postgres:17 >/dev/null
  echo "created $PG_CONTAINER"
fi
for _ in $(seq 1 60); do
  docker exec "$PG_CONTAINER" pg_isready -U happy -d happy >/dev/null 2>&1 && break
  sleep 2
done

say "Database schema"
( cd "$NM/happy-server-self-host" \
  && DATABASE_URL="postgresql://happy:${PGPASS}@127.0.0.1:${PG_PORT}/happy" \
     ./node_modules/.bin/prisma migrate deploy --schema ./prisma/schema.prisma 2>&1 | tail -3 )

say "launchd agents"
mkdir -p "$HOME/Library/LaunchAgents"
for label in dev.happy.server dev.happy.daemon; do
  out="$HOME/Library/LaunchAgents/$label.plist"
  sed -e "s|__HAPPY_DIR__|$HERE|g" -e "s|__HOME__|$HOME|g" \
      "$HERE/launchd/$label.plist.template" > "$out"
  plutil -lint "$out" >/dev/null
  # bootout is asynchronous; bootstrapping before the old job is fully gone
  # fails with "Bootstrap failed: 5: Input/output error". Wait it out, then retry.
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
  for _ in $(seq 1 25); do
    launchctl print "gui/$(id -u)/$label" >/dev/null 2>&1 || break
    sleep 0.4
  done
  ok=0
  for _ in $(seq 1 10); do
    if launchctl bootstrap "gui/$(id -u)" "$out" 2>/dev/null; then ok=1; break; fi
    sleep 1
  done
  [ "$ok" = 1 ] || { echo "! failed to bootstrap $label"; launchctl bootstrap "gui/$(id -u)" "$out" || true; }
  launchctl enable "gui/$(id -u)/$label" 2>/dev/null || true
  echo "installed $label"
done

say "Tailscale TLS"
DNS_NAME="$(tailnet_dns_name || true)"
if [ -z "$DNS_NAME" ]; then
  echo "! Tailscale not reachable — start it, then re-run."
else
  TS="$(resolve_tailscale)"
  if "$TS" serve status 2>/dev/null | grep -q '127.0.0.1:3005'; then
    echo "serve already configured"
  else
    echo "configuring: https://$DNS_NAME -> 127.0.0.1:3005"
    "$TS" serve --bg --https=443 http://127.0.0.1:3005 || {
      echo "! serve failed. Enable HTTPS certs at login.tailscale.com/admin/dns"; }
  fi
  printf '%s\n' "  server URL for the phone app:  https://$DNS_NAME"
fi

say "Verify"
for _ in $(seq 1 30); do
  body="$(curl -s --max-time 5 http://127.0.0.1:3005/ || true)"
  [ "$body" = "Welcome to Happy Server!" ] && break
  sleep 2
done
if [ "${body:-}" = "Welcome to Happy Server!" ]; then
  echo "OK: server responds with the string the mobile app validates against"
else
  echo "! server not healthy yet — check ~/.happy/logs/launchd-server.log"
fi

cat <<'NEXT'

Next (manual, once):
  1. Phone: install Happy, set Server Configuration to the https URL above,
     then Create account.
  2. Mac:   happy auth login   -> choose "1. Mobile App" and scan the QR.
  3. happy claude
NEXT
