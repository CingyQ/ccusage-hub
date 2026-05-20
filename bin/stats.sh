#!/usr/bin/env bash
# Run unified ccusage on the hub. Auto-discovers all per-host subdirs
# under $HUB_BASE/ and includes them + hub's own data in env vars.
#
# Usage:
#   bin/stats.sh                              # monthly --compact (default)
#   bin/stats.sh daily                        # any ccusage subcommand
#   bin/stats.sh "monthly --json" > out.json  # raw JSON
#   bin/stats.sh --show-env                   # print resolved env vars and exit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [ ! -f "$PROJECT_ROOT/hosts.conf" ]; then
  echo "error: hosts.conf not found. Copy the template first:" >&2
  echo "  cp hosts.conf.example hosts.conf   # then edit it" >&2
  exit 1
fi
# shellcheck disable=SC1091
source "$PROJECT_ROOT/hosts.conf"

HUB() { ssh -o ConnectTimeout=10 -o ServerAliveInterval=30 "$HUB_SSH" "$@"; }

SHOW_ENV=0
if [ "${1:-}" = "--show-env" ]; then SHOW_ENV=1; shift; fi
CCUSAGE_ARGS="${*:-monthly --compact}"

# Discover all host subdirs under $HUB_BASE on remote (newline-separated, CR stripped)
HOSTS_LIST=$(HUB "ls -1 \"$HUB_BASE\" 2>/dev/null" | tr -d '\r' || true)

# Build comma-separated path list for a given sub (e.g. .claude / .codex / opencode),
# combining hub's own data dir (if set) + every per-host subdir.
build_list() {
  local hub_local="$1"
  local sub="$2"
  local parts=()
  [ -n "$hub_local" ] && parts+=("$hub_local")
  for h in $HOSTS_LIST; do
    parts+=("$HUB_BASE/$h/$sub")
  done
  local IFS=','
  echo "${parts[*]}"
}

CLAUDE_LIST=$(build_list "${HUB_CLAUDE:-}"   ".claude")
CODEX_LIST=$(build_list  "${HUB_CODEX:-}"    ".codex")
OPENCODE_LIST=$(build_list "${HUB_OPENCODE:-}" "opencode")

if [ "$SHOW_ENV" -eq 1 ]; then
  echo "Hosts on hub: $(echo "$HOSTS_LIST" | tr '\n' ' ')"
  echo "CLAUDE_CONFIG_DIR=$CLAUDE_LIST"
  echo "CODEX_HOME=$CODEX_LIST"
  echo "OPENCODE_DATA_DIR=$OPENCODE_LIST"
  exit 0
fi

# Build the remote command. Quoting note:
# - Local shell expands $CLAUDE_LIST etc. into the heredoc.
# - Remote shell expands $HOME inside the resulting env-var values.
# - \$PATH is escaped so remote uses its own PATH.
HUB bash -lc "'
  export PATH=\"$HUB_NODE_BIN:\$PATH\"
  export CLAUDE_CONFIG_DIR=\"$CLAUDE_LIST\"
  export CODEX_HOME=\"$CODEX_LIST\"
  export OPENCODE_DATA_DIR=\"$OPENCODE_LIST\"
  npx -y ccusage@latest $CCUSAGE_ARGS
'"
