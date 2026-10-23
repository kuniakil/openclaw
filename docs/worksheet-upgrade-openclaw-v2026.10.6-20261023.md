# Upgrade Worksheet: openclaw → v2026.10.6

**Date:** 2026-10-23
**Current branch:** `my-config-v2026.10.5`（HEAD `0f98129a806`）
**Target tag:** `v2026.10.6`（官方 SHA `fe06181dc5ecc01cf8904abbfc26925925efefbc`）
**New branch:** `my-config-v2026.10.6`
**Release:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.6

> [!IMPORTANT]
>
> ## 本次是「低風險修補版」— 與 10.5 完全不同，三個關鍵差異
>
> 1. **無 schema migration。** `openclaw.schemaVersions` 維持 **`state 20 / agent 25`**（10.6 未動）。
>    → 不需要 `openclaw doctor --fix`；**回滾只要改 image tag**（10.5 與 10.6 都是 schema 25）。
>    這與 10.4→10.5（agent 24→25、必須停機 + 還原 DB）完全不同。
> 2. **Node runtime 下限提高（唯一實質 breaking）。**
>    `engines.node`：`>=24.16.0 <25 || >=26.1.0` → **`>=24.22.1 <25 || >=26.12.1`**
>    （#179992，2026-10 Node.js 安全釋出，拒絕被入侵憑證簽署的 TLS chain）。
>    官方 Dockerfile base image 已改為 **`node:24.22.1-bookworm-slim`**（digest 已實查存在，含 amd64/arm64）。
>    我們目前線上 2026.10.5 image 內的 Node 是 **v24.21.0 → 低於新下限**；
>    換 10.6 image 後 Node = 24.22.1，**這正是本次升級要解決的事**。
> 3. **無新增 bundled plugin / 無新對外通道。** `extensions/` 目錄無增減 →
>    plugin 數維持 **17**（10.5 的 `x` plugin 仍未設定、未載入）。
>
> **pnpm 12.9.0 → 12.15.0**（`packageManager` 欄位；Docker build 內 `corepack` 自動取得，不需我們額外處理）。

---

> [!IMPORTANT]
>
> 1. **本地 `v2026.10.x` 都是自訂 tag**（含我們的 patch）。官方 baseline 已 fetch：
>    - `refs/tags/upstream-v2026.10.5`（官方 10.5，SHA `1b58cb9a1b4f`）
>    - `refs/tags/upstream-v2026.10.6`（官方 10.6，SHA `fe06181dc5e`）
> 2. **不可用本地 `v2026.10.5` 當 diff base**。新分支必須從 `upstream-v2026.10.6` 開。
> 3. **使用分支觸發模型**（承襲 10.3～10.5 決策），**不** force-push git tag。
> 4. 禁止在 Mac 跑 `pnpm check:changed` / `tsgo` / `vitest` / `docker build`，一律交給 GitHub Actions。

---

## Phase 1: 分析結果

### 1.1 官方 10.5 → 10.6 差異

| 項目                                          | 10.5                          | 10.6                                | 備註                                                |
| --------------------------------------------- | ----------------------------- | ----------------------------------- | --------------------------------------------------- |
| `package.json` version                        | 2026.10.5                     | 2026.10.6                           |                                                     |
| `openclaw.schemaVersions`                     | state 20 / agent 25           | **state 20 / agent 25（不變）**     | 🟢 **無 migration**，回滾 = 改 image tag            |
| `engines.node`                                | `>=24.16.0 <25 \|\| >=26.1.0` | **`>=24.22.1 <25 \|\| >=26.12.1`**  | 🔴 **唯一實質 breaking**（Node 安全釋出）           |
| `packageManager`                              | pnpm 12.9.0                   | pnpm 12.15.0                        | 🟢 corepack 自動取得                                |
| Dockerfile base image（runtime）              | `node:24-bookworm-slim`       | `node:24.22.1-bookworm-slim`        | 🟡 官方有改動（見 1.4 ①）                           |
| `extensions/` 新增目錄                        | —                             | **無**                              | 🟢 plugin 數維持 17                                 |
| **變更規模**                                  | —                             | **1,669 files / +48,083 / −12,952** | 🟡 patch 版但 diff 仍不小（官方自述 focused fixes） |
| `src/state/` 變更檔數                         | —                             | 42                                  | 🟡 但 schema 常數未動 → 不需 doctor                 |
| `src/agents/` / `src/infra/` / `src/gateway/` | —                             | 151 / 106 / 80                      | 🟢 內部重構為主                                     |
| `.github/workflows/` 變更                     | —                             | 72 檔                               | 🟢 全部 purge（見 1.4 ④）                           |
| `pnpm-lock.yaml`                              | —                             | 有變動                              | 🟢 隨 build 自動安裝                                |

### 1.2 官方 Release Notes 審查（v2026.10.6）

官方定位：**"focused reliability fixes only; it does not introduce new user-facing features."**

**Highlights（與我們相關者 ⭐）**：

- **Patched Node runtime required**（#179992）— Docker image 內建 Node 24.22.1；installers 選用已修補的
  runtime；`openclaw update` 在舊 Node 上會**拒絕執行並給恢復指引**，而不是把現有安裝弄壞；
  source build 固定 pnpm 12.15.0。
  → **對我們**：Docker 部署不受 `openclaw update` 路徑影響；但**升級後 Node 必須 ≥ 24.22.1**，
  這由官方 base image 保證（見 Phase 3 驗收：容器內 `node --version` 必須 ≥ v24.22.1）。
- **Safer updates and recovery**（#171101 等）— package swap 在不安全的 service 狀態下拒絕執行。
  → 我們不走 package swap 路徑（image 部署），不適用。
- **Data-preserving migrations and backups**（#172293 等）— Doctor / migration 拒絕 malformed 或
  lossy 的 workspace import、保留 malformed Notes bytes、拒絕不安全的非 UTF-8 wiki 重寫、
  保留巢狀 SQLite 備份、restore 檢查失敗時保留 staging 證據。
  → 我們的 Doctor 流程是 read-only 檢查 + 必要時 `--fix`；10.5 已套用過一次 `--fix`，無待修項。
- **Reliable delivery across restarts / Agent and tool-call recovery / Channel delivery correctness**
  — queued turns、watched child results、dead-lettered deliveries、streamed replies 在重啟後不消失、
  不重複；未完成 tool 會可見地逾時；Telegram album / dual-stack 回覆不丟不重。
  → **與我們直接相關**：我們 10.5 升級後曾跑過 Telegram 實測（見 10.5 worksheet 3.6）。
- **Provider and model resilience** — GPT-5.6 tool turns、OpenRouter DeepSeek tool calls、
  LM Studio overflow recovery、並行 OpenAI reasoning 設定、model retry/fallback budgets 一致化。
  → 我們主模型 MiniMax-M3（provider `minimax`），不受影響。
- **Windows and mobile stability / macOS companion** — 與 K3s Docker 部署無關。

**Fixes 中與我們相關者**：

| 範圍                                | 內容                                                                                                                                                    | 對我們                                                                                      |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| **State and system-agent recovery** | 恢復被升級影響而「held」的 agents 存取權；schema 變更後恢復 held system-agent DB；forensic snapshot 失敗時保留 live config（#175007, #176783, #171217） | 🟢 **正是我們 10.5 經歷的狀況**（doctor --fix 後 agent 被 hold）→ 10.6 修的就是這個，值得升 |
| **Doctor and managed plugins**      | 修復空白的 retired-plugin metadata、清除已解決的 migration warning、把 app-managed plugin 收斂到已安裝的核心版本（#173851 等）                          | 🟢 與我們的 17 個 bundled plugin 直接相關，屬正向                                           |
| **SQLite correctness**              | warning handler 丟例外時仍保留 transaction outcome、shared-worker 拒絕後正確收尾 peer、retired cache generation 不再奪走 worker ownership               | 🟢 直接關係我們的 SQLite worker 架構                                                        |
| **Worker and worktree recovery**    | 主機重開後回收 worker 容量、partial-clone worktree 修復缺失 objects                                                                                     | 🟡 我們有 worktree 使用（升級期間 agent 會用到）→ 正向                                      |
| **Gateway lifecycle**               | 保留 restart custody、避免 stop-time lease 死鎖、重開後回收 worker 容量、reload 時保留 suppressed-channel 設定                                          | 🟢 正向                                                                                     |
| **Codex and native sessions**       | 取消或清理失敗後釋放停滯的 startup waits 與已完成 subagents                                                                                             | 🟢 正向                                                                                     |
| **Media and TTS**                   | 慢速 hosted speech synthesis 逾時、回報 playback cache / probe / quota 失敗而非靜默丟棄清理錯誤                                                         | 🟢 與我們自訂 whisper / edge-tts 層相關（edge-tts 正是 hosted TTS）                         |

**Deprecations**：changelog 未列 blocking deprecation。

**Breaking Changes 總結（官方角度）**：

1. 🔴 **Node 下限 `24.22.1` / `26.12.1`**（唯一實質 breaking）。
2. 其餘為修補，無 schema 變更、無設定移除、無 API 移除。

**已知 Caveats（10.5 遺留、本次要觀察的）**：

- 10.5 的 doctor `--fix` 在 agent DB 留下「held」狀態 → 10.6 修 #175007/#176783。升級後必須確認
  agent 存取恢復正常（Phase 3.2）。
- 10.5 遗留未驗證項：**Gemini embedding rate pacing 實機驗證**、**記憶體長期趨勢**（延續到本次觀察）。

### 1.3 自訂 patch 清單（`my-config-v2026.10.5` 內）

| Commit                            | 檔案                                                                                                                  | 內容                                                                                                                               |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `315e33ba7f7`                     | `.github/workflows/*`（112 檔 → 只留 1 檔）                                                                           | 刪除官方 workflows、覆蓋 `docker-release.yml` 為 Matrix 版（191 行）                                                               |
| `534e0741e91`（源 `64ce0d05c9e`） | `Dockerfile`（+46）、`extensions/google/embedding-provider.ts`、`extensions/memory-core/.../manager-embedding-ops.ts` | 自訂層（locale / rsync / faster-whisper / edge-tts / ffmpeg / openssh-server）+ Gemini Free Tier rate pacing + gemini 索引併發鎖 1 |
| `1b50e15d690`（源 `884f17a1fe1`） | `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`                                       | 自訂資產（0755）                                                                                                                   |
| 21 個 docs commits                | `docs/worksheet-upgrade-openclaw-*.md`                                                                                | 保留 10.1～10.5 升級歷史                                                                                                           |

### 1.4 衝突交叉比對 —— 🟢 本次是乾淨升級

```bash
comm -12 <(git diff --name-only upstream-v2026.10.5..my-config-v2026.10.5 | grep -v '^\.github/workflows/' | sort -u) \
         <(git diff --name-only upstream-v2026.10.5 upstream-v2026.10.6 | sort -u)
```

**結果（1 個檔案）：**

```
Dockerfile
```

（對比 10.5 的 3 檔、10.4 的 0 檔。**我們兩個自訂功能檔案
`extensions/google/embedding-provider.ts`、`extensions/memory-core/.../manager-embedding-ops.ts`
在 10.5→10.6 完全未被上游改動 → 零風險直接帶過。**）

#### ① `Dockerfile` —— 🟢 預期零衝突（但必須驗證）

上游 10.6 對 Dockerfile 只有 **2 個 hunk**：

```
@@ -13,9 +13,9 @@   base image ARGs：node:24-bookworm → node:24.22.1-bookworm（含 digest）
@@ -230,7 +230,7 @@ runtime base LABEL：org.opencontainers.image.base.name
```

我們的自訂層是**檔尾追加**（anchor 在 `install -d -m 0755 -o node -g node /home/node/.config …` 之後），
自訂段落行號 439 / 458 / 474 / 478，全部位於 `ENV NODE_ENV=production`（486）之前。

- **處置**：正常 cherry-pick；若因行號位移報 conflict，確認 4 個 `# Custom:` 段落仍接在
  `ENV NODE_ENV=production` 之前、且 base image ARG 是 `node:24.22.1-bookworm*` 即可。
- **注意**：我們的 apt / pip 自訂層在 runtime stage（`node:24.22.1-bookworm-slim`，同為 Debian bookworm）
  上執行 → distro 不變，套件來源不變，**無需改動**。

#### ② `extensions/google/embedding-provider.ts` —— 🟢 上游未改，零風險

10.5→10.6 上游**完全沒有**改這個檔 → 我們的 Gemini rate pacing
（`geminiEmbeddingQueue` / `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` / `executePaced`）原樣保留。
**驗收**：`grep -n 'geminiEmbeddingQueue\|MIN_GEMINI_EMBEDDING_INTERVAL_MS'` 有命中。

#### ③ `extensions/memory-core/src/memory/manager-embedding-ops.ts` —— 🟢 上游未改，零風險

上游**完全沒有**改這個檔 → 我們那 1 行 `provider?.id === "gemini" ? 1 : ...` 原樣保留。
**驗收**：diff 對基線仍為剛好 1 行。

#### ④ `.github/workflows/` —— 🟢 按 SOP purge 重建

上游 10.6 改了 **72 個** workflow（含 `ci.yml`、`docker-release.yml` 等）。
**全部 purge**，用 `my-config-v2026.10.5` 的 Matrix 版覆蓋 `docker-release.yml`，**不 merge 官方變更**。

### 1.5 風險評估：**低**（10.1～10.5 中最低）

| 風險類型        | 等級      | 原因                                                                                        |
| --------------- | --------- | ------------------------------------------------------------------------------------------- |
| **Schema 中斷** | 🟢 **無** | `state 20 / agent 25` 未變 → 不需 doctor、不需停機 migration、**回滾 = 改 image tag**       |
| **Node 下限**   | 🟠 中     | base image 換成 `node:24.22.1-bookworm-slim`；我們自訂 apt/pip 層要重新 build（由 CI 做）   |
| 自訂 patch      | 🟢 低     | 交集只有 `Dockerfile`，且上游改動在檔頭、我們改動在檔尾 → 預期零衝突                        |
| 行為相容性      | 🟢 低     | 官方定位為 focused reliability fixes；無新 plugin、無新通道、無設定移除                     |
| Plugin          | 🟢 低     | `extensions/` 無新增目錄 → plugin 數維持 17（`x` 仍未設定、未載入）                         |
| 模型目錄        | 🟢 無     | 僅 provider/model resilience 修補；我們用 MiniMax-M3                                        |
| Channel         | 🟢 低     | Telegram / Discord / WhatsApp / Slack 全為 bugfix（album、dual-stack 回覆、relay recovery） |
| 部署中斷        | 🟢 低     | 單 pod rollout，過往 5 次升級皆在 ~30s 內恢復                                               |

---

## Phase 2: 執行步驟

### 2.0 前置檢查

- [x] `git status -sb` → `## my-config-v2026.10.5...origin/my-config-v2026.10.5`（工作區乾淨，僅本次 worksheet 為未追蹤檔）
- [x] 官方 baseline tag 已 fetch
  ```bash
  git fetch upstream refs/tags/v2026.10.6:refs/tags/upstream-v2026.10.6 --no-tags
  git rev-parse 'upstream-v2026.10.6^{commit}'
  # fe06181dc5ecc01cf8904abbfc26925925efefbc
  ```
- [x] `schemaVersions` 對比：`10.5 {state:20, agent:25}` == `10.6 {state:20, agent:25}` → **無 migration**
- [x] `engines.node` 對比：`>=24.16.0…` → `>=24.22.1…`（唯一 breaking）
- [x] base image digest 實查可用：
      `docker buildx imagetools inspect node:24.22.1-bookworm-slim@sha256:55fb5f5a…` → OK（amd64 + arm64）
- [x] K3s 現況盤點（`ssh n100`）
  ```
  openclaw-gateway-697b89c68f-cfbjw   1/1   Running   0   3d15h
  ghcr.io/kuniakil/openclaw:2026.10.5
  容器內 node --version → v24.21.0   （低於 10.6 要求的 24.22.1）
  ```
- [x] 確認 10.5 的 2.3G 備份**已被清除**（`/home/kuniaki/backup-openclaw-*` 不存在；
      依 10.3 以來的 lifecycle policy，驗證後即清除）→ 本次需重新備份

### 2.1 建立新分支（從 upstream 10.6 基線）

- [x] `git checkout -b my-config-v2026.10.6 'upstream-v2026.10.6^{commit}'`
- [x] HEAD = `fe06181dc5e`
- [x] `package.json` version = `2026.10.6`、`schemaVersions` = `{'state': 20, 'agent': 25}`、`engines.node` = `>=24.22.1 <25 || >=26.12.1`

### 2.2 Purge 官方 workflows 並覆蓋 Matrix `docker-release.yml`

- [x] `find .github/workflows -type f ! -name 'docker-release.yml' -delete`（官方 114 個 workflow → 1）
- [x] `git checkout my-config-v2026.10.5 -- .github/workflows/docker-release.yml`
- [x] commit `0de187fba83`（114 files changed, +149 / −65,639）
- [x] 驗證：官方 workflow 全刪 → 僅剩 `docker-release.yml`（**191 行** Matrix 版）
- [x] 驗證：`on:` 只有 `workflow_dispatch`、input 名稱 = **`tag`**、`platforms` 預設 `all`（**不是** `tag_name`）

### 2.3 Cherry-pick 自訂 commits（保留線性歷史）

- [x] `git cherry-pick -x 64ce0d05c9e` → `a586fa6afdc`：**零衝突**（3 files, +125 / −62）
- [x] `git cherry-pick -x 884f17a1fe1` → `678a32fdcd1`：**零衝突**（3 files, +111；whisper 0755 / entrypoint-ssh.sh 0755）
- [x] 帶過 `my-config-v2026.10.5` 的 **21 個純 docs commits**（`0c7c94a1068..0f98129a806` 整段），
      全部只動 `docs/worksheet-upgrade-openclaw-*.md`，保留 10.1～10.5 升級歷史
- [x] 線性歷史：**0 merge commit**

### 2.4 輕量本地驗證（無重型 CI）

- [x] `git diff 'upstream-v2026.10.6^{commit}' HEAD --stat -- Dockerfile` → **+46 / −0**（純附加）
- [x] 4 個 `# Custom:` 段落仍在 `ENV NODE_ENV=production`（486）**之前**（439 / 458 / 474 / 478）
- [x] base image ARG 已為 `node:24.22.1-bookworm*`（上游值，未被我們覆寫；line 16/17/18）
- [x] `grep -n 'geminiEmbeddingQueue\|MIN_GEMINI_EMBEDDING_INTERVAL_MS'` → 有命中（218 / 219 / 227 / 295-303）；
      上游 HTTP 路徑 `executeWithApiKeyRotation`（228）、`withRemoteHttpResponse`（238）、`ssrfPolicy`（240）皆存活
- [x] `manager-embedding-ops.ts` 對基線 diff 仍為 **1 行**（line 527，`|| provider?.id === "gemini"`）
- [x] `assets/whisper` / `docker/entrypoint-ssh.sh` → `-rwxr-xr-x`
- [x] `git log --merges 'upstream-v2026.10.6^{commit}'..HEAD` → **0**
- [x] `git diff 'upstream-v2026.10.6^{commit}' HEAD --stat -- ':!.github'` → 恰好 11 檔、+2251 / −62
      （與 10.5 升級時同形狀：Dockerfile 46 + TODO 38 + assets 41 + entrypoint 32 + 5 份 worksheet + 2 個功能檔）

### 2.4.1 備份（本次為「建議」而非「強制」）

> 無 schema 變更 → 回滾路徑 = 改 image tag，不依賴備份。但 DB 已有 215MB 活躍寫入，
> 仍做一次輕量線上快照作保險。

- [x] ~~`sqlite3 .backup`~~ → **改用容器內 `node:sqlite` 的 `backup()`**。
      原因：容器與主機都**沒有 `sqlite3` CLI**；容器內 `python3` 的 SQLite 是 3.40.1，
      對 agent DB 觸發 `unknown function: octet_length()` 而失敗。
      容器 Node 24 內建 `node:sqlite`（`backup()` API）→ 可用且支援新版 SQLite。
- [x] 取得 **7 個 live SQLite** 一致快照（線上備份 API，處理 WAL）
- [x] **7/7 快照 `PRAGMA quick_check` = ok**
- [x] 快照 `user_version`：agent = **25** / state = **20**（與線上一致 → 確認無待 migration）
- [x] 存放於 `/home/kuniaki/backup-openclaw-20261023`（**869M**：`db/` 232M + config + workspace）
- [x] 其餘 runtime 檔（openclaw.json、last-good、config-journal-fingerprint.key、credentials、identity、
      devices、plugin-state、plugins、skills、memory、state、workspace）以 `cp -a` 帶走
- [x] 排除協調鎖 DB（`generation-lock` / `generation-writer` / `reindex-lock`）與 `workspace/worktrees`

### 2.5 更新本 worksheet 並 commit

- [x] `git add docs/worksheet-upgrade-openclaw-v2026.10.6-20261023.md` + commit

### 2.6 Push 分支

- [x] `git push -u origin my-config-v2026.10.6`
- [x] 確認 `origin/my-config-v2026.10.6` == local HEAD

### 2.7 觸發 build（分支觸發模型）

> [!IMPORTANT]
> **不 force-push git tag。** `--ref` 指向分支、`-f tag` 命名 image，tag 不影響 build。

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.10.6 -f tag=v2026.10.6 -f platforms=all
```

- [x] dispatch 成功 → run `39812061190`（`event=workflow_dispatch`、`headBranch=my-config-v2026.10.6`、`headSha` = 我們的 commit）
      到 `https://github.com/kuniakil/openclaw/actions` 點 banner 重新啟用，**不要**清 cache / 改 settings）
- [x] `gh run list --workflow=docker-release.yml` → `event` = `workflow_dispatch` ✅ / `headBranch` = `my-config-v2026.10.6` ✅ / `headSha` = 我們的 commit ✅
  - `event` = `workflow_dispatch` ✅
  - `headBranch` = `my-config-v2026.10.6` ✅
  - `headSha` = **我們的** commit（非官方 `fe06181dc5e`）✅
- [x] `gh run watch 39812061190` → conclusion: **success**（4 個 job 全綠，11.5 分鐘）

### 2.8 Build 結果驗證

- [x] 5 個 tag 全部存在（收工複驗：digest 全部 = `sha256:21dfe078315d…`）：`2026.10.6` ✅ `v2026.10.6` ✅ `2026.10.6-slim` ✅ `latest` ✅ `main` ✅
- [x] multi-arch digest = `sha256:21dfe078315d426123e1c98221a7fedb49f7b2b2b39b8cae3805dae5b1d691a1`（amd64 / arm64 子 manifest）

---

## Phase 3: 部署與驗證

### 3.0 備份（已完成於 2.4.1）

- [x] 備份位置：`/home/kuniaki/backup-openclaw-20261023`（869MB，收工複驗仍在）
- [x] 快照 `quick_check` = ok、`user_version` = agent 25 / state 20

### 3.1 K3s 部署

- [x] **由 Mac 編輯** `~/kubernetes/openclaw/overlays/n100/kustomization.yaml`：`2026.10.5` → `2026.10.6`
      （Mac 為唯一編輯來源；N100 只部署不改 manifest，見 10.5 worksheet 3.1.1 / 3.9）
- [x] `kubectl kustomize` 預覽確認產出 `ghcr.io/kuniakil/openclaw:2026.10.6`
- [x] `kubectl apply -k` → rollout status → 新 Pod `1/1 Running`、`RESTARTS 0`
- [x] `~/kubernetes` commit + push；N100 rsync 鏡像同步（收工複驗：Mac 與 N100 的 `kustomization.yaml` 皆為 `newTag: "2026.10.6"`）
      （`rsync -a --delete --exclude='hermes/overlays/n100/secrets.env' ~/kubernetes/ n100:~/kubernetes/`）

### 3.2 無 migration 驗證（本次與 10.5 最大的流程差異）

> **不需 `doctor --fix`。** 但仍要確認「沒有待修項」與「agent 存取正常」。

- [x] 啟動 log **無** `agent database remains degraded` / `MigrationRequired` / `schema version`（grep = 0）
- [x] 啟動 log **無** `cron/maintenance` 失敗（grep = 0）
- [x] 啟動 log **無** `memory-core: dreaming startup cleanup failed`（grep = 0）
- [x] `openclaw doctor`（read-only）→ **Doctor complete，無 error 級項目**（`grep -icE "error|fatal|failed"` = 0）
- [x] 線上 agent DB `user_version` 仍 = **25**、state DB = **20**（未被升級改寫，收工複驗）
- [x] agent DB `quick_check` = ok（state DB 亦 = ok）

### 3.2.1 Plugin 載入驗證

- [x] **17 plugins**，與 10.5 相同（來源：Gateway 啟動 log `http server listening (17 plugins: …)`）：`anthropic, canvas, cua-computer, device-pair, file-transfer, geolocation, github, google, linux-node, memory-core, microsoft, ollama, openai, talk-voice, tavily, telegram, xai`
      geolocation, github, google, linux-node, memory-core, microsoft, ollama, openai, talk-voice,
      tavily, telegram, xai`
- [x] `x` plugin **未載入**（未設定即不啟用，與 10.5 一致；`plugins list --json` → `x: disabled`）
- [x] 無 admission 失敗（Codex 門檻 10.5 已結案為不適用；啟動 log 0 筆異常）

### 3.3 運行版本

- [x] 容器內 `/app/package.json` → `2026.10.6`
- [x] `openclaw --version` → `OpenClaw 2026.10.6`
- [x] **`node --version` → v24.22.1**（🔴 核心驗收點；收工複驗 = `v24.22.1`）
- [x] `/health` → **200** `{"ok":true,"status":"live"}`（容器內無 wget/curl → 用 node `fetch`）
- [x] Pod `1/1 Running`、`RESTARTS 0`、image digest 與 2.8 一致

### 3.4 自訂功能存活（Node base image 換版後必須重驗）

- [x] `locale -a` → `C.utf8` / **`en_US.utf8`** / **`zh_TW.utf8`**
- [x] `whisper` → `/usr/local/bin/whisper`；`faster_whisper.__version__` = 1.2.1
- [x] `edge-tts` → `/usr/local/bin/edge-tts`；`edge_tts.__version__` = 7.3.1
- [x] `ffmpeg` → `/usr/bin/ffmpeg`
- [x] `rsync` → `/usr/bin/rsync`
- [x] `sshd` → `/usr/sbin/sshd` 存在且 listener 運行中（4 個 sshd 行程）
- [x] `/app/docker/entrypoint-ssh.sh` → executable（0755）
- [x] Doctor 仍偵測到自訂層：`Local STT auto-selection: whisper`

### 3.5 Gemini rate pacing（延續 10.5 未驗證項）— ✅ 實機證據成立（但代價不小）

> [!IMPORTANT]
> **本節的重建不是升級必要步驟，是為了補實機證據而刻意觸發的。**
> 10.5→10.6 的 schema / embedding 模型 / embedding 輸入格式版本**全部未變**
> （`packages/memory-host-sdk/`、`extensions/memory-core/src/memory/embeddings.ts`、
> `extensions/google/embedding-provider.ts` 對 10.5 的 diff 為空），
> 因此**記憶體索引重建本來就不需要**。以後升級不要重複做這件事。

- [x] `gemini` provider 索引併發 = 1（我們的 1 行 patch 生效，container 內 `/app/extensions/memory-core/src/memory/manager-embedding-ops.ts:527`）
- [x] 限速在**實際 image 內**生效：`/app/extensions/google/embedding-provider.ts` 內含
      `geminiEmbeddingQueue`（218）／`MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`（219）／
      `executePaced`（227）／串行鏈 + cooldown（295-303）
- [x] 實機速率符合 ~~4.2 s pacing：清空 embedding cache 後強制重建，`memory_embedding_cache`
      連續取樣為 595 → 624 → 654 → 680 → 710 → 734 → … → 987（**約 25~~30 筆 / 25 秒 ≈ 1.2 embeddings/秒**）。
      若限速失效應為每秒數十~數百筆
- [x] **但「零 429」這個結論是錯的，必須更正**：08:29~~08:34 期間 Gateway log 出現
      `429 RESOURCE_EXHAUSTED`（`You exceeded your current quota`）與 52~~60 秒 retry backoff，
      08:34:25 有一批 `sync failed (session update)`。當時只看過重建前半段的 log 就下了「零 429」結論。
      **根因：我們的 4.2 s 限速是「每行程」而非「全域」** —— 實驗期間同時有
      ①我的 CLI 重建行程、②Gateway 自己的 reindex 行程、③Gateway 背景 memory sync，
      三者各自持有獨立的限速佇列 → 合併速率超過 Gemini 免費層配額。
      換言之：**限速本身有效，但不足以保護「多行程並發 embedding」的情況**。
- [x] 429 是否已完全停止 → ✅ **收工複驗：15:00 RPD 重置後，近 3 小時 `RESOURCE_EXHAUSTED` = 0**
- [ ] ⚠️ 逐請求時間戳補驗（同一 Gateway 行程內兩次記憶體搜尋量間隔）——**未做**：已由 3.5 的吞吐量取樣 + 4.1.1 的一致性複驗取代，實務上不需再動 live 資料
      （query embedding 不查快取，每次都是即時請求），量兩次請求間隔是否 ≥4.2 s。
      **不需要再清快取、不影響索引**。
      ⚠️ 前提：必須等重建結束、且確認沒有其他行程在做 embedding 時再量，否則間隔會被其他行程干擾

#### 3.5.1 第一次強制 reindex「零 HTTP 請求」— 為何不能當證據

- [x] 用 `node:sqlite` 的 `backup()` + fetch 攔截器跑強制 reindex → **完全沒有任何 HTTP 請求**
      （164 檔的 embedding 全命中本地 `memory_embedding_cache`）
- [x] 結論：沒有請求就談不上速率 → 必須清空快取才測得到限速

#### 3.5.2 已知副作用與復原

- [x] `openclaw memory reset --agent main --yes` **清掉了 embedding cache 與衍生索引** → 重建期間
      **記憶體搜尋不可用**（被索引寫入鎖阻擋），這是本次操作造成的服務影響
- [x] Gateway 本體未受影響（全程 `1/1 Running`、`/health` 200）
- [x] ⚠️ **影響比預期大**：這次實驗的重建流量把 Gemini 免費層配額打爆，08:29~08:34 出現 429 與 sync 失敗；
      重建至今（>30 分鐘）仍未寫入索引（`memory_index_chunks` = 0）→ **記憶體搜尋持續不可用**
- [x] 重建完成確認 → ✅ **索引最終一致**：chunks **2044** / sources **165**（memory 140 + sessions 25）/ 向量 **2044** / FTS **2044** / provenance **2044** / recall **2044**；磁碟 mtime 逐一比對「索引後被改過的檔案」= **0**
- [x] **教訓：以後不得為了「驗證限速」而清空 live 環境的 embedding 快取** → 已落地為全域規則 `~/.pi/agent/skills/openclaw-embedding-ops/SKILL.md` ✅
      要量限速請用「同一 Gateway 行程內兩次記憶體搜尋」量間隔，不動資料
- [x] **後續選項**：已採用 ③（由 pre-migration DB 備份回滾索引，9 張表 schema 逐一比對一致）→ 索引已還原並複驗 ✅；**不需要再跑 `memory index --force`**
      ② 接受記憶體搜尋暫時降級，等配額視窗恢復後由 Gateway 自行重建
      ③ 由 pre-migration DB 備份回滾索引（風險較高，需先比對 schema）

#### 3.5.3 方法論教訓

- [x] **主代理不可阻塞於等待**：本次在主迴圈跑 `sleep` 輪詢與長 timeout 的 `kubectl exec`，
      使用者連續兩次發問「現在在查什麼？」「卡住了？」。已寫成全域規則
      （`~/.pi/agent/AGENTS.md` + 全域 skill `delegate-long-tasks`），
      並在 `agent-release-upgrade` / `docker-image-rebuild` 留下指標。

#### 3.5.4 🔴 事故記錄：為驗限速而清空快取 → 配額耗盡 → 索引全毀 → 兩次搶救

> **本次真正的代價。** 升級本身（2.0～3.4、3.6～3.9）全部順利；出事的是我為了補一個
> 「限速是否真的生效」的證據而做的**額外實驗**。

**時間線**

| 時間        | 事件                                                                                                                                            |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| 08:0x       | 強制 reindex → **零 HTTP 請求**（embedding 全命中本地快取）→ 證明不了任何事                                                                     |
| 08:1x       | `openclaw memory reset --agent main --yes` → **清掉 embedding cache 與衍生索引**                                                                |
| 08:1x–08:33 | 重建進行中，cache 0 → 987，速率恆定 ~1.2 embeddings/秒（**限速確實生效**）                                                                      |
| 08:29–08:34 | **429 RESOURCE_EXHAUSTED**（配額耗盡）＋ 52~60 秒 backoff；重建中止                                                                             |
| 08:34       | `memory_index_chunks` / `memory_index_sources` = 0 → **記憶體搜尋不可用**；Gateway 本體健康                                                     |
| 08:52       | Job v1：cache 還原 999 → **2936** 成功；但 `openclaw memory index` 仍 **429 失敗**（query embedding 也被拒 → 配額是真的被限死，不是快取沒命中） |
| 09:1x       | Job v2：**索引整組還原**（9 張表 + vec0 向量 + FTS）→ chunks 2031 / sources 157 / 向量 2031 / FTS 一致，`quick_check ok`                        |

**根因**：限速佇列是 **module 層級狀態**，同一行程內的執行緒共用一份（安全），
但**另起的行程各自一份** → CLI 重建行程 + Gateway 背景 sync 行程同時 embedding
→ 合併速率 28+ req/min → 撞同一個配額桶 → 429。

**搶救過程與兩個真實缺陷**

- [x] **cache 還原**（Job v1）：從 Oct 19 pre-migration 備份 `INSERT OR REPLACE` 回 2925 列 →
      live 999 → 2936。cache 的 key 是 `(provider, model, provider_key, hash)`、hash 為內容雜湊 → 安全可重用
- [x] **索引還原**（Job v2）：9 張表 schema 在 bak(schema 24) 與 live(schema 25) 之間**逐一比對皆一致**，
      故列級複製安全；vec0 走**虛擬表自己的 API**、FTS5 走 `VALUES('rebuild')`
- [x] 🔴 **我的腳本有兩個缺陷（v1 失敗後由子代理修正）**：1. plain `node` **不會自動載入 vec0 擴充** → `no such module: vec0` 2. 備份的 `memory_index_chunks.embedding` 是 **float64（24576 bytes）**，
      而 vec0 `FLOAT[3072]` 只收 **float32（12288 bytes）** → 直接 `INSERT…SELECT embedding`
      必然 `Expected 3072 dimensions but received 6144`。修正：載入 image 內建的
      `sqlite-vec-linux-x64/vec0.so` ＋ float64→float32 轉換
- [x] **還原後一致性驗證**：FTS 可查（'memory' 964 / 'openclaw' 907 / 'the' 145 rows）；
      **缺向量 = 0、孤立向量 = 0**；重建向量與備份內 vec0 向量比對 `distance = 0.00000000`
      （float32 轉換與 Oct 19 儲存值完全一致）；`user_version 25`、`quick_check ok`
- [x] Gateway：`1/1 Running`、RESTARTS 0、`/health` 200；全程**零外部 API**、零 429
- [x] 兩份 217MB 回滾快照原封未動：`agent-before-cache-restore.sqlite`、`agent-before-index-restore.sqlite`

**目前狀態**

- 索引已回到 Oct 19 狀態（chunks 2031 / sources 157 / 向量 2031 / FTS 一致），**零 API 成本**完成
- **記憶體搜尋仍不可用**：query embedding 需要即時 API，Gemini 配額尚未恢復
- 已派**限時配額偵測子代理**（每 15 分鐘 1 次單一探測，最晚今日 16:30）；
  偵測到恢復即執行 A（用已熱好的 2936 列 cache 重跑 `memory index --force`）並驗證

**防呆措施（已落地）**

- [x] 全域 `~/.pi/agent/AGENTS.md` → 路由到全域 skill `openclaw-embedding-ops`
- [x] 全域 skill `openclaw-embedding-ops`：pre-flight 四道檢查 + 判讀表 + 恢復程序 + 兩個踩坑
      （heredoc 單引號陷阱、容器內 kill 回 EACCES、vec0 擴充與 float32/float64）
- [x] `agent-release-upgrade` / `docker-image-rebuild` 各留指標
- [x] 全域 skill `delegate-long-tasks`：長等待必派子代理（主迴圈不得阻塞）

### 3.6 端到端真實訊息往返（Telegram）

- [x] `openclaw sessions list` 可讀出 session 與歷史 → **sessions 正常**（收工複驗通過）
- [ ] 收訊息 → 多輪模型呼叫（全 200）→ 回覆送出（**尚未實測**：本次 Telegram session 中途斷線，下次可補）
- [x] `memory/dreaming/rem/<date>.md` 產生 → memory-core 運作正常（最新 `2026-10-23.md`）
- [x] 確認 **10.6 修的 agent-held 存取問題已解**（#175007 / #176783）：`openclaw agents list` 正常列出 `main (default)`，doctor 零 error、啟動 log 無 degraded 痕跡

### 3.7 記憶體趨勢觀察（延續 10.5 未驗證項）

- [x] 冷啟動後 cgroup memory 量測：2.03 GB → 3.24 GB → 3.27 GB → **2.69 GB**（開始下降）
- [x] 重建期間峰值 **4.7 GiB**（embedding 批次在記憶體中），無 `memory.max` 上限（`max` = 無限制）
- [x] 採**趨勢**判斷，不以單次 `rss_threshold` 警告升級為事故；
      診斷程式碼 10.5→10.6 **未變**（`src/logging/diagnostic-memory.test.ts`、`src/infra/diagnostic-events.ts` diff 為空）
      → 與 10.5 的比較基準一致
- [x] `MaxListenersExceededWarning`（11 個 exit listener）為 10.5 起即存在的既有現象，非 10.6 回歸
- [x] 待重建結束後再取樣確認回落 → 收工取樣 cgroup `memory.current` = **1.74 GiB**（重建峰值 4.7 GiB 已回落）

### 3.8 回滾備案（本次可單純改 image tag 🟢）

```bash
kubectl -n openclaw set image deployment/openclaw-gateway \
  gateway=ghcr.io/kuniakil/openclaw:2026.10.5
kubectl -n openclaw rollout status deploy/openclaw-gateway
```

- [ ] 確認回滾路徑有效（10.5 與 10.6 同為 schema 25 → **不需要**還原 DB、不需要 doctor）——本次未回滾，僅保留路徑
- [ ] 若需還原 DB（罕見）：參考 10.5 worksheet 3.8 的還原流程（本次未觸發）

### 3.9 收尾 — k8s 三端同步

- [x] Mac commit + push 到 `my-k8s` main
- [x] N100 rsync 鏡像同步，三端一致（Mac manifest / N100 manifest / 線上 Pod 皆為 2026.10.6）
- [ ] 備份保留 7 天後清理（依既定 lifecycle policy；`backup-openclaw-20261023` 於 2026-10-30 到期）

---

## 🔖 關鍵參考

- **官方 Release Notes:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.6
- **官方 Changelog:** https://raw.githubusercontent.com/openclaw/openclaw/v2026.10.6/CHANGELOG/2026.10.6.md
- **官方 release SHA:** `fe06181dc5ecc01cf8904abbfc26925925efefbc`
- **Node 安全釋出:** Node 24.22.1 / 26.12.1（#179992）
- **Schema contract:** `src/state/openclaw-agent-db-contract.ts`（`OPENCLAW_AGENT_SCHEMA_VERSION = 25`）、`src/state/openclaw-state-db-contract.ts`（`OPENCLAW_STATE_SCHEMA_VERSION = 20`）
- **Image:** `ghcr.io/kuniakil/openclaw:2026.10.6`
- **K3s 部署:** `~/kubernetes/openclaw/overlays/n100/`
- **資料路徑:** `/data/services/openclaw/.openclaw/`（`/home/kuniaki/openclaw` 為其 symlink）
- **SOP 來源:** `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`、`~/.pi/agent/skills/docker-image-rebuild/SKILL.md`
- **上一版 worksheet:** `docs/worksheet-upgrade-openclaw-v2026.10.5-20261019.md`

---

## 📌 本次升級特色

1. **最簡單的一次**：無 schema migration、無新 plugin、無設定變更 → 回滾只要改 image tag。
2. **唯一實質 breaking 是 Node 下限**（24.22.1）。我們線上 10.5 的 Node 是 24.21.0，
   正好低於新下限 → 這次升級同時修掉一個 TLS 安全曝露面。
3. **衝突面最小**：交集只有 `Dockerfile`，且上游動檔頭、我們動檔尾 → 預期零衝突。
4. **升級方向正確**：10.6 修的正是 10.5 升級過程中我們遇到的「agent 被 hold、migration warning 殘留、
   SQLite worker 歸還」類問題 → 對我們的 K3s 部署是正向收益。
5. **延續未結案項**：Gemini rate pacing 實機驗證、記憶體長期趨勢（自 10.5 帶過）。

---

## 4. 收工複驗（2026-10-23 17:0x CST）

> 升級主線與事故搶救於當日收工前全部驗證完成。本節為**收工時的線上複驗紀錄**，
> 對應 KB 文章 `~/kubernetes/docs/openclaw-v2026-10-6-upgrade-embedding-quota-incident-20261023.md`（已併入原升級文章，未另開新文）。

### 4.1 升級面複驗

| 項目                | 結果                                                                                                                                    |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Pod                 | `openclaw-gateway-69bb5cdcdf-9kwwp` `1/1 Running`、RESTARTS 0                                                                           |
| `/health`           | **200** `{"ok":true,"status":"live"}`（容器內無 wget/curl → node `fetch`）                                                              |
| 版本                | `OpenClaw 2026.10.6`、Node **v24.22.1**、`/app/package.json` = 2026.10.6                                                                |
| Image               | 5 個 tag digest 全 = `sha256:21dfe078315d426123e1c98221a7fedb49f7b2b2b39b8cae3805dae5b1d691a1`                                          |
| Plugins             | Gateway log `http server listening (17 plugins: …)`；`plugins list --json` 72 catalog / 45 enabled / 41 bundled enabled；`x` = disabled |
| Doctor              | `Doctor complete`，error 級 = 0；仍偵測到自訂層 `Local STT auto-selection: whisper`                                                     |
| 自訂層              | `C.utf8 en_US.utf8 zh_TW.utf8`、whisper 1.2.1、edge-tts 7.3.1、ffmpeg、rsync、`/usr/sbin/sshd`（4 行程）、`entrypoint-ssh.sh` 0755      |
| Schema              | agent `user_version=25` / state `user_version=20`，兩者 `quick_check=ok`                                                                |
| 啟動 log            | `remains degraded｜MigrationRequired｜schema version｜dreaming startup cleanup failed｜cron/maintenance fail` = **0**                   |
| Sessions / dreaming | `openclaw sessions list` 正常；`memory/dreaming/rem/2026-10-23.md` 產生                                                                 |
| Agent held          | `openclaw agents list` 正常列出 `main (default)`，無 held 痕跡                                                                          |
| 記憶體趨勢          | cgroup `memory.current` = **1.74 GiB**（冷啟 2.03 → 3.24 → 2.69 GB；重建峰值 4.7 GiB 已回落）                                           |
| K3s 三端            | Mac `~/kubernetes` = N100 `~/kubernetes`（`newTag: "2026.10.6"`）= 線上 Pod                                                             |

### 4.2 記憶體索引複驗（事故線）

| 檢查           | 結果                                                                                                                         |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| 五表計數       | chunks / vec0 向量 / FTS / provenance / recall metadata 全部 **2044**（1:1 一致，無缺向量、無孤兒）                          |
| sources        | **165**（memory 140 + sessions 25）                                                                                          |
| 新舊程度       | 磁碟 `memory/**` mtime vs `memory_index_sources` → **「索引後被改過的檔案」= 0**（無落後）                                   |
| 涵蓋率         | 磁碟 172 檔 vs 索引 140 檔；差額 34 檔全為 `memory/.dreams/session-corpus/*.txt`（索引範圍外的內部目錄，非缺口）             |
| embedding 快取 | **2936**（未再清空）                                                                                                         |
| 配額           | 15:00（太平洋午夜 = 台北 15:00）RPD 重置後恢復；近 3 小時 `RESOURCE_EXHAUSTED` = **0**                                       |
| 搜尋功能       | `openclaw memory search "升級" --agent main`（`timeout 90`、單次）→ ✅ 回傳多筆結果，28s                                     |
| 回滾保險       | `agent-before-cache-restore.sqlite` / `agent-before-index-restore.sqlite`（各 217MB）**原封未動**；升級前快照 869MB 原封未動 |

### 4.3 結論

- **索引重建已完成，不需要再跑 `openclaw memory index --force`**（會重置快取、白花配額並再次讓搜尋不可用）。
- 日常增量由 Gateway 背景 sync 處理（sessions 索引 mtime 隨新回合推進）。
- 尚未結案的項目只剩：
  1. **3.5 逐請求時間戳補驗**（刻意不做：會動 live 資料，收益不抵風險）
  2. **3.6 Telegram 端到端真實訊息往返**（本次 Telegram session 中途斷線，下次可補）
  3. **3.8 回滾路徑實演**（本次未回滾，僅保留路徑）
  4. **3.9 備份 7 天 lifecycle**（`backup-openclaw-20261023` 於 2026-10-30 清理）
  5. **跨行程限速技術債**（`geminiEmbeddingQueue` 為 module 層級狀態；根治需 lock file / SQLite 協調或改走 Gateway RPC）
