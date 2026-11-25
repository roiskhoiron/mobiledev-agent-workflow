# Workflow choice
(superpowers / ponytail = plugin Claude Code; di coding agent lain pakai padanan skill-nya bila ada, atau ikuti alur yang sama secara manual.)
- Fitur besar / pekerjaan multi-langkah (fitur baru, refactor, perubahan lintas modul): pakai superpowers (brainstorming → writing-plans → TDD → review → verification).
- Fix kecil (bug lokal, typo, config, perubahan beberapa baris): pakai ponytail; lewati brainstorming dan plan formal.
- Ragu ukurannya: anggap kecil dulu; naik ke superpowers bila ternyata menyentuh banyak file atau butuh keputusan desain.

# Agent workflow tiket
- Platform tiket (Jira / GitHub Projects / GitLab Issue Board / tanpa platform) per project, dari memory project. Belum ada = `none` → tanya user dulu sebelum langkah lain; bingung → sarankan board bawaan host git (GitHub Projects / GitLab Issue Board). Detail: `rules.md` → Platform tiket.
- Perintah (skill): `validate-tiket`, `develop-tiket`, `rilis-tiket`, `branch-manager`, `audit-issue`; dipanggil dengan cara skill di agenmu (mis. `/validate-tiket` di Claude Code). Aturan bersama: `~/.agent-workflow/repo/skills/_shared/rules.md`; peran: `~/.agent-workflow/repo/agents/<peran>.md`.
- Workspace Orca: root project hanya untuk audit, tanya, `/rilis-tiket`, dan `/branch-manager`; kerja kode di workspace domain yang dibuka user (id `$ORCA_WORKTREE_ID`). Multi-agent = panel split di workspace itu, bukan tab, workspace, atau project baru. Tiap tiket boleh worktree sendiri `<repo>-<nomor>` sejajar checkout domain; agen menghapusnya setelah Ready To Review bila bersih dan sudah di-push. Tidak aman dibagi → solo.
- Keputusan per project tidak ditulis agen ke file instruksi project (CLAUDE.md / AGENTS.md / GEMINI.md / .cursor/rules): agen memberi blok `## Catatan agen` untuk di-commit user.
