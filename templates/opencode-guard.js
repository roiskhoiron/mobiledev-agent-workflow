// agent-workflow guard bridge for OpenCode (installed by install.sh; __GUARD__ is replaced with the guard path).
// Maps OpenCode tool calls to the Claude-style hook JSON that hooks/guard.sh reads; guard exit 2 = block.
import { spawnSync } from "node:child_process";

const GUARD = __GUARD__;
const NAMES = { bash: "Bash", edit: "Edit", write: "Write", patch: "apply_patch" };

export const AgentWorkflowGuard = async ({ directory }) => ({
  "tool.execute.before": async (input, output) => {
    const name = NAMES[input.tool];
    if (!name) return;
    const a = output.args ?? {};
    const tool_input =
      name === "Bash" ? { command: a.command ?? "" }
      : name === "apply_patch" ? { command: a.patchText ?? a.patch ?? "" }
      : { file_path: a.filePath ?? a.file_path ?? "" };
    const r = spawnSync(GUARD, [], {
      input: JSON.stringify({ tool_name: name, tool_input, cwd: a.workdir ?? directory ?? process.cwd() }),
      encoding: "utf8",
    });
    if (r.status === 2) throw new Error((r.stderr || "DIBLOKIR oleh guard").trim());
  },
});
