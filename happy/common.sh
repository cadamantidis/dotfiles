#!/usr/bin/env bash
# Shared resolvers for the Happy self-host service scripts.
#
# Everything is resolved at RUNTIME rather than baked into the launchd plists,
# so an nvm upgrade or a tailnet rename does not silently break the services
# at next boot.

# Print the path to a node binary that actually has $1 installed globally.
# Falls back to any node if the package can't be located.
resolve_node_with_pkg() {
  local pkg="$1" c fallback=""
  local candidates=()
  if [ -d "$HOME/.nvm/versions/node" ]; then
    while IFS= read -r c; do candidates+=("$c"); done \
      < <(ls -1d "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -Vr)
  fi
  candidates+=(/opt/homebrew/bin/node /usr/local/bin/node)
  local path_node; path_node="$(command -v node 2>/dev/null || true)"
  [ -n "$path_node" ] && candidates+=("$path_node")

  for c in "${candidates[@]}"; do
    [ -x "$c" ] || continue
    [ -z "$fallback" ] && fallback="$c"
    if [ -d "$(dirname "$c")/../lib/node_modules/$pkg" ]; then
      printf '%s\n' "$c"; return 0
    fi
  done
  [ -n "$fallback" ] && { printf '%s\n' "$fallback"; return 0; }
  return 1
}

# Global node_modules dir for a given node binary.
global_node_modules() {
  local node_bin="$1"
  ( cd "$(dirname "$node_bin")/../lib/node_modules" 2>/dev/null && pwd )
}

# Path to the Tailscale CLI (App Store build hides it inside the bundle).
resolve_tailscale() {
  local c
  for c in /Applications/Tailscale.app/Contents/MacOS/Tailscale \
           /usr/local/bin/tailscale /opt/homebrew/bin/tailscale; do
    [ -x "$c" ] && { printf '%s\n' "$c"; return 0; }
  done
  command -v tailscale 2>/dev/null && return 0
  return 1
}

# This machine's MagicDNS name, without the trailing dot.
tailnet_dns_name() {
  local ts; ts="$(resolve_tailscale)" || return 1
  "$ts" status --json 2>/dev/null \
    | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null
}
