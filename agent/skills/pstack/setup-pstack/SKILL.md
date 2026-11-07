---
name: setup-pstack
description: Configure which models pstack uses per role and at what reasoning budget. Detects your available models and writes an always-applied rule that overrides the skill defaults. Use for /setup-pstack, "configure pstack models", "pstack budget", or changing pstack's model choices.
---

# Setup pstack

Write `__PI_AGENT_DIR__/pstack-models.md`, a plain markdown file that sets pstack's model per role. The role-reading skills read it by that absolute path.

## Steps

### 1. Detect available models

Enumerate the model slugs available to this pi session: read `providers.*.models[].id` from `__PI_AGENT_DIR__/models.json`, which is the dependable source. For this setup that is the `soclaas` provider, whose IDs look like `soclaas/x-test-2`. If you cannot read that file, ask the user to paste the slugs they have access to. Never write a real slug you have not confirmed is available. The aliases `inherit-parent` and `auto` are always valid even though they are not detected slugs.

### 2. Load current state

The default role-to-model mapping is the rule shape shown in step 5 below. If `__PI_AGENT_DIR__/pstack-models.md` already exists, read it and treat its `# budget` line and its role values as the current choices. Otherwise start from those defaults. A line whose role is not in step 5, such as `how critics`, is from a retired role. Drop it.

### 3. Budget, map, and confirm

**(a) Ask for a budget.** Ask in plain text in your reply, with these four options and these exact labels, and name the current budget when the table records one. With no table, say that `large` matches the skill defaults.

- `unlimited — max reasoning`
- `large — xhigh reasoning`
- `medium — high reasoning`
- `small — medium reasoning`

**(b) Apply it.** Build the working table from the skill defaults, and on a re-run keep any role you changed by family, list, or alias (`inherit-parent`, `auto`). `unlimited`, `large`, `medium`, and `small` set the effort token of every real slug, panel entries included, to `max`, `xhigh`, `high`, or `medium`. The effort token is the last token, or the one before a trailing `fast`, on the ladder `max` > `xhigh` > `high` > `medium` > `low`, and a slug here carries its effort as a `:<effort>` suffix or a `-<effort>` tail. If the result is not a detected slug, use the same family's detected slug with the highest effort at or below the target, else mark the role as needing a choice. `inherit-parent` and `auto` do not change. Check `__PI_AGENT_DIR__/models.json`'s `thinkingLevelMap` before promising an effort: on this setup `soclaas/x-test-1` and `x-test-2` map `xhigh` to `max`, while `x-test-3` and `x-test-4` top out at `xhigh`.

**(c) Show the roles and confirm.** Show every role with its model, marking any real slug not in the detected set as needing a choice. Also list each line step 2 dropped. Ask whether to accept as-is or change specific roles, offering the detected models plus `inherit-parent` and `auto` (both mean: this role runs on the parent chat model, which keeps the child on whatever model the parent is running) as the options. Ask in plain text in your reply. For panel roles (arena runners, architect runners, interrogate reviewers) the value is a list, and one subagent runs per entry, alias entries included, so the list length sets the count. `arena cross-judge pool` is also a list, but Arena selects one value from it whose model family differs from the parent's when possible. `swarm workers` is the default model for every worker unless a race or comparison assigns another model per arm.

### 4. Validate

Every real slug written must be in the detected set. `inherit-parent` and `auto` always pass. If a chosen real slug is not available, stop and ask again.

### 5. Write the rule

Write `__PI_AGENT_DIR__/pstack-models.md` with a `# budget` line with the chosen label and its target effort, and one line per role, using the same labels poteto-mode uses. Overwrite the whole file so re-runs stay idempotent. No frontmatter: pi has no always-applied rule mechanism, so this file is plain markdown read by absolute path. Shape:

```
<!-- pstack per-role model choices. Read by the pstack role-reading skills. -->
# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit the child's `model`). Alias entries in a panel list still count toward its fan-out.
# budget: large (xhigh)
feature, refactoring: soclaas/x-test-2
bug-fix: soclaas/x-test-2
perf-issue: soclaas/x-test-1
hillclimb: soclaas/x-test-1
judgment and prose: soclaas/x-test-2
hardest tasks: soclaas/x-test-2
how explorer: soclaas/x-test-4
how explainer: soclaas/x-test-1
why investigators: soclaas/x-test-4
why synthesizer: soclaas/x-test-1
reflect tooling: soclaas/x-test-4
reflect judgment, divergent, synthesizer: soclaas/x-test-2
arena runners: soclaas/x-test-2, soclaas/x-test-1
arena cross-judge pool: soclaas/x-test-4, soclaas/x-test-3
swarm workers: soclaas/x-test-1
architect runners: soclaas/x-test-2, soclaas/x-test-4
interrogate reviewers: soclaas/x-test-1, soclaas/x-test-4
```

### 6. Confirm

Tell the user the table was written to `__PI_AGENT_DIR__/pstack-models.md` and that the role-reading skills pick it up on their next run. Re-running this skill updates it.

### 7. Offer a verification skill (optional)

Check whether the project has a way to drive the real app for proof (a `verify-*` skill, or an existing harness). If not, offer once: "want a project-local verification skill, so agents can drive the app the way a user does and prove changes work? I can generate one with /create-verification-skill." On yes, invoke `/create-verification-skill` (resolves wherever pstack is installed: workspace, user, or plugin). On no, move on without pushing.

### 8. Offer a formal verification skill (optional)

Check whether the project already has a formal verification skill (a project skill that runs a model checker, a proof, or another verifier against the code). If not, offer once: "want a formal verification skill, so agents can prove a key property of your code holds in every case in scope, not only the cases tests reach? I can generate one with /create-formal-verification-skill." On yes, invoke `/create-formal-verification-skill` (resolves wherever pstack is installed: workspace, user, or plugin). On no, move on without pushing.
