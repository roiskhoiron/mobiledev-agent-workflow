#!/usr/bin/env bash
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
G="$REPO/hooks/guard.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
M="$T/main"; L="$T/linked"
git init -q "$M"; git -C "$M" -c user.name=t -c user.email=t@t commit -q --allow-empty -m i
# main checkout without linked worktree: editable
assert_eq 0 "$(printf '%s' "$(jq -cn --arg p "$M/a.txt" --arg c "$M" '{tool_name:"Edit",tool_input:{file_path:$p},cwd:$c}')" | "$G" 2>/dev/null >/dev/null; echo $?)" "[0] main without linked worktree"
git -C "$M" worktree add -q -b feat/x "$L"
mkdir -p "$T/plain" "$T/st"
cat > "$T/st/jira-transitions.json" <<'J'
{"PROJ":{"allow":["21","31"],"names":{"21":"In Progress","31":"Ready To Review"}},"AB2":{"allow":["21"]}}
J
export AGENT_WORKFLOW_STATE="$T/st"

run() { printf '%s' "$1" | "$G" 2>"$T/err" >/dev/null; echo $?; }
file_check() { # expected tool path
  local j; j=$(jq -cn --arg t "$2" --arg p "$3" --arg c "$M" '{tool_name:$t,tool_input:{file_path:$p},cwd:$c}')
  assert_eq "$1" "$(run "$j")" "[$1] $2 $3"
}
jira() { # expected key transition-json
  local j; j=$(jq -cn --arg k "$2" --argjson t "$3" '{tool_name:"mcp__claude_ai_Atlassian__transitionJiraIssue",tool_input:{cloudId:"c",issueIdOrKey:$k,transition:$t},cwd:"/"}')
  assert_eq "$1" "$(run "$j")" "[$1] jira $2 $3"
}

for t in Edit Write MultiEdit; do
  file_check 2 $t "$M/a.txt"
  file_check 2 $t "$M/new/dir/a.txt"
  file_check 0 $t "$L/a.txt"
  file_check 0 $t "$L/new/dir/a.txt"
  file_check 0 $t "$T/plain/a.txt"
done
file_check 2 Edit "$T/main/../main/a.txt"
ln -s "$M" "$T/sym"; file_check 2 Edit "$T/sym/a.txt"
assert_eq 0 "$(run "$(jq -cn --arg c "sed -i s/a/b/ $M/a.txt" --arg d "$M" '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}')")" "[0] bash sed -i not checked"

jira 0 PROJ-5 '{"id":"21"}'
jira 0 PROJ-5 '{"id":21}'
jira 0 AB2-15 '{"id":"21"}'
jira 2 PROJ-5 '{"id":"41"}'; grep -q "Done hanya dipindah kolega" "$T/err"; assert_eq 0 $? "msg Done"
jira 2 AB2-15 '{"id":"31"}'
jira 2 NOPE-1 '{"id":"21"}'; grep -q "jalankan setup transisi" "$T/err"; assert_eq 0 $? "msg setup"
jira 2 PROJ-5 '{}'
echo 'bukan json' > "$T/st/jira-transitions.json"
jira 2 PROJ-5 '{"id":"21"}'; grep -q "jalankan setup transisi" "$T/err"; assert_eq 0 $? "invalid config msg"
rm "$T/st/jira-transitions.json"
jira 2 PROJ-5 '{"id":"21"}'
# GitHub Projects / GitLab board: never close issues, status only from ticket-status.json
bash_check() { # expected command
  assert_eq "$1" "$(run "$(jq -cn --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:"/"}')")" "[$1] bash $2"
}
bash_check 2 'gh issue close 12'
bash_check 2 'glab issue close 12'
bash_check 2 'cd /x && gh issue delete 12 --yes'
bash_check 0 'gh issue comment 12 --body hi'
bash_check 0 'gh issue view 12 --comments'
bash_check 2 'gh project item-edit --project-id PVT_1 --id I --field-id F --single-select-option-id o2'
cat > "$T/st/ticket-status.json" <<'J'
{"github":{"PVT_1":{"allow":["o1","o2"]}},"gitlab":{"g/r":{"allow":["status::todo","status::review"]}}}
J
bash_check 0 'gh project item-edit --project-id PVT_1 --id I --field-id F --single-select-option-id o2'
bash_check 0 'gh project item-edit --project-id=PVT_1 --id I --field-id F --single-select-option-id=o1'
bash_check 2 'gh project item-edit --project-id PVT_1 --id I --field-id F --single-select-option-id o9'; grep -q "Done hanya dipindah kolega" "$T/err"; assert_eq 0 $? "msg gh Done"
bash_check 2 'gh project item-edit --project-id PVT_2 --id I --field-id F --single-select-option-id o1'
bash_check 0 'gh project item-edit --project-id PVT_1 --id I --field-id F --text hi'
bash_check 2 'gh project item-edit --project-id PVT_1 --id I --field-id F --clear'
bash_check 2 'gh project item-archive 3 --owner o --id I'
bash_check 0 'glab issue update 12 --unlabel status::todo --label status::review'
bash_check 0 'glab issue update 12 -l status::todo,status::review'
bash_check 2 'glab issue update 12 --label status::done'
bash_check 0 'glab issue update 12 --title x'
# other coding agents: Gemini CLI / Cursor / Codex tool names go through the same checks
agent_check() { # expected tool tool_input-json
  assert_eq "$1" "$(run "$(jq -cn --arg t "$2" --argjson i "$3" --arg c "$M" '{tool_name:$t,tool_input:$i,cwd:$c}')")" "[$1] $2 $3"
}
agent_check 2 run_shell_command '{"command":"gh issue close 3"}'
agent_check 2 Shell '{"command":"gh issue close 3","working_directory":"/"}'
agent_check 2 Bash '{"command":"glab issue close 3"}'
agent_check 0 run_shell_command '{"command":"gh issue view 3"}'
agent_check 2 write_file "{\"file_path\":\"$M/a.txt\",\"content\":\"x\"}"
agent_check 2 replace "{\"file_path\":\"$M/a.txt\"}"
agent_check 0 write_file "{\"file_path\":\"$L/a.txt\"}"
agent_check 2 Write "{\"path\":\"$M/a.txt\"}"
agent_check 2 Delete "{\"file_path\":\"$M/a.txt\"}"
agent_check 2 apply_patch "$(jq -cn --arg p "*** Begin Patch
*** Update File: $L/ok.txt
@@
-a
+b
*** Add File: $M/new.txt
+x
*** End Patch" '{command:$p}')"
agent_check 0 apply_patch "$(jq -cn --arg p "*** Begin Patch
*** Update File: $L/ok.txt
*** Move to: $L/ok2.txt
*** End Patch" '{command:$p}')"
agent_check 2 apply_patch "$(jq -cn --arg p "*** Begin Patch
*** Update File: $L/ok.txt
*** Move to: $M/moved.txt
*** End Patch" '{command:$p}')"
agent_check 0 read_file "{\"file_path\":\"$M/a.txt\"}"
exit $((FAILS>0))
