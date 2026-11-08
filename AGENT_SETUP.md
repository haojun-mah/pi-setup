# AGENT_SETUP

You are setting up a pi agent environment on this machine from the repo you were pointed at. This file is the runbook. Follow it in order and do not improvise around the checks.

The end state: `~/.pi/agent` holds this environment, `pi` runs the `soclaas` provider, `soclaas/x-test-2` is the default model at `xhigh` thinking, the three packages are installed, 59 skills and 28 agent definitions are on disk, and the poteto playbook is reachable both as a skill and as an advertised delegate.

## Rules for you, the setup agent

- Ask the human exactly one thing: the SoCLaaS API key, and only if step 3 says it is missing. Do not ask anything else. Defaults are already decided in this repo.
- Never write the API key into this repo, into a commit, into `models.json`, or into `auth.json`. It goes to the shell environment, and optionally one line in the shell rc.
- Do not edit the payload to make it fit. If a step fails, report the failure and the exact error instead of working around it by hand-editing skills or agents.
- Everything is idempotent. A second run is safe, so prefer re-running over hand-fixing.
- Do not `git push`, do not open a PR, do not change the repo. Read it, run it.

## Step 1: confirm the repo

```bash
cd ~/pi-setup      # wherever you cloned it
ls agent/skills agent/agents install.sh verify.sh
```

You should see `install.sh`, `verify.sh`, and `agent/` with `skills/` and `agents/` inside. If `agent/` is missing, the clone is incomplete: re-clone, then continue.

## Step 2: confirm prerequisites

```bash
node --version        # needs v22.19 or newer
git --version
command -v pi || echo "PI MISSING"
command -v bun || echo "BUN MISSING"
```

- **`pi` missing**: install it with `npm install -g --ignore-scripts @earendil-works/pi-coding-agent`.
- **`bun` missing**: not fatal, but the poteto playbook scripts (`watch-pr`, `orch`) and the statechart helpers need it. Install with `curl -fsSL https://bun.sh/install | bash` and make sure `~/.bun/bin` is on PATH. Mention it in your report as a degradation if you skip it.
- **`node` too old**: stop and report. Pi will not run.

## Step 3: resolve the API key

The `soclaas` provider authenticates with `$SOCLAAS_API_KEY`. The repo never carries it.

```bash
[ -n "${SOCLAAS_API_KEY:-}" ] && echo "KEY PRESENT" || echo "KEY MISSING"
```

- **Present**: continue. Nothing to ask.
- **Missing**: ask the human for it, once, in plain words: the setup needs their SoCLaaS API key, and they can either paste it or put it in a file you can read. Then:

  ```bash
  ./install.sh --key-file /path/they/gave/you
  ```

  Offer `--persist-key` so the export lands in their shell rc and the next shell has it. Confirm before writing to their rc if they did not ask for it.
- **Missing and the human wants no prompt**: they can `export SOCLAAS_API_KEY=...` themselves and you re-run. Do not invent a key and do not continue without one: `pi` will report "No models available" and the install cannot be verified.

## Step 4: install

```bash
./install.sh --yes
```

Add flags only for a reason named here:

| Situation | Flag |
| --- | --- |
| The human has other skills or agents in `~/.pi/agent` they want kept | `--merge` |
| The human wants the key exported to their shell rc permanently | `--persist-key` |
| They gave you the key in a file | `--key-file PATH` |
| They want `poteto-mode` to stay command-only (`/skill:poteto-mode`) | `--poteto-explicit` |
| Playwright's Chromium is missing and they are fine with a download | `--playwright install` |
| They have their own browser binary | `--chrome PATH` |
| They use a non-default agent dir | `--agent-dir PATH` or `PI_CODING_AGENT_DIR` |

What the script does, in order: checks prerequisites, resolves the key, finds a Chromium for the playwright MCP server (and drops that server from `mcp.json` if there is none), backs up the existing `~/.pi/agent` to `~/.pi/agent-backups/<timestamp>/`, copies the payload, makes the poteto-mode skill model-invocable unless `--poteto-explicit`, renders the two path placeholders against this machine, runs `pi install` for each of the three package sources, and prints the summary.

Read its output. Any `!!` line is a degradation you must report.

## Step 5: verify

```bash
./verify.sh
```

This checks pi and bun, the four payload files, the skill and agent counts, that exactly 13 agents are advertised, that `poteto-mode` and `poteto-agent` exist as definitions and the skill resolves, that no placeholder or stale home path survived, that the key is set, that `pi --list-models` sees the soclaas models, that all three packages resolve, and finally that a live `soclaas/x-test-2` request answers.

`--no-ping` skips the live request, which is the only check that costs tokens.

Exit 0 is the bar. On a failure, the message names the file or check; re-run `install.sh` for anything about a missing file or placeholder, `pi update --extensions` for a package that does not resolve, and report a live-request failure with the error text rather than retrying it repeatedly.

## Step 6: prove the poteto wiring

The two things this repo exists to carry are the soclaas provider and poteto as an agentic part. Confirm both, cheaply.

```bash
pi --list-models soclaas | head -20
grep -l '^advertise: true' ~/.pi/agent/agents/pstack/*.md | xargs -n1 basename
```

The first must show the soclaas models, `x-test-2` among them. The second must list 13 files including `poteto-mode.md`, `poteto-agent.md`, `comment-sicko.md`, and the advertised `pstack-*` procedures.

Then one end-to-end smoke test, in a scratch directory:

```bash
mkdir -p /tmp/pi-setup-smoke && cd /tmp/pi-setup-smoke
pi -p "Name the agents you have available whose description mentions poteto, in one line." 
```

An answer that names `poteto-mode` and `poteto-agent` proves the advertisement reached the parent prompt: the catalog is injected from the agent files, not from the skill.

## Step 7: report

Report in this shape, and keep it short:

- **Installed**: agent dir, pi version, default provider and model, skill count, agent count, advertised count.
- **Key**: where it came from (already exported, file, prompt, rc) and whether it was persisted. Never print the key.
- **Degradations**: every `!!` from `install.sh`, any skipped verification check, and whether bun or Chromium is missing.
- **Verification**: pass or fail per check, and the exact error for any failure.
- **Next**: that `pi` is ready, and that `install.sh` can be re-run after a pull.

If something failed and you could not fix it, say which step and paste the error. An honest partial install beats a claim that everything worked.

## Reference: what is in the payload

`settings.json` sets `soclaas` as the default provider, `x-test-2` as the default model, `xhigh` thinking, compaction on, and the three package sources (`git:github.com/1broseidon/ketch`, `npm:billion-context`, `npm:@quintinshaw/pi-dynamic-workflows`).

`models.json` declares the `soclaas` provider: base URL `https://soclaas-api.comp.nus.edu.sg/v1`, `openai-completions`, `apiKey: "$SOCLAAS_API_KEY"`. Eight real models and four `x-test-*` routes, each with its context window, capabilities, and `thinkingLevelMap`. `x-test-1` and `x-test-2` map `xhigh` to `max`; `x-test-3` and `x-test-4` top out at `xhigh`. Aliases `coder`, `coding`, `default`, `ornith1.0:35b`, and `qwen3.6:27b` point at the sensible defaults.

`pstack-models.md` is pstack's per-role model table, read by the pstack skills at an absolute path. Every role maps to a soclaas slug: `feature`/`refactoring`/`bug-fix`/`judgment`/`hardest` on `x-test-2`, `perf-issue`/`hillclimb`/`swarm workers`/`interrogate` on `x-test-1`, `how explorer`/`why investigators`/`reflect tooling` on `x-test-4`, `arena cross-judge` on `x-test-4` and `x-test-3`, with the benchmark evidence for each pick in a trailing comment.

`skills/pstack/` holds 58 skills. `poteto-mode` carries 23 playbooks, `references/bugbot-triage.md`, and the `scripts/` tooling (`watch-pr`, `orch`, `check-plan.mjs`) which bootstraps its own dependencies through bun from a checked-in `bun.lock`. The 22 `principle-*` leaves are what poteto mode cites. `arena`, `architect`, `swarm`, `interrogate`, `how`, `why`, `recall`, `reflect`, `teach`, `blast-radius`, `statechart`, `tdd`, `correct`, `unslop`, `no-comments`, and `setup-pstack` round it out.

`agents/pstack/` holds 28 poteto agent definitions. 13 carry `advertise: true`, which is the whole advertisement budget (16 entries, 12 KiB). Each wraps one skill with the launch contract, and `CONVENTIONS.md` holds the Cursor-to-pi translation the skills are read against. `_generate.py` regenerates them from a table and is not loaded as an agent.

`extensions/poteto-delegate/` is what makes those files callable. It registers `poteto_delegate`, `poteto_delegate_wait`, and `poteto_delegate_cancel`; `poteto_delegate` reads every `.md` under `agents/`, then spawns a `pi` child with that file's body as an appended system prompt and its `tools:` line as the child's `--tools` allowlist. Async by default, so the result arrives as a follow-up; `async: false` blocks for it. `pi-subagents` is not involved and not required.

Two behaviours worth knowing, both verified against this pi:

- A child inherits `BILLION_CONTEXT_PROXY`. When billion-context runs inline that value is the sentinel `http://billion-context.inline`, which a child process can never reach, so its ACP tools silently fail to register. The extension drops that variable for the child, which then arms its own lane.
- `--tools` is an allowlist, so naming tools drops the four ACP compression tools. The extension appends `compress`, `decompress`, `search_context`, and `acp_status` to every child's list.

Read-only is enforced by tool removal, not by policy: an agent with `acceptanceRole: read-only` never receives `edit` or `write`. It can still write through `bash` if its `tools:` line includes `bash`, which is the same limitation billion-context's restricted roles have.

`mcp.json` adds the `playwright` MCP server, headless, 1280x720, isolated profile, with the absolute Chromium path rendered at install time.

`APPEND_SYSTEM.md` is one line: `Always respond in English.`

## Reference: what is not in the payload, and why

`sessions/` (tens of MB of transcripts), `npm/` and `git/` (package clones, re-fetched by `pi install`), `bin/fd` and `bin/rg` (5 MB ELF binaries pi re-downloads on demand), `auth.json` (empty; the key lives in the environment), `missions/` (run journals), `*.bak`, `pi-debug.log`, and `models-store.json`. Nothing that is machine-local, secret, or reproducible belongs in the repo.
