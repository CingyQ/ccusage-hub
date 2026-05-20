#!/usr/bin/env bash
# Incremental push: compare local vs remote manifests (relpath + size),
# tar only changed/new files and stream to hub. Files only on remote are
# left intact (never deletes).
#
# Usage:
#   bin/push.sh              # push delta
#   bin/push.sh --dry-run    # show what would be pushed
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

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# ssh wrapper with sane defaults
HUB() { ssh -o ConnectTimeout=10 -o ServerAliveInterval=30 "$HUB_SSH" "$@"; }

push_one() {
  local label="$1"      # claude | codex | opencode
  local local_dir="$2"  # absolute local source path
  local remote_sub="$3" # path under $HUB_BASE/$LOCAL_NAME/

  if [ -z "$local_dir" ]; then
    echo "[$label] skipped (no local path configured)"
    return
  fi
  if [ ! -d "$local_dir" ]; then
    echo "[$label] skipped (local dir missing: $local_dir)"
    return
  fi

  local remote_dir="$HUB_BASE/$LOCAL_NAME/$remote_sub"
  HUB "mkdir -p \"$remote_dir\""

  local local_mf remote_mf to_push
  local_mf=$(mktemp); remote_mf=$(mktemp); to_push=$(mktemp)
  trap 'rm -f "$local_mf" "$remote_mf" "$to_push"' RETURN

  # Manifest: <relpath>\t<size>. Use LC_ALL=C on both sides so sort order
  # matches comm's expectation regardless of locale.
  ( cd "$local_dir" && LC_ALL=C find . -type f -printf '%P\t%s\n' 2>/dev/null | LC_ALL=C sort ) > "$local_mf"
  HUB "if [ -d \"$remote_dir\" ]; then cd \"$remote_dir\" && LC_ALL=C find . -type f -printf '%P\t%s\n' 2>/dev/null | LC_ALL=C sort; fi" \
    | tr -d '\r' > "$remote_mf" || true

  # Lines in local manifest absent from remote (new file OR size differs)
  LC_ALL=C comm -23 "$local_mf" "$remote_mf" | cut -f1 > "$to_push"

  local local_n remote_n delta_n
  local_n=$(wc -l < "$local_mf"  | tr -d ' ')
  remote_n=$(wc -l < "$remote_mf" | tr -d ' ')
  delta_n=$(wc -l < "$to_push"   | tr -d ' ')

  printf '[%s] local=%s  remote=%s  to_push=%s\n' "$label" "$local_n" "$remote_n" "$delta_n"

  if [ "$delta_n" -eq 0 ]; then
    return
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  --- preview (first 5) ---"
    head -n 5 "$to_push" | sed 's/^/  /'
    if [ "$delta_n" -gt 5 ]; then echo "  ... ($((delta_n - 5)) more)"; fi
    return
  fi

  # Stream tar of just the delta files
  ( cd "$local_dir" && tar czf - --files-from="$to_push" ) \
    | HUB "tar xzf - -C \"$remote_dir\""
  echo "[$label] pushed $delta_n file(s)"
}

echo "═══ ccusage-hub push ═══"
echo "Hub:     $HUB_SSH"
echo "Local:   $LOCAL_NAME"
echo "Remote:  $HUB_BASE/$LOCAL_NAME/"
[ "$DRY_RUN" -eq 1 ] && echo "MODE:    dry-run"
echo

push_one claude   "${LOCAL_CLAUDE_PROJECTS:-}" ".claude/projects"
push_one codex    "${LOCAL_CODEX_SESSIONS:-}"  ".codex/sessions"
push_one opencode "${LOCAL_OPENCODE_DIR:-}"    "opencode"

echo
echo "Done."
