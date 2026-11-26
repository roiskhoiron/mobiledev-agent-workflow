# Pasang di komputer lain (macOS)

1. Prasyarat:
   ```bash
   brew install jq gh glab maestro firebase-cli cocoapods uv
   uv tool install schemathesis
   brew tap pact-foundation/pact-ruby-standalone && brew install pact-legacy
   ```
   Plus: Xcode (juga untuk XCUITest runner), Android SDK (`adb`, emulator, `android`), Orca, dan minimal satu coding agent (Claude Code, Codex CLI, Gemini CLI, Cursor, atau OpenCode). Untuk mode tim: `/config` → Teammate mode → `auto` (lihat [Tim agen](tim-agen.md)).
2. Plugin Claude Code: `superpowers` dan `ponytail` (lewat `/plugin`); `kotlin-agent-skills` opsional untuk project Kotlin/KMP. Skill pendukung lain ([daftar](alat.md#skill-pendukung)) ada di `~/.claude/skills`: `orca-cli`, `orca-computer-use`, `orchestration` (symlink ke `~/.agents/skills`, dari Orca), `android-cli` (`android init` memasang skill default), `graphify` (`uv tool install graphifyy && graphify install --platform claude`).
3. Konektor claude.ai (opsional): **Claude Docs** bila ada project yang menulis laporan ke Claude Docs (default: folder `docs/` di repo, tanpa konektor); **Atlassian** hanya bila ada project yang memakai Jira. GitHub Projects / GitLab Issue Board cukup `gh`/`glab` (GitHub Projects butuh scope `project`: `gh auth refresh -s project`).
4. Login CLI: `gh auth login`, `glab auth login`, `firebase login`.
5. Pasang dan cek:
   ```bash
   git clone https://github.com/roiskhoiron/agent-workflow ~/agent-workflow
   bash ~/agent-workflow/install.sh && bash ~/agent-workflow/tests/run.sh   # harus "ALL PASS"
   ```
   Tanpa argumen di terminal, installer bertanya: **coding agent** mana dan **scope** apa (lihat bagian berikut). Ia membuat jangkar `~/.agent-workflow/repo` (symlink ke repo ini, dirujuk semua skill/agen), symlink skill, hook guard (file JSON yang diubah di-backup sekali ke `*.bak-agent-workflow`), instruksi agen (sekali saja), dan job launchd housekeeping. Karena symlink, perubahan di repo langsung berlaku tanpa pasang ulang; pasang ulang hanya bila ada skill/agen/hook baru.

## Pilih coding agent dan scope

```bash
bash install.sh                                          # menu interaktif
bash install.sh --agent claude                           # sama seperti dulu: Claude Code, global
bash install.sh --agent codex,gemini --scope global
bash install.sh --agent all --scope project --project ~/work/app-android
bash install.sh --help
```

| Agen | Skill | Hook guard | Instruksi | Catatan |
| --- | --- | --- | --- | --- |
| Claude Code | `~/.claude/skills` + `agents/` | `settings.json` → PreToolUse | `~/.claude/CLAUDE.md` | fitur penuh, termasuk `--tim` (teammate) |
| Codex CLI | `~/.agents/skills` | `~/.codex/hooks.json` → PreToolUse (`Bash`, `apply_patch`) | `~/.codex/AGENTS.md` | jalankan `/hooks` sekali untuk **trust** hook |
| Gemini CLI | `~/.gemini/skills` | `~/.gemini/settings.json` → BeforeTool | `~/.gemini/GEMINI.md` | |
| Cursor | `~/.cursor/skills` | `~/.cursor/hooks.json` → preToolUse | global: tempel ke Settings → Rules | |
| OpenCode | `~/.config/opencode/skills` | plugin `plugins/agent-workflow-guard.js` | `~/.config/opencode/AGENTS.md` | plugin meneruskan tool call ke `guard.sh` |

**Scope project** memakai folder yang sama di dalam project (`.claude/`, `.agents/skills` + `.codex/`, `.gemini/`, `.cursor/`, `.opencode/`). Claude Code memakai `settings.local.json` dan `CLAUDE.local.md` supaya setting tim tidak berubah. Semua file buatan installer (symlink berisi path lokal) dicatat di `.git/info/exclude`, jadi tidak ikut ter-commit. Pengecualian: `AGENTS.md` / `GEMINI.md` yang sudah ada di repo; installer menambah blok di bawahnya dan mengingatkanmu untuk memeriksanya. Jangkar `~/.agent-workflow/repo` dan state (`~/.agent-workflow/`) selalu per komputer.

**Beda kemampuan antar agen:**
- Mode `--tim` (teammate, panel Orca) hanya di Claude Code. Agen lain menjalankan peran berurutan dalam satu sesi (solo); `agents/<peran>.md` dibaca sebagai instruksi, frontmatter `model:` diabaikan.
- Guard membaca format hook Claude Code; nama tool Codex (`Bash`, `apply_patch`), Gemini CLI (`run_shell_command`, `write_file`, `replace`), dan Cursor (`Shell`, `Write`, `Delete`) dinormalkan. Pemeriksaan tool MCP Atlassian (transisi Jira, mode audit) baru untuk nama tool Claude Code.
- Memory project: Claude Code memakai memory bawaannya; agen lain memakai `~/.agent-workflow/projects/<nama-repo>/MEMORY.md`.
- Plugin Claude Code (`superpowers`, `ponytail`) tidak ada di agen lain; pakai padanannya bila ada.

Tidak ikut repo (per komputer):
- Platform tiket per project: disimpan di memory project (Claude Code: memory bawaan; agen lain: `~/.agent-workflow/projects/<nama-repo>/MEMORY.md`); agen menanyakannya saat pertama jalan di project baru (awalnya `none`).
- `~/.agent-workflow/jira-transitions.json` (Jira) / `ticket-status.json` (GitHub/GitLab): agen menanyakan status Todo / In Progress / Ready To Review yang boleh ia pakai, sekali per project.
- `~/.agent-workflow/build-roots.txt` (opsional): folder project, satu per baris. Dipakai housekeeping dan guard (agen boleh menghapus artefak build di folder ini).
- Kredensial `qa.local.properties` per project, kunci App Store Connect.

---
[← kembali ke README](../README.md)
