#!/usr/bin/env bash
# Health checks for an installed pi agent environment.
#
# Usage: ./verify.sh [--agent-dir PATH] [--no-ping]

set -uo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
DO_PING=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent-dir) AGENT_DIR="${2:?}"; shift 2 ;;
    --no-ping)   DO_PING=0; shift ;;
    -h|--help)   sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
AGENT_DIR="${AGENT_DIR/#\~/$HOME}"

FAIL=0
SKIP=0
pass() { printf '\033[1;32m  PASS\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m  FAIL\033[0m %s\n' "$*"; FAIL=$((FAIL + 1)); }
skip() { printf '\033[1;33m  SKIP\033[0m %s\n' "$*"; SKIP=$((SKIP + 1)); }

printf '\033[1mVerifying %s\033[0m\n\n' "$AGENT_DIR"

# --- pi itself
if command -v pi >/dev/null 2>&1; then
  pass "pi on PATH ($(pi --version 2>/dev/null || echo version unknown))"
else
  fail "pi is not on PATH"
fi

if command -v bun >/dev/null 2>&1; then
  pass "bun on PATH ($(bun --version 2>/dev/null))"
else
  skip "bun missing (poteto-mode scripts and statechart helpers need it)"
fi

# --- payload files
for f in settings.json models.json APPEND_SYSTEM.md pstack-models.md; do
  if [[ -s "$AGENT_DIR/$f" ]]; then pass "$f"; else fail "$f missing or empty"; fi
done

[[ -f "$AGENT_DIR/mcp.json" ]] && pass "mcp.json" || skip "mcp.json absent (no Chromium was available at install time)"

SKILL_COUNT=$(find "$AGENT_DIR/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SKILL_COUNT" -ge 59 ]]; then
  pass "$SKILL_COUNT skills"
else
  fail "only $SKILL_COUNT skills found, expected at least 59"
fi

AGENT_COUNT=$(find "$AGENT_DIR/agents" -name '*.md' ! -name CONVENTIONS.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$AGENT_COUNT" -ge 28 ]]; then
  pass "$AGENT_COUNT agent definitions"
else
  fail "only $AGENT_COUNT agent definitions, expected at least 28"
fi

ADVERTISED=$(grep -rl '^advertise: true' "$AGENT_DIR/agents" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$ADVERTISED" -eq 13 ]]; then
  pass "13 advertised agents"
elif [[ "$ADVERTISED" -gt 0 ]]; then
  fail "$ADVERTISED advertised agents, expected 13"
else
  fail "no agent has advertise: true"
fi

# --- poteto wiring
POTETO_AGENTS=0
for name in poteto-mode poteto-agent; do
  if grep -q "^name: $name\$" "$AGENT_DIR/agents/pstack/$name.md" 2>/dev/null; then
    POTETO_AGENTS=$((POTETO_AGENTS + 1))
  fi
done
if [[ "$POTETO_AGENTS" -eq 2 ]]; then
  pass "poteto-mode and poteto-agent definitions present"
else
  fail "poteto agent definitions missing ($POTETO_AGENTS of 2)"
fi

# --- delegate extension
EXT_DIR="$AGENT_DIR/extensions/poteto-delegate"
if [[ -f "$EXT_DIR/index.ts" && -f "$EXT_DIR/agents.ts" && -f "$EXT_DIR/runner.ts" ]]; then
  pass "poteto-delegate extension present"
  if grep -q 'poteto_delegate' "$EXT_DIR/index.ts" 2>/dev/null; then
    pass "poteto_delegate tool is registered"
  else
    fail "index.ts does not register poteto_delegate"
  fi
else
  fail "extensions/poteto-delegate is incomplete (expect index.ts, agents.ts, runner.ts)"
fi

if [[ -d "$AGENT_DIR/agents/pstack" ]] && grep -rq 'subagent, contact_supervisor' "$AGENT_DIR/agents/pstack" 2>/dev/null; then
  fail "agent files still name the removed subagent/contact_supervisor tools"
else
  pass "no agent names a removed tool"
fi

if [[ -f "$AGENT_DIR/skills/pstack/poteto-mode/SKILL.md" ]]; then
  pass "poteto-mode skill present"
  if grep -q '^disable-model-invocation: true' "$AGENT_DIR/skills/pstack/poteto-mode/SKILL.md"; then
    skip "poteto-mode skill is command-only (agentic via the two agents)"
  else
    pass "poteto-mode skill is model-invocable"
  fi
else
  fail "poteto-mode skill missing"
fi

# --- portability
# Machine-local trees hold transcripts and package clones that were never part of
# the payload, so they are excluded: a placeholder there is not an install bug.
LEFT=$(grep -rl '__PI_AGENT_DIR__\|__PLAYWRIGHT_CHROME__' "$AGENT_DIR" \
  --exclude-dir=sessions --exclude-dir=npm --exclude-dir=git \
  --exclude-dir=missions --exclude-dir=node_modules 2>/dev/null | wc -l | tr -d ' ')
if [[ "$LEFT" -eq 0 ]]; then
  pass "no unrendered placeholders"
else
  fail "$LEFT files still contain placeholders (re-run install.sh)"
fi

# A path rendered for a different machine points the skills at an agent directory
# that does not exist here. Only `/home/<user>/.pi/agent` counts: other home paths
# in the payload are test fixtures and example strings, not settings.
STRAY=$(grep -rhoE '/home/[a-z0-9_-]+/\.pi/agent' "$AGENT_DIR/skills" "$AGENT_DIR/agents" 2>/dev/null \
  | sort -u | grep -vx "/home/$(whoami)/.pi/agent" || true)
if [[ -z "$STRAY" ]]; then
  pass "no agent-directory path rendered for another user"
else
  fail "agent-dir paths for another user survived install: $(tr '\n' ' ' <<<"$STRAY")"
fi

# --- soclaas provider
if [[ -n "${SOCLAAS_API_KEY:-}" ]]; then
  pass "SOCLAAS_API_KEY set (${#SOCLAAS_API_KEY} chars)"
else
  fail "SOCLAAS_API_KEY is not exported in this shell"
fi

if command -v pi >/dev/null 2>&1 && [[ -n "${SOCLAAS_API_KEY:-}" ]]; then
  MODELS=$(pi --list-models soclaas 2>/dev/null | awk '$1 == "soclaas"' | wc -l | tr -d ' ')
  if [[ "${MODELS:-0}" -ge 8 ]]; then
    pass "$MODELS soclaas models visible to pi"
  else
    fail "pi --list-models shows ${MODELS:-0} soclaas models, expected at least 8"
  fi
  if pi --list-models soclaas 2>/dev/null | awk '{print $2}' | grep -qx 'x-test-2'; then
    pass "default model soclaas/x-test-2 is available"
  else
    fail "x-test-2 is not in the soclaas model list"
  fi
fi

# --- packages
if command -v pi >/dev/null 2>&1; then
  PKGS=$(pi list 2>/dev/null | grep -cE 'ketch|billion-context|pi-dynamic-workflows' || true)
  if [[ "${PKGS:-0}" -ge 3 ]]; then
    pass "all three packages resolve"
  else
    fail "${PKGS:-0} of 3 packages resolve (run: pi update --extensions)"
  fi
fi

# --- live request
if [[ $DO_PING -eq 1 && -n "${SOCLAAS_API_KEY:-}" ]] && command -v pi >/dev/null 2>&1; then
  printf '  ...  live soclaas request\n'
  OUT=$(timeout 180 pi -p --no-session --no-tools --provider soclaas --model x-test-2 \
        'Reply with exactly: PI-SETUP-OK' 2>&1 | tr -d '\r')
  if grep -q 'PI-SETUP-OK' <<<"$OUT"; then
    pass "live soclaas/x-test-2 request answered"
  else
    fail "live request failed: $(head -3 <<<"$OUT" | tr '\n' ' ')"
  fi
fi

printf '\n'
if [[ $FAIL -eq 0 ]]; then
  printf '\033[1;32mAll checks passed.\033[0m'; [[ $SKIP -gt 0 ]] && printf ' (%d skipped)' "$SKIP"; printf '\n'
  exit 0
fi
printf '\033[1;31m%d check(s) failed.\033[0m' "$FAIL"; [[ $SKIP -gt 0 ]] && printf ' (%d skipped)' "$SKIP"; printf '\n'
exit 1
