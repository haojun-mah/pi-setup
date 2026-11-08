# pi-setup

My personal [pi](https://pi.dev) agent environment, as a portable, one-shot installer.

Point a fresh pi agent at this repo and it reproduces the whole environment: model provider, default model, thinking level, packages, 59 skills, 28 agent definitions, the MCP server, and the surface system prompt. Nothing is hand-edited afterward.

```bash
git clone https://github.com/haojun-mah/pi-setup ~/pi-setup && ~/pi-setup/install.sh
```

The repo is private. On a machine without SSH keys or a saved token, clone it with `gh` instead, after `gh auth login`:

```bash
gh repo clone haojun-mah/pi-setup ~/pi-setup && ~/pi-setup/install.sh
```

## One-shot from a bare machine

Two paths, both idempotent and safe to re-run.

**Path A: let the agent do it.** On the new machine, install pi (`npm install -g --ignore-scripts @earendil-works/pi-coding-agent`), start it anywhere, and paste:

```text
Clone https://github.com/haojun-mah/pi-setup to ~/pi-setup, read AGENT_SETUP.md there, and set up my pi environment end to end. Ask me only for the SoCLaaS API key if it is not already in my environment.
```
The agent reads `AGENT_SETUP.md`, runs `install.sh` with the right flags, handles the API key, runs `verify.sh`, and reports. The key is the one thing it cannot invent, so it asks once.

**Path B: no agent.** Export the key, then run one command:

```bash
export SOCLAAS_API_KEY=...        # your SoCLaaS key
git clone https://github.com/haojun-mah/pi-setup ~/pi-setup
~/pi-setup/install.sh --yes
```

`--yes` means "never prompt, take the defaults". Missing prerequisites it can install, it installs. The Playwright browser it cannot, it skips with a one-line note.

## What lands on disk

Everything goes to `~/.pi/agent` (or `$PI_CODING_AGENT_DIR` if that is set).

| File | Contents |
| --- | --- |
| `settings.json` | `soclaas` as default provider, `x-test-2` as default model, `xhigh` thinking, compaction on, three package sources |
| `models.json` | The `soclaas` provider: base URL `https://soclaas-api.comp.nus.edu.sg/v1`, OpenAI-compatible, key read from `$SOCLAAS_API_KEY`, eight real models plus four `x-test-*` routes with their `thinkingLevelMap` effort ceilings |
| `pstack-models.md` | pstack's per-role model table. Every role maps to a soclaas slug, with the benchmark evidence for the pick in a trailing comment |
| `mcp.json` | `playwright` MCP server, headless, 1280x720, isolated profile, absolute Chromium path rendered at install time |
| `APPEND_SYSTEM.md` | `Always respond in English.` |
| `skills/pstack/` | 58 pstack skills: `poteto-mode` (plus 23 playbooks and the `watch-pr` / `orch` / `bun` tooling), the 22 `principle-*` leaves, `arena`, `architect`, `swarm`, `interrogate`, `how`, `why`, `recall`, `reflect`, `teach`, `blast-radius`, `statechart`, `tdd`, `unslop`, `no-comments`, `setup-pstack`, and the rest |
| `skills/reverse-engineer-anything/` | REA, with its reference bundle |
| `agents/pstack/` | 28 poteto agent definitions, 13 of them `advertise: true` |
| `agents/pstack/CONVENTIONS.md` | The Cursor-to-pi translation table the skills are read against |
| `agents/pstack/_generate.py` | The table that generates the agent files; not loaded as an agent |
| `extensions/poteto-delegate/` | The `poteto_delegate` tool that launches those agents in a `pi` child process |

Skipped on purpose: `sessions/` (35 MB), `npm/`, `git/` (package clones, re-fetched), `bin/` (`fd` and `rg` are re-downloaded by pi on demand), `auth.json` (empty anyway), `*.bak`, logs, mission journals.

## The SoCLaaS settings and the poteto wiring

The two things this repo exists to carry over, spelled out.

**SoCLaaS.** `models.json` declares the provider and reads the key from `$SOCLAAS_API_KEY`. The key is never stored in this repo and never written to `auth.json`. `install.sh` takes it from the environment, from `--key-file`, or, when run interactively, from a hidden prompt; `--persist-key` appends one `export SOCLAAS_API_KEY=...` line to your shell rc if it is not already there. `pstack-models.md` then routes every pstack role through soclaas slugs, so the poteto skills and the soclaas provider are one decision, not two.

**poteto as an agentic part.** `poteto-mode` exists twice on purpose:

- `skills/pstack/poteto-mode/SKILL.md` is the procedure, its playbooks, and the report shape.
- `agents/pstack/poteto-mode.md` and `agents/pstack/poteto-agent.md` are the delegate definitions that make it a launchable, advertised agent. `poteto-mode` orchestrates (it holds `poteto_delegate`); `poteto-agent` is the worker other playbook steps hand code to. Both carry `advertise: true`, so they appear in the parent agent catalog as `poteto-mode` (`potato-mode`) and `poteto-agent` (`poteto`, `potato-agent`).

The agent files are inert on their own. `extensions/poteto-delegate/` is what turns them into tools: it reads every `.md` under `agents/`, and `poteto_delegate` spawns a `pi` child with that file's body appended as its system prompt and its `tools:` line as the child's allowlist. Nothing here depends on `pi-subagents`.

The skill keeps `disable-model-invocation: true` so it is not thrown into context by description matching, which is how it was tuned. `install.sh` strips that line by default so the skill is also model-invocable; pass `--poteto-explicit` to keep it command-only (`/skill:poteto-mode`). Either way the agents stay advertised.

## Portability

The export holds no absolute paths from the machine it came from. Agent definitions and skills reference the agent directory as `__PI_AGENT_DIR__`, and `mcp.json.tmpl` references the browser as `__PLAYWRIGHT_CHROME__`. `install.sh` renders both against the target machine, then verifies no placeholder survived.

Chromium is detected in `~/.cache/ms-playwright`, or anywhere `--chrome <path>` points. If it is missing, the `playwright` server is left out of `mcp.json` and the install says so, rather than shipping a server that fails on every launch. Add it later with `install.sh --playwright install`.

## Verify

```bash
~/pi-setup/verify.sh
```

Checks pi and its version, the agent directory, that every payload file arrived with no placeholder left, that the 13 advertised agents parse, that all three packages resolve, that `SOCLAAS_API_KEY` is set, that `pi --list-models` shows the soclaas models, and that a real `soclaas/x-test-2` request answers. The last check costs one tiny request; `--no-ping` skips it.

## Updating

`install.sh` backs up the previous `settings.json`, `models.json`, `mcp.json`, `APPEND_SYSTEM.md`, `pstack-models.md`, `skills/`, and `agents/` to `~/.pi/agent-backups/<timestamp>/` before it writes anything, so a re-run is reversible. Re-run it after pulling. Use `--merge` to keep skills and agents that are not in this repo instead of replacing the trees.

To refresh this repo from a live machine, run `export.sh` there. It re-copies the payload, re-templatizes the absolute paths, strips machine-local noise from `settings.json`, and fails if it finds a leak, a key, or a stray path.

## Layout

```text
pi-setup/
├── README.md
├── AGENT_SETUP.md      runbook the agent follows
├── install.sh          idempotent installer
├── verify.sh           health checks
├── export.sh           regenerate this repo from a live agent dir
└── agent/              the payload, copied verbatim into ~/.pi/agent
```
