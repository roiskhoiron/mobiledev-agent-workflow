#!/usr/bin/env bash
# Pasang agent workflow untuk satu atau beberapa coding agent. Idempotent.
#
# Usage: install.sh [--agent LIST] [--scope global|project] [--project DIR] [--home DIR] [--no-launchd]
#   --agent    claude,codex,gemini,cursor,opencode (pisah koma) atau all. Default: claude.
#   --scope    global  = untuk semua project di komputer ini (default)
#              project = hanya untuk satu project (--project DIR, default folder saat ini)
#   --home     pasang ke HOME lain (tes); launchd tidak di-load.
#   --no-launchd  lewati job housekeeping macOS.
# Tanpa --agent/--scope dan dijalankan di terminal → menu interaktif.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd -P)"
ALL_AGENTS="claude codex gemini cursor opencode"
DEST="$HOME"; CUSTOM=0; AGENTS=''; SCOPE=''; PROJ=''; LAUNCHD=1

die() { echo "install.sh: $*" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case $1 in
    --home) DEST="${2:?--home butuh folder}"; CUSTOM=1; shift 2;;
    --agent|--agents) AGENTS="${2:?--agent butuh nilai}"; shift 2;;
    --scope) SCOPE="${2:?--scope butuh nilai}"; shift 2;;
    --project) PROJ="${2:?--project butuh folder}"; shift 2;;
    --no-launchd) LAUNCHD=0; shift;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) die "argumen tidak dikenal: $1 (lihat --help)";;
  esac
done

# ---------- pilihan interaktif ----------
if [ -z "$AGENTS$SCOPE" ] && [ -t 0 ] && [ -t 1 ]; then
  echo "Coding agent yang dipasangi workflow (pisah spasi/koma, Enter = claude):"
  echo "  1) claude    Claude Code"
  echo "  2) codex     OpenAI Codex CLI"
  echo "  3) gemini    Gemini CLI"
  echo "  4) cursor    Cursor"
  echo "  5) opencode  OpenCode"
  echo "  6) all       semua di atas"
  printf '> '; read -r ans || ans=''
  AGENTS=''
  for a in $(echo "${ans:-1}" | tr ',' ' '); do
    case $a in 1) a=claude;; 2) a=codex;; 3) a=gemini;; 4) a=cursor;; 5) a=opencode;; 6) a=all;; esac
    AGENTS="$AGENTS,$a"
  done
  echo "Scope:"
  echo "  1) global   semua project di komputer ini"
  echo "  2) project  hanya satu project"
  printf '> '; read -r ans || ans=''
  case ${ans:-1} in 2|project) SCOPE=project;; *) SCOPE=global;; esac
  if [ "$SCOPE" = project ] && [ -z "$PROJ" ]; then
    printf 'Folder project [%s]: ' "$PWD"; read -r ans || ans=''
    PROJ="${ans:-$PWD}"
  fi
fi
[ -n "$AGENTS" ] || AGENTS=claude
[ -n "$SCOPE" ] || SCOPE=global
case $SCOPE in global|project) ;; *) die "--scope harus global atau project";; esac
AGENTS=$(echo "$AGENTS" | tr ',' ' ' | tr 'A-Z' 'a-z')
case " $AGENTS " in *' all '*) AGENTS=$ALL_AGENTS;; esac
for a in $AGENTS; do case " $ALL_AGENTS " in *" $a "*) ;; *) die "agen tidak dikenal: $a (pilihan: $ALL_AGENTS, all)";; esac; done
if [ "$SCOPE" = project ]; then
  PROJ="$(cd "${PROJ:-$PWD}" 2>/dev/null && pwd -P)" || die "folder project tidak ada"
  [ "$PROJ" != "$REPO" ] || die "--project tidak boleh repo workflow ini sendiri"
fi
command -v jq >/dev/null || die "jq tidak ditemukan (brew install jq)"

GUARD="$REPO/hooks/guard.sh"
GUARD_CMD="\"$GUARD\""
NOTES=''
note() { NOTES="$NOTES
- $*"; }

# ---------- helper ----------
# jangkar netral: semua skill/agen merujuk ~/.agent-workflow/repo (lihat rules.md → Lokasi)
mkdir -p "$DEST/.agent-workflow"
ln -sfn "$REPO" "$DEST/.agent-workflow/repo"

# project scope: file buatan installer (symlink/path lokal) jangan sampai ter-commit
exclude() { # relpath
  [ "$SCOPE" = project ] || return 0
  local ex
  ex=$(git -C "$PROJ" rev-parse --git-path info/exclude 2>/dev/null) || return 0
  case $ex in /*) ;; *) ex="$PROJ/$ex";; esac
  mkdir -p "$(dirname "$ex")"
  grep -qxF "/$1" "$ex" 2>/dev/null || echo "/$1" >> "$ex"
}

link_skills() { # dir relpath-for-exclude [shared]
  local dir=$1 rel=$2 d n
  mkdir -p "$dir"
  for d in "$REPO"/skills/*/; do
    n=$(basename "$d")
    if [ "$n" = _shared ]; then [ "${3:-}" = shared ] || continue; n=_agent-workflow-shared; fi
    ln -sfn "${d%/}" "$dir/$n"
    exclude "$rel/$n"
  done
}

json_init() { # file → ada + backup isi asli pertama (project: file baru & backup di-exclude dari git)
  mkdir -p "$(dirname "$1")"
  [ -f "$1" ] || { echo '{}' > "$1"; exclude "${1#"$PROJ"/}"; }
  [ -e "$1.bak-agent-workflow" ] || cp "$1" "$1.bak-agent-workflow"
  exclude "${1#"$PROJ"/}.bak-agent-workflow"
  if [ "$SCOPE" = project ] && git -C "$PROJ" ls-files --error-unmatch "$1" >/dev/null 2>&1; then
    note "$1 ter-commit di repo project: hook guard ditambahkan, periksa sebelum commit."
  fi
}

json_apply() { # file jq-filter [jq args...]
  local f=$1 flt=$2 tmp; shift 2
  tmp=$(mktemp)
  jq "$@" "$flt" "$f" > "$tmp" || { rm -f "$tmp"; die "gagal memperbarui $f (JSON rusak?)"; }
  mv "$tmp" "$f"
}

# hook gaya Claude (Claude Code, Codex, Gemini CLI): .hooks[EVENT] = [{matcher, hooks:[{type,command}]}]
merge_hook() { # file event matcher
  json_init "$1"
  json_apply "$1" '
    def isg: (.command | tostring | test("/guard\\.sh\"?$"));
    def isguard: any((.hooks // [])[]?; isg);
    .hooks[$ev] = ((.hooks[$ev] // [])
      | if any(.[]; isguard) then map(if isguard then .matcher = $m | .hooks |= map(if isg then .command = $cmd else . end) else . end)
        else . + [{matcher:$m, hooks:[{type:"command",command:$cmd}]}] end)' \
    --arg ev "$2" --arg m "$3" --arg cmd "$GUARD_CMD"
}

append_instructions() { # file [frontmatter untuk file baru]
  local f=$1 T="$REPO/templates/agent-instructions.md"
  [ -f "$T" ] || return 0
  mkdir -p "$(dirname "$f")"
  grep -qsE '^# (Jira agent workflow|Agent workflow tiket)' "$f" && return 0
  if [ -n "${2:-}" ] && [ ! -s "$f" ]; then printf '%s\n' "$2" > "$f"; fi
  { [ -s "$f" ] && echo; cat "$T"; } >> "$f"
  if [ "$SCOPE" = project ] && git -C "$PROJ" ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    note "$f ter-commit di repo project: blok workflow ditambahkan di bawahnya, periksa sebelum commit."
  fi
}

# ---------- per agen ----------
install_claude() {
  local C S f
  if [ "$SCOPE" = global ]; then C="$DEST/.claude"; S="$C/settings.json"; else C="$PROJ/.claude"; S="$C/settings.local.json"; fi
  link_skills "$C/skills" .claude/skills shared
  mkdir -p "$C/agents"
  for f in "$REPO"/agents/*.md; do
    [ -e "$f" ] || continue
    ln -sfn "$f" "$C/agents/$(basename "$f")"; exclude ".claude/agents/$(basename "$f")"
  done
  merge_hook "$S" PreToolUse 'Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__claude_ai_Atlassian__.*'
  # drop adb uninstall/pm clear soft_deny: guard.sh now blocks them on device locks
  json_apply "$S" 'if .autoMode.soft_deny then .autoMode.soft_deny |= map(select(test("^Bash\\(adb:\\* (uninstall|shell pm clear) \\*\\)$") | not)) else . end'
  if [ "$SCOPE" = global ]; then append_instructions "$C/CLAUDE.md"
  else append_instructions "$PROJ/CLAUDE.local.md"; exclude CLAUDE.local.md; exclude .claude/settings.local.json; fi
}

install_codex() {
  local C K
  if [ "$SCOPE" = global ]; then
    if [ "$CUSTOM" = 1 ]; then C="$DEST/.codex"; else C="${CODEX_HOME:-$DEST/.codex}"; fi
    K="$DEST/.agents/skills"
  else C="$PROJ/.codex"; K="$PROJ/.agents/skills"; fi
  link_skills "$K" .agents/skills
  merge_hook "$C/hooks.json" PreToolUse 'Bash|apply_patch'
  exclude .codex/hooks.json
  if [ "$SCOPE" = global ]; then append_instructions "$C/AGENTS.md"; else append_instructions "$PROJ/AGENTS.md"; fi
  note "Codex: buka Codex lalu jalankan /hooks untuk me-review dan trust hook guard (hook baru dilewati sampai di-trust)."
}

install_gemini() {
  local G
  if [ "$SCOPE" = global ]; then G="$DEST/.gemini"; else G="$PROJ/.gemini"; fi
  link_skills "$G/skills" .gemini/skills
  merge_hook "$G/settings.json" BeforeTool 'run_shell_command|write_file|replace'
  if [ "$SCOPE" = global ]; then append_instructions "$G/GEMINI.md"; else append_instructions "$PROJ/GEMINI.md"; fi
}

install_cursor() {
  local U H
  if [ "$SCOPE" = global ]; then U="$DEST/.cursor"; else U="$PROJ/.cursor"; fi
  link_skills "$U/skills" .cursor/skills
  H="$U/hooks.json"
  json_init "$H"
  json_apply "$H" '
    def isguard: (.command | tostring | test("/guard\\.sh\"?$"));
    .version = (.version // 1)
    | .hooks.preToolUse = ((.hooks.preToolUse // [])
      | if any(.[]; isguard) then map(if isguard then .matcher = $m | .command = $cmd else . end)
        else . + [{command:$cmd, matcher:$m}] end)' \
    --arg m 'Shell|Write|Delete' --arg cmd "$GUARD_CMD"
  if [ "$SCOPE" = global ]; then
    note "Cursor: aturan global bukan file. Tempel isi templates/agent-instructions.md ke Cursor Settings → Rules → User Rules."
  else
    append_instructions "$PROJ/.cursor/rules/agent-workflow.mdc" $'---\ndescription: Agent workflow tiket (mobiledev-agent-workflow)\nalwaysApply: true\n---'
    exclude .cursor/rules/agent-workflow.mdc; exclude .cursor/hooks.json
  fi
}

install_opencode() {
  local O g
  if [ "$SCOPE" = global ]; then
    if [ "$CUSTOM" = 1 ]; then O="$DEST/.config/opencode"; else O="${XDG_CONFIG_HOME:-$DEST/.config}/opencode"; fi
  else O="$PROJ/.opencode"; fi
  link_skills "$O/skills" .opencode/skills
  mkdir -p "$O/plugins"
  g=$(jq -cn --arg g "$GUARD" '$g')
  GUARD_JSON="$g" python3 -c 'import os,sys; print(open(sys.argv[1]).read().replace("__GUARD__", os.environ["GUARD_JSON"]), end="")' \
    "$REPO/templates/opencode-guard.js" > "$O/plugins/agent-workflow-guard.js"
  exclude .opencode/plugins/agent-workflow-guard.js
  if [ "$SCOPE" = global ]; then append_instructions "$O/AGENTS.md"; else append_instructions "$PROJ/AGENTS.md"; fi
}

for a in $AGENTS; do "install_$a"; echo "ok: $a ($SCOPE)"; done

# ---------- housekeeping (per mesin, tidak tergantung agen) ----------
P="$REPO/launchd/com.agentworkflow.housekeeping.plist"
if [ "$LAUNCHD" = 1 ] && [ -f "$P" ]; then
  out="$DEST/Library/LaunchAgents/$(basename "$P")"
  mkdir -p "$(dirname "$out")" "$DEST/.agent-workflow/logs"
  sed -e "s|__AGENT_WORKFLOW_DIR__|$REPO|g" -e "s|__HOME__|$DEST|g" "$P" > "$out"
  if [ "$CUSTOM" = 0 ] && command -v launchctl >/dev/null; then
    launchctl bootout "gui/$(id -u)" "$out" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$out"
  fi
fi

if [ "$SCOPE" = project ]; then echo "installed into $PROJ (project) + jangkar $DEST/.agent-workflow/repo"
else echo "installed into $DEST"; fi
[ -z "$NOTES" ] || echo "Catatan:$NOTES"
