#!/usr/bin/env bash
# Install this pi agent environment onto the current machine.
#
# Idempotent: every step is safe to re-run. Anything it overwrites is backed up
# first, under ~/.pi/agent-backups/<timestamp>/.
#
# Usage: ./install.sh [options]

set -euo pipefail

AGENT_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$REPO_DIR/agent"

ASSUME_YES=0
MERGE=0
PERSIST_KEY=0
KEEP_POTETO_EXPLICIT=0
PLAYWRIGHT_MODE="auto"   # auto | install | skip
CHROME_PATH=""
KEY_FILE=""
SKIP_PACKAGES=0
SKIP_MCP=0

usage() {
  cat <<'EOF'
Install this pi agent environment onto the current machine.

Usage: ./install.sh [options]

  -y, --yes              Never prompt. Take defaults, skip anything that needs
                         a browser download, and fail if the API key is missing.
      --merge            Merge skills/ and agents/ into what is already there
                         instead of replacing the trees.
      --persist-key      Append `export SOCLAAS_API_KEY=...` to your shell rc
                         when the key is not already exported there.
      --poteto-explicit  Keep `disable-model-invocation: true` on the poteto-mode
                         skill. Default strips it so the skill is model-invocable.
      --key-file PATH    Read the SoCLaaS API key from PATH instead of prompting.
      --playwright MODE  auto (default) | install | skip. `install` downloads the
                         Chromium build if it is missing. `skip` never touches it
                         and leaves the playwright MCP server out.
      --chrome PATH      Use this Chromium binary for the playwright MCP server.
      --agent-dir PATH   Install into PATH instead of $PI_CODING_AGENT_DIR or
                         ~/.pi/agent.
      --no-packages      Do not run `pi install` for the four package sources.
      --no-mcp           Do not write mcp.json.
  -h, --help             Show this help.

Environment:
  SOCLAAS_API_KEY        SoCLaaS key. If set and exported from your shell rc, no
                         prompt appears and nothing is written to disk.
  PI_CODING_AGENT_DIR    Agent directory override. Same as --agent-dir.
EOF
}

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes)            ASSUME_YES=1; shift ;;
    --merge)             MERGE=1; shift ;;
    --persist-key)       PERSIST_KEY=1; shift ;;
    --poteto-explicit)   KEEP_POTETO_EXPLICIT=1; shift ;;
    --key-file)          KEY_FILE="${2:?--key-file needs a path}"; shift 2 ;;
    --playwright)        PLAYWRIGHT_MODE="${2:?--playwright needs a mode}"; shift 2 ;;
    --chrome)            CHROME_PATH="${2:?--chrome needs a path}"; shift 2 ;;
    --agent-dir)         AGENT_DIR="${2:?--agent-dir needs a path}"; shift 2 ;;
    --no-packages)       SKIP_PACKAGES=1; shift ;;
    --no-mcp)            SKIP_MCP=1; shift ;;
    -h|--help)           usage; exit 0 ;;
    *) die "unknown option: $1 (try --help)" ;;
  esac
done

[[ -d "$PAYLOAD" ]] || die "payload directory missing: $PAYLOAD"
AGENT_DIR="${AGENT_DIR/#\~/$HOME}"

# ---------------------------------------------------------------- prerequisites

log "Checking prerequisites"

if ! command -v pi >/dev/null 2>&1; then
  warn "pi is not on PATH"
  if [[ $ASSUME_YES -eq 1 ]]; then
    command -v npm >/dev/null 2>&1 || die "neither pi nor npm is available"
    log "Installing pi via npm"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
  else
    read -r -p "Install pi now with npm? [Y/n] " reply
    [[ "${reply:-Y}" =~ ^[Yy] ]] || die "pi is required"
    command -v npm >/dev/null 2>&1 || die "npm is not available"
    npm install -g --ignore-scripts @earendil-works/pi-coding-agent
  fi
fi
ok "pi $(pi --version 2>/dev/null || echo '(version unknown)')"

PI_MAJOR_MINOR="$(pi --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+' || true)"
if [[ -n "$PI_MAJOR_MINOR" ]]; then
  IFS=. read -r pj pm <<<"$PI_MAJOR_MINOR"
  if (( pj < 1 )) || { (( pj == 1 )) && (( pm < 5 )); }; then
    warn "this environment was exported from pi 1.5; older versions may miss settings or frontmatter fields"
  fi
fi

command -v node >/dev/null 2>&1 && ok "node $(node --version)" || warn "node not found; pi needs Node 22.19+"
command -v git  >/dev/null 2>&1 || die "git is required (pi clones git: packages)"
command -v bun  >/dev/null 2>&1 && ok "bun $(bun --version)" \
  || warn "bun not found; the poteto-mode watch-pr/orch scripts and statechart helpers need it (curl -fsSL https://bun.sh/install | bash)"

# ---------------------------------------------------------------- api key

log "Resolving SOCLAAS_API_KEY"

key_is_exported_in_rc() {
  local rc="$1"
  [[ -f "$rc" ]] || return 1
  grep -qE '^[[:space:]]*export[[:space:]]+SOCLAAS_API_KEY=' "$rc"
}

API_KEY="${SOCLAAS_API_KEY:-}"
KEY_SOURCE="already in this shell"

if [[ -z "$API_KEY" && -n "$KEY_FILE" ]]; then
  [[ -r "$KEY_FILE" ]] || die "cannot read --key-file: $KEY_FILE"
  API_KEY="$(tr -d '[:space:]' <"$KEY_FILE")"
  KEY_SOURCE="read from $KEY_FILE"
fi

if [[ -z "$API_KEY" && -n "${PI_SETUP_API_KEY:-}" ]]; then
  API_KEY="$PI_SETUP_API_KEY"
  KEY_SOURCE="read from PI_SETUP_API_KEY"
fi

if [[ -z "$API_KEY" ]]; then
  if [[ $ASSUME_YES -eq 1 ]]; then
    die "SOCLAAS_API_KEY is not set and --yes forbids prompting. Export it, pass --key-file, or drop --yes."
  fi
  warn "the SoCLaaS key is not in your environment"
  printf '  Paste it (input hidden, nothing echoes): '
  IFS= read -rs API_KEY || true
  printf '\n'
  [[ -n "$API_KEY" ]] || die "an API key is required for the soclaas provider"
  KEY_SOURCE="entered at the prompt"
fi

ok "key resolved ($KEY_SOURCE, ${#API_KEY} chars)"
export SOCLAAS_API_KEY="$API_KEY"

if [[ $PERSIST_KEY -eq 1 ]]; then
  RC=""
  case "${SHELL:-}" in
    */zsh)  RC="$HOME/.zshrc" ;;
    */bash) RC="$HOME/.bashrc" ;;
  esac
  [[ -n "$RC" ]] || RC="$HOME/.profile"
  if key_is_exported_in_rc "$RC"; then
    ok "$RC already exports SOCLAAS_API_KEY"
  else
    printf '\nexport SOCLAAS_API_KEY=%s\n' "$API_KEY" >>"$RC"
    ok "appended the export to $RC"
  fi
fi

# ---------------------------------------------------------------- chromium

detect_chrome() {
  local candidates=()
  [[ -n "$CHROME_PATH" ]] && candidates+=("$CHROME_PATH")
  local cache="$HOME/.cache/ms-playwright"
  if [[ -d "$cache" ]]; then
    # newest chromium-<rev>/chrome-linux*/chrome, then the headless shell
    while IFS= read -r p; do candidates+=("$p"); done < <(
      find "$cache" -maxdepth 3 -type f \( -name chrome -o -name 'headless_shell' \) 2>/dev/null | sort -r
    )
  fi
  candidates+=(
    "/usr/bin/google-chrome"
    "/usr/bin/google-chrome-stable"
    "/usr/bin/chromium"
    "/usr/bin/chromium-browser"
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  )
  local c
  for c in "${candidates[@]}"; do
    [[ -n "$c" && -x "$c" ]] && { printf '%s\n' "$c"; return 0; }
  done
  return 1
}

CHROME_BIN=""
if [[ $SKIP_MCP -eq 0 && "$PLAYWRIGHT_MODE" != "skip" ]]; then
  log "Locating a Chromium for the playwright MCP server"
  if CHROME_BIN="$(detect_chrome)" && [[ -n "$CHROME_BIN" ]]; then
    ok "using $CHROME_BIN"
  elif [[ "$PLAYWRIGHT_MODE" == "install" ]]; then
    command -v npx >/dev/null 2>&1 || die "--playwright install needs npx"
    log "Downloading Chromium via playwright"
    npx -y playwright@1.56.0 install chromium
    CHROME_BIN="$(detect_chrome || true)"
    [[ -n "$CHROME_BIN" ]] && ok "using $CHROME_BIN" || die "Chromium still not found after install; re-run with --chrome PATH"
  else
    warn "no Chromium found; the playwright MCP server will be left out of mcp.json"
    warn "add it later with: $0 --playwright install   (or --chrome PATH)"
  fi
fi

# ---------------------------------------------------------------- backup

STAMP="$(date +%Y%m%d-%H%M%S)-$$"
BACKUP="$(dirname -- "$AGENT_DIR")/agent-backups/$STAMP"
if [[ -d "$AGENT_DIR" ]] && [[ -n "$(ls -A "$AGENT_DIR" 2>/dev/null || true)" ]]; then
  log "Backing up the current agent directory"
  mkdir -p "$BACKUP"
  for item in settings.json models.json mcp.json APPEND_SYSTEM.md pstack-models.md skills agents extensions auth.json; do
    [[ -e "$AGENT_DIR/$item" ]] && cp -a "$AGENT_DIR/$item" "$BACKUP/" || true
  done
  ok "$BACKUP"
fi

# ---------------------------------------------------------------- payload

log "Installing payload into $AGENT_DIR"
mkdir -p "$AGENT_DIR"

install_file() {
  local name="$1"
  cp "$PAYLOAD/$name" "$AGENT_DIR/$name"
  ok "$name"
}

install_file settings.json
install_file models.json
install_file APPEND_SYSTEM.md
install_file pstack-models.md

if [[ $MERGE -eq 1 ]]; then
  log "Merging skills, agents, and extensions (existing files not in this repo are kept)"
  mkdir -p "$AGENT_DIR/skills" "$AGENT_DIR/agents" "$AGENT_DIR/extensions"
  cp -a "$PAYLOAD/skills/." "$AGENT_DIR/skills/"
  cp -a "$PAYLOAD/agents/." "$AGENT_DIR/agents/"
  [[ -d "$PAYLOAD/extensions" ]] && cp -a "$PAYLOAD/extensions/." "$AGENT_DIR/extensions/"
else
  rm -rf "$AGENT_DIR/skills" "$AGENT_DIR/agents"
  cp -a "$PAYLOAD/skills" "$AGENT_DIR/skills"
  cp -a "$PAYLOAD/agents"  "$AGENT_DIR/agents"
  if [[ -d "$PAYLOAD/extensions" ]]; then
    rm -rf "$AGENT_DIR/extensions"
    cp -a "$PAYLOAD/extensions" "$AGENT_DIR/extensions"
  fi
fi
ok "skills/ ($(find "$AGENT_DIR/skills" -name SKILL.md | wc -l | tr -d ' ') skills)"
ok "agents/ ($(find "$AGENT_DIR/agents" -name '*.md' ! -name CONVENTIONS.md | wc -l | tr -d ' ') agent definitions)"
if [[ -d "$AGENT_DIR/extensions" ]]; then
  ok "extensions/ ($(find "$AGENT_DIR/extensions" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ') extension packages)"
fi
ok "$(grep -rl '^advertise: true' "$AGENT_DIR/agents" 2>/dev/null | wc -l | tr -d ' ') advertised in the parent catalog"

# poteto-mode frontmatter. The skill ships command-only on purpose; the agents
# are what make it agentic, so either way it stays launchable as a delegate.
POTETO_SKILL="$AGENT_DIR/skills/pstack/poteto-mode/SKILL.md"
if [[ -f "$POTETO_SKILL" ]]; then
  if [[ $KEEP_POTETO_EXPLICIT -eq 1 ]]; then
    ok "poteto-mode skill left command-only (/skill:poteto-mode)"
  else
    python3 - "$POTETO_SKILL" <<'PY'
import sys
p = sys.argv[1]
lines = open(p, encoding="utf-8").read().split("\n")
if lines and lines[0].strip() == "---":
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            break
        if lines[i].startswith("disable-model-invocation:"):
            del lines[i]
            break
open(p, "w", encoding="utf-8").write("\n".join(lines))
PY
    ok "poteto-mode skill made model-invocable (--poteto-explicit reverts)"
  fi
fi

# ---------------------------------------------------------------- mcp

if [[ $SKIP_MCP -eq 0 && -n "$CHROME_BIN" ]]; then
  log "Writing mcp.json"
  python3 - "$REPO_DIR/agent/mcp.json.tmpl" "$AGENT_DIR/mcp.json" "$CHROME_BIN" <<'PY'
import json, sys
tmpl, out, chrome = sys.argv[1:4]
cfg = json.loads(open(tmpl, encoding="utf-8").read().replace("__PLAYWRIGHT_CHROME__", chrome))
open(out, "w", encoding="utf-8").write(json.dumps(cfg, indent=2) + "\n")
PY
  ok "mcp.json (playwright -> $CHROME_BIN)"
else
  [[ -f "$AGENT_DIR/mcp.json" ]] && { warn "mcp.json left untouched"; } || true
fi

# ---------------------------------------------------------------- templating

log "Rendering agent-directory paths"
python3 - "$AGENT_DIR" <<'PY'
import os, sys
root = sys.argv[1]
token = "__PI_AGENT_DIR__"
skip = {"sessions", "npm", "git", "missions", "node_modules", ".git"}
changed = 0
for base, dirs, files in os.walk(root):
    dirs[:] = [d for d in dirs if d not in skip]
    if any(f"{os.sep}{s}{os.sep}" in base + os.sep for s in skip):
        continue
    for name in files:
        if not name.endswith((".md", ".py", ".json", ".sh", ".ts", ".mjs")):
            continue
        p = os.path.join(base, name)
        try:
            s = open(p, encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        if token not in s:
            continue
        open(p, "w", encoding="utf-8").write(s.replace(token, root))
        changed += 1
print(f"  ok rendered paths in {changed} files -> {root}")
PY

LEFTOVER="$(grep -rl --exclude-dir=sessions --exclude-dir=npm --exclude-dir=git \
  --exclude-dir=missions --exclude-dir=node_modules \
  '__PI_AGENT_DIR__\|__PLAYWRIGHT_CHROME__' "$AGENT_DIR" 2>/dev/null | head -5 || true)"
[[ -z "$LEFTOVER" ]] || die "placeholders survived rendering in: $(tr '\n' ' ' <<<"$LEFTOVER")"
ok "no placeholders left"

# ---------------------------------------------------------------- packages

if [[ $SKIP_PACKAGES -eq 0 ]]; then
  log "Installing pi packages"
  while IFS= read -r src; do
    [[ -n "$src" ]] || continue
    if pi install "$src" >/tmp/pi-setup-install.log 2>&1; then
      ok "$src"
    else
      warn "failed: $src"
      sed 's/^/      /' /tmp/pi-setup-install.log | tail -5 >&2
    fi
  done < <(python3 -c '
import json, os, sys
p = os.path.join(sys.argv[1], "settings.json")
for s in json.load(open(p)).get("packages", []):
    print(s if isinstance(s, str) else s.get("source", ""))
' "$AGENT_DIR")
fi

# ---------------------------------------------------------------- done

printf '\n\033[1;32mInstalled.\033[0m\n\n'
printf '  agent dir      %s\n' "$AGENT_DIR"
[[ -d "$BACKUP" ]] && printf '  backup         %s\n' "${BACKUP/#$HOME/~}"
printf '  default model  soclaas/x-test-2 (xhigh)\n\n'
printf 'Next:\n'
printf '  1. %s/verify.sh\n' "$REPO_DIR"
printf '  2. export SOCLAAS_API_KEY=...   # only if you did not use --persist-key\n'
printf '  3. pi\n\n'
printf 'Re-run this script after pulling; it backs up before overwriting.\n'
