# OpenClaw v2026.10.9 升級工作表（2026-10-30）

> 目標：把 `my-config-v2026.10.8`（線上 2026.10.8）對齊官方 `v2026.10.9`，
> 保留自訂 Docker 層、Gemini 限速 patch、精簡 Matrix `docker-release.yml` 與線性歷史。
> 本檔在取得使用者 Go-Sign **之前**只是計畫；Phase 2/3 的 checkbox 於執行時才勾選。

---

## 🚦 執行前提（Go-Sign Gate）

- [x] **使用者已明確核准開始執行 Phase 2**（2026-10-30，並指定「做輕量線上快照」）
- [x] 升級期間不在 Mac 跑 `pnpm check:changed` / `tsgo` / `vitest` / `docker build`（全交給 GitHub Actions）
- [x] 升級期間不執行 `openclaw memory index` / `memory search` / `memory reset` / `agent --local`
- [x] 任何 `gh run watch`（10+ 分鐘）派給背景子代理，主迴圈保持可回應

> [!IMPORTANT]
>
> 1. 本地 `v2026.10.x` tag 都是**自訂 tag**（含我們的 patch）。官方 baseline 已 fetch：
>    - `refs/tags/upstream-v2026.10.9`（SHA `8b18b5578f66eab1501cba4cef2310d88bfb9a41`，與官方 release notes 的 `release SHA` 一致）
>    - `refs/tags/upstream-v2026.10.8`（SHA `dc2523e5a5c7a309517fd7fa834add938231d526`）
> 2. **不可用本地 `v2026.10.8` 當 diff base**；新分支必須從 `upstream-v2026.10.9` 開。
> 3. 採**分支觸發模型**：`--ref my-config-v2026.10.9` + `-f tag=v2026.10.9`，**不** force-push git tag。
> 4. **無 schema 變更** → 回滾 = 改 image tag，不需要 DB 還原。

---

## Phase 1: 分析結果

### 1.1 官方 10.8 → 10.9 差異

| 項目                      | 10.8                           | 10.9                             | 備註                                                          |
| ------------------------- | ------------------------------ | -------------------------------- | ------------------------------------------------------------- |
| `package.json` version    | 2026.10.8                      | **2026.10.9**                    | `package.json` 只有版本號一行變更                             |
| `openclaw.schemaVersions` | state 20 / agent 25            | **state 20 / agent 25（不變）**  | 🟢 **無 migration**，回滾 = 改 image tag                      |
| `updateAdmissionProtocol` | 1                              | **1（不變）**                    | 🟢                                                            |
| `engines.node`            | `>=24.22.1 <25 \|\| >=26.12.1` | **不變**                         | 🟢 線上/容器內皆 `v24.22.1`                                   |
| `packageManager`          | pnpm 12.15.0                   | **不變**                         | 🟢 corepack 自動取得                                          |
| `pnpm-lock.yaml`          | —                              | **+35 / −45（安全相依補丁）**    | 🟡 見 1.2；無新增原生模組，build 會重抓受影響套件             |
| `Dockerfile`              | —                              | **上游 diff = 空**               | 🟢 自訂層零衝突；base image digest 相同                       |
| `extensions/` 目錄數      | 176                            | **176（逐項相同）**              | 🟢 plugin 數維持 17                                           |
| `extensions/` 變更        | —                              | 172 檔 / +977 / −418             | 🟡 多為 `package.json` 版本號；Teams/IMAP 相依更新            |
| `.github/workflows/`      | —                              | 上游仍 **114 個 workflow**       | 🟢 一律 purge；上游動到 2 個 workflow，反正都會被刪           |
| **變更規模**              | —                              | **441 files / +11,800 / −2,044** | 🟡 約為 10.8 的 1/3，多為 `src/infra`、`src/cli`、`src/state` |
| 上游 commits              | —                              | **43**                           | 🟢 官方貢獻紀錄：48 個 PR                                     |

變更熱區（檔案數）：`src/infra` 45、`src/cli` 32、`src/agents` 27、`src/state` 25、
`test/scripts` 23、`.agents/skills` 13、`src/gateway` 10、`scripts/lib` 8。

### 1.2 官方 Release Notes 審查（v2026.10.9）

官方定位：**維護型 release**，主題是「安全相依補丁、復原、資料保留、可靠性」。7 個 Highlights：

1. **安全相依補丁**：`fast-uri` 4.2.3（MCP schema 驗證拒malformed URI）、
   `zod` patch（A2UI / Discord embedded app SDK 大型集合早期拒絕）、
   `nodemailer` 10.1.4（IMAP sender 解析，防偽造 sender 通過 token gate）、
   `@azure/msal-node` 7.1.1（Microsoft Teams）。
   → **本專案有 IMAP / Discord / MCP 路徑**，屬正向安全修補。
2. **`tools.fs.workspaceOnly` 套用到 Gateway-built tools**（delegate 變更仍需審批、
   media tools 留在 workspace 內）。→ 我們 config **未設** `tools.fs` → 無行為改變，
   但 Phase 3 要驗一次 workspace 外的檔案操作是否仍可讀。
3. **憑證不外洩**：MCP CLI inspection 不再帶 live credentials、Google OAuth client secret 在 log 中遮罩。
4. **Update rollback 安全化**：Git-source rollback 保留 operator 修改；npm rollback 重試 Windows 暫時性錯誤。
   → 我們走 image 部署，不適用；但 doctor/狀態修復路徑有連帶改善。
5. **SQLite tokenizer 變更後的復原**（#176234 / #176220 / #176833 / #181206）：
   「FTS5-only `malformed inverted index` 可修」，Node 升/降版造成 `unicode61` tokenization 改變時，
   可重建**衍生 FTS 表**（不動內容、不改 schema）；啟動時可做**一次有界自動修復**（需備份 + 授權檢查）。
   → **與我們的 memory FTS 索引直接相關**（見 1.4）。
6. **大型 transcript archive migration 不再撞 Node string limit**（#170853 / #170847）。
   → **我們有 299 MB / 69 檔的 `session-sqlite-import-archive`**，正是這條修補的目標。
7. **磁碟寫滿後可自動恢復**（不需重啟）。→ 目前磁碟 34%，僅記錄。

**Breaking Changes / Deprecations / 強制 migration**：**無**。
`schemaVersions`、DB 契約常數、DB schema 檔皆未變 → 不需要 migration script、不需要 `doctor --fix`。

> 官方已知告警（與我們無關）：Android APK skipped（`apps/android/version.json` 仍 2026.8.2）。

### 1.3 相依變更明細（`pnpm-lock.yaml`）

| 套件                        | 10.8              | 10.9                  | 影響                                      |
| --------------------------- | ----------------- | --------------------- | ----------------------------------------- |
| `fast-uri`                  | 4.2.1             | **4.2.3**             | MCP schema 驗證（安全）                   |
| `nodemailer`                | 10.0.13           | **10.1.4**            | IMAP sender 解析（安全）                  |
| `@azure/msal-node`          | 5.6.0 / 6.0.1     | **7.1.1**             | Microsoft Teams OAuth（我們未啟用 Teams） |
| `@azure/msal-common`        | 16.13.0 / 16.14.1 | **16.14.3**           | 同上                                      |
| `zod`                       | 3.25.76           | 3.25.76（patch_hash） | A2UI / Discord SDK 大型集合限制           |
| `@discord/embedded-app-sdk` | 2.5.0             | 2.5.0（patch_hash）   | 同上                                      |

→ 全部為**既有套件升級/補丁**，無新增 runtime 相依、無原生編譯需求。build cache 部分失效（正常）。

### 1.4 記憶體 / FTS 索引影響（重點）

```bash
git diff upstream-v2026.10.8 upstream-v2026.10.9 -- \
  packages/memory-host-sdk/ \
  extensions/memory-core/src/memory/embeddings.ts \
  extensions/google/embedding-provider.ts \
  extensions/memory-core/src/memory/manager-embedding-ops.ts
```

結果：

| 檔案                                                     | 變更       | 判定                                                       |
| -------------------------------------------------------- | ---------- | ---------------------------------------------------------- |
| `packages/memory-host-sdk/src/host/memory-schema-fts.ts` | +37 / −16  | 🟡 新增 canonical FTS DDL variants（給修復路徑比對用）     |
| `src/state/openclaw-agent-fts-schema.ts`                 | 新檔（+5） | 🟡 匯出 agent DDL + FTS variants 給 integrity 分類用       |
| `src/infra/sqlite-index-schema.ts`                       | +34 / −?   | 🟡 `repairSqliteIndexCorruption` 支援 **FTS-only rebuild** |
| `extensions/google/embedding-provider.ts`                | **0 行**   | 🟢 Gemini 限速 patch 不受影響                              |
| `extensions/memory-core/.../manager-embedding-ops.ts`    | **0 行**   | 🟢 gemini 併發鎖 1 不受影響                                |
| embedding 模型 / 輸入格式版本                            | **未變**   | 🟢 **不需要重建 embedding 索引**                           |

> **關鍵區別**：這次改的是 **FTS5 全文索引**（derived text index），**不是 embedding**。
> 即使啟動時觸發 FTS `rebuild`，也**不會呼叫 Gemini embedding** → 無 429 配額風險。
> 前提是 Node/SQLite 版本不變（我們維持 `v24.22.1`）→ 預期**不會**觸發；
> Phase 3 仍要 grep 啟動 log 是否出現 FTS repair / quarantine 字樣。

### 1.5 自訂 patch 清單（`my-config-v2026.10.8` 內）

| Commit             | 檔案                                                                                                                  | 內容                                                                                               |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `21942a9a797`      | `.github/workflows/*`（官方 114 → 只留 1 檔）                                                                         | Purge 官方 workflows + 覆蓋 Matrix `docker-release.yml`（191 行）                                  |
| `e693812b9b0`      | `Dockerfile`（+46）、`extensions/google/embedding-provider.ts`、`extensions/memory-core/.../manager-embedding-ops.ts` | 自訂層（locale/rsync/tini/whisper/edge-tts/ffmpeg/sshd）+ Gemini rate pacing + gemini 索引併發鎖 1 |
| `ae70390a569`      | `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`                                       | 自訂資產（0755）                                                                                   |
| 36 個 docs commits | `docs/worksheet-upgrade-openclaw-v2026.10.1..10.8*.md`                                                                | 保留 10.1～10.8 升級歷史                                                                           |

### 1.6 衝突交叉比對

```bash
comm -12 <(git diff --name-only upstream-v2026.10.8 my-config-v2026.10.8 | sort -u) \
         <(git diff --name-only upstream-v2026.10.8 upstream-v2026.10.9 | sort -u)
```

**結果（僅 2 個檔，且兩者都會被 purge 刪除）：**

| 檔                                              | 處置                                |
| ----------------------------------------------- | ----------------------------------- |
| `.github/workflows/full-release-validation.yml` | Phase 2.2 purge 時刪除 → 衝突不存在 |
| `.github/workflows/install-smoke-reusable.yml`  | Phase 2.2 purge 時刪除 → 衝突不存在 |

**自訂非 workflow 檔逐一比對（上游 10.8→10.9 diff）：**

| 檔                                                           | 上游 diff | 判定      |
| ------------------------------------------------------------ | --------- | --------- |
| `Dockerfile`                                                 | **0 行**  | 🟢 零衝突 |
| `extensions/google/embedding-provider.ts`                    | **0 行**  | 🟢 零衝突 |
| `extensions/memory-core/src/memory/manager-embedding-ops.ts` | **0 行**  | 🟢 零衝突 |
| `assets/whisper`                                             | **0 行**  | 🟢 零衝突 |
| `docker/entrypoint-ssh.sh`                                   | **0 行**  | 🟢 零衝突 |
| `TODO-docker-build-rsync-utf8.md`                            | **0 行**  | 🟢 零衝突 |

→ **實質零衝突**（真正要 cherry-pick 的 5 個檔上游完全沒動）。

### 1.7 風險評估：**低**

| 風險類型                    | 等級      | 原因 / 處置                                                                           |
| --------------------------- | --------- | ------------------------------------------------------------------------------------- |
| Schema 中斷                 | 🟢 **無** | `state 20 / agent 25` 未變；回滾 = 改 image tag                                       |
| Node / base image           | 🟢 無     | 下限未變、Dockerfile 未動、`v24.22.1` 不變                                            |
| 自訂 patch                  | 🟢 **零** | 5 個自訂檔上游 diff 全空                                                              |
| 相依                        | 🟡 低     | 安全補丁 + msal-node major bump；Teams 未啟用，無原生模組                             |
| **FTS 索引修復路徑**        | 🟡 低     | 只在 integrity 有 FTS finding 時觸發；Node 未變 → 預期不觸發，Phase 3 查 log          |
| **大型 transcript archive** | 🟡 低     | 我們有 299 MB / 69 檔 archive；10.9 正是為此加 streaming migration，屬正向修補        |
| `tools.fs.workspaceOnly`    | 🟢 無     | config 未設 → 預設行為不變，Phase 3 抽驗一次                                          |
| Plugin                      | 🟢 低     | 176 → 176 目錄，預期仍載入 17 個                                                      |
| Telegram                    | 🟢 無     | 本次未改 Telegram 契約，但仍做一次真實往返驗證                                        |
| **Actions 停用 (422)**      | 🟡 **中** | fork 累計 runs 已超過自動停用量級；處置 = 去 `/<repo>/actions` 橫幅重新啟用（見 2.8） |

### 1.8 線上現況盤點（2026-10-30 唯讀採樣）

```
image        : ghcr.io/kuniakil/openclaw:2026.10.8
pod          : openclaw-gateway-7d44bbf895-8hn8j  1/1 Running  RESTARTS 0  AGE 2d4h
node         : v24.22.1
agent dir    : 539M（含 session-sqlite-import-archive 299M / 69 檔，2 檔 >10M）
tools.fs     : 未設定（undefined）→ workspaceOnly 行為不變
tools.media  : keys = audio, models
session.store / agents.defaults.sessionStore : 未設定 → 走預設路徑
備份         : /home/kuniaki/backup-openclaw-20261028（294M，10.8 升級前快照）
磁碟         : / 586G / 1.8T（34%）
```

---

## Phase 2: 執行步驟

### 2.0 前置檢查

- [x] `git status -sb` → `## my-config-v2026.10.8...origin/my-config-v2026.10.8`（僅本 worksheet 為 untracked）
- [x] 官方 baseline tag 已 fetch
      `bash
  git fetch upstream refs/tags/v2026.10.9:refs/tags/upstream-v2026.10.9 --no-tags
  git rev-parse 'upstream-v2026.10.9^{commit}'   # 8b18b5578f66eab1501cba4cef2310d88bfb9a41
  `
- [x] `schemaVersions` 對比：`10.8 {state:20, agent:25}` == `10.9 {state:20, agent:25}` → **無 migration**
- [x] `engines.node` / `packageManager` / `updateAdmissionProtocol` 對比 → 不變
- [x] 官方 Release Notes 已審閱（無 breaking / 無 migration）
- [x] 衝突交叉比對 → 僅 2 個 workflow（將被 purge）
- [x] Dockerfile 上游 diff = 空
- [x] embedding 相關檔 diff = 空 → **不重建 embedding 索引**
- [x] `extensions/` 目錄清單 176 == 176
- [x] 線上現況盤點（見 1.8）
- [x] 備份決策確認：**使用者指定「做輕量線上快照」**（見 2.5）

### 2.1 建立新分支（從 upstream 10.9 基線）

```bash
git checkout -b my-config-v2026.10.9 'upstream-v2026.10.9^{commit}'
```

- [x] HEAD = `8b18b5578f66`
- [x] `package.json` version = `2026.10.9`、`schemaVersions` = `{state: 20, agent: 25}`
- [x] 確認 `docs/worksheet-upgrade-openclaw-v2026.10.9-20261030.md` 隨 checkout 保留（untracked）

### 2.2 Purge 官方 workflows 並覆蓋 Matrix `docker-release.yml`

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.10.8 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [x] 官方 114 個 workflow → 1（commit `920e37d91b9`）
- [x] `docker-release.yml` 仍為 191 行；`on:` 只有 `workflow_dispatch`；input = **`tag`**（不是 `tag_name`）
- [x] `platforms` 預設 `all`

### 2.3 Cherry-pick 自訂 commits（保留線性歷史）

```bash
git cherry-pick -x e693812b9b0   # Dockerfile + Gemini pacing + gemini 併發鎖
git cherry-pick -x ae70390a569   # assets/whisper + docker/entrypoint-ssh.sh + TODO
# 36 個純 docs commits（10.1～10.8 worksheets）
git cherry-pick -x $(git log --reverse --format=%h upstream-v2026.10.8..my-config-v2026.10.8 -- docs | tr '\n' ' ')
```

- [x] 兩個 code commit **零衝突**（`2066fb0ed81`、`f4a1700886b`；3 + 3 files）
- [x] 36 個 docs commits 全部帶過（只動 `docs/worksheet-*.md`；tip `85e73bee4fd`）
- [x] `git log --merges upstream-v2026.10.9..HEAD` = **0 merge commit**（共 39 commits）

### 2.4 輕量本地驗證（不跑重型 CI）

- [x] `git diff 'upstream-v2026.10.9^{commit}' HEAD --stat -- Dockerfile` → **+46 / −0**（純附加）
- [x] 4 個 `# Custom:` 段落（439 / 458 / 474 / 478）在 `ENV NODE_ENV=production`（486）之前
- [x] base image ARG 仍為 `node:24.22.1-bookworm`（line 16）/ `node:24.22.1-bookworm-slim`（line 17），digest 未變
- [x] `grep -n 'geminiEmbeddingQueue\|MIN_GEMINI_EMBEDDING_INTERVAL_MS'` → 有命中（218 / 219 / 295-298）
- [x] `manager-embedding-ops.ts` 對基線 diff 仍為 **1 行**（+1 / −1）
- [x] `assets/whisper` / `docker/entrypoint-ssh.sh` → `-rwxr-xr-x`
- [x] `git diff 'upstream-v2026.10.9^{commit}' HEAD --stat -- ':!.github'` → **14 檔、+3930 / −62**
      （Dockerfile 46 + TODO 38 + assets 41 + entrypoint 32 + 8 份舊 worksheet + 本次 worksheet + 2 個功能檔）
- [x] 自訂 7 檔（含 `docker-release.yml`）與 `my-config-v2026.10.8` **逐檔 byte-identical**（`git rev-parse` 比對全部 SAME）

### 2.5 備份（建議：輕量線上快照，比照 10.8）

> 無 schema 變更 → 技術上可只靠 image tag 回滾。但本次啟動路徑會碰 FTS 修復與
> transcript archive migration，**建議仍取一份一致快照**（成本 ~1 分鐘、~300 MB）。

- [x] `/home/kuniaki/backup-openclaw-20261030`（**280M**，502 個檔案）
  - [x] 用容器內 `node:sqlite` 的 `backup()` 取 7 個 live SQLite 一致快照（WAL 安全）
  - [x] 7/7 `PRAGMA quick_check` = ok；`user_version` 與線上一致
        （agent 25 / state 20 / quarantine 2 / codex ×4 = 0）
  - [x] 快照大小：agent 234,135,552 B；state 16,269,312 B；quarantine 20,480 B；codex ×4 共 299,008 B
  - [x] `cp -a` / `rsync` 帶走 `openclaw.json`、`openclaw.json.last-good`、`config-journal-fingerprint.key`、
        `credentials/`、`identity/`、`devices/`、`plugin-state/`、`plugins/`、`skills/`、`memory/`、
        `state/`（非 sqlite）、`workspace/`
  - [x] 排除協調鎖 DB（generation-lock / writer / reindex-lock / gateway locks）、
        `workspace/oracle-hunt`、`workspace/worktrees`
  - [x] 容器內暫存目錄 `tmp/backup-20261030` 與 `/tmp/snapshot-openclaw.mjs` 已刪除
  - [x] 快照 `-shm` / `-wal` 空檔已清除（DB 已關閉，重新開啟時會自動建立）
  - [x] 磁碟 `/` 587G / 1.8T（34%）
- [x] 舊備份 `backup-openclaw-20261028` 保留（待 10.9 驗收後再由使用者決定清理）

### 2.6 更新本 worksheet 並 commit

- [x] 勾選 Phase 2 已完成項目 → commit `3dd7277f877`（`docs: add v2026.10.9 upgrade worksheet and mark Phase 2 preparation completed`）

### 2.7 Push 分支

- [x] `git push -u origin my-config-v2026.10.9`
- [x] `origin/my-config-v2026.10.9` == local HEAD == `3dd7277f877fb5fd0cc6cab07210a7e24d70aea2`

### 2.8 觸發 build（分支觸發模型）

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.10.9 -f tag=v2026.10.9 -f platforms=all
```

- [x] dispatch 成功 → **run ID `40998752900`**（未觸發 422，Actions 未被停用）
- [x] `gh run list --workflow=docker-release.yml --limit 1 --json databaseId,event,headBranch,headSha,status`
  - `event` = `workflow_dispatch` ✅
  - `headBranch` = `my-config-v2026.10.9` ✅
  - `headSha` = `3dd7277f877fb5fd0cc6cab07210a7e24d70aea2`（**我們的** commit，非官方 `8b18b5578f66`）✅
- [x] `gh run watch` → conclusion: **success**（⭐ 派背景子代理監看，主迴圈未阻塞）
  - `prepare` ✅ 4s
  - `build-and-push (linux/arm64, ubuntu-24.04-arm)` ✅ 9m24s
  - `build-and-push (linux/amd64, ubuntu-latest)` ✅ 10m38s
  - `merge` ✅ 18s

### 2.9 Build 結果驗證

- [x] 8 個 tag 全部存在：`2026.10.9` ✅ `v2026.10.9` ✅ `2026.10.9-slim` ✅ `v2026.10.9-slim` ✅
      `latest` ✅ `slim` ✅ `main` ✅ `main-slim` ✅
- [x] multi-arch manifest 含 **amd64 + arm64**
  - manifest list digest：`sha256:2a7f4a680fd65396aec9b40c66227271be4aa0b5f16af9da75e74126ec047429`
  - amd64 digest：`sha256:63ce8ae5d5e12645c9c205eab16bc74c0d87185a7f78e8a288940812de8e7622`
  - arm64 digest：`sha256:30e4c04dd679a677f1201558b6c6032a947b573873e9745f7b313cfaa4c7bbe6`

---

## Phase 3: 部署與驗證

### 3.1 K3s 部署

- [x] **Mac 編輯** `~/kubernetes/openclaw/overlays/n100/kustomization.yaml`：`2026.10.8` → `2026.10.9`
- [x] `kubectl kustomize` 預覽 → `ghcr.io/kuniakil/openclaw:2026.10.9`
- [x] Mac commit + push `my-k8s` main（`6b1f671`）→ N100 `git pull origin main`（HEAD `6b1f671`）
- [x] `kubectl apply -k` → `rollout status` → 新 Pod `openclaw-gateway-7759d86874-kq5gc` `1/1 Running`、**RESTARTS 0**
      （image pull 1m30s，image 大小 1,205,690,351 B）
- [x] 三端一致：Mac manifest / N100 manifest / 線上 Pod 皆 `2026.10.9`
  - 線上 `imageID` = `ghcr.io/kuniakil/openclaw@sha256:2a7f4a680fd65396aec9b40c66227271be4aa0b5f16af9da75e74126ec047429`
    （**與 build manifest list digest 完全一致**）
  - Mac / N100 `~/kubernetes` git HEAD 皆 `6b1f671`

#### 3.1.1 無 migration 驗證（含 10.9 新增復原路徑）

- [x] 啟動 log **無** `MigrationRequired` / `schema version` / `agent database remains degraded`（grep = **0**）
- [x] **FTS 專項**：grep `malformed inverted index` / `FTS5` / `rebuild` / `quarantine` = **0**；
      啟動 admission log 明確為 `integrityGateOutcome=healthy`、**`repairedIndexCount=0`**
      → 未觸發任何 FTS 重建（符合預期：Node 仍為 `v24.22.1`）
- [x] **transcript archive 專項**：grep `transcript` / `Invalid string length` / `heap out of memory` = **0**
      → 299 MB archive 未觸發 migration 路徑
- [x] 線上 agent DB `user_version` = **25**、state DB = **20**、quarantine = **2**；三者 `quick_check` = **ok**
- [x] `openclaw doctor --json`（read-only）→ `ok:false` 僅因 2 個 **既有 config warning**（見 3.1.1.1），**error = 0**
- [x] 容器啟動後 25 分鐘：`ERROR|FATAL|panic` = **0**、`RESOURCE_EXHAUSTED` = **0**、`[memory]` = **0**

##### 3.1.1.1 Doctor 兩則 warning（皆為既有 config 狀態，非 10.9 迴歸）

| Warning                           | 歸因                                                                                  |
| --------------------------------- | ------------------------------------------------------------------------------------- |
| `config.plaintext_secrets`        | `skills.entries.web-search.apiKey`、`channels.telegram.botToken` 仍為明碼；與版本無關 |
| `gateway.bind_network_accessible` | `--bind lan`（我們刻意用 K3s Service + Ingress 對外）；既有部署設定                   |

> 本次**不執行** `openclaw doctor --fix`（屬狀態變更，非升級必要項）。明碼 secret 遷移與 bind 策略另案評估。

#### 3.1.2 Plugin / 版本

- [x] Gateway 啟動 log → **17 plugins**（`anthropic, canvas, cua-computer, device-pair, file-transfer,
    geolocation, github, google, linux-node, memory-core, microsoft, ollama, openai, talk-voice,
    tavily, telegram, xai`；14.0s）
- [x] 無 admission 失敗、無 plugin quarantine
- [x] `/app/package.json` = `2026.10.9`、`openclaw --version` = `OpenClaw 2026.10.9`、`node v24.22.1`
- [x] `/health` = 200 `{"ok":true,"status":"live"}`

#### 3.1.3 行為變更觀察（10.9 新增）

- [x] `tools.fs` **未設定** → `workspaceOnly` 新套用邏輯不生效，檔案工具行為不變
      （已由 11:56 的真實 Telegram turn 驗證工具鏈可用）
- [x] `tools.media` keys = `audio, models`（不變）；`whisper` STT 設定仍在
- [x] MCP CLI inspection 憑證隱藏：本次未使用 MCP CLI（無相關操作），僅記錄為安全改善
- [x] `standing_intents` 仍為 **0**
- [x] `openclaw sessions list` → **6** 個 session（`agent:main:main`、
      `agent:main:telegram:default:direct:830338761`、3×cron、1×node）

#### 3.1.4 自訂功能存活

- [x] `locale -a` → **`en_US.utf8`** / **`zh_TW.utf8`**
- [x] `faster_whisper` = **1.2.1**、`edge_tts` = **7.3.1**、`/usr/bin/ffmpeg`、`/usr/bin/rsync`
- [x] `/usr/sbin/sshd` 存在（0755）；`/app/docker/entrypoint-ssh.sh` mode **0755**（938 B）
- [x] Doctor 仍偵測 `Local STT auto-selection: whisper`
- [x] 容器內 `MIN_GEMINI_EMBEDDING_INTERVAL_MS` = **2** 處命中、`provider?.id === "gemini"` = **1** 處命中
- [x] 自訂 7 檔與 `my-config-v2026.10.8` **逐檔 byte-identical**（`git rev-parse` 全部 SAME）

### 3.2 記憶體索引狀態確認（**唯讀，不重建**）

- [x] 五表計數**升級前後完全相同**（以升級前快照 `backup-openclaw-20261030/db/agent.sqlite` 直接比對）

  | 表                        | 升級前快照 | 升級後線上 |
  | ------------------------- | ---------- | ---------- |
  | `memory_index_chunks`     | 1278       | **1278**   |
  | `memory_index_sources`    | 184        | **184**    |
  | `memory_index_chunks_fts` | 1278       | **1278**   |
  | `memory_embedding_cache`  | 3289       | **3289**   |
  | `standing_intents`        | 0          | **0**      |

  > 注：10.8 worksheet 於 2026-10-28 記錄 chunks=2256，本次升級**前**（10-30 11:39 快照）已是 1278，
  > 代表這 2 天內索引曾變動（非本次 10.9 造成）。本次升級前後計數**零差異**，是更強的證據。

- [x] 近 1 小時 `RESOURCE_EXHAUSTED` = **0**、`[memory]` 事件 = **0**（本次升級期間零 embedding 請求）
- [x] 全程未執行 `openclaw memory index` / `memory search` / `memory reset` / `agent --local`

### 3.3 記憶體趨勢觀察

- [x] cgroup `memory.current` 三次取樣：**1,842,098,176 → 2,174,054,400 → 1,803,563,008 B**
      （≈ 1.72–2.02 GiB）→ **低於**升級前 2.4–2.6 GiB 區間，無單調上升
- [x] 啟動 log 有 `MaxListenersExceededWarning`（10.5 起既有現象），非 10.9 迴歸
- [x] 上游 #185578（heap floor）仍為未結案議題 → 不以單點定罪

### 3.4 回滾備案

```bash
kubectl -n openclaw set image deployment/openclaw-gateway \
  gateway=ghcr.io/kuniakil/openclaw:2026.10.8
kubectl -n openclaw rollout status deploy/openclaw-gateway
```

- [x] 確認 10.8 / 10.9 同為 agent schema 25 → **不需**還原 DB、不需 doctor
- [x] `ghcr.io/kuniakil/openclaw:2026.10.8` 仍可解析（`docker buildx imagetools inspect` OK）

### 3.5 Telegram 端到端真實訊息往返

- [x] 使用者實際發訊到 `@N100_openclaw_mike_bot`（**2026-10-30 11:56:38 CST**，direct, 7 chars）
- [x] 完整鏈路：
  - `11:56:38.305` polling 收到 `updateId=596795931`
  - `11:56:38.820` **Inbound message** `telegram:830338761` → `@N100_openclaw_mike_bot`
  - `11:56:41.611` `models.list` 回應（agent turn 進行中）
  - `11:56:46.760` **outbound send ok** `chatId=830338761 messageId=2719 chunkCount=1`
- [x] 期間 `RESOURCE_EXHAUSTED` = **0**、`[memory]` 事件 = **0**

### 3.6 收尾

- [x] Mac / N100 `~/kubernetes` git HEAD 一致（`6b1f671`）；Pod imageID = build manifest digest
- [x] 備份 lifecycle：`backup-openclaw-20261028`（294M）與 `backup-openclaw-20261030`（280M）**皆保留**
      （待使用者決定清理舊份）
- [x] 無 `*.memory-reindex-*` orphan shadow DB；容器內暫存目錄已清除
- [x] 更新本 worksheet 勾選與結果，commit

### 3.7 未結案項（結轉自 10.8）

- [ ] 跨行程 Gemini 限速技術債（module 層級限速；上游未修）
- [ ] MiniMax Token Plan 額度
- [ ] 上游 #185578（heap floor 只增不減）
- [ ] 1 筆 legacy delivery field（`agent:main:main` 的 `session_nodes.entry_json.channel`）
- [ ] Telegram 群組未設定（`channels.telegram.groups` 空）
- [ ] 3 筆 dead-lettered ingress event（歷史殘留）
- [ ] doctor cron 面板 `file lock timeout for openclaw.sqlite.cron-authority`（doctor 獨立行程 vs Gateway 持鎖，非迴歸）
- [ ] **2 個 config warning**（`config.plaintext_secrets`：`web-search.apiKey`、`channels.telegram.botToken` 明碼；
      `gateway.bind_network_accessible`：`--bind lan`）—— 既有部署決策，非 10.9 迴歸；secret 遷移另案評估

---

## 🔖 關鍵參考

- **官方 Release Notes:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.9
- **官方 release SHA:** `8b18b5578f66eab1501cba4cef2310d88bfb9a41`
- **Schema contract:** `src/state/openclaw-agent-db-contract.ts`（agent = 25）、`src/state/openclaw-state-db-contract.ts`（state = 20）
- **Image:** `ghcr.io/kuniakil/openclaw:2026.10.9`
- **Branch:** `my-config-v2026.10.9`
- **K3s 部署:** `~/kubernetes/openclaw/overlays/n100/`
- **資料路徑:** `/data/services/openclaw/.openclaw/`（`/home/kuniaki/openclaw` 為其 symlink）
- **SOP:** `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`、`~/.pi/agent/skills/docker-image-rebuild/SKILL.md`、`~/.pi/agent/skills/k3s-sync-ops/SKILL.md`
- **上一版 worksheet:** `docs/worksheet-upgrade-openclaw-v2026.10.8-20261028.md`

---

## 📌 本次升級特色

1. **零 schema 變更、零自訂檔衝突、零 embedding 變更** —— 回滾仍是改 image tag。
2. **安全相依補丁為主**（fast-uri / nodemailer / zod / msal-node）→ 修補 IMAP sender spoofing、MCP URI 驗證等。
3. **唯一需要盯的啟動路徑**：FTS5 修復（本次新增）與大型 transcript archive streaming migration
   —— 我們有 299 MB archive，屬官方針對性修補；兩者都**不會**觸發 embedding，無 Gemini 配額風險。
4. **風險主要在流程**：fork GitHub Actions 可能已被自動停用（422），處置方式已知（`/actions` 橫幅）。
