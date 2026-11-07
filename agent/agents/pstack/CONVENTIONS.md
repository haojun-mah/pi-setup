# pstack delegate conventions on pi

The pstack skills were written for Cursor. This file is the translation. Read it once per run, apply it to every instruction the skill gives that names a Cursor-only concept, and do not restate it back to the caller.

Each pstack skill has a matching agent here when the skill is a procedure worth running on its own. The agent adds a launch contract; the SKILL.md stays the source of the steps. Read the SKILL.md before you start.

## Cursor concept to pi equivalent

| The skill says | Do this instead |
| --- | --- |
| `Task` tool | `subagent` tool. One child per call, or `workflow` for a fan-out. |
| `subagent_type: "generalPurpose"` | `worker` for a change, `scout` for a read-only slice, `poteto-agent` for a poteto-styled piece of code. |
| `subagent_type: "poteto-agent"` | The `poteto-agent` agent. |
| `subagent_type: "comment-sicko"` | The `comment-sicko` agent. |
| `subagent_type: "<skill name>"` | `pstack-<skill name>` when this agent set defines one, otherwise read that SKILL.md and do the step yourself. |
| the **how** skill, the **arena** skill (a bold skill name in prose) | The delegate `pstack-how`, `pstack-arena`, and so on, when you need it as separate work. When the step is small, read `__PI_AGENT_DIR__/skills/pstack/how/SKILL.md` and do it yourself instead of paying for a child. |
| `readonly: true` | An agent whose `acceptanceRole` is `read-only`, or your own restraint when you are the one reading. There is no per-call read-only flag. |
| `run_in_background: true` | The default for `subagent` is async. Use `async: true` and collect with the completion notification. |
| `run_in_background: false` | `async: false` on the `subagent` call. |
| `environment: "cloud"` / `environment: "local"` | There is no cloud worker. Everything runs locally in the child's cwd. Drop the field. |
| `cloud_base_branch` | Drop it. A candidate runs in a git worktree off the current HEAD, or in `/tmp/arena-<slug>/candidate-<n>/`. |
| `AskQuestion` / a question card | Plain text in your reply, or `contact_supervisor` with `need_decision` when you are a child that cannot continue. |
| `update_state` | Nothing. Write the state into your reply and into the decision log. |
| `~/.cursor/rules/pstack-models.mdc` | `__PI_AGENT_DIR__/pstack-models.md`. pi has no always-applied rule file, so that markdown table is read by absolute path. Children inherit the parent model when its role line is `auto` or `inherit-parent`, or when the role is absent. |
| `.cursor/skills/<name>/` | `__PI_AGENT_DIR__/skills/<name>/`, and pstack's own skills under `__PI_AGENT_DIR__/skills/pstack/<name>/`. |
| `.cursor/projects/*/agent-transcripts/*.jsonl` | `__PI_AGENT_DIR__/sessions/--<workspace path with / turned into ->--/*.jsonl`. One JSONL line per message. |
| `.cursor/skills/create-skill` | Write the skill by hand at `__PI_AGENT_DIR__/skills/<name>/SKILL.md`, matching the frontmatter of the skills already there. |
| `deslop` | Delete the slop yourself. Replace hedges and restatement with the fact. |
| `control-cli` (from `cursor-team-kit`) | No equivalent. Drive the CLI yourself with `bash`; the Playwright MCP server exists but covers only browsers. |
| `control-ui` (from `cursor-team-kit`) | The Playwright MCP tools, when this session exposes a `browser_*` tool. Check first; if none is present, say the surface cannot be driven here instead of claiming a fix works. |
| `.cursor/worktrees`, `.cursor/plugins` | Worktrees come from `git worktree add`; plugins have no equivalent. |

## What the child has

Tools are `read`, `grep`, `find`, `ls`, `bash`, plus `edit` and `write` when the agent is a writer, plus `subagent` when it orchestrates. `contact_supervisor` reaches the parent chat.

Anything else in a skill, such as a Playwright browser or a Datadog MCP server, is not guaranteed to exist in a child. Check with `which` or a cheap probe before you plan around a tool, and record the skip instead of failing late.

Children do not inherit the parent's skills. A child that needs a procedure reads the SKILL.md by absolute path.

A forked child sees the parent's tool declarations. Calling one you do not own returns `Tool <name> not found` and runs nothing, so do not retry it. Use the tools in your own list.

## Spawning rules

Give each child a self-contained brief. File pointers with line numbers, not inlined source. The intent paragraph, not a summary of the intent.

One writer per file. When several children would touch the same tree, split the tree or serialize them.

State a model only when the caller configured one for that role. Never guess a slug from a model family; an unresolvable slug fails the launch.

`workflow` is for fan-out with declared phases. Use it when the skill says "parallel workers", "one reviewer per model", or "one investigator per source". Otherwise a single `subagent` call is the cheaper route.

## What this set does not cover

A skill with no `pstack-` agent is one you apply while you work, not one you dispatch. The principles, the prose rules, and the style skills are read into your own run and follow you. Spawning a child to apply `unslop` or a principle wastes a launch, because those skills need the text you are already holding.

Left as skills on purpose, because each one edits text the caller is already holding or restates a rule you apply inline:

- the 24 `principle-*` leaves, which `poteto-mode` cites by name.
- `bro`, `in-your-own-words`, `sharpen`, `unslop`, `technical-writing`, `typescript-best-practices`, which rewrite or constrain prose in place.
- `ketchup` and `ketchup-video`. Both describe a reply to the person in this chat, from this chat's record, so a delegate has nothing to hand back. They ran as forks and looped on the inherited tool list, so the agents were removed rather than patched.

If one of those needs a delegate later, add it to the table in `_generate.py` next to this file and re-run it. Do not hand-write a new agent file beside the generated ones.

## Reporting back

Leave the caller able to act without re-reading the skill. Say what you did, what you measured, what you skipped and why, what still needs a human decision, and the file pointers a reviewer would open first.

Label an inference as an inference. A fact you did not run or read is not evidence, and "I did not check" is a complete sentence.
