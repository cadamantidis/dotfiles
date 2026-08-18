#!/usr/bin/env bash
# Happy CLI daemon (launchd: dev.happy.daemon).
# Spawns and supervises coding sessions; required for starting sessions
# from the phone. `start-sync` is the foreground form suitable for launchd.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$HERE/common.sh"

NODE="$(resolve_node_with_pkg happy)" || { echo "no node found" >&2; exit 78; }
NM="$(global_node_modules "$NODE")"
ENTRY="$NM/happy/dist/index.mjs"
[ -f "$ENTRY" ] || { echo "missing $ENTRY — run: npm i -g happy" >&2; exit 78; }

# claude must be reachable; launchd gives us a minimal PATH.
export PATH="/opt/homebrew/bin:$(dirname "$NODE"):/usr/bin:/bin:/usr/sbin:/sbin"

# A daemon started before credentials existed holds this lock forever and makes
# every later start fail with "Failed to acquire daemon lock".
LOCK="$HOME/.happy/daemon.state.json.lock"
if [ -f "$LOCK" ]; then
  LOCKPID="$(tr -dc '0-9' < "$LOCK" 2>/dev/null || true)"
  if [ -n "$LOCKPID" ] && ! kill -0 "$LOCKPID" 2>/dev/null; then
    rm -f "$LOCK"
  fi
fi

exec "$NODE" --no-warnings --no-deprecation "$ENTRY" daemon start-sync
