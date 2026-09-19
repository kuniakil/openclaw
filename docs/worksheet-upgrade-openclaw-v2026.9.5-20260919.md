# OpenClaw 升級工作表：v2026.9.4 → v2026.9.5

**日期**：2026-09-19  
**目標 Tag**：`v2026.9.5`（Release SHA: `ec9c1a13db8938e5a3eaa51fca2e981cde2395a9`）  
**來源**：https://github.com/openclaw/openclaw/releases/tag/v2026.9.5  
**Changelog**：https://raw.githubusercontent.com/openclaw/openclaw/main/CHANGELOG/2026.9.5.md  
**目前分支**：`my-config-v2026.9.4`（HEAD: `91eb9e85d97`）  
**目標分支**：`my-config-v2026.9.5`

---

## ⚠️ 重大破壞性變更（MUST READ BEFORE PROCEEDING）

### 🔴 Database Schema 升級到 Schema 21

> **原文**：「This release upgrades agent databases to **schema 21**, which older builds cannot open. [Make and verify a pre-upgrade backup](https://docs.openclaw.ai/install/backups) that includes committed data still in the database journal, or WAL. Going back requires restoring that backup with its matching older build and loses work saved after the backup.」

- **影響**：Schema 21 是不可逆升級，舊版 build 無法讀取
- **特別注意**：從 2026.9.2 升級的用戶需要手動 schema-upgrade，參閱 [manual schema-upgrade instructions](https://docs.openclaw.ai/install/updating#updating-from-2026.9.2-across-a-schema-bump)
- **應對**：升級前必須在 K3s 叢集的 OpenClaw Pod 上執行資料庫備份
- **新功能**：schema21 減少 repeated session admission scans（效能改善）

### 🟡 Cold Transcript Storage 資料庫變更

> 「This release changes the conversation database even with archiving off, so going back requires the matching older build and backup.」

- 即使未啟用 archiving，conversation database 也會被修改
- 回滾需要完整的備份 + 配對的舊版 build

### 🟡 Plugin SDK：await registration/deletion methods

> 「Plugin authors must await the updated registration and deletion methods and use a supporting host.」（iMessage, WhatsApp, Signal, Matrix 相關）

- 若有使用 channel plugin，approval 控制的 `registration` 和 `deletion` 方法現在為 async，需要 await
- 目前我們的 custom 程式碼 `extensions/google/embedding-provider.ts` 需要確認是否受影響

### 🟡 `openclaw migrate` CLI 行為改變

> 「The `apply` command does not support dry runs and now rejects a preceding `--dry-run` before changing anything.」

- `openclaw migrate apply --dry-run` 不再被接受，改用 `openclaw migrate plan`
- 對 Docker 環境影響：若有 entrypoint script 使用此 flag 需修改

### 🟢 Node.js 相容性

- 新增支援 `nodejs`, `node24`, `node-24`（含 `.exe` variants）
- 無 runtime 版本 bump，現有 `node:22` base image 應繼續相容

---

## 📋 我們的自定義 Patches 清單（需攜帶至新版）

來自 `c7222116169`（chore: upgrade to v2026.9.4）和 `91eb9e85d97`（ci: streamline docker-release）：

| 自定義內容     | 所在位置                                  | 說明                                                                      |
| -------------- | ----------------------------------------- | ------------------------------------------------------------------------- |
| Locale layer   | `Dockerfile`                              | `en_US.UTF-8` / `zh_TW.UTF-8`                                             |
| 額外系統套件   | `Dockerfile`                              | `rsync`, `tini`, `faster-whisper`, `edge-tts`, `ffmpeg`, `openssh-server` |
| SSH Entrypoint | `docker/entrypoint-ssh.sh`                | 自定義 SSH 入口                                                           |
| Whisper 資源   | `assets/whisper/`                         | 本地 Whisper 模型設定                                                     |
| Rate Pacing    | `extensions/google/embedding-provider.ts` | Embedding rate 限速 patch                                                 |
| Memory 補丁    | `src/memory/manager-embedding-ops.ts`     | 小型修正                                                                  |
| CI Matrix      | `.github/workflows/docker-release.yml`    | 精簡版 matrix CI                                                          |
| TODO 文件      | `TODO-docker-build-rsync-utf8.md`         | 記錄待辦事項                                                              |
| .gitignore     | `.gitignore`                              | 自定義 ignores                                                            |
| AGENTS.md      | `AGENTS.md`                               | 本地 agent 規則                                                           |

---

## 📝 升級步驟工作表

### Phase 1：Pre-Upgrade 分析（已完成 ✅）

- [x] 閱讀官方 Release Notes（v2026.9.5）
- [x] 提取 Breaking Changes（Schema 21、DB 變更、Plugin SDK async）
- [x] 確認 Deprecations（`migrate apply --dry-run` 被移除）
- [x] 確認 Dependency/Runtime 變更（無重大 runtime bump）
- [x] 確認現有自定義 patches 清單
- [x] 生成本工作表

### Phase 2：Pre-Execution Prep（已完成 ✅）

- [x] **[CRITICAL]** 在 K3s 叢集備份 OpenClaw 資料庫（Schema 20 → 21 不可逆）
  - 已於 Pod 內建立備份：`/home/node/.openclaw/backups/manual-pre-v2026.9.5-20260919195844` (179MB)
  - 已同步保存驗證完整性至本機：`/Users/mlee/openclaw-backups/`
- [x] 確認 `git fetch upstream --tags` 完成，`v2026.9.5` tag 已可用
- [x] 確認 upstream/release/2026.9.5 分支存在

### Phase 3：建立新分支（已完成 ✅）

- [x] Checkout v2026.9.5 tag 並建立新分支 `my-config-v2026.9.5`

### Phase 4：CI Workflow 清理（已完成 ✅）

- [x] 清除官方 CI workflows，保留並覆寫我們的 docker-release.yml

### Phase 5：移植自定義 Patches（已完成 ✅）

- [x] Cherry-pick 或手動套用 Dockerfile 自定義層
  - locale (zh_TW.UTF-8/C.UTF-8), rsync, tini, faster-whisper, edge-tts, ffmpeg, openssh-server
- [x] 還原 `docker/entrypoint-ssh.sh`
- [x] 還原 `assets/whisper/`
- [x] 還原 `extensions/google/embedding-provider.ts`（rate pacing patch 15 RPM queue）
- [x] 還原 `extensions/memory-core/src/memory/manager-embedding-ops.ts`（gemini concurrency = 1）
- [x] 更新 `.gitignore`
- [x] 更新 `AGENTS.md`（保留本地規則與 Mac Host 保護原則）
- [x] 還原 `TODO-docker-build-rsync-utf8.md`

### Phase 6：衝突風險評估（已完成 ✅）

- [x] 確認 `extensions/google/embedding-provider.ts` 上游無衝突
- [x] 確認 `extensions/memory-core/src/memory/manager-embedding-ops.ts` 上游無衝突
- [x] 確認 `Dockerfile` 上游無衝突
- [x] 確認 `package.json` 中 Node.js 版本相容

### Phase 7：本地輕量驗證（已完成 ✅）

- [x] `git status` 確認乾淨
- [x] `git diff HEAD~2..HEAD --stat` 確認 patch 範圍合理
- [x] 目視確認 `Dockerfile` syntax 正確
- [x] 確認 `docker-release.yml` 完整性

### Phase 8：Push 並觸發 CI（已完成 ✅）

- [x] Push 新分支 `my-config-v2026.9.5`
- [x] 打 Tag 並 Push `v2026.9.5`
- [x] 確認 GitHub Actions `docker-release.yml` 觸發並成功（Run #35441426976）
- [x] 確認 `ghcr.io/kuniakil/openclaw:2026.9.5` 與 `:latest` 雙架構成功發佈

### Phase 9：部署驗證（已完成 ✅）

- [x] 確認 GHCR image 可用
- [x] 在 K3s 叢集更新 OpenClaw image 至 `ghcr.io/kuniakil/openclaw:2026.9.5`
- [x] 停止 Gateway 執行獨立 Pod 跑 `openclaw doctor --fix`
- [x] 成功將資料庫升級至 **Schema 21** (`v19 -> v21`)
- [x] Gateway 正常重啟，HTTP 監聽就緒
- [x] `/healthz` 健康檢查通過：`{"ok":true,"status":"live"}`
- [x] 運行時版本確認：`OpenClaw 2026.9.5`

---

## 🔍 2026.9.5 主要功能亮點（非破壞性）

| 類別             | 功能                                                   |
| ---------------- | ------------------------------------------------------ |
| **Installation** | 新增 FreeBSD CLI 支援                                  |
| **Installation** | Docker 容器內 workspace/skill 檔案路徑對應修正         |
| **Installation** | systemd 239 相容性修復                                 |
| **Installation** | Mac CLI 臨時目錄權限錯誤修復                           |
| **Web UI**       | 專員角色/團隊選擇（specialist team setup）             |
| **Web UI**       | Agent/Conversation 頭像生成                            |
| **Web UI**       | 側邊欄 plugin 頁面排序                                 |
| **Web UI**       | Command palette 文字輸入                               |
| **Web UI**       | 瀏覽器 tab 對話活動指示                                |
| **Migration**    | 多 agent 設定後重啟保留 default agent                  |
| **Migration**    | Schema 21：session admission scan 效能改善             |
| **Provider**     | Apple Foundation Models（需 macOS 27 + Apple silicon） |
| **Docker**       | sandbox workspace 路徑對應（#147276）                  |
| **Docker**       | Matrix source build 修復（#146081）                    |
| **Pairing**      | 配對 ID 允許前後空白/換行                              |
| **Pairing**      | trusted-proxy 用戶可產生 QR setup code                 |

---

## 📌 風險摘要

| 風險                                   | 等級  | 處理方案                             |
| -------------------------------------- | ----- | ------------------------------------ |
| Schema 21 不可逆升級                   | 🔴 高 | 升級前必須備份 K3s PVC               |
| Cold transcript DB 變更                | 🟡 中 | 同上，隨 Schema 備份一起處理         |
| embedding-provider.ts Plugin SDK async | 🟡 中 | 升級時需重新驗證 rate pacing patch   |
| migrate apply --dry-run 移除           | 🟢 低 | 確認 entrypoint script 未使用此 flag |
| Dockerfile 上游變動衝突                | 🟢 低 | 執行時確認 diff                      |

---

## ✅ 授權確認（Go-Sign）

> 此工作表需要用戶明確 **「開始執行」** 才會進行任何 git 操作。  
> **目前狀態：等待 Go-Sign。**

---

_由 Antigravity 於 2026-09-19T19:41 生成，遵循 `agent-release-upgrade` SOP。_
