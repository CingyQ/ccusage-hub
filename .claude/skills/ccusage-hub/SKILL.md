---
name: ccusage-hub
description: Use when the user wants to sync, push, or aggregate Claude Code / Codex / OpenCode usage data across multiple machines, or run ccusage stats covering more than one PC. Triggers include "推一下", "同步用量", "统计花了多少", "ccusage 多机", "monthly", "汇总".
---

# ccusage-hub

Aggregates `~/.claude`, `~/.codex`, `~/.local/share/opencode` usage data from multiple machines onto one "hub" host, then runs a single unified `ccusage` report covering all of them.

## Core idea

ccusage only reads local files. To get a true cross-machine total, push each machine's data into per-host subdirs on a hub, then point ccusage at all of them via the comma-separated `CLAUDE_CONFIG_DIR` / `CODEX_HOME` / `OPENCODE_DATA_DIR` env vars. ccusage dedupes by message+request id, so overlap is safe.

Layout on hub:
```
$HUB_BASE/
  win-pc/.claude/projects/...
  win-pc/.codex/sessions/...
  win-pc/opencode/...
  mac-laptop/.claude/projects/...
  ...
```
Hub's own `~/.claude` / `~/.codex` are included automatically via `HUB_CLAUDE` / `HUB_CODEX` in config.

## Quick reference

| Intent | Command |
|--------|---------|
| Preview what would push | `bash bin/push.sh --dry-run` |
| Push delta to hub | `bash bin/push.sh` |
| Monthly stats (default) | `bash bin/stats.sh` |
| Daily / weekly / session | `bash bin/stats.sh daily` |
| JSON output | `bash bin/stats.sh "monthly --json"` |
| Show resolved env vars | `bash bin/stats.sh --show-env` |

Typical flow: **push, then stats**. Push first to make sure the latest local data is on the hub.

## How push.sh is smart

1. For each source dir, walks files locally with `find -printf '%P\t%s\n'` → manifest of `relpath\tsize`.
2. Asks the hub for the same manifest of its existing copy.
3. `comm -23 local remote` → lines in local not in remote (new files OR size changed; JSONL files only grow, so size delta = appended bytes).
4. `tar czf - --files-from=<delta>` piped over ssh → only changed files are transferred.
5. Files only on remote are **left intact** (never deletes — protects historical data).

Result: first push transfers everything; subsequent pushes are typically a few MB.

## How stats.sh is smart

- SSH to hub, `ls $HUB_BASE` to discover **all** per-host subdirs (no central registry needed — add a new machine just by pushing from it).
- For each platform (claude/codex/opencode), builds comma-separated list of `HUB_<platform>` + every `$HUB_BASE/<host>/<sub>/`.
- Exports the three env vars, runs `npx -y ccusage@latest <args>` (default `monthly --compact`). One command, auto-detects all three platforms.

## Configuration

Edit `hosts.conf` at the project root. Required fields:

- `HUB_SSH` — ssh alias or `user@host` (uses `~/.ssh/config`)
- `HUB_BASE` — remote dir for aggregated data (default `$HOME/ccusage-multi`)
- `HUB_NODE_BIN` — path to a directory containing node ≥ 18 (blank if already on `$PATH`)
- `LOCAL_NAME` — unique label for this machine (becomes its subdir on the hub)
- `LOCAL_CLAUDE_PROJECTS` / `LOCAL_CODEX_SESSIONS` / `LOCAL_OPENCODE_DIR` — local source paths (leave empty to skip a platform)
- `HUB_CLAUDE` / `HUB_CODEX` / `HUB_OPENCODE` — hub's OWN data dirs so its local usage is also counted (empty to skip)

To add another machine: copy this whole project to the new PC, change `LOCAL_NAME`, edit local source paths if different, push.

## Common mistakes

| Mistake | Fix |
|---------|-----|
| Hub has old node (< 18) → `ccusage` crashes | Install nvm + node 22 on hub, point `HUB_NODE_BIN` at its `bin/` |
| Forgot to push before stats → numbers stale | Always `push.sh` first |
| Same `LOCAL_NAME` on two machines → data collides | Each machine needs a distinct `LOCAL_NAME` |
| Pushed `opencode` but stats shows nothing | OpenCode dir on tar-extract nests as `<dest>/opencode/`. The push script handles this by tarring the named source dir; ensure `LOCAL_OPENCODE_DIR` points to the parent of `opencode.db` |
| Hub-side hostname missing from stats | Hub itself isn't auto-pushed; set `HUB_CLAUDE` / `HUB_CODEX` / `HUB_OPENCODE` to include its local data |

## When NOT to use

- Only one machine — just run `npx ccusage@latest monthly --compact` locally.
- Hub is unreachable or has no node 18+ — use the per-machine local report instead.
- You want to delete remote data — these scripts are **append-only by design**; do remote cleanup manually.

## Trust but verify

After pushing, sanity-check by running `stats.sh --show-env` to confirm the comma-lists include every expected host subdir, then compare the run total against expectations (a large drop usually means a path got dropped from env).
