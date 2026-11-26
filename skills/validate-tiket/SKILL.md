---
name: validate-tiket
description: Validasi tiket sebelum dikerjakan (cek layak, reproduksi bug di device, laporan bergambar di platform dokumentasi), solo atau tim (PdM, Product Designer, Contract Runner, HoE, PjM, Spesialis eskalasi). Dipanggil lewat `/validate-tiket KODE... [--solo|--tim]`. Use when asked to validate, check feasibility, or reproduce a ticket; kata kunci - validasi tiket, cek tiket, reproduksi bug, layak dikerjakan.
argument-hint: KODE-TIKET... [--solo|--tim]
---
Validasi satu atau lebih tiket (`$ARGUMENTS`). Peranmu = **Validator**; di mode tim kamu juga **SPV** (orchestrator). Tidak menulis kode produk, tidak memindah tiket ke Done.

Baca dulu (jangan disalin ke sini): `~/.agent-workflow/repo/skills/_shared/rules.md`, `devices.md`, `credentials.md`, `report-format.md`, `build-release.md`, dan `~/.agent-workflow/repo/agents/validator.md` (langkah rinci per tiket); mode tim juga `~/.agent-workflow/repo/agents/{pdm,product-designer,contract-runner,hoe,pjm,eskalasi}.md`. Skrip: `$AGENT_WORKFLOW_DIR/bin/<skrip>`, `AGENT_WORKFLOW_DIR` diisi seperti di `rules.md`.

**Mode:** sesi ini bertindak langsung sebagai Validator/SPV (bukan subagen `validator`), supaya akses platform tiket dan platform dokumentasi tetap di satu tempat. Tiket berurutan.
- `--solo` (atau tanpa flag untuk tiket kecil/jelas, satu platform): sesi ini mengerjakan semua langkah sendiri.
- `--tim` (tanpa flag: tiket fitur yang menyentuh bisnis + desain + API, atau bug lintas platform): langkah 4 dibagi ke teammate, lihat "Mode tim".

```mermaid
flowchart LR
  P[Prasyarat] --> B[Baca tiket] --> J{Bug?}
  J -- ya --> R[Reproduksi + screenshot] --> L[Laporan Docs]
  J -- fitur --> C[Cek requirement/API/desain] --> L
  L --> K[Komentar tiket] --> G{Layak?}
  G -- ya --> I[In Progress]
  G -- tidak --> T[Tetap Todo]
```

## Langkah
1. **Prasyarat (sekali, sebelum tiket pertama):**
   - Adapter platform terjangkau (cek koneksi di tabel `rules.md` → Platform tiket; Jira: `mcp__claude_ai_Atlassian__atlassianUserInfo`); gagal → berhenti, lapor ke user.
   - Checklist **Platform dokumentasi** di `rules.md` lulus (belum ada di memory project → tanya; tanpa jawaban lain = folder `docs/` di repo).
   - Checklist **Platform tiket** di `rules.md` lulus (platform belum ada di memory project → berhenti & tanya user dulu); daftar status project ada (`jira-transitions.json` / `ticket-status.json`); belum → jalankan "Setup status tiket" di `rules.md` (berhenti & tanya user untuk memilih id/label; tanpa platform → lewati).
   - Ada tiket bug → device lewat `device-pick.sh` (lihat `devices.md`); setiap panggilan `device-lock.sh`/`device-pick.sh` diawali `AGENT_LOCK_PID=$PPID` di panggilan Bash yang sama. Semua sibuk → tunggu, jangan pakai device lain.
   - Akun uji: cari sesuai `credentials.md`; tidak ditemukan → berhenti & tanya (aturan "Selalu berhenti dan tanya" di `rules.md`).
   - **Sinkron sumber (sekali per sesi):** lokasi dokumen business discovery, prototipe desain + handover + token (`rules.md` → Masukan desain), kontrak API, blueprint dari memory project (`rules.md` → Lokasi; belum ada → tanya user, simpan). Repo yang sama dengan kode → `git fetch upstream` lalu baca dari `upstream/<protected>` (branch project dari memory, `rules.md` → Lokasi) tanpa checkout; repo dokumen terpisah → `git pull` di checkout dokumen itu (bukan worktree primary). Lalu `graphify update` bila project memakai graphify. Catat ref yang dibaca di laporan.
2. **Per tiket, berurutan.** Ulangi 3–8 untuk tiap KODE; satu laporan per tiket.
3. **Baca** tiket, komentar, dan link terkait lewat adapter platform (`rules.md` → Platform tiket; Jira: `mcp__claude_ai_Atlassian__getJiraIssue`). Catat AC dan versi yang tertulis.
   **Deteksi jejak** (tiap tiket): branch `git branch -r --list 'origin/*/<KODE>*' | grep -E '/<KODE>(-r[0-9]+)?$' | grep -vE 'origin/(un)?revert/'` yang punya commit di luar laporan (`git log --oneline <branch> --not upstream/<primary> upstream/<protected> -- . ':(exclude)docs/tickets/<KODE>'` tidak kosong; branch yang hanya berisi laporan validasi bukan jejak), PR/MR `gh pr list --state all --search <KODE>` / `glab mr list --all --search <KODE>`, dan komentar tiket berisi laporan uji/rencana agen. Ada salah satunya → **mode validasi ulang** (tiket kembali ke Todo): baca penolakan sejak putaran terakhir = komentar arahan QA di tiket (dari `/rilis-tiket`) + komentar review PR/MR manusia, lalu **golongkan** tiap poin:
   | Golongan | Tindakan |
   |---|---|
   | **Implementasi meleset** (requirement tetap) | Keputusan **Layak**; daftar revisi masuk "Yang ditolak" |
   | **Requirement berubah/kurang** | Cek ulang bisnis/prototipe/kontrak terhadap dokumen terbaru; tidak jelas → tanya user/PM; keputusan memakai tabel "Aturan keputusan" |
   Jejak ada tapi tidak ada komentar penolakan (mis. tiket dipindah ke Todo manual) → tanya user apa yang ditolak. PR/MR tiket sudah **merged** → tidak dipakai ulang: pengerjaan lewat branch baru `<jenis>/<KODE>-r<n>` dari base terkini + Draft PR/MR baru yang menyebut yang lama. Tidak ada jejak → validasi biasa.
4. **Bug:** tentukan versi dari tiket (kosong → build dev/beta terbaru, lihat `build-release.md`). Ambil device **fisik dulu, lalu emulator/simulator** (`device-pick.sh <plat> <owner> --prefer-physical`; `--physical` bila wajib hardware asli, lihat `devices.md`), reproduksi via Maestro (cadangan per platform di `devices.md`); screenshot tiap langkah.
   **Fitur:** cek requirement lengkap, API siap (spec di repo), desain tersedia: prototipe per state + handover + token (`rules.md` → Masukan desain); tiket lama hanya mockup → paling tinggi **Layak dengan catatan**.
   **Tiket terkait (solo dan tim):** selain link yang ada, cari tiket Todo/In Progress yang tidak di-link tapi menyentuh komponen/label/layar/fitur/endpoint yang sama (JQL `text ~`); mode tim dikerjakan PjM. Link antar tiket tidak dibuat sendiri: cukup disarankan di komentar.
   **Aturan keputusan** (temuan PdM/PjM/HoE atau pemeriksaanmu sendiri):
   | Kondisi | Keputusan | Tindakan |
   |---|---|---|
   | Informasi minim, AC inti jelas | Layak dengan catatan | Pertanyaan di komentar tiket untuk reporter |
   | Informasi minim, AC inti kabur | Tidak layak | Tetap Todo; komentar berisi daftar yang harus dilengkapi |
   | Bertabrakan dengan tiket/dokumen lain | Tidak layak sampai diputuskan | Komentar menyebut kedua tiket + titik tabrakan (kutipan); tanya user mana yang berlaku |
   | Tumpang tindih tapi selaras | Layak dengan catatan | Saran urutan pengerjaan atau penggabungan |
5. **Screenshot bertanda:** ambil bounds dari `maestro hierarchy` atau `-frames.json` XCUITest (bukan ditebak), lalu `$AGENT_WORKFLOW_DIR/bin/annotate.py`. File kerja hanya di `${TMPDIR:-/tmp}/validate/<KODE>/`, bukan di repo.
6. **Laporan** di platform dokumentasi sesuai `report-format.md` (judul `Validasi <KODE> — judul singkat`). Folder `docs/` (default): pakai worktree + branch tiket (`rules.md` → Workspace & worktree; belum ada → buat seperti `/develop-tiket` langkah 3, jenis dari tiket), tulis `docs/tickets/<KODE>/validasi.md` + `img/` (screenshot bertanda dari `${TMPDIR:-/tmp}/validate/<KODE>/`), commit `docs(<KODE>): laporan validasi`, push branch itu ke `origin`; link = URL file di branch `origin`. Worktree yang bersih dan sudah di-push boleh dihapus; `/develop-tiket` memakai branch yang sama. Platform lain: unggah screenshot ke dokumen. Tanpa kredensial (sebut nama kunci saja). **Validasi ulang:** laporan berbentuk **delta**: apa yang berubah dibanding validasi sebelumnya (link laporan lama) + bagian **Yang ditolak** (tiap poin: sumber komentar, golongan, saran tugas/TC). Lalu dikomentari dan ditransisikan seperti biasa.
7. **Komentar tiket** (adapter platform): baris pertama = link laporan, lalu keputusan: **Layak** / **Layak dengan catatan** / **Tidak layak** + alasan singkat.
8. **Transisi:** Layak / Layak dengan catatan → pindah status ke In Progress (adapter platform, id/label dari daftar status project). Tidak layak → tetap Todo. Lepas kunci device/akun (`AGENT_LOCK_PID=$PPID ... device-lock.sh release ...`).
9. **Mode tim** (menggantikan langkah 4–5, SPV tetap menulis laporan, komentar, transisi):
   - Panggil teammate paralel (tool Agent, `name` dari tabel "Nama agen" di `rules.md`, `subagent_type` = peran, `model` dari tabel): PdM, Product Designer (tiket UI/bug UI), Contract Runner (tiket menyentuh API), HoE, PjM.
     | Peran | Model | Catatan |
     |---|---|---|
     | PdM | `claude-sonnet-5-5` | dokumen business discovery |
     | Product Designer | `claude-sonnet-5-5`; eskalasi `claude-opus-5-5` | tiket UI/bug UI |
     | Contract Runner | `claude-sonnet-5-5` | tiket yang menyentuh API; hasil diteruskan ke HoE |
     | HoE | `claude-opus-5-5` | selalu di mode tim |
     | PjM | `claude-sonnet-5-5` | selalu di mode tim |
     | Spesialis eskalasi | `claude-fable-5-2` (jangan isi `model`: frontmatter yang berlaku) | hanya saat pemicu; dihentikan setelah membalas | Brief: KODE, ringkasan tiket + AC, lokasi dokumen + ref, worktree/repo, jatah device/akun (bug), folder `${TMPDIR:-/tmp}/validate/<KODE>/`. Prompt: "Ikuti `~/.agent-workflow/repo/agents/<peran>.md`".
   - Hasil Contract Runner diteruskan ke HoE. Bug UI → Product Designer reproduksi; bug logika/API → HoE.
   - **Eskalasi Product Designer ke opus:** reproduksi bug UI gagal/rumit setelah satu putaran → panggil ulang dengan `model: claude-opus-5-5`.
   - **Spesialis eskalasi (`eskalasi`, fable) hanya bila:** bug logika gagal direproduksi HoE setelah satu putaran; temuan HoE ambigu (bug atau disengaja); tiket berlabel high-risk (pembayaran, autentikasi, perubahan skema data); konflik antar-agen yang tidak bisa kamu selesaikan. Sebut pemicunya di brief.
   - Gabungkan semua `${TMPDIR:-/tmp}/validate/<KODE>/*.md` jadi satu laporan (`report-format.md` → bagian Bisnis / Desain / Teknis / Ketergantungan). Tiket UI tanpa prototipe (hanya mockup, atau tidak ada keduanya) → paling tinggi **Layak dengan catatan**. Hentikan teammate yang tugasnya habis; akhir sesi → hentikan semua dan pastikan kunci dilepas.
10. **Ringkasan akhir** (setelah semua tiket):

   | KODE | Keputusan | Link laporan |
   |---|---|---|

Keputusan parsial boleh; TC yang butuh device lebih dari tersedia = Tertahan.
