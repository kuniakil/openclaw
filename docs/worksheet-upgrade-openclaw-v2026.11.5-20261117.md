# OpenClaw 升級工作表：v2026.11.4 → v2026.11.5

- 日期：2026-11-17
- 目前分支：`my-config-v2026.11.4`（HEAD `bdf0b1cd637`）
- 目標：`v2026.11.5`（發佈 2026-11-17 10:47 UTC，stable，非 prerelease）
  - upstream commit：`e13cf15ece9bbd969b7362927c315362c90c97ff`（`upstream-v2026.11.5`）
  - 前一版 baseline：`upstream-v2026.11.4` = `d843d6af39a42cd3c30084edbeabeece732fd93a`
- 新分支：`my-config-v2026.11.5`
- 目標 Image：`ghcr.io/kuniakil/openclaw:2026.11.5`
- 線上現況：`ghcr.io/kuniakil/openclaw:2026.11.4`，Pod `openclaw-gateway-694894b6b7-f864f`（1/1 Running）

---

## 摘要（先讀這段）

| 項目                 | 結論                                                                                                                                                                                                        |
| :------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 目標版本             | `v2026.11.5`（npm `latest` 已為 2026.11.5，release 發佈 2026-11-17 10:47 UTC，stable）                                                                                                                      |
| 升級性質             | **中型功能升級，不是 patch**（上游 11.4 → 11.5 為兩條分歧歷史，見 §1.2）                                                                                                                                    |
| 不可逆點             | **state schema 22→36、agent schema 27→38** → 升級前完整備份為強制（§1.3）                                                                                                                                   |
| 自訂 patch 可移植性  | Dockerfile / Gemini 限速 / 並發鎖 / assets / SSH → **零衝突**；CJK bigram 索引 → **舊 11.4 commit 不能用；改 cherry-pick PR #193815 的 `ce792e38b54`（乾跑僅 3 個衝突，其中 2 個為生成檔）**（§1.5 / §1.7） |
| 上游 breaking change | 1 項（#175837 harness/plugin session 控制）→ **對我們無影響**（無自建 harness／plugin）                                                                                                                     |
| 已知上游 bug 影響    | #200583（升級後首次啟動 SQLite I/O error，重啟即恢復）、#200629（cron 復原修正不在 11.5）、#200557（Gateway 運作時 memory CLI 不可用）（§1.9）                                                              |
| Base image           | **bookworm → trixie**（Debian 13 / Python 3.13）→ 我們的自訂層自動合併但需實機驗證（§1.8）                                                                                                                  |
| CJK 策略決議         | **已拍板採方案 B（保留 CJK 伴隨索引）**：在上游尚未合入 PR [#193815](https://github.com/openclaw/openclaw/pull/193815) 前，升級維持保留自訂實作（§1.7）                                                     |
| 目前狀態             | Phase 1 完成（方案 B 已定案），**等待 Phase 2 Go-Sign**（尚未建立分支、未推送、未觸發建置、未動線上）                                                                                                       |

---

## 🚦 Go-Sign Gate

- [x] Phase 1 完成官方 Release Notes、`schemaVersions` 與衝突乾跑分析
- [x] **CJK Han Bigram 伴隨索引策略拍板：採方案 B（在 11.5 保留實作，參考 PR #193815 `ce792e38b54` 對齊）**
- [ ] 使用者明確核准執行 Phase 2（Go-Sign）← **等待中**
- [x] 不在 Mac 本機跑重型 CI（`tsgo`/`vitest`）或本機 `docker build`（全交 GitHub Actions）
- [x] 升級期間不另起 `openclaw memory index/search/reset`、`agent --local`（避免雙行程撞 Gemini 配額）
- [x] 10+ 分鐘長等待（`gh run watch`、`kubectl rollout status`）一律派給背景子代理

---

## Phase 1: 分析結果

### 1.1 官方 Release Notes 摘要（351 PRs，範圍 `90a5029e4278..a1f3f16e7b2e`）

**Breaking changes（1 項）**

- **#175837 — harness 與 plugin 的 session 控制契約變更**
  - 第三方 harness 必須在 host 的 `runAttempt` callback 內註冊 session-keyed active runs，並保留回傳的 cleanup function。
  - Plugin RPC handler 必須以 authorized Gateway method dispatch 取代 `chatAbortControllers` / `chatQueuedTurns`。
  - Start-owner observation 欄位由 `expiresAtMs` 改為 `startDeadlineAtMs`；上游註明 bundled consumers 已一併遷移。
  - **對我們的影響：無。** 我們沒有自建 harness／自建 plugin；映像僅內建 `OPENCLAW_EXTENSIONS=diagnostics-otel,codex`（皆為上游 bundled extension），無自撰 plugin RPC handler。

**其他重點（與本部署相關）**

- **Restart-safe conversations**：queued messages、send permissions、最終 chat write 於 Gateway 重啟後保留（#196923 / #196540 / #196493）→ 直接改善「維護／升級時對話中斷」風險。
- **Safer updates**：Doctor 或 Gateway 啟動失敗會回滾已套用的 update；還原後的 npm package 對非 root service 仍可讀（#197851 / #193272）。
- **Telegram widgets**：互動 widget 可在 Telegram 訊息中渲染，含私聊 topic（#196991 / #198022）。
- **Telegram 回覆與審批**：ACP 回覆在 progress-stream 模式恢復；審批留在私聊或 forum topic（#197191 / #198038 / #192162）。
- **Telegram hooks**：delivery hook 取得 runtime session key；disabled 按鈕以 non-interactive 渲染（#197519 / #191647）。
- **Faster memory recovery**：大型 memory-index 重建更可靠；embedding indexing 可從 gateway 截斷的 batch-limit 錯誤中恢復（#196378 / #187797）→ 對我們的 Gemini embedding 流程有直接價值。
- **Model fallback**：已設定的 primary account 不再阻擋 Claude CLI fallback；OpenAI session 可從 compaction item 衝突恢復（#198427 / #198357）。
- **Cron**：排程 account 選擇、重試期限、completion-run identity 保留；late scheduler wakeup 不再靜默丟 job（#180677 / #197449 / #197484）。
- **Doctor 與升級**：Doctor 啟動等待有上限、處理 SIGTERM；升級期間 DB 還原可用、容忍無害的 empty-WAL 轉換、Gateway 啟動成功後才進行 post-update 檢查（#192083 / #193134 / #192942 / #187936 / #191125）。
- **Memory / SQLite**：避免重複 Dreaming inventory 讀取、釋放完成的 SQLite reader、避免 cursor 重啟（#180692 / #190242）。

**無 breaking config 變更**：`memory.search` 新增欄位皆為 optional（`extraPaths[].evergreen`、`inputFormat`、`queryInstruction`），既有設定相容。

### 1.2 關鍵發現 A：上游 tag 歷史分歧（diverged）

GitHub 官方 compare API 對 `v2026.11.4...v2026.11.5` 的結果為：

```
status = "diverged"    ahead_by = 11811    behind_by = 1779
```

- `v2026.11.4` 與 `v2026.11.5` **沒有祖先關係**，共同祖先是 `459cad765304`（2026-10-14）。
- `upstream/main`（`a3dd700bb86`）與兩者皆無祖先關係，其 `package.json` version 仍為 `2026.11.4`、schemaVersions 為 `{state:40, agent:42}`（**高於** 11.5 tag 的 `{36, 38}`）。
- 影響：`git diff upstream-v2026.11.4 upstream-v2026.11.5` 高達 45,871 檔／11,811 commits，**不是**語意上的 11.4→11.5 差異。不可用該 diff 判斷「上游改了什麼」，也不可假設「11.5 ＝ 11.4 + 351 PRs」。
- 實務結論：
  1. 本次升級必須視為**中型功能升級**（非 patch），風險等級高於 11.3→11.4。
  2. 官方 release notes 的「Shipped baseline exclusions」已列出 v2026.11.1（39 PRs）、v2026.11.2（8）、v2026.11.3（0）、v2026.11.4（41）→ 內容層面 11.5 **涵蓋**已發佈的 11.1–11.4。
  3. 我們的實機 11.4 具體功能（串流 session 匯出、`manager-embedding-ops.ts` 的 `streamSessionEntry` / `prepareIndexEntry`）在 11.5 tree 中確認仍存在（逐項比對見 §1.6）。

### 1.3 關鍵發現 B：schemaVersions 變更（不可逆）

| 版本                     | `openclaw.schemaVersions.state` | `openclaw.schemaVersions.agent` |
| :----------------------- | :------------------------------ | :------------------------------ |
| `v2026.11.4`（現行線上） | 22                              | 27                              |
| `v2026.11.5`（目標）     | **36**                          | **38**                          |

- 這是**不可逆**的狀態資料庫遷移：state 22→36、agent 27→38。
- **舊的 11.4 映像無法讀取升級後的資料庫**；單純把 image tag 改回去 ≠ 回滾。
- 因此 **升級前完整備份為強制項目**（非選用），且回滾必須同時還原備份。
- 沿用 `v2026.9.5`（schema 19/20→21）已驗證的做法：`scale 0` → 一次性維護 Pod 執行 `openclaw doctor --fix` 完成遷移 → `scale 1` 上線（見 `~/kubernetes/docs/openclaw-upgrade-v2026.9.5-schema21-guide-20260919.md`）。

**將於本次升級執行的遷移（上游 `STATE_SCHEMA_MIGRATION_DESCRIPTIONS` 對照）**

state 22 → 36 會依序套用：`meeting-transcript-start-time` → `task-run-indexes-v24` → `subagent-operator-recovery-v25` → `session-state-head-layout-v26` → `state-write-indexes-v27` → `github-publication-draft-v28` → `local-client-credentials-v29` → **`automation-policy-fence-v30`（Heartbeat monitors → 一般 automation 的時序與投遞政策柵欄）** → `local-workspace-manifests-v31` → `local-workspace-cas-v35` → `template-names-v36`。

> ⚠️ **v30 heartbeat → automation 折疊會改變 cron／automation 資料**：我們線上有 `Memory Dreaming Promotion` 等排程，升級後需比對 cron job 清單是否新增、重複或遺失（並對應上游 issue #200224 的 heartbeat 設定遷移）。

agent 27 → 38 對應 `AGENT_*_SCHEMA_VERSION`：`write-layout-v28` → `index-retirement-v29` → `trajectory-storage-v30` → `memory-revision-v31` → `vector-decoder-v32` → `vector-search-v33` → `cold-archive-chunks-v37` → **`text-search-v38`（`AGENT_TEXT_SEARCH_SCHEMA_VERSION`，即 FTS／文字搜尋層整體改版）**。

> ⚠️ **agent v38 會重建記憶索引的 FTS 腿** → `memory_index_chunks` 的 `chunk_rowid` 可能改變：
>
> - 已決議方案 B（保留伴隨索引）：PR #193815 版本的伴隨表以 row-count 比對判定是否重建（canonical vs derived count），**若 agent v38 重建後筆數相同但 `chunk_rowid` 已改變，可能靜默指向錯誤的 chunk** → 部署後須驗證 CJK 查詢結果正確（§2.9），必要時以 `ensureMemoryIndexSchema` force rebuild（零 embedding 呼叫）。

### 1.4 自訂 Patch 清單（`upstream-v2026.11.4..my-config-v2026.11.4`）

| Commit                                | 內容                                                                                                                                                                                   | 需移植的檔案                                                                                                                                                                                                                                           |
| :------------------------------------ | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `605cf3c8f06`                         | 精簡 Matrix `.github/workflows/docker-release.yml` + 清除其餘官方 workflows                                                                                                            | `.github/workflows/**`                                                                                                                                                                                                                                 |
| `2fe158be6d6`                         | Dockerfile 自訂層（locale / rsync / tini / faster-whisper / edge-tts / ffmpeg / openssh-server）+ Gemini 限速 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` + Gemini index concurrency = 1 | `Dockerfile`、`extensions/google/embedding-provider.ts`、`extensions/memory-core/src/memory/manager-embedding-ops.ts`、`TODO-docker-build-rsync-utf8.md`                                                                                               |
| `d442939fd66`                         | `assets/whisper`、`docker/entrypoint-ssh.sh`                                                                                                                                           | 新增檔（上游無）                                                                                                                                                                                                                                       |
| `403fa5afb14`                         | CJK Han bigram 伴隨 FTS 索引（19 檔）                                                                                                                                                  | `extensions/memory-core/**`、`packages/memory-host-sdk/**`、`src/agents/memory-search.ts`、`src/config/zod-schema.memory-search.ts`、`src/infra/database-engine/sqlite-memory-search-fragments.ts`、`src/plugin-sdk/memory-core-host-engine-schema.ts` |
| `652dab92b65`                         | `docs/reference/memory-config.md` CJK bigram 文件                                                                                                                                      | 文件                                                                                                                                                                                                                                                   |
| `58c1af585bb` + 4 個 worksheet commit | 歷史升級工作表                                                                                                                                                                         | `docs/worksheet-upgrade-openclaw-v2026.*.md`                                                                                                                                                                                                           |

### 1.5 衝突乾跑（`git merge-tree --write-tree` + 實際 cherry-pick 乾跑）

以 `--merge-base=upstream-v2026.11.4` 模擬「把我們的 11.4 自訂 diff 套到 11.5」，並在 `/tmp` 臨時 worktree（detached HEAD @ `upstream-v2026.11.5`）實際執行 `git cherry-pick -n` 逐一驗證（已於分析後移除，working tree 乾淨）：

| 乾跑對象                                                      | 結果                   |
| :------------------------------------------------------------ | :--------------------- |
| `2fe158be6d6`（Dockerfile + Gemini 限速 + 併發鎖）            | **零衝突**             |
| `d442939fd66`（`assets/whisper`、`docker/entrypoint-ssh.sh`） | **零衝突**（純新增檔） |
| `403fa5afb14`（CJK bigram 19 檔）                             | **8 個衝突**（下表）   |
| `652dab92b65`（memory-config.md）                             | **零衝突**             |
| `58c1af585bb`（歷史工作表）                                   | **零衝突**             |

- **Workflows：107 個 modify/delete 衝突** → 預期，依 SOP 直接 purge 並覆蓋我們的 Matrix `docker-release.yml`。

> ⚠️ **以下為舊 commit `403fa5afb14` 的乾跑結果（已不採用）**：8 個衝突全部落在 CJK bigram 索引，且上游 11.5 已**重寫整個 FTS／搜尋層**（raw `MATCH` 字串 → `TextQuery` 結構化查詢引擎、`memory-schema-fts.ts` 刪除並下移至 `src/infra/database-engine/sqlite-search-schema.ts`、`manager-keyword-retrieval.ts` 拆成 `manager-search-retrieval.ts` + `manager-search.worker.ts`、引入 generated schema fingerprint）。
> **結論：舊 11.4 CJK commit 不移植；改採 PR #193815 的 `ce792e38b54`（已對齊新 FTS 架構）。** 乾跑實測（臨時 worktree，已移除）：`git cherry-pick -n ce792e38b54` 到 `upstream-v2026.11.5` 僅 **3 個衝突**：`docs/.generated/config-baseline.counts.json`、`docs/.generated/config-baseline.sha256`（生成檔，重跑 `pnpm config:docs:gen`）與 `extensions/memory-core/src/memory/manager-search-types.ts`（小檔，手動合併）。注意該 commit 基於 main（schema 40/42，非 11.5 的 36/38），能套用不代表執行期正確，需 §2.9 驗證。見 §1.7。
> 以下 8 個衝突清單僅供歷史參考。

- **程式碼：8 個真衝突**（全在 CJK FTS 區域）：

| #   | 檔案                                                               | 衝突型態      | 處置方向                                                            |
| :-- | :----------------------------------------------------------------- | :------------ | :------------------------------------------------------------------ |
| 1   | `extensions/memory-core/src/memory/keyword-query.ts`               | content       | 依上游 11.5 查詢重構重新套用 bigram 分支                            |
| 2   | `extensions/memory-core/src/memory/manager-db-kernel.ts`           | content       | 同上（schema/table 建立路徑）                                       |
| 3   | `extensions/memory-core/src/memory/manager-publication-task.ts`    | content       | 同步 bigram 寫入路徑                                                |
| 4   | `extensions/memory-core/src/memory/manager-source-index-kernel.ts` | content       | 同上                                                                |
| 5   | `extensions/memory-core/src/memory/manager-sync-ops.ts`            | content       | 同上                                                                |
| 6   | `packages/memory-host-sdk/src/host/memory-schema-fts.ts`           | modify/delete | **上游 11.5 已刪除此檔**（內容併入 `memory-schema.ts`）→ 需跟著搬移 |
| 7   | `packages/memory-host-sdk/src/host/memory-schema.ts`               | content       | 把 CJK FTS table 常數與 trigger 定義併入上游新結構                  |
| 8   | `src/infra/database-engine/sqlite-memory-search-fragments.ts`      | content       | bigram SQL fragment 對齊新 schema                                   |

- **自動無衝突合併（已驗證 merged tree 內容）**：
  - `Dockerfile` → 4 段 `# Custom:` 層完整保留，且 base image 已由上游更新為 trixie。
  - `extensions/google/embedding-provider.ts` → `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` 保留（L226 / L305）。
  - `extensions/memory-core/src/memory/manager-embedding-ops.ts` → `provider?.id === "gemini"` 併發鎖 1 保留（L453–455）。
  - `packages/memory-host-sdk/src/host/cjk-bigram.ts` → 新檔保留（該檔本身為 self-contained，可原樣沿用於方案 B）。
  - `extensions/memory-core/src/memory/manager-keyword-retrieval.ts` → 上游改名為 `manager-search-retrieval.ts`，git 偵測到 rename 並自動帶入我們的 `MEMORY_INDEX_CJK_FTS_TABLE` 串接；**但上游已把 FTS 查詢改為 `TextQuery` 結構化查詢，該自動結果在語意上已過時，僅供參考。**
  - `src/config/zod-schema.memory-search.ts` → `memory.search.store.fts.cjk: "bigram"` 可自動保留（方案 A 已捨棄）。
  - `docs/reference/memory-config.md` → 自動合併。

### 1.6 11.4 已發佈功能是否仍存在於 11.5（內容累計性抽查）

- [x] `extensions/memory-core/src/memory/manager-embedding-ops.ts`：`streamSessionEntry` / `prepareIndexEntry` → 11.5 中命中 3 處 ✅
- [x] **Gemini tool schema 省略非字串 `enum`** → 11.5 以**不同實作**保留同一行為（`packages/ai/src/providers/clean-for-gemini.ts`：11.4 的 `cleanGeminiEnumValues()` helper 在 11.5 改為 cleaning loop 內直接判斷 `type === "string"`，非字串 schema 直接不複製 `enum`，註解明寫「drop their enum so tool argument generation and runtime validation still agree」）✅ 行為保留、程式碼已重寫
- [ ] 線上 `openclaw.json` 的 `memory.search.store.fts = { tokenizer: "trigram", cjk: "bigram" }`：方案 B 保留不動；待 §2.4 cherry-pick 後確認 11.5 zod 保留 `cjk` 鍵
- [x] Telegram inline button / `callback_query` 路由 → 11.5 `extensions/telegram/src/bot-handlers.runtime.ts` 等仍在 ✅
- [x] 記憶索引串流匯出（避免 worker OOM）→ 11.5 `manager-embedding-ops.ts` 保留 ✅

**量化補充（自我驗證，非官方聲明）**：把 11.3→11.4 期間新增的原始碼行（去測試檔）比對 11.5 tree，**逐行相同者約 58%**。剩餘差異主要是上游在 main 線上持續一個月的重構（函式被改名／搬移／改寫），不等於功能消失（`clean-for-gemini.ts` 即為實例）。→ **判讀原則：11.5 是「功能上大致累計、原始碼已重寫」，不可用逐行 diff 判斷功能增減。**

### 1.7 CJK Han Bigram 伴隨索引：生產現況與方案決議（✅ 已拍板：方案 B）

**生產現況（已於 N100 實機確認，非推測）**

- 線上 `openclaw.json`：`memory.search.store.fts = { "tokenizer": "trigram", "cjk": "bigram" }` → **雙開關皆啟用**，我們的伴隨索引**在正式環境是生效的**。
- 線上 agent DB 實際存在 `memory_index_chunks_cjk_fts`（含 `_config/_content/_data/_docsize/_idx` shadow tables），筆數 **1467**，與 `memory_index_chunks`（1467）、`memory_index_chunks_fts`（1467）一致。
- 功能價值（commit `403fa5afb14` 實測）：CJK 密集語料 400 個兩字詞，trigram 單獨使用 = recall 400/400 但 **BM25 可排序 0/400**；加伴隨索引 = **400/400 可排序**，查詢 901ms → 99ms，額外磁碟 0.84 MB。

**上游 11.5 是否已涵蓋？→ 沒有**

- `extensions/memory-core/src/memory/keyword-query.ts`（上游 11.5）：`trigram` 下長度 < 3 的 term 走 substring fallback → **可被找到，但無 BM25 分數**（`manager-search.ts` 的 `textScore` 為 0，排序由向量腿決定）。
- `docs/reference/memory-config.md`（上游 11.5）：仍寫明「With `trigram`, query terms shorter than three characters use substring matching」。
- 新增的 `extensions/memory-core/src/memory/tokenize.ts`（CJK bigram+unigram）僅用於 **Jaccard 相似度／去重**，非 FTS 路徑；`packages/memory-host-sdk/src/host/query-expansion.ts` 是停用詞／關鍵詞抽取，且在 trigram 模式下刻意保留整段 CJK run。**兩者都不提供 2 字中文的 BM25 排序。**
- 反向的改進：上游 11.5 的 `src/infra/database-engine/sqlite-full-text.ts` 原生支援 **phrase 查詢**（`TextQuery`），`contract.ts` 的 `SearchSchema.text` 為泛用索引註冊表，且有 `standing_intents_fts`（觸發器式衍生 FTS 表 + shadow table 白名單）作為先例 → **11.5 版的重新實作比移植更小、且可支援 Postgres**。

**兩個方案**

|          | 方案 A：對齊上游（已捨棄）                                                                                                                                | 方案 B：保留 CJK 伴隨索引（✅ 已決議；以 `ce792e38b54` cherry-pick）                                                                                                                                                               |
| :------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 內容     | 本次升級只做 base alignment；移除 `cjk` 設定與 `cjk_fts` 表                                                                                               | 本次升級保留伴隨索引：cherry-pick PR #193815 的 `ce792e38b54`（已用 11.5 新 FTS 架構實作）                                                                                                                                         |
| 前置動作 | 線上 `openclaw.json` 移除 `cjk` 鍵並 drop 孤兒表                                                                                                          | cherry-pick 後解 3 個衝突（2 個生成檔重跑 `pnpm config:docs:gen`）；線上設定不動                                                                                                                                                   |
| 風險     | 2 字中文查詢**找得到但排序退化**（由 BM25 降為向量腿／recency 決定）；`unicode61` 下嵌入長詞組的 2 字詞本來就找不到（上游 11.4 與 11.5 相同，非本次退化） | 需做 codegen、Postgres parity 取捨，且落在與上游分歧的 fork delta 上（未來 rebase 摩擦較高）；**但已有 PR [#193815](https://github.com/openclaw/openclaw/pull/193815)（`ce792e38b54`，已對齊新架構）可作為現成藍本，無需從零摸索** |
| 交付時程 | 本次升級即可完成                                                                                                                                          | 本次升級一併完成                                                                                                                                                                                                                   |

**決議：採方案 B，在官方尚未合入 PR #193815 前，升級維持保留 CJK 伴隨索引實作。**

- 實作藍本：優先參考已通過機器人審查（`Findings: None`、`proof: sufficient`）的 PR #193815（`ce792e38b54`）新架構寫法（`sqlite-search-schema.ts`、NFC 正規化、Kysely 型別化刪除），再視 11.5（agent v38）與 `main`（agent v42）差異微調。
- 備註：此為個人 fork 部署分支的保留實作，不影響掛在上游等候 Maintainer 審查的 PR #193815。

**其他相關判斷**

- `schemaVersions` **已變更**（state 22→36 / agent 27→38）→ 上游 migration 會改寫衍生表；記憶索引位於 **agent DB**（`agents/main/agent/openclaw-agent.sqlite`），受 **agent 27→38** 影響。
- **預設不主動 reset / force reindex**；由上游 migration 自行處理，並在部署後比對 `chunks / fts / cjk_fts` 三者筆數與 2 字中文查詢結果。
- 方案 B 的失效判定風險：上游 11.5 升級後會重建 memory index（chunk_rowid 可能改變），PR 版本僅以 row-count 比對，部署後須實測 CJK 查詢結果正確；若發現錯位，補 epoch／版本戳或 force rebuild（零 embedding 呼叫）。
- 索引重建期間禁止另起 `openclaw memory index/search/reset`（雙行程撞 Gemini 免費層配額 → 429 `RESOURCE_EXHAUSTED`）。

### 1.8 Dockerfile base image 變更（bookworm → trixie）

上游 11.5 將 base image 由 `node:24.22.1-bookworm(-slim)` 改為 `node:24.22.1-trixie(-slim)`：

- 我們的自訂層 **自動合併成功**（4 段 `# Custom:` 全數保留），但需注意：
  - 我們的 apt cache mount id 仍為 `openclaw-bookworm-apt-cache` / `openclaw-bookworm-apt-lists`，與上游新的 `openclaw-trixie-*` 分屬兩個 cache（功能無礙，僅 cache 不共用；建議同步改名為 trixie 以重用上游 cache）。
  - trixie = Debian 13，Python 預設為 3.13。已查 PyPI：`ctranslate2 4.9.0`（faster-whisper 依賴）提供 `cp313` 且含 `manylinux_2_27_aarch64` wheel → arm64 建置預期可成功，仍須以 CI 建置結果驗證。
  - OpenSSH 於 trixie 為 10.x；`UseDNS` 等舊選項與 `/usr/sbin/sshd` 路徑需在部署後實機確認（k3s deployment command 會直接啟動 sshd）。
  - `locales`（含 `zh_TW.UTF-8`）、`rsync`、`ffmpeg`、`tini`、`openssh-server` 於 trixie 套件名不變。

### 1.9 Runtime / 依賴

- `engines.node` **不變**（`>=24.16.0 <25 || >=26.1.0`）；`packageManager` **不變**（pnpm 12.15.0）→ 無需調整 node/pnpm 版本。
- 頂層依賴 **35 項變動**，與我們相關者：
  - `@openclaw/fs-safe` 0.26.7 → **0.26.13**（上游 Dockerfile 新增 `fs-safe-npm-cli-preload/protocol` 相關 .mjs 檔案）
  - `@google/genai` 2.27.0 → **2.30.0**（我們的 Gemini embedding 限速 patch 直接依賴此 SDK → 需重測限速與 429 行為）
  - `openai` 7.28.0 → 7.39.0、`@anthropic-ai/sdk` 0.131 → 0.135（與我們的 minimax provider 無直接關係）
  - 新增 `@modelcontextprotocol/{client,core,node,server}`（MCP 2.x）、`@types/pg`（Postgres 支援 → 上游 11.5 記憶搜尋已支援 Postgres）
  - 移除 `@mistralai/mistralai` 2.7.0（頂層）

### 1.10 上游已知問題（2026-11-16 起，針對 11.4 → 11.5）

| Issue                                                         | 狀態   | 內容                                                                                                                                                                                                              | 對我們的處置                                                                                                                                                  |
| :------------------------------------------------------------ | :----- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [#200583](https://github.com/openclaw/openclaw/issues/200583) | open   | **從 11.4 升級後第一次啟動 Gateway 會以 `disk I/O error \| ERR_SQLITE_ERROR` 失敗，重啟即恢復**。根因：升級期 config check 對暫存 `.upgrade-…` DB 留著未關閉的 reader，DB 改名後該連線路徑失效，切 WAL 時讀取失敗 | **部署流程必須容許「首次啟動失敗 → 重啟一次」**，不得直接判定升級失敗或回滾                                                                                   |
| [#200629](https://github.com/openclaw/openclaw/issues/200629) | open   | cron 復原修正 #194048 **不在** v2026.11.4 / v2026.11.5；shared-state worker 遺失後排程會停擺直到 Gateway 重啟                                                                                                     | 部署後 24h 內確認 cron（含 `Memory Dreaming Promotion`）持續觸發；若停擺 → 重啟 Gateway Pod                                                                   |
| [#200594](https://github.com/openclaw/openclaw/issues/200594) | open   | `candidate-doctor` 會把**有效**的 cold transcript archive 誤判為 missing，阻擋 update                                                                                                                             | 我們走 Docker image 替換（非 `openclaw update`），不觸發 candidate-doctor；但 `doctor --fix` 若報 cold archive 錯誤，需先以 sha256 / `zstd -t` 驗證檔案再判定 |
| [#200606](https://github.com/openclaw/openclaw/issues/200606) | open   | candidate Doctor 因 plugin migration 衝突阻擋更新                                                                                                                                                                 | 同上，Docker 路徑不適用                                                                                                                                       |
| [#200224](https://github.com/openclaw/openclaw/issues/200224) | open   | 11.5 beta 拒絕已退役的 `agents.defaults.heartbeat` 設定                                                                                                                                                           | **不適用**：線上 `agents.defaults` 僅有 `compaction / model / modelPolicy / models / workspace`，無 `heartbeat`                                               |
| [#200557](https://github.com/openclaw/openclaw/issues/200557) | closed | 11.4 起 memory CLI 在 Gateway 運作時拒絕執行（移除線上讀取路徑）                                                                                                                                                  | 驗證記憶體時**必須走 Gateway 路徑**（`openclaw agent`），不要用 CLI `memory search/index`                                                                     |

---

## Phase 2: 執行步驟（取得 Go-Sign 後）

### 2.1 備份與基線確認（強制）

- [x] `git status -sb` 乾淨
- [x] 建立本地分支備份：`git branch -f backup/my-config-v2026.11.4 origin/my-config-v2026.11.4`
- [x] 確認 `git rev-parse upstream-v2026.11.5^{commit}` = `e13cf15ece9bbd969b7362927c315362c90c97ff`
- [x] **N100 完整備份** `/data/services/openclaw/.openclaw/` → `/root/backup-openclaw-20261117-pre-v2026.11.5`（schema 遷移不可逆，無備份不可回滾；熱備份須含 `-wal`/`-shm` 檔，或於 §2.8 `scale --replicas=0` 後再補做一次停機冷備份）
  - [ ] 需互動式 sudo（`kuniaki` 帳號對 `/root` 無讀寫權；`sudo -n` 會失敗）
  - [x] 核對容量（N100 `/` 現況：`1.8T` 總量、`637G` 已用、`1.1T` 可用）
- [x] Mac 本地異地備份關鍵 DB（`openclaw.json`、`openclaw.sqlite`、`openclaw-agent.sqlite`）→ `/Users/mlee/openclaw-backups/`，並以 `gzip -t` 校驗
- [x] 盤點既有備份（保留 `/root/backup-openclaw-20261116-v2026.11.4`，確認本次新備份成功後再刪舊檔）

### 2.2 建立新分支

- [x] `git checkout -b my-config-v2026.11.5 upstream-v2026.11.5`

### 2.3 Purge 官方 Workflows 並覆蓋 Matrix `docker-release.yml`

- [x] `find .github/workflows -type f ! -name 'docker-release.yml' -delete`（上游 11.5 有 121 個 workflow）
- [x] `git checkout origin/my-config-v2026.11.4 -- .github/workflows/docker-release.yml`
- [x] `git add .github/workflows && git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"`

### 2.4 移植自訂 Commits（cherry-pick 順序：workflow → Dockerfile → assets → CJK → docs → worksheets）

- [x] `git cherry-pick 2fe158be6d6 d442939fd66`
- [ ] （選用）將 `Dockerfile` 中自訂層的 `openclaw-bookworm-apt-cache` / `openclaw-bookworm-apt-lists` 改名為 `openclaw-trixie-*` 以共用上游 cache（或維持不改）
- [x] **CJK 對齊（方案 B）**：`git cherry-pick ce792e38b54`（PR #193815 單一 squash commit；**不再**使用舊 `403fa5afb14`）
  - [x] 預期 3 個衝突：`docs/.generated/config-baseline.counts.json` / `.sha256` 不手解，取上游版後執行 `pnpm config:docs:gen` 重新生成；`manager-search-types.ts` 手動合併保留雙方欄位
  - [x] `src/infra/update-candidate-state.inventory.test.ts`、`scripts/pr-lib/wrapper-components.txt` 的變更隨 commit 帶入，確認無遺漏
  - [ ] 檢查 `AGENT_SCHEMA_COMPATIBILITY.allowedMissingTables` 與 schema fingerprint／postgres catalog 是否需 `pnpm db:postgres:gen`（交 CI 驗證，本機不跑重型檢查）
  - [ ] 閱讀 `manager-source-index-kernel.ts` / `sqlite-search-schema.ts` 確認 11.5（agent v38）下 `cjk_fts` 重建判定行為（見 §1.3 提示）
- [x] 確認 `docs/reference/memory-config.md` 含 CJK bigram 說明（`ce792e38b54` 未必含文件；缺少再 `git cherry-pick 652dab92b65`，衝突則以 PR 版本為準）
- [x] `git checkout origin/my-config-v2026.11.4 -- docs/worksheet-upgrade-openclaw-v2026.*.md` 帶入完整歷史工作表（含 11.4）並 commit
- [x] 驗證自訂層仍在：`git grep -q 'Custom: Install faster-whisper' HEAD -- Dockerfile`
- [x] 驗證 Gemini 限速仍在：`git grep -n MIN_GEMINI_EMBEDDING_INTERVAL_MS HEAD -- extensions/google/embedding-provider.ts`
- [x] 驗證 gemini 並發鎖：`git grep -n 'provider?.id === "gemini"' HEAD -- extensions/memory-core/src/memory/manager-embedding-ops.ts`
- [x] 驗證 `assets/whisper`、`docker/entrypoint-ssh.sh` 存在且具執行權限
- [x] 驗證 `src/config/zod-schema.memory-search.ts` 保留 `cjk: "bigram"`（與線上 `openclaw.json` 一致）

### 2.5 本地輕量驗證（嚴禁重型 CI / 本機 docker build）

- [x] `git status -sb`、`git diff --check`
- [x] `git diff upstream-v2026.11.5 --stat -- . ':!docs' ':!.github'` 僅含預期自訂檔案
- [x] 確認 `.github/workflows/` 只剩 `docker-release.yml`，且僅有 `workflow_dispatch` 觸發、input 名為 `tag`
- [x] 確認 `Dockerfile` base image 為 trixie 且自訂層完整

### 2.6 Commit Worksheet 並推送分支至 Fork (`origin`)

- [x] `git add docs/worksheet-upgrade-openclaw-v2026.11.5-20261117.md && git commit -m "docs: add v2026.11.5 upgrade worksheet"`
- [x] `git push -u origin my-config-v2026.11.5`（**不推 git tag**；image tag 由 dispatch 輸入決定）

### 2.7 觸發 GHCR Matrix Build 與監控

- [x] `grep -A6 workflow_dispatch: .github/workflows/docker-release.yml` 確認 input 為 `tag`
- [x] 觸發：`gh workflow run docker-release.yml --repo kuniakil/openclaw --ref my-config-v2026.11.5 -f tag=v2026.11.5 -f platforms=all`
- [x] 驗證 Run：`event=workflow_dispatch`、`headBranch=my-config-v2026.11.5`、`headSha` 為我們的 commit（且 `git merge-base --is-ancestor ce792e38b54 <headSha>` 不適用 squash 時，改以 `git grep -l cjk-bigram <headSha>` 確認 CJK 檔案存在）
  - 若回 `HTTP 422 Actions has been disabled`：**停止重試**，依 Hard Rule 8 到 `https://github.com/kuniakil/openclaw/actions` 點 banner 重新啟用（不要清 cache、不要改 settings）
- [x] **派發背景子代理**執行 `gh run watch <run_id> --repo kuniakil/openclaw`（`prepare` / `amd64` / `arm64` / `merge` 皆須 `success`）
  - 特別確認 arm64 job 的 pip 安裝（trixie + Python 3.13）成功
- [x] 以 `docker buildx imagetools inspect` 驗證 tags：`2026.11.5`、`v2026.11.5`、`2026.11.5-slim`、`latest`、`main`

### 2.8 K3s 部署與 schema 遷移（不可逆，須先備份）

- [x] 更新 `~/kubernetes/openclaw/overlays/n100/kustomization.yaml` 的 `newTag` 為 `"2026.11.5"` 並 commit `~/kubernetes` repo
- [x] `kubectl -n openclaw scale deployment/openclaw-gateway --replicas=0`（避免 SQLite 寫入鎖衝突）
- [x] 啟動一次性維護 Pod（沿用 11.4 做法：同一 hostPath + `secrets-env`）：
  - [x] 執行 `openclaw doctor --fix --non-interactive --yes`
  - [x] 確認日誌出現 `Upgraded agent database schema ...: v27 -> v38` 與 state schema 22→36 的遷移紀錄
  - [x] 確認 `openclaw --version` = `OpenClaw 2026.11.5`
  - [x] 以唯讀 sqlite 檢查 agent DB：`memory_index_chunks` / `_fts` / `_cjk_fts` 筆數應一致（升級前 1467 ×3）；不符先停下評估，勿直接上線
- [x] 刪除維護 Pod，`kubectl apply -k ~/kubernetes/openclaw/overlays/n100` 恢復 `replicas=1`
- [x] **派發背景子代理**監控 `kubectl rollout status deployment/openclaw-gateway -n openclaw`
- [x] 確認 Pod `1/1 Running`、`RESTARTS 0`
- [ ] ⚠️ **若首次啟動因 `disk I/O error | ERR_SQLITE_ERROR` 失敗（上游 #200583）→ 直接重啟一次 Pod，勿回滾**（重啟即恢復）

### 2.9 部署後實機驗證（沿用 `openclaw-upgrade-check` A–K 16 項）

- [x] `openclaw --version` = `OpenClaw 2026.11.5`
- [x] 自訂工具鏈：`faster-whisper 1.2.1`、`/usr/local/bin/whisper`、`/usr/local/bin/edge-tts`、`/usr/bin/ffmpeg`、`/usr/bin/rsync`、`/usr/bin/tini`、`/usr/sbin/sshd`、`/app/docker/entrypoint-ssh.sh`、`en_US.utf8` / `zh_TW.utf8`
- [x] sshd 在 trixie 上可正常啟動（`/usr/sbin/sshd -f ... -D`）
- [x] Gateway logs：20 plugins 正常載入、Telegram `@N100_openclaw_mike_bot` 輪詢啟動、無 429 / `RESOURCE_EXHAUSTED`、無意外全量 reindex、無 `rss_threshold` 警告
- [x] Memory 索引：`chunks == fts == cjk_fts`（升級前 1467 / 1467 / 1467），且確認 `cjk_fts` 已隨新 schema／epoch 重建對齊
- [x] 2 字中文查詢實測（方案 B）：透過 Gateway 路徑查詢雙字詞（如「配置」「設定」），確認 `textScore > 0` 且維持 BM25 可排序
- [x] Cron 排程（`Memory Dreaming Promotion` 等）維持 `inferenceBinding` 綁定且未中斷
- [x] **比對升級前後的 cron／automation 清單**（state v30 heartbeat → automation 折疊會改寫排程資料；確認無新增、重複或遺失）
- [ ] **24h 內確認 cron 持續觸發**（上游 #200629：worker 遺失後排程會靜默停擺，需重啟 Gateway）
- [ ] 記憶體驗證走 Gateway 路徑（`openclaw agent`），**不要**用 CLI `openclaw memory search/index`（上游 #200557）
- [ ] Telegram 實機往返（收發、回覆、審批 topic 隔離）
- [x] `openclaw doctor --non-interactive` Error 級 = 0（僅預期容器內無 systemd busctl 提示）
- [x] 記憶體 cgroup 觀察（上次基準 2.03–2.14 GiB）

---

## Phase 3: 收尾與清理

- [x] 更新本工作表完成狀態並 commit / push
- [ ] 產出 post-mortem 文件至 `~/kubernetes/docs/`（對齊 `openclaw-v2026-11-4-upgrade-20261116.md` 格式），必要時發佈至 WordPress 知識庫
- [ ] 觀察期（3–5 天）後刪除舊備份 `/root/backup-openclaw-20261116-v2026.11.4`，僅保留 `/root/backup-openclaw-20261117-pre-v2026.11.5`
- [ ] 更新 `~/kubernetes/docs/service-version-matrix.md`

---

## 回滾預案（Rollback Plan）

- **本次為不可逆 schema 遷移（state 22→36 / agent 27→38）**，單純改回 image tag **不等於回滾**。
- 正確回滾順序：
  1. `kubectl -n openclaw scale deployment/openclaw-gateway --replicas=0`
  2. 將 `~/kubernetes/openclaw/overlays/n100/kustomization.yaml` 的 `newTag` 改回 `"2026.11.4"`（`git revert` 或手動修改並 commit）
  3. 以 **11.4 映像** + 還原後的 `.openclaw`（來自 `/root/backup-openclaw-20261117-pre-v2026.11.5`）啟動一次維護 Pod
  4. 執行 `openclaw doctor --fix` 讓 11.4 重新驗證／修復 schema
  5. 刪除維護 Pod，`kubectl apply -k ~/kubernetes/openclaw/overlays/n100` 恢復 `replicas=1`
- 前置條件（缺一不可）：§2.1 的 N100 完整備份 + Mac 異地備份皆已完成且可讀。

---

## 已知風險（Go-Sign 前請確認）

1. **上游 tag 歷史分歧**（§1.2）→ 本次為中型升級，非 patch；官方 release notes 的 351 PRs 不能代表全部內容差異。
2. **不可逆 schema 遷移**（§1.3）→ 備份失敗即不得升級。
3. **舊 CJK commit 的 8 個衝突不採用**（§1.5 / §1.7）→ 已定案採方案 B：改 cherry-pick PR #193815 的 `ce792e38b54`（乾跑僅 3 衝突）；風險在於該 commit 基於 main（agent v42），`cjk_fts` 在 agent v38 重建後須實測筆數與查詢正確。
4. **base image bookworm → trixie**（§1.8）→ Python 3.13 / OpenSSH 10.x / apt cache id 差異需實機驗證。
5. **線上 `openclaw.json` 的 `cjk: "bigram"` 必須與分支實作一致** → 方案 B 須確保 11.5 zod schema 保留 `cjk` 鍵且通過 `strictObject` 驗證，否則 Gateway 無法啟動。
