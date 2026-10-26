# Upgrade Worksheet: openclaw → v2026.10.7

**Date:** 2026-10-26
**Current branch:** `my-config-v2026.10.6`（HEAD `9e811a32d3b`）
**Target tag:** `v2026.10.7`（官方 SHA `157d8c2bc3ea2fa183afdc11088e69690bf8e64e`）
**New branch:** `my-config-v2026.10.7`
**Release:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.7

> [!IMPORTANT]
>
> ## 本次是「零 schema 變更、零衝突」的純 patch 升級
>
> 1. **無 schema migration。** `openclaw.schemaVersions` 維持 **`state 20 / agent 25`**，
>    `src/state/openclaw-*-db-contract.ts` 兩個契約檔 **diff 為空**。
>    → 不需要 `openclaw doctor --fix`；**回滾只要改 image tag**（10.6 與 10.7 同為 agent schema 25）。
> 2. **無 Node 下限變動。** `engines.node` 仍是 `>=24.22.1 <25 || >=26.12.1`（10.6 已抬高）。
>    線上 10.6 image 內 Node 已是 **v24.22.1** → 10.7 沒有新的 runtime 要求。
> 3. **上游 Dockerfile 對 10.6→10.7 改動為空**（`git diff` 無輸出）→ 我們的自訂層
>    （locale / rsync / faster-whisper / edge-tts / ffmpeg / openssh-server）**可原封帶過，預期零衝突**。
> 4. **冲突交叉比對結果為空**（0 個檔案）→ 這是 10.1～10.6 以來最乾淨的一次。
> 5. **不需要重建記憶體 embedding 索引**（schema / embedding 模型 / embedding 輸入格式版本皆未變）。
>    **絕對不要**為了驗證而清空 embedding cache —— 那是 10.6 配額事故的根因。
>
> **唯一需要留意的行為變更**：`extensions/memory-core/index.ts` 移除了 standing-intent 工具的
> `senderIsOwner !== true` 守門 → **非 owner 發送者也會拿到 `intent` 工具**（上游刻意決策，
> 範圍由 `senderScope: sender|anyone` 與 executor 端控制）。我們是私人 Telegram bot，影響低，
> 但 Phase 3 需觀察一次。

---

> [!IMPORTANT]
>
> 1. **本地 `v2026.10.x` 都是自訂 tag**（含我們的 patch）。官方 baseline 已 fetch：
>    - `refs/tags/upstream-v2026.10.7`（官方 10.7，SHA `157d8c2bc3e`）
>    - `refs/tags/upstream-v2026.10.6`（官方 10.6，SHA `fe06181dc5e`）
> 2. **不可用本地 `v2026.10.6` 當 diff base**。新分支必須從 `upstream-v2026.10.7` 開。
> 3. **使用分支觸發模型**（承襲 10.3～10.6 決策），**不** force-push git tag。
> 4. 禁止在 Mac 跑 `pnpm check:changed` / `tsgo` / `vitest` / `docker build`，一律交給 GitHub Actions。
> 5. **備份不強制**（無 schema 變更 → 回滾 = 改 image tag），但既有 10.6 備份仍在保留期內，
>    需先盤點（見 2.0）。

---

## Phase 1: 分析結果

### 1.1 官方 10.6 → 10.7 差異

| 項目                            | 10.6                           | 10.7                             | 備註                                              |
| ------------------------------- | ------------------------------ | -------------------------------- | ------------------------------------------------- |
| `package.json` version          | 2026.10.6                      | 2026.10.7                        |                                                   |
| `openclaw.schemaVersions`       | state 20 / agent 25            | **state 20 / agent 25（不變）**  | 🟢 **無 migration**，回滾 = 改 image tag          |
| `OPENCLAW_AGENT_SCHEMA_VERSION` | 25                             | **25（不變）**                   | 🟢 契約檔 diff 為空                               |
| `OPENCLAW_STATE_SCHEMA_VERSION` | 20                             | **20（不變）**                   | 🟢                                                |
| `engines.node`                  | `>=24.22.1 <25 \|\| >=26.12.1` | **不變**                         | 🟢 線上已是 24.22.1                               |
| `packageManager`                | pnpm 12.15.0                   | pnpm 12.15.0（不變）             | 🟢 corepack 自動取得                              |
| `@openclaw/fs-safe`             | 0.25.0                         | **0.26.0**                       | 🟡 唯一的相依升級（隨 build 自動安裝）            |
| Dockerfile                      | —                              | **上游 diff 為空**               | 🟢 自訂層零風險帶過                               |
| `extensions/` 目錄數            | 176                            | **176（無增減）**                | 🟢 plugin 數維持 17                               |
| `extensions/` 變更檔數          | —                              | 213（新增 4 個內部檔）           | 🟢 codex/copilot/cua-computer 內部檔，無新 plugin |
| `.github/workflows/` 變更       | —                              | **1 檔（`ci.yml`）**             | 🟢 全部 purge                                     |
| **變更規模**                    | —                              | **599 files / +16,326 / −3,980** | 🟢 官方標示 patch 版                              |
| 上游 commits                    | —                              | 73                               | 🟢                                                |
| `src/state/` 變更檔數           | —                              | 15                               | 🟡 但 schema 常數未動 → 不需 doctor               |

### 1.2 官方 Release Notes 審查（v2026.10.7）

官方定位：修補型 release（8 個 Highlights 主題 + 1 個 Changes + 4 個 Fixes），**無 breaking change 宣稱**。

**與我們 K3s Docker 部署相關者 ⭐**：

- **Gateway logging（#160433）** — 「已刪除或過期的臨時 log 目錄會在日期翻轉時讓 Gateway 卡在 100% CPU」。
  → **直接相關**：我們的 Pod 已連續運行 3 天 4 小時、且已跨過一次日期翻轉（10.23→10.24）。
  10.7 修掉這個 → 對長駐 Pod 是正向收益，也是本次升級最實用的修復之一。
- **Database and worker continuity（#175987, #179320, #170122, #171372, #172756, #168862）** —
  維護拒絕時保留 peer readers/borrowers、不相容的舊 agent DB 保持隔離、空 transcript 刪除時跳過不必要
  的 archive materialization、worker shutdown 在 inventory 退役後完成。
  → **直接相關**：我們正是 SQLite + worker 架構；「空 transcript 跳過 archive」對記憶體索引與
  session 清理是正面。
- **Replay-safe session recovery（#153728, #168764, #172068, #177716, #176682, #176783, #176675, #159715, #181801）** —
  中斷的 session 保留 recovery provenance 與未完成 tool 結果、終止的對話在收下一則訊息前清掉終止殘留。
  → **直接相關**：10.6 的「agent 被 hold / 對話中斷」類問題的後續修補。
- **Backup and state durability（#164297, #171292, #152565, #160409, #175707）** —
  快照保留受支援的舊版 exec-approval policy、截斷寫入時 config observation 保留 last-known-good、
  Memory Wiki re-import 保留人手撰寫的筆記。
  → 🟢 與我們的 doctor / 備份流程一致。
- **Provider and plugin continuity（#176709, #178522, #173366, #173292, #162226, #161267, #168391）** —
  model refresh、已設定帳號的就緒狀態、增量 plugin 載入。
  → 🟢 我們主模型 MiniMax-M3，不受影響。
- **Safer update activation and recovery（#181166, #181307, #173862, #167459, #172768, #172769, #181389）** —
  驗證過的 activation 不因後續維護/ledger 錯誤而失敗、package update 中斷可安全續跑。
  → 🟢 我們走 image 部署、不走 package swap 路徑，不適用。
- **Operator control continuity（#169385, #169400, #164511, #176218, #174530）** —
  cron announcements 保留 CLI 對話、history maintenance 先讀 identity 再讀 payload。
  → 🟢 正向。
- **Cross-platform app-managed upgrades（#171508, #174297, #175007, #176174, #178155, #178779, #180010, #180576, #180769）** —
  涵蓋 #175007（10.6 已列的 agent-held 存取修補）在 app-managed 路徑的延伸。
  → 🟢 與我們 10.6 已驗證的「agent 存取恢復正常」一致。

**Changes**：Google models 新增 **Gemini 4 Argon**（#171852）→ 與我們無關（我們用 MiniMax-M3）。

**Fixes**：update guidance 收斂、macOS onboarding、Gateway logging（上述）、Control UI slash-steer chip 清除。

**Deprecations / Breaking Changes / 遷移要求**：**無**。
`schemaVersions` 與 DB 契約常數皆未動 → **不需要 migration script、不需要 doctor --fix**。

**官方 release notes 中的已知告警（與我們無關但記錄）**：
Android APK skipped（`apps/android/version.json` 仍是 2026.8.2，release train 是 2026.10.7）。

### 1.3 自訂 patch 清單（`my-config-v2026.10.6` 內）

| Commit                            | 檔案                                                                                                                  | 內容                                                                 |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `0de187fba83`                     | `.github/workflows/*`（官方 114 檔 → 只留 1 檔）                                                                      | 刪除官方 workflows、覆蓋 `docker-release.yml` 為 Matrix 版（191 行） |
| `a586fa6afdc`（源 `64ce0d05c9e`） | `Dockerfile`（+46）、`extensions/google/embedding-provider.ts`、`extensions/memory-core/.../manager-embedding-ops.ts` | 自訂層 + Gemini Free Tier rate pacing + gemini 索引併發鎖 1          |
| `678a32fdcd1`（源 `884f17a1fe1`） | `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`                                       | 自訂資產（0755）                                                     |
| 24 個 docs commits                | `docs/worksheet-upgrade-openclaw-*.md`                                                                                | 保留 10.1～10.6 升級歷史                                             |

### 1.4 衝突交叉比對 —— 🟢 **零衝突**（本次最乾淨）

```bash
comm -12 <(git diff --name-only upstream-v2026.10.6..my-config-v2026.10.6 | grep -v '^\.github/workflows/' | sort -u) \
         <(git diff --name-only upstream-v2026.10.6 upstream-v2026.10.7 | sort -u)
```

**結果：空（0 個檔案）。**

我們自訂修改的 5 個非 docs 檔（`Dockerfile`、`extensions/google/embedding-provider.ts`、
`extensions/memory-core/src/memory/manager-embedding-ops.ts`、`assets/whisper`、`docker/entrypoint-ssh.sh`）
**沒有任何一個被上游 10.6→10.7 觸及**。

#### ① `Dockerfile` —— 🟢 上游 diff 為空

```bash
git diff upstream-v2026.10.6 upstream-v2026.10.7 -- Dockerfile   # → 無輸出
```

我們的自訂層是檔尾追加（4 個 `# Custom:` 段落，位於 `ENV NODE_ENV=production` 之前），
上游完全沒動這個檔 → cherry-pick 必然零衝突。

#### ② `extensions/google/embedding-provider.ts` —— 🟢 上游未改

我們的 Gemini rate pacing（`geminiEmbeddingQueue` / `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` /
`executePaced`）原樣保留。**驗收**：grep 有命中。

#### ③ `extensions/memory-core/src/memory/manager-embedding-ops.ts` —— 🟢 上游未改

我們那 1 行 `provider?.id === "gemini" ? 1 : ...` 原樣保留。**驗收**：diff 對基線仍為剛好 1 行。

#### ④ `extensions/memory-core/index.ts` —— 🟡 上游有動，但我們沒改這個檔

上游移除了 standing-intent 工具的 `ctx.senderIsOwner !== true` 守門 → 非 owner 發送者也可能拿到
`intent` 工具。**我們無 patch 衝突**，但列為 Phase 3 觀察項（3.1.4）。

#### ⑤ `.github/workflows/` —— 🟢 按 SOP purge 重建

上游只改了 1 個 workflow（`ci.yml`）。**全部 purge**，用 `my-config-v2026.10.6` 的 Matrix 版覆蓋
`docker-release.yml`，**不 merge 官方變更**。

### 1.5 記憶體 embedding —— 🟢 **不需重建**

```bash
git diff upstream-v2026.10.6 upstream-v2026.10.7 -- packages/memory-host-sdk/ \
  extensions/memory-core/src/memory/embeddings.ts extensions/google/embedding-provider.ts
# → 空
```

`extensions/memory-core/` 本次只動 3 檔（`index.ts`、`package.json`、`index.test.ts`），
**不涉及 embedding 輸入格式、不涉及 embedding 模型、不涉及 schema**。
→ 索引與快取繼續沿用。**本次升級絕不執行** `openclaw memory index` / `memory reset` /
`memory search`（會觸發 embedding → 有 429 配額風險；限速是每行程一份）。

### 1.6 風險評估：**低**（與 10.6 同級，為 10.1～10.6 中最低之一）

| 風險類型        | 等級      | 原因                                                                                  |
| --------------- | --------- | ------------------------------------------------------------------------------------- |
| **Schema 中斷** | 🟢 **無** | `state 20 / agent 25` 未變 → 不需 doctor、不需停機 migration、**回滾 = 改 image tag** |
| Node runtime    | 🟢 無     | 下限未變，線上已是 24.22.1                                                            |
| 自訂 patch      | 🟢 **零** | 交集為空 → 預期零衝突                                                                 |
| 相依            | 🟢 低     | 只升 `@openclaw/fs-safe` 0.25→0.26（由 CI build 安裝）                                |
| 行為相容性      | 🟢 低     | 官方 patch 版；唯一行為變更 = standing-intent 不再 owner-only（見 1.4 ④）             |
| Plugin          | 🟢 低     | `extensions/` 無增減 → plugin 數維持 17                                               |
| 模型目錄        | 🟢 無     | 僅新增 Gemini 4 Argon；我們用 MiniMax-M3                                              |
| Channel         | 🟢 低     | 無新通道；session recovery / DB worker 修補為正向                                     |
| 部署中斷        | 🟢 低     | 單 pod rollout，過往 6 次升級皆在 ~30s 內恢復                                         |

---

## Phase 2: 執行步驟

### 2.0 前置檢查

- [x] `git status -sb` → `## my-config-v2026.10.6...origin/my-config-v2026.10.6`（工作區乾淨）
- [x] 官方 baseline tag 已 fetch
  ```bash
  git fetch upstream refs/tags/v2026.10.7:refs/tags/upstream-v2026.10.7 --no-tags
  git rev-parse 'upstream-v2026.10.7^{commit}'   # 157d8c2bc3ea2fa183afdc11088e69690bf8e64e
  ```
- [x] `schemaVersions` 對比：`10.6 {state:20, agent:25}` == `10.7 {state:20, agent:25}` → **無 migration**
- [x] `engines.node` 對比：`>=24.22.1…` → `>=24.22.1…`（不變）
- [x] 官方 Release Notes + `CHANGELOG/2026.10.7.md` 已審閱（無 breaking / 無 migration）
- [x] 衝突交叉比對 → **空**
- [x] Dockerfile 上游 diff → **空**
- [x] embedding 相關檔 diff → **空** → 不需重建索引
- [x] `extensions/` 目錄數 176 == 176（無新 plugin）
- [x] 線上現況盤點（`ssh n100`）
  ```
  openclaw-gateway-69bb5cdcdf-9kwwp   1/1   Running   0   3d4h
  線上 image：ghcr.io/kuniakil/openclaw:2026.10.6
  ```
- [x] 既有備份盤點（**只有 10.6 那一份，仍在保留期**）
  ```
  /home/kuniaki/backup-openclaw-20261023   869M   （到期日 2026-10-30）
  磁碟 / 1.8T 已用 570G（33%）
  ```
- [x] **備份決策：使用者 Go 時指定 (b)** → 另做一次輕量線上快照
      （7 個 SQLite + 設定，含 workspace 的非 git 部分；排除 `workspace/oracle-hunt` 524M git repo，可由 git 還原）。
      10.6 的 869M 快照仍在保留期（到期 2026-10-30），清理需使用者確認（見 3.5）。

### 2.1 建立新分支（從 upstream 10.7 基線）

- [x] `git checkout -b my-config-v2026.10.7 'upstream-v2026.10.7^{commit}'`
- [x] HEAD = `157d8c2bc3e`
- [x] `package.json` version = `2026.10.7`、`schemaVersions` = `{'state': 20, 'agent': 25}`、
      `engines.node` = `>=24.22.1 <25 || >=26.12.1`

### 2.2 Purge 官方 workflows 並覆蓋 Matrix `docker-release.yml`

- [x] `find .github/workflows -type f ! -name 'docker-release.yml' -delete`（官方 114 個 workflow → 1）
- [x] `git checkout my-config-v2026.10.6 -- .github/workflows/docker-release.yml`
- [x] commit `79f0dd1d1b1`（114 files changed, +149 / −65,639）
- [x] 驗證：僅剩 `docker-release.yml`（**191 行**）；`on:` 只有 `workflow_dispatch`、input 名稱 = **`tag`**、
      `platforms` 預設 `all`（**不是** `tag_name`）

### 2.3 Cherry-pick 自訂 commits（保留線性歷史）

- [x] `git cherry-pick -x a586fa6afdc` → `eb32eb0318c`：**零衝突**（3 files, +125 / −62）
- [x] `git cherry-pick -x 678a32fdcd1` → `6581f174900`：**零衝突**（3 files, +111；whisper 0755 / entrypoint-ssh.sh 0755）
- [x] 帶過 `my-config-v2026.10.6` 的 **27 個純 docs commits**（`678a32fdcd1..9e811a32d3b` 整段），全部只動
      `docs/worksheet-upgrade-openclaw-*.md`，保留 10.1～10.6 升級歷史
- [x] 線性歷史：**0 merge commit**（`git log --merges upstream-v2026.10.7..HEAD` = 0）

### 2.4 輕量本地驗證（無重型 CI）

- [x] `git diff 'upstream-v2026.10.7^{commit}' HEAD --stat -- Dockerfile` → **+46 / −0**（純附加）
- [x] 4 個 `# Custom:` 段落仍在 `ENV NODE_ENV=production`（486）**之前**（439 / 458 / 474 / 478）
- [x] base image ARG = `node:24.22.1-bookworm`（line 16）與 `node:24.22.1-bookworm-slim`（line 17，上游值，未被覆寫）
- [x] `grep -n 'geminiEmbeddingQueue\|MIN_GEMINI_EMBEDDING_INTERVAL_MS'` → 有命中（218 / 219 / 295-303）
- [x] `manager-embedding-ops.ts` 對基線 diff 仍為 **1 行**（line 527，`|| provider?.id === "gemini"`）
- [x] `assets/whisper` / `docker/entrypoint-ssh.sh` → `-rwxr-xr-x`
- [x] `git diff 'upstream-v2026.10.7^{commit}' HEAD --stat -- ':!.github'` → 恰好 12 檔、+2841 / −62
      （Dockerfile 46 + TODO 38 + assets 41 + entrypoint 32 + 6 份 worksheet + 2 個功能檔）

### 2.5 備份（視 2.0 決策）

- [x] **選 (b)：輕量線上快照** → `/home/kuniaki/backup-openclaw-20261026`（**267M**）
  - [x] 用容器內 `node:sqlite` 的 `backup()`（module-level `backup(db, path)`）取 **7 個 live SQLite** 一致快照
        （WAL 安全；agent 222MB + state 16MB + quarantine + codex-home ×4）
  - [x] **7/7 快照 `PRAGMA quick_check` = ok**
  - [x] 快照 `user_version`：agent = **25** / state = **20** / quarantine = 2（與線上一致 → 確認無待 migration）
  - [x] 其餘 runtime 檔以 `cp -a` / `rsync` 帶走：`openclaw.json`、`openclaw.json.last-good`、
        `config-journal-fingerprint.key`、`credentials/`、`identity/`、`devices/`、`plugin-state/`、
        `plugins/`、`skills/`、`memory/`、`state/`（非 sqlite）、`workspace/`（排除 `oracle-hunt` 524M git repo）
  - [x] **排除**協調鎖 DB（generation-lock / generation-writer / reindex-lock / gateway locks）與 `workspace/worktrees`
  - [x] 快照檔案大小與來源一致（agent 222,097,408 B；state 16,068,608 B）

### 2.6 更新本 worksheet 並 commit

- [ ] `git add docs/worksheet-upgrade-openclaw-v2026.10.7-20261026.md` + commit

### 2.7 Push 分支

- [ ] `git push -u origin my-config-v2026.10.7`
- [ ] 確認 `origin/my-config-v2026.10.7` == local HEAD

### 2.8 觸發 build（分支觸發模型）

> [!IMPORTANT]
> **不 force-push git tag。** `--ref` 指向分支、`-f tag` 命名 image，tag 不影響 build。

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.10.7 -f tag=v2026.10.7 -f platforms=all
```

- [ ] dispatch 成功；若回 `HTTP 422 "Actions has been disabled for this repository"` →
      到 `https://github.com/kuniakil/openclaw/actions` 點橫幅重新啟用
      （**不要**清 cache / 改 settings / 重試）
- [ ] `gh run list --workflow=docker-release.yml --limit 1 --json databaseId,event,headBranch,headSha,status`
  - `event` = `workflow_dispatch` ✅
  - `headBranch` = `my-config-v2026.10.7` ✅
  - `headSha` = **我們的** commit（非官方 `157d8c2bc3e`）✅
- [ ] `gh run watch <run_id>` → conclusion: **success**（⭐ **必須派給背景子代理**，主迴圈不得阻塞）

### 2.9 Build 結果驗證

- [ ] 5 個 tag 全部存在且 digest 一致：`2026.10.7` ✅ `v2026.10.7` ✅ `2026.10.7-slim` ✅ `latest` ✅ `main` ✅
- [ ] multi-arch manifest 確認含 amd64 + arm64

---

## Phase 3: 部署與驗證

### 3.1 K3s 部署

- [ ] **由 Mac 編輯** `~/kubernetes/openclaw/overlays/n100/kustomization.yaml`：`2026.10.6` → `2026.10.7`
      （Mac 為唯一編輯來源；N100 只部署不改 manifest）
- [ ] `kubectl kustomize` 預覽確認產出 `ghcr.io/kuniakil/openclaw:2026.10.7`
- [ ] `kubectl apply -k` → rollout status → 新 Pod `1/1 Running`、`RESTARTS 0`
      （⭐ rollout status 若逾時 → 派背景子代理）
- [ ] `~/kubernetes` commit + push；N100 rsync 鏡像同步（Mac / N100 / 線上 Pod 三端一致）

#### 3.1.1 無 migration 驗證

- [ ] 啟動 log **無** `agent database remains degraded` / `MigrationRequired` / `schema version`（grep = 0）
- [ ] 啟動 log **無** `cron/maintenance` 失敗 / `dreaming startup cleanup failed`（grep = 0）
- [ ] `openclaw doctor`（read-only）→ **Doctor complete，無 error 級項目**
- [ ] 線上 agent DB `user_version` = **25**、state DB = **20**（未被升級改寫）
- [ ] agent DB 與 state DB `quick_check` = ok

#### 3.1.2 Plugin 載入驗證

- [ ] **17 plugins**（與 10.6 相同）：`anthropic, canvas, cua-computer, device-pair, file-transfer,
    geolocation, github, google, linux-node, memory-core, microsoft, ollama, openai, talk-voice,
    tavily, telegram, xai`
- [ ] `x` plugin **未載入**（未設定即不啟用，與 10.6 一致）
- [ ] 無 admission 失敗

#### 3.1.3 運行版本

- [ ] 容器內 `/app/package.json` → `2026.10.7`
- [ ] `openclaw --version` → `OpenClaw 2026.10.7`
- [ ] `node --version` → **v24.22.1**（下限未變，應維持）
- [ ] `/health` → **200** `{"ok":true,"status":"live"}`（容器內無 wget/curl → 用 node `fetch`）

#### 3.1.4 行為變更觀察（10.7 新增）

- [ ] standing-intent 工具（`intent`）現在對非 owner 也可能開放（上游移除 `senderIsOwner` 守門）
      → 確認我們的 Telegram session 仍只有 owner 對話，且沒有非授權的 standing intent 被建立
      （`intent` list 為空 / 僅有 owner 建立者）
- [ ] 記憶體搜尋仍可用（**不得**為了驗證而觸發 embedding；索引未重建，預期直接可查）
- [ ] `openclaw sessions list` 正常（10.7 重點修的就是 session recovery）

#### 3.1.5 自訂功能存活

- [ ] `locale -a` → `C.utf8` / **`en_US.utf8`** / **`zh_TW.utf8`**
- [ ] `whisper` → `/usr/local/bin/whisper`；`faster_whisper.__version__` = 1.2.1
- [ ] `edge-tts` → `/usr/local/bin/edge-tts`；`edge_tts.__version__` = 7.3.1
- [ ] `ffmpeg` / `rsync` 存在；`/usr/sbin/sshd` 存在且 listener 運行中
- [ ] `/app/docker/entrypoint-ssh.sh` → executable（0755）
- [ ] Doctor 仍偵測到自訂層：`Local STT auto-selection: whisper`
- [ ] 容器內 `extensions/google/embedding-provider.ts` 仍含 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`
      （我們的 Gemini rate pacing 存活 → 保護配額）

### 3.2 記憶體索引狀態確認（**唯讀，不重建**）

- [ ] 五表計數仍為 chunks 2044 / sources 165 / 向量 2044 / FTS 2044（**不重建、不清 cache**）
- [ ] `memory_embedding_cache` 筆數 ≥ 2936（未再被清空）
- [ ] 近 3 小時 `RESOURCE_EXHAUSTED` = 0（本次升級期間不得出現新的 429）

### 3.3 記憶體趨勢觀察（延續 10.6 觀察項）

- [ ] 冷啟動後 cgroup `memory.current` 取樣 3 次（應落在 ~1.7–2.5 GiB 區間）
- [ ] 以**趨勢**判斷，不以單次 `rss_threshold` 警告升級為事故

### 3.4 回滾備案（本次可單純改 image tag 🟢）

```bash
kubectl -n openclaw set image deployment/openclaw-gateway \
  gateway=ghcr.io/kuniakil/openclaw:2026.10.6
kubectl -n openclaw rollout status deploy/openclaw-gateway
```

- [ ] 確認 10.6 與 10.7 同為 agent schema 25 → **不需要**還原 DB、不需要 doctor
- [ ] 保留路徑（本次不實際回滾）

### 3.5 收尾 — k8s 三端同步

- [ ] Mac commit + push 到 `my-k8s` main
- [ ] N100 rsync 鏡像同步，三端一致（Mac manifest / N100 manifest / 線上 Pod 皆為 2026.10.7）
- [ ] 備份 lifecycle：**提示使用者、等明確確認才刪**
  - A 層 `/home/kuniaki/backup-openclaw-20261023`（869M）→ 到期日 **2026-10-30**
  - B 層 `/data/services/openclaw/.openclaw/tmp/cache-restore-20261023/`（435M）→ 索引連續 3 天穩定後
    （10.23 還原 → 今日 10.26 滿 3 天，**可依此判定**）
  - C 層 Doctor pre-migration bak（241M）→ 同上

---

## 🔖 關鍵參考

- **官方 Release Notes:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.7
- **官方 Changelog:** https://raw.githubusercontent.com/openclaw/openclaw/v2026.10.7/CHANGELOG/2026.10.7.md
- **官方 release SHA:** `157d8c2bc3ea2fa183afdc11088e69690bf8e64e`
- **Schema contract:** `src/state/openclaw-agent-db-contract.ts`（agent = 25）、`src/state/openclaw-state-db-contract.ts`（state = 20）—— 兩者對 10.6 diff 皆為空
- **Image:** `ghcr.io/kuniakil/openclaw:2026.10.7`
- **K3s 部署:** `~/kubernetes/openclaw/overlays/n100/`
- **資料路徑:** `/data/services/openclaw/.openclaw/`（`/home/kuniaki/openclaw` 為其 symlink）
- **SOP 來源:** `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`、`~/.pi/agent/skills/docker-image-rebuild/SKILL.md`
- **上一版 worksheet:** `docs/worksheet-upgrade-openclaw-v2026.10.6-20261023.md`

---

## 📌 本次升級特色

1. **最乾淨的一次**：衝突交叉比對為空、Dockerfile 上游 diff 為空、schema 未動、Node 下限未動。
2. **回滾 = 改 image tag**（同為 agent schema 25），不需要停機 migration、不需要 DB 還原。
3. **最實用的修復**：#160433 修掉「日期翻轉時 Gateway 因過期 temp log 目錄卡在 100% CPU」——
   對我們的長駐 Pod 是直接風險消除。
4. **不需要碰記憶體索引**：schema / embedding 模型 / embedding 輸入格式全部未變 → 不重建、不清 cache，
   避免重蹈 10.6 的配額事故。
5. **唯一觀察項**：standing-intent 工具不再限定 owner（上游刻意決策）。
