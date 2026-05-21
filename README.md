# ccusage-hub

Aggregate [ccusage](https://github.com/ryoppippi/ccusage) usage data from
**multiple machines** onto one host and get a single, unified token/cost report
across all of them — covering Claude Code, Codex, and OpenCode at once.

`ccusage` only reads local files, so by design it can't see usage spread across
your laptop, desktop, and servers. `ccusage-hub` solves that: each machine
incrementally pushes its data into a per-host folder on a central **hub**, then
one command runs `ccusage` over the merged set. ccusage dedupes by
message + request id, so overlapping copies are counted only once.

```
┌──────────┐  push    ┌────────────────────────────┐
│ laptop   │ ───────▶ │ hub:  ~/ccusage-multi/      │
├──────────┤          │         laptop/.claude ...  │   ccusage-all
│ desktop  │ ───────▶ │         desktop/.claude ... │ ───────────────▶  one merged report
├──────────┤          │         server/.claude ...  │   (Claude+Codex+OpenCode)
│ server   │ ───────▶ │       + hub's own ~/.claude │
└──────────┘          └────────────────────────────┘
```

## Why

- ccusage is local-only ([feature request #222](https://github.com/ryoppippi/ccusage/issues/222) for multi-device was closed as *not planned*).
- You code on more than one machine and want the real total.
- You don't want to babysit a full re-sync every time — pushes should be incremental.

## Features

- **Incremental push** — manifest diff (relative path + size); only new/changed files are tarred and streamed over SSH. Never deletes remote data.
- **Unified stats** — one `ccusage monthly --compact` covering every machine; all three platforms auto-detected.
- **Zero-config scale-out** — the hub auto-discovers host folders; add a machine just by pushing from it.
- **No agent on the hub** — plain SSH + a Node ≥ 18 runtime is all the hub needs.
- **Claude Code skill included** — open the repo in Claude Code and say "push" / "stats"; the bundled skill drives the scripts.

## Requirements

- **Each machine:** `bash`, `ssh`, GNU `tar`, GNU `find` (the `-printf` flag). On Windows, Git Bash provides all of these.
- **Hub:** SSH access (key-based recommended) and Node ≥ 18 (`npx` runs `ccusage`).

## Setup

```bash
git clone https://github.com/CingyQ/ccusage-hub.git
cd ccusage-hub
cp hosts.conf.example hosts.conf
# edit hosts.conf: HUB_SSH, LOCAL_NAME, source paths, HUB_NODE_BIN
```

Key fields in `hosts.conf`:

| Field | Meaning |
|-------|---------|
| `HUB_SSH` | ssh alias or `user@host` for the hub |
| `HUB_BASE` | remote dir for aggregated data (default `$HOME/ccusage-multi`) |
| `HUB_NODE_BIN` | dir containing node ≥ 18 on the hub (empty if already on `PATH`) |
| `CCUSAGE_VERSION` | npm version/tag of ccusage to run (`latest`, or pin e.g. `19`) |
| `LOCAL_NAME` | **unique** label for this machine (its subdir on the hub) |
| `LOCAL_CLAUDE_PROJECTS` / `LOCAL_CODEX_SESSIONS` / `LOCAL_OPENCODE_DIR` | local source dirs (empty to skip a platform) |
| `HUB_CLAUDE` / `HUB_CODEX` / `HUB_OPENCODE` | hub's own data dirs, so its local usage is counted too |

## Usage

From any machine, in the project dir:

```bash
bash bin/push.sh --dry-run     # preview the delta
bash bin/push.sh               # push new/changed files to the hub
bash bin/stats.sh              # unified monthly report (--compact)
bash bin/stats.sh daily        # any ccusage subcommand
bash bin/stats.sh "monthly --json" > usage.json
bash bin/stats.sh --show-env   # show the resolved CLAUDE_CONFIG_DIR/CODEX_HOME/OPENCODE_DATA_DIR
```

Typical flow is **push, then stats**.

### Run directly on the hub (optional)

Install the standalone runner so you can report without SSHing from a client:

```bash
scp bin/ccusage-all  HUB:~/.local/bin/ccusage-all   # ensure ~/.local/bin is on PATH
ssh HUB
ccusage-all                    # monthly --compact over every pushed host + the hub itself
ccusage-all daily
ccusage-all --show-env
```

`ccusage-all` is configured purely by environment variables (`HUB_BASE`,
`NODE_BIN`, `HUB_CLAUDE`, …) — see the header of the script.

## Adding another machine

1. Clone the repo on the new machine.
2. `cp hosts.conf.example hosts.conf`, set a **distinct** `LOCAL_NAME`.
3. `bash bin/push.sh`.

That's it — `stats.sh` / `ccusage-all` discover the new host folder automatically.

## How it works

- `bin/push.sh` — builds a `relpath\tsize` manifest locally and on the hub, `comm -23` to find files that are new or have grown (JSONL logs only append), then `tar --files-from=<delta> | ssh "tar x"`. Files present only on the hub are left untouched.
- `bin/stats.sh` — SSHes to the hub, lists `$HUB_BASE` to discover all host folders, builds comma-separated path lists, exports the three env vars, and runs `npx ccusage@latest`.
- `bin/ccusage-all` — the same merge logic, but run locally on the hub.

A Claude Code skill at `.claude/skills/ccusage-hub/SKILL.md` documents the
workflow for agent-driven use.

## Notes & limitations

- Append-only by design: these scripts never delete remote files. Do cleanup manually.
- OpenCode stores `cost: 0` in its records; ccusage recomputes cost from tokens via the LiteLLM price table.
- Clock skew between machines may make `tar` print a harmless "timestamp in the future" warning.
- ccusage **v20.0.0–20.0.1** has a `monthly` aggregation bug ([#1097](https://github.com/ryoppippi/ccusage/issues/1097)) that expands agent rows per day instead of per month. Until it's fixed in a release, set `CCUSAGE_VERSION="19"` in `hosts.conf`. Switch back to `latest` once resolved.

## License

MIT — see [LICENSE](LICENSE).
