<!-- pstack per-role model choices. Read by the pstack role-reading skills. -->
<!-- pi has no "always-applied rule" file; this is a plain file that skills read by absolute path. -->

# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` or `auto` as a value: the role runs on the parent chat model (omit Task `model`). Alias entries in a panel list still count toward its fan-out.
# All slugs are soclaas provider models. budget: unlimited (max).
# budget: unlimited (max)  # x-test-1/2 map xhigh->max; x-test-3/4 top out at `xhigh` (nearest ceiling)
# Allocation evidence (2026-10-25): Artificial Analysis Intelligence Index (DS1017 45 > MiniMax 42 = GLM-flash 42; MiniMax HLE 48% best),
# Vals AI (GLM-flash best Terminal-Bench 4.0 37.4%), BenchLM (DS1017 NL2Repo #1 68.2%), eqbench.com (GLM line best open-weight prose),
# arena.ai Text Arena (DS1017 human-pref #1 of pool), aider polyglot (GLM-flash 88%).
feature, refactoring: soclaas/x-test-2   # DeepSeek V4.1 Flash 1017: NL2Repo #1 (repo-level SWE), AA Intelligence Index #1 of pool
bug-fix: soclaas/x-test-2                # DeepSeek V4.1 Flash 1017: strongest general SWE reasoning, HLE w/tools 63.9
perf-issue: soclaas/x-test-1             # GLM-5.3-Flash: terminal tracing + cheapest for long measurement loops
hillclimb: soclaas/x-test-1              # GLM-5.3-Flash: best sustained terminal iteration (TB4.0 leader), cheapest
judgment and prose: soclaas/x-test-2     # DeepSeek V4.1 Flash 1017: AA #1 + best human text preference of pool
hardest tasks: soclaas/x-test-2          # DeepSeek V4.1 Flash 1017: highest intelligence index in pool at max effort
how explorer: soclaas/x-test-4           # MiniMax M3.1 Flash: best complex reasoning (HLE 48%), agentic tool use, cheapest
how explainer: soclaas/x-test-1          # GLM-5.3-Flash: GLM line is best open-weight prose on EQ-Bench
why investigators: soclaas/x-test-4      # MiniMax M3.1 Flash: deep reasoning + agentic investigation at lowest cost
why synthesizer: soclaas/x-test-1        # GLM-5.3-Flash: prose quality for written synthesis
reflect tooling: soclaas/x-test-4        # MiniMax M3.1 Flash: automation/computer-use leader
reflect judgment, divergent, synthesizer: soclaas/x-test-2   # DeepSeek V4.1 Flash 1017: highest-fidelity judgment
arena runners: soclaas/x-test-2, soclaas/x-test-1            # two strongest families bake off: DeepSeek vs GLM
arena cross-judge pool: soclaas/x-test-4, soclaas/x-test-3   # judge families differ from runners: MiniMax + Qwen
swarm workers: soclaas/x-test-1          # GLM-5.3-Flash: cheapest per token AND best terminal model — fan-out + verification
architect runners: soclaas/x-test-2, soclaas/x-test-4        # reasoning-heaviest pair for design work
interrogate reviewers: soclaas/x-test-1, soclaas/x-test-4    # adversarial panel: GLM agentic-eye + MiniMax reasoning
