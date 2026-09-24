# Worksheet: OpenClaw v2026.9.6 自訂分支升級

> 建立日期：2026-09-24
> 目標：對齊官方 `v2026.9.6`（commit `eb377ac5`，已 fetch 為 `refs/tags/upstream/v2026.9.6`）
> 起點：`my-config-v2026.9.5` HEAD `5f5af13850f`
> 預計新分支：`my-config-v2026.9.6`

---

## 0. 升級前置 — 官方公告必讀審查

### 0.1 官方釋出頁重要警示 ⚠️

- [x] **macOS app 崩潰**：2026.9.6 macOS app 啟動崩潰（[#156861](https://github.com/openclaw/openclaw/issues/156861)），官方已從 Sparkle feed 撤回。預計 2026.9.7 hotfix。
- [x] **對本升級無影響**：本倉庫產出的是 `ghcr.io/kuniakil/openclaw:<version>` Docker image，對應 npm/Gateway 套件，**未受 macOS bug 影響**。
- [x] **無需退回 9.5**：npm 套件 + Gateway 路徑已被官方宣告「unaffected」。

### 0.2 Schema 版本躍升（package.json）

- [x] `state` schema：**17 → 18**
- [x] `agent` schema：**21 → 23**
- [x] 自動遷移保證：#153657 已確保 2026.9.2 之後的升級會自動完成 schema migration。
- [x] 動作：升級後首次啟動前確認 `~/.openclaw/` 已有 schema migration 紀錄（`openclaw doctor` 會報告）。

### 0.3 重大移除（Breaking Removals）

- [x] **Compaction checkpoint controls 已退役**（PR #154131）：
  - 移除 API：`sessions.compaction.list`、`sessions.compaction.branch`、`sessions.compaction.restore`
  - 保留：Fork、rewind、conversation history、compaction summaries、token-savings reporting
  - **無資料清除、無 config migration 必要**
  - **動作**：升級後檢查 `~/.openclaw/config.yaml`、plugin config、`.openclaw/` 下任何 YAML 是否引用上述三個 key；如有需手動移除（預期無，因為這是 v11 之後才有的實驗功能）

### 0.4 新功能（無需手動設定）

- 30 天完整 Usage reporting
- GitHub reader（公開討論 + diffs）
- 遠端 workspace：Files / Memory / Skills
- Optional Decision Models（TypeSafe Jev、本地 choices）
- 聊天模型支援新增：Claude Opus 5.5、GPT-6 Sol / Luna、Grok 4.7

### 0.5 預設值變更

- [x] **Tool Search 預設啟用**（PR #154068）：embedded 與 Copilot run 預設會用結構化 Tool Search。
  - 動作：如要保留舊行為，在 config 設定 `tools.toolSearch: false`。
  - **本倉庫未使用**：我們用的是 Docker Gateway + 自己 host 的 LLM，不會受影響。

### 0.6 Installer / 平台相關

- [x] **FreeBSD**：source install 不再被支援（PR #151227），會引導用戶改用 pkg / npm。**本倉庫不受影響**。
- [x] **Windows**：Node package-manager 失敗會繼續嘗試直到 portable runtime 下載成功。**本倉庫不受影響**。
- [x] **macOS**：見 §0.1。

### 0.7 Docker / 映像大小優化

- [x] npm 安裝少 18 MiB 未用的 Bash parser
- [x] Cloudflare 模板映像移除非必要 Litestream archive
- **本倉庫影響**：Docker 映像理論上會略小，自訂層（locales / rsync / faster-whisper / edge-tts / openssh-server）仍保留。

---

## 1. 自訂 patch 盤點（從 `my-config-v2026.9.5` 取得）

來源 commit：`b53d387ccf5 chore: upgrade to v2026.9.5; restore custom Dockerfile layer, scripts, rate pacing, and TODOs`

### 1.1 Dockerfile 自訂層

- [x] 已確認官方 9.6 仍未包含：locales、rsync、openssh-server、ffmpeg、faster-whisper、edge-tts、whisper CLI
- [x] tini 已是官方預設，本倉保留即可
- 自訂層落在 Dockerfile 第 418 行之後的附加 RUN/COPY 段（`# Custom: Generate UTF-8 locales...`）

### 1.2 自訂檔案清單（需從 `my-config-v2026.9.5` 還原）

- [ ] `assets/whisper`（fast-whisper CLI wrapper，41 行）
- [ ] `docker/entrypoint-ssh.sh`（Zeabur SSH 入口，32 行）
- [ ] `TODO-docker-build-rsync-utf8.md`（升級 checklist）
- [ ] `docs/post-mortem/docker-ci-build-optimization-analysis-20260915.md`（上週事後分析）
- [ ] `docs/worksheet-upgrade-openclaw-v2026.9.5-20260919.md`（前次升級工作表，留作歷史）

### 1.3 修改檔案（需從 `my-config-v2026.9.5` 還原後處理衝突）

- [ ] `.github/workflows/docker-release.yml`（191 行 Matrix 版本，覆蓋官方 700+ 行）
- [ ] `Dockerfile`（46 行自訂層，附加在第 418 行後）
- [ ] `extensions/google/embedding-provider.ts`（Gemini Free Tier 15 RPM queue mutex）
- [ ] `extensions/memory-core/src/memory/manager-embedding-ops.ts`（`gemini` 加入 single-concurrency）
- [ ] `AGENTS.md`（自訂調整）
- [ ] `.gitignore`（自訂調整）

---

## 2. 衝突風險評估

| #   | 風險點                                                   | 等級  | 處理策略                                                                                                                                       |
| --- | -------------------------------------------------------- | ----- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | `embedding-provider.ts` 完全自訂（官方 9.5 與 9.6 皆無） | 🟢 低 | `git checkout my-config-v2026.9.5 -- <file>`                                                                                                   |
| 2   | `manager-embedding-ops.ts` 周圍 imports 變了             | 🟡 中 | 用 `git show my-config-v2026.9.5:extensions/memory-core/src/memory/manager-embedding-ops.ts > /tmp/my.patch` 後手動 port `gemini` 那行到新位置 |
| 3   | Dockerfile 新增 COPY 指令                                | 🟢 低 | 官方新增在前段，自訂層在後段；以整檔還原 Dockerfile（自訂層是「附加」）                                                                        |
| 4   | `package.json` schema 版本                               | 🟢 低 | 官方 tag 自帶 18/23，無需手動處理                                                                                                              |
| 5   | `docker-release.yml` 被官方覆蓋                          | 🟢 低 | `git checkout my-config-v2026.9.5 -- .github/workflows/docker-release.yml`                                                                     |
| 6   | 官方 `compaction checkpoint` 移除                        | 🟢 低 | 不影響本倉庫 config（無使用相關 API）                                                                                                          |

---

## 3. 執行步驟（待用戶 Go-Sign 後才開始）

### Phase A：建立新分支

- [x] **A1** 確認工作區乾淨：`git status -sb` 應只有 `my-config-v2026.9.5` 線乾淨
- [x] **A2** 建立分支：
  ```bash
  git fetch upstream refs/tags/v2026.9.6:refs/tags/upstream/v2026.9.6  # 已完成
  git checkout -b my-config-v2026.9.6 refs/tags/upstream/v2026.9.6
  ```

### Phase B：還原自訂檔案（無衝突）

- [x] **B1** 還原簡單檔案（單行覆蓋即可）：
  ```bash
  git checkout my-config-v2026.9.5 -- \
    assets/whisper \
    docker/entrypoint-ssh.sh \
    TODO-docker-build-rsync-utf8.md \
    AGENTS.md \
    .gitignore
  ```
- [x] **B2** 還原歷史文件（保留歷史紀錄，實際路徑修正為 `docs/openclaw-docker-ci-build-optimization-analysis-20260915.md` 而非 `docs/post-mortem/`）：
  ```bash
  git checkout my-config-v2026.9.5 -- \
    docs/openclaw-docker-ci-build-optimization-analysis-20260915.md
  ```

### Phase C：還原 workflow（覆蓋官方版）

- [x] **C1** 確認官方帶了哪些 workflow：109 個官方 workflow
- [x] **C2** 移除官方除了 `docker-release.yml` 之外的所有 workflow
- [x] **C3** 從 `my-config-v2026.9.5` 還原自訂 Matrix 版本
- [x] **C4** 驗證：`wc -l .github/workflows/docker-release.yml` = **191 行**
- [x] **C5** 提交：commit `bbd4da39500 chore: purge official CI workflows; use optimized matrix docker-release.yml`

### Phase D：還原 Dockerfile 自訂層

- [x] **D1** 整檔還原 Dockerfile（自訂層是附加，會疇在官方版本後面）
- [x] **D2** 驗證自訂層存在：`# Custom:` 計數 = **4**，關鍵字命中 **11 處**
- [x] **D3** 驗證官方 9.6 新增的 COPY 指令：手動補回 3 條 — `cli-root-options.mjs`/`gateway-run-argv.mjs`/`gateway-shutdown-budget.mjs`、`node-host-launcher.mjs`、`scripts/lib/fs-safe-prebuild.mjs`

### Phase E：還原 rate pacing（高風險）

- [x] **E1** 還原 `extensions/google/embedding-provider.ts`：`MIN_GEMINI_EMBEDDING_INTERVAL_MS` 計數 = **2** ✅
- [x] **E2** 還原 `manager-embedding-ops.ts`：**注意 — 不可直接整檔 checkout**（9.6 周圍 imports 變了）；保留 9.6 base，手動 port `gemini` 行到第 186 行的 `resolveMemoryIndexConcurrency`：
  ```ts
  return params.providerId === "ollama" || params.providerId === "gemini"
    ? 1
    : EMBEDDING_INDEX_CONCURRENCY;
  ```
  - 驗證：`grep -c "providerId === \"gemini\"" extensions/memory-core/src/memory/manager-embedding-ops.ts` = **1** ✅

### Phase F：提交自訂 patch

- [x] **F1** 確認 git status
- [x] **F2** 提交：commit `9c5c205aea9 chore: upgrade to v2026.9.6; restore custom Dockerfile layer, scripts, rate pacing, and TODOs`（3 files changed, 127 insertions, 62 deletions）

### Phase G：本地輕量驗證（Mac host 保護）

- [x] **G1** git log 線性：2 commits on `eb377ac59e6` ✅
- [x] **G2** 工作區乾淨（只有 worksheet 未追蹤）✅
- [x] **G3** `docker-release.yml` yaml 解析 OK ✅
- [x] **G4** package.json：`version=2026.9.6 state=18 agent=23` ✅
- [x] **G5** 自訂層完整性：Dockerfile 4 markers / whisper 可執行 / entrypoint-ssh 可執行 / rate pacing 兩檔都就位 ✅
- [x] **G6** **未執行** heavy CI（`pnpm check:changed` / `tsgo:all` / `vitest` / `docker build`）依 Mac host 保護規定

### Phase H：推送與 CI 驗證

- [x] **H1** 推送分支：`my-config-v2026.9.6` → origin ✅
- [x] **H2** 由於 `docker-release.yml` 是 `workflow_dispatch` only，先標 tag 再手動觸發
- [x] **H3** Push tag `v2026.9.6` → origin ✅（commit `9c5c205aea9`）
- [x] **H4** 觸發 GitHub Actions：
  - **Run ID**: `35967326698`
  - **URL**: https://github.com/kuniakil/openclaw/actions/runs/35967326698
  - **狀態**: queued
  - **Event**: `workflow_dispatch`
  - **Branch**: `v2026.9.6`
  - **對照歷史**: my-config-v2026.9.5 (35441426976) 為 success，workflow 設定可用

### Phase I：首次部署檢查（升級後第一次啟動 Gateway 時）

- [ ] **I1** 啟動前執行 `openclaw doctor --fix`（處理 compaction checkpoint 殘留）
- [ ] **I2** 確認 schema migration 已完成：
  ```bash
  openclaw doctor 2>&1 | grep -iE "schema|migration"
  ```
- [ ] **I3** 確認 30-day Usage reporting 在 Web UI 可用
- [ ] **I4** 確認 `~/.openclaw/config.yaml` 沒有 `sessions.compaction.*` 殘留 key

### Phase J：文檔與收尾

- [ ] **J1** CI 綠燈後，更新 CHANGELOG / 任何 owner docs（如有）
- [ ] **J2** CI 綠燈後，把本 worksheet 標記完成並提交
- [ ] **J3** CI 綠燈後，撰寫升級紀錄（預期留實在 `docs/` 或 PR 內）

---

## 4. 預期時間軸

- Phase A-C：~5 分鐘
- Phase D-E：~10 分鐘（含 port 自訂行）
- Phase F-G：~5 分鐘
- Phase H（CI）：~30-60 分鐘（GitHub Actions 編譯）
- Phase I-J：~10 分鐘

總計主動時間約 30 分鐘，被動等待 CI 約 1 小時。

---

## 5. 風險與回退方案

- **若 CI 失敗**：檢查 log，常見原因：
  1. Dockerfile 自訂層語法錯誤 → 對照 `b53d387ccf5` 的 Dockerfile diff
  2. rate pacing 與官方 import 衝突 → 重新 port
  3. workflow 缺少必要 secrets → 確認 `DOCKER_USERNAME` / `DOCKER_PASSWORD` 已設
- **若 runtime 啟動失敗**：回退到 `my-config-v2026.9.5`，並把這次嘗試留作 post-mortem
- **若 macOS bug 復發（不可能但保險）**：本倉庫 image 不含 macOS GUI，不受影響

---

## 6. 待辦：等待用戶 Go-Sign ⏸️

完成 Phase A-J 後，於 `CHANGELOG.md` 或 `docs/post-mortem/` 補一篇 v2026.9.6 升級紀錄（建議於 J3 階段撰寫）。
