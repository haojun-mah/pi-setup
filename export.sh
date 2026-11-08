#!/usr/bin/env bash
# Regenerate this repo's payload from a live pi agent directory.
#
# Use after changing skills, agents, models, or settings on a machine that is
# already set up. Rewrites agent/ in place, then refuses to finish if it finds a
# secret, a leftover absolute path, or machine-local noise.
#
# Usage: ./export.sh [--from PATH] [--dry-run]

set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from) SRC="${2:?}"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
SRC="${SRC/#\~/$HOME}"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

[[ -d "$SRC/skills" && -d "$SRC/agents" ]] || die "not a pi agent dir: $SRC"
[[ -f "$SRC/settings.json" ]] || die "missing $SRC/settings.json"
[[ -f "$SRC/models.json" ]]   || die "missing $SRC/models.json"

log "Exporting from $SRC"
[[ $DRY -eq 1 ]] && log "dry run: nothing will be written"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -a "$SRC/skills" "$STAGE/skills"
cp -a "$SRC/agents" "$STAGE/agents"
# The poteto delegate extension: the tool layer that launches agents/*.md.
if [[ -d "$SRC/extensions" ]]; then
  cp -a "$SRC/extensions" "$STAGE/extensions"
fi
for f in settings.json models.json APPEND_SYSTEM.md pstack-models.md; do
  [[ -f "$SRC/$f" ]] && cp "$SRC/$f" "$STAGE/$f"
done

# Drop machine-local noise from settings.json: changelog bookkeeping that pins
# versions of the exporting machine, and anything that is not a declared preference.
python3 - "$STAGE/settings.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p, encoding="utf-8"))
for key in ("lastChangelogVersion", "extensionChangelogVersions", "lastUpdateCheck", "trustedProjects"):
    d.pop(key, None)
open(p, "w", encoding="utf-8").write(json.dumps(d, indent=2) + "\n")
PY

# mcp.json carries an absolute browser path; the rest is portable.
if [[ -f "$SRC/mcp.json" ]]; then
  python3 - "$SRC/mcp.json" "$STAGE/mcp.json.tmpl" <<'PY'
import json, os, re, sys
src, out = sys.argv[1], sys.argv[2]
cfg = json.load(open(src, encoding="utf-8"))
cache = os.path.expanduser("~/.cache/ms-playwright")
for server in cfg.get("mcpServers", {}).values():
    args = server.get("args") or []
    for i, a in enumerate(args):
        if a == "--executable-path" and i + 1 < len(args):
            args[i + 1] = "__PLAYWRIGHT_CHROME__"
        elif isinstance(a, str) and (a.startswith(cache) or a.startswith(os.path.expanduser("~") + "/")):
            args[i] = "__PLAYWRIGHT_CHROME__"
open(out, "w", encoding="utf-8").write(json.dumps(cfg, indent=2) + "\n")
PY
fi

log "Rendering absolute paths back to placeholders"
python3 - "$STAGE" "$SRC" <<'PY'
import os, sys
stage, src = sys.argv[1], sys.argv[2]
home = os.path.expanduser("~")
subs = [(src, "__PI_AGENT_DIR__"), (home + "/.pi/agent", "__PI_AGENT_DIR__")]
changed = 0
for base, _dirs, files in os.walk(stage):
    for name in files:
        if not name.endswith((".md", ".py", ".json", ".sh", ".ts", ".mjs", ".tmpl")):
            continue
        p = os.path.join(base, name)
        try:
            s = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        orig = s
        for needle, token in subs:
            s = s.replace(needle, token)
        if s != orig:
            open(p, "w", encoding="utf-8").write(s)
            changed += 1
print(f"  ok {changed} files templatized")
PY

log "Scanning for leaks and stray paths"
LEAK=0

# The real SoCLaaS key, if this shell has it.
if [[ -n "${SOCLAAS_API_KEY:-}" ]]; then
  if grep -rlF -- "$SOCLAAS_API_KEY" "$STAGE" >/dev/null 2>&1; then
    printf '  found the live SOCLAAS_API_KEY in the payload\n' >&2
    LEAK=1
  fi
fi

# Common credential shapes.
if grep -rlnE '(sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY)' "$STAGE" 2>/dev/null | grep -v 'statechart.test.mjs' | grep -q .; then
  printf '  found something shaped like a credential:\n' >&2
  grep -rlnE '(sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{30,}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY)' "$STAGE" 2>/dev/null | sed 's/^/    /' >&2
  LEAK=1
fi

# Absolute home paths that the placeholders should have absorbed.
STRAY=$(grep -rn "$HOME" "$STAGE" 2>/dev/null | grep -v '__PI_AGENT_DIR__' | head -10 || true)
if [[ -n "$STRAY" ]]; then
  printf '  absolute paths survived templatizing:\n%s\n' "$(sed 's/^/    /' <<<"$STRAY")" >&2
  LEAK=1
fi

[[ $LEAK -eq 0 ]] || die "refusing to write: fix the findings above, then re-run"

if [[ $DRY -eq 1 ]]; then
  log "dry run complete; would have written agent/ with:"
  find "$STAGE" -type f | wc -l | sed 's/^/    /'
  exit 0
fi

log "Writing agent/"
rm -rf "$REPO_DIR/agent"
mkdir -p "$REPO_DIR/agent"
cp -a "$STAGE/." "$REPO_DIR/agent/"

log "Done"
printf '  files      %s\n' "$(find "$REPO_DIR/agent" -type f | wc -l | tr -d ' ')"
printf '  skills     %s\n' "$(find "$REPO_DIR/agent/skills" -name SKILL.md | wc -l | tr -d ' ')"
printf '  agents     %s\n' "$(find "$REPO_DIR/agent/agents" -name '*.md' ! -name CONVENTIONS.md | wc -l | tr -d ' ')"
printf '  extensions %s\n' "$(find "$REPO_DIR/agent/extensions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
printf '  size       %s\n' "$(du -sh "$REPO_DIR/agent" | cut -f1)"
printf '\nReview the diff, then commit.\n'
