#!/usr/bin/env bash
# install.sh --agent/--scope: tiap coding agent dapat skill, hook guard, dan instruksi; idempotent; project scope tidak ter-commit.
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
is_link() { [ -L "$1" ] && echo yes || echo no; }
guard_n() { jq --arg ev "$2" '[.hooks[$ev][]? | select(any(.hooks[]?; .command|test("guard.sh")))] | length' "$1"; }
I=(bash "$REPO/install.sh" --no-launchd)

# ---- global, semua agen ----
H="$T/home"; mkdir -p "$H/.gemini"
echo '{"theme":"x","hooks":{"BeforeTool":[{"matcher":"x","hooks":[{"type":"command","command":"other"}]}]}}' > "$H/.gemini/settings.json"
assert_exit 0 "global all run 1" -- "${I[@]}" --home "$H" --agent all --scope global
assert_exit 0 "global all run 2" -- "${I[@]}" --home "$H" --agent all --scope global
assert_eq "$REPO" "$(cd "$H/.agent-workflow/repo" && pwd -P)" "jangkar netral ~/.agent-workflow/repo"
assert_eq yes "$(is_link "$H/.claude/skills/validate-tiket")" "claude skill"
assert_eq yes "$(is_link "$H/.agents/skills/develop-tiket")" "codex skill di ~/.agents/skills"
assert_eq no "$(is_link "$H/.agents/skills/_agent-workflow-shared")" "codex: _shared tidak jadi skill"
assert_eq yes "$(is_link "$H/.gemini/skills/rilis-tiket")" "gemini skill"
assert_eq yes "$(is_link "$H/.cursor/skills/audit-issue")" "cursor skill"
assert_eq yes "$(is_link "$H/.config/opencode/skills/branch-manager")" "opencode skill"
assert_eq 1 "$(guard_n "$H/.codex/hooks.json" PreToolUse)" "codex hook sekali"
assert_eq 'Bash|apply_patch' "$(jq -r '.hooks.PreToolUse[0].matcher' "$H/.codex/hooks.json")" "codex matcher"
assert_eq 1 "$(guard_n "$H/.gemini/settings.json" BeforeTool)" "gemini hook sekali"
assert_eq x "$(jq -r .theme "$H/.gemini/settings.json")" "gemini setting lain tetap"
assert_eq other "$(jq -r '.hooks.BeforeTool[0].hooks[0].command' "$H/.gemini/settings.json")" "gemini hook lain tetap"
assert_eq 1 "$(jq '[.hooks.preToolUse[]|select(.command|test("guard.sh"))]|length' "$H/.cursor/hooks.json")" "cursor hook sekali"
assert_eq 1 "$(jq .version "$H/.cursor/hooks.json")" "cursor version 1"
assert_eq yes "$(grep -q "\"$REPO/hooks/guard.sh\"" "$H/.config/opencode/plugins/agent-workflow-guard.js" && echo yes || echo no)" "opencode plugin menunjuk guard"
for f in .claude/CLAUDE.md .codex/AGENTS.md .gemini/GEMINI.md .config/opencode/AGENTS.md; do
  assert_eq 1 "$(grep -c '^# Agent workflow tiket' "$H/$f")" "instruksi sekali: $f"
done

# ---- project scope ----
P="$T/proj"; git init -q "$P"; echo "# Tim" > "$P/AGENTS.md"; git -C "$P" add AGENTS.md
H2="$T/home2"; mkdir -p "$H2"
assert_exit 0 "project run 1" -- "${I[@]}" --home "$H2" --agent claude,codex,cursor,opencode,gemini --scope project --project "$P"
assert_exit 0 "project run 2" -- "${I[@]}" --home "$H2" --agent claude,codex,cursor,opencode,gemini --scope project --project "$P"
assert_eq yes "$(is_link "$P/.claude/skills/develop-tiket")" "project claude skill"
assert_eq 1 "$(guard_n "$P/.claude/settings.local.json" PreToolUse)" "project claude hook di settings.local.json"
assert_eq no "$([ -e "$P/.claude/settings.json" ] && echo yes || echo no)" "project: settings.json tim tidak disentuh"
assert_eq yes "$(is_link "$P/.agents/skills/develop-tiket")" "project codex skill"
assert_eq 1 "$(guard_n "$P/.codex/hooks.json" PreToolUse)" "project codex hook"
assert_eq 1 "$(grep -c '^# Agent workflow tiket' "$P/AGENTS.md")" "AGENTS.md: blok sekali walau codex+opencode"
assert_eq 1 "$(grep -c '^alwaysApply: true' "$P/.cursor/rules/agent-workflow.mdc")" "cursor rule alwaysApply"
assert_eq yes "$([ -f "$P/.opencode/plugins/agent-workflow-guard.js" ] && echo yes || echo no)" "project opencode plugin"
assert_eq yes "$(is_link "$H2/.agent-workflow/repo")" "project scope tetap membuat jangkar"
assert_eq no "$([ -e "$H2/.claude" ] && echo yes || echo no)" "project scope tidak menyentuh ~/.claude"
untracked=$(git -C "$P" status --porcelain --untracked-files=all | grep -v ' AGENTS.md$\| GEMINI.md$' || true)
assert_eq "" "$untracked" "project: file buatan installer di-exclude (kecuali AGENTS.md/GEMINI.md)"

# ---- argumen salah ----
assert_exit 2 "agen tidak dikenal" -- "${I[@]}" --home "$T/h3" --agent vim
assert_exit 2 "scope salah" -- "${I[@]}" --home "$T/h3" --scope semua
assert_exit 2 "project = repo workflow" -- "${I[@]}" --home "$T/h3" --scope project --project "$REPO"

# ---- opencode plugin memanggil guard (butuh node) ----
if command -v node >/dev/null; then
  M="$T/main"; L="$T/linked"
  git init -q "$M"; git -C "$M" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i; git -C "$M" worktree add -q -b x "$L"
  cp "$H/.config/opencode/plugins/agent-workflow-guard.js" "$T/p.mjs"
  r=$(cd "$T" && node --input-type=module -e "
    const { AgentWorkflowGuard } = await import('./p.mjs');
    const h = (await AgentWorkflowGuard({ directory: '$M' }))['tool.execute.before'];
    const out = [];
    for (const [tool, args] of [['bash',{command:'git push upstream x'}],['edit',{filePath:'$M/a.txt'}],['edit',{filePath:'$L/a.txt'}],['read',{filePath:'$M/a.txt'}]]) {
      try { await h({ tool }, { args }); out.push('allow'); } catch { out.push('block'); }
    }
    console.log(out.join(','));" 2>/dev/null)
  assert_eq "block,block,allow,allow" "$r" "opencode plugin: push upstream & edit worktree utama diblokir"
fi
exit $FAILS
