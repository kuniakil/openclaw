# OpenClaw v2026.10.10 升級工作表（2026-11-03）

> 目標：將現行線上與分支 `my-config-v2026.10.9`（線上 `2026.10.9-cjk-bigram.1`）對齊官方 `v2026.10.10`（SHA `7dc3350cb9f08fcf9a0af5c4845a20d5b2f1a8be`），
> 保留自訂 Docker 層、Gemini 限速 patch、**Companion CJK Bigram FTS 索引（#170997）**、精簡 Matrix `docker-release.yml` 與線性歷史。
> 本檔在取得使用者 Go-Sign **之前**僅為規劃書；Phase 2 / Phase 3 的 checkbox 於核准後執行時勾選。

---

## 🚦 執行前提（Go-Sign Gate）

- [ ] **使用者已明確核准開始執行 Phase 2（Go-Sign）**
- [ ] **使用者已確認升級前強制備份方式**（⚠️ **本次含不可逆 DB Schema 升級：`state 20 → 22`、`agent 25 → 27`，備份為強制項**）
- [ ] 升級期間不在 Mac 跑重型 CI（`pnpm check:changed` / `tsgo:all` / `vitest` / `docker build` 全交給 GitHub Actions）
- [ ] 升級期間**禁止**在 CLI 另起行程執行 `openclaw memory index` / `memory search` / `memory reset` / `agent --local`（⚠️ 本次 `MEMORY_CHUNKING_VERSION` `5 → 6`，Gateway 啟動後會自動在背景對變動邊界的 chunk 重算，須避免雙行程撞 Gemini 15 RPM 配額）
- [ ] 任何 `gh run watch`（10+ 分鐘）或長等待一律派給背景子代理，主迴圈保持可回應

> [!CAUTION]
> **⚠️ 不可逆資料庫 Schema 遷移聲明（MANDATORY PRE-UPGRADE BACKUP）**
>
> 1. **`openclaw.schemaVersions` 已變更（不可逆）**：
>    - Shared State DB (`openclaw.sqlite`)：**`20 → 22`**
>    - Agent DB (`agent.sqlite`)：**`25 → 27`**
> 2. **回滾限制**：一旦 `v2026.10.10` 啟動並在入場交易中完成 `20 → 22` 與 `25 → 27` 遷移，舊版 `2026.10.9` 執行檔**會拒絕開啟已升版之 SQLite 資料庫**（且禁止手動調降 `PRAGMA user_version` 或 `schema_meta`）。
> 3. **強制備份**：部署新 image 前，**必須**依 `docker-image-rebuild` Phase 4.2 建立完整、WAL-aware 的升級前快照（`/root/backup-openclaw-20261103`）；若需回滾至 `2026.10.9-cjk-bigram.1`，必須同時還原該升級前 DB 快照與對應 image tag。

---

## Phase 1: 升級前深度分析（Planning Phase）

### 1.1 官方 `v2026.10.9` → `v2026.10.10` 核心差異表

| 項目                                 | `v2026.10.9`（現行基底）                   | `v2026.10.10`（目標版本）                    | 影響與處置                                                                                                                                                             |
| ------------------------------------ | ------------------------------------------ | -------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 官方 Release Tag SHA                 | `8b18b5578f66eab1501cba4cef2310d88bfb9a41` | `7dc3350cb9f08fcf9a0af5c4845a20d5b2f1a8be`   | 已安全 fetch 至 `refs/tags/upstream-v2026.10.10`                                                                                                                       |
| `package.json` version               | `2026.10.9`                                | **`2026.10.10`**                             | 版本號推進                                                                                                                                                             |
| **`openclaw.schemaVersions`**        | **`state: 20, agent: 25`**                 | **`state: 22, agent: 27`**                   | 🔴 **不可逆 Schema 遷移**（見 1.2）；啟動自動遷移，**升級前強制備份**                                                                                                  |
| `openclaw.databaseEngines`           | 無（僅 SQLite）                            | **`["sqlite", "postgres"]`**                 | 新增實驗性 PostgreSQL 16+ 支援；我們維持預設 SQLite 不變                                                                                                               |
| `updateAdmissionProtocol`            | `1`                                        | **`1`（不變）**                              | 🟢                                                                                                                                                                     |
| `engines.node`                       | `>=24.22.1 <25 \|\| >=26.12.1`             | **`>=24.16.0 <25 \|\| >=26.1.0`**            | 🟢 放寬下限；容器內 Node image 維持 `24.22.1-bookworm` 不變                                                                                                            |
| `packageManager`                     | `pnpm@12.15.0`                             | **`pnpm@12.15.0`（不變）**                   | 🟢                                                                                                                                                                     |
| `Dockerfile`                         | —                                          | **6 行變更**                                 | 🟢 `OPENCLAW_BUN_IMAGE` `1.4.2 → 1.4.4`、新增 `COPY tools/solid-lint/package.json`、移除 A2UI `.bundle.hash` stub；Node base image digest 未變，與我們底部自訂層零衝突 |
| **`MEMORY_CHUNKING_VERSION`**        | **`5`**                                    | **`6`** (`#168867`)                          | 🟡 獨立標題與後續內容合併；未變動 chunk 直接命中 `memory_embedding_cache`，僅邊界變動之少數 chunk 會透過 Gemini 限速佇列重嵌（見 1.4）                                 |
| `MEMORY_INDEX_PROVENANCE_VERSION`    | `1`                                        | **`1`（不變）**                              | 🟢                                                                                                                                                                     |
| `resolveEmbeddingInputFormatVersion` | `v0`（Gemini）/ `v1`（embeddinggemma）     | **不變**                                     | 🟢                                                                                                                                                                     |
| `extensions/` 目錄數                 | `166`                                      | **`171`（+5）**                              | 新增 `advisor`、`mcp-events`、`mcp-relay`、`muse`、`particle`（預設多為 opt-in）                                                                                       |
| `.github/workflows/`                 | 114 個                                     | 114 個（32 檔變更）                          | 🟢 Phase 2.2 一律 purge，覆蓋為我們的精簡 Matrix `docker-release.yml`                                                                                                  |
| **變更規模**                         | —                                          | **4,945 commits / 3,028 PRs / 25,524 files** | 主線大型功能匯入（Solid 2 UI、Chat Details、Advisor、Database Engine Kysely 化）                                                                                       |

---

### 1.2 官方 Release Notes 與 Schema 遷移審查（Mandatory Audit）

#### A. 功能亮點（Highlights）

1. **Chat Details Panel（`#161674` / `#172436`）**：Control UI 聊天視窗右側新增 Session Details 面板（寬螢幕自動展開，收窄自動隱藏），整合進度卡、Subagents 樹狀檢視與工具呼叫狀態。
2. **Advisor（`#169564`）**：實驗性任務監督功能（預設關閉，於 `Settings → System → Labs` 啟用），可在 Agent 偏離方向或重複失敗時提出修正建議。
3. **Split Speech Voice Mode（`#170343`）**：瀏覽器 Talk 新增分離語音模式（使用當前對話模型回答，搭配獨立設定之 STT/TTS 服務）。
4. **Device Folder Sessions（`#169722`）**：支援在已配對裝置的本地資料夾直接執行 Agent 工作（受 `nodeHost.workerRuns.folders` 控制）。
5. **MCP Relay & Event-Triggered Automations（`#168233` / `#165399`）**：支援從 ChatGPT / Claude 透過 opt-in MCP Relay 連線，以及接收 MCP Events Webhook 觸發自動化任務（預設皆關閉）。
6. **Google Gemini 4 Argon 支援（`#171429` / `#171852`）**：Google 與 Vertex 路由新增 Gemini 4 Argon 模型與 thinking levels 支援（注：新建 Google API-key 設定預設選為 primary，既有 `openclaw.json` 設定不受影響）。
7. **Telegram 穩定性修復**：
   - 進度草稿清理期間保留問題與按鈕（`#183028`）。
   - 預設 Telegram bot 支援與具名帳號並存解析 root secrets（`#183618`）。
   - 群組回覆鏈不再誤報傳送失敗（`#185899`），進度文字改以純文字渲染避免格式破損（`#168723`）。
8. **Memory Search 檢索與索引優化**：
   - **On-demand 索引啟動（`#174718`）**：啟動 OpenClaw 時不再一次打開所有 Agent 的記憶體索引，改為按需開啟。
   - **對話靜止後批次索引**：對話更新改於 quiet period 後批次寫入索引，不再於活躍回合中反覆觸發。
   - **自然語言問題 fallback 與混合檢索權重調整（`#161165` / `#177450` / `#168692`）**：自然語言提問在嚴格匹配無結果時自動走關鍵字展開（`matchAny` + `extractKeywords`），並修復舊日期筆記被過度衰減的問題。
   - **獨立標題合併（`#168867`）**：修正獨立 Markdown 標題與後續內文切分問題（`MEMORY_CHUNKING_VERSION` `5 → 6`）。

#### B. 強制性 Schema 遷移與破壞性變更（Breaking Changes & Schema Bumps）

1. **Shared State DB：`state 20 → 22`（不可逆）**
   - **Schema 21（`#169414`）**：於 `meeting_transcript_sessions` 新增 7 個衍生文字欄位、`meeting_transcript_summaries` 新增 `overview`、`delivery_queue_entries` 新增 `retention_id_prefix` / `retention_max_age_ms` / `retention_max_entries`。
   - **Schema 22（`#170280`）**：於 ACP metadata 衍生 `resume_agent_session_id` 與 `resume_acpx_session_id` 取代舊 JSON expression index；並於 `operator_approvals`、`cron_run_receipts`、`execution_decision_facts`、`skill_workshop_changes` 新增唯一 `cursor_id` 欄位（由 `rowid` 回填）。
   - **執行時機**：Gateway 啟動（及 `openclaw doctor --fix`）在 shared-state 獨占交易內自動完成一次性掃描與回填。
2. **Agent DB：`agent 25 → 27`（不可逆）**
   - **Schema 26（`#169315`）**：將 `session_nodes`、`session_transcript_events`、`context_engine_turn_outbox` 的高頻 JSON 查詢屬性提升為實體 `TEXT` / `INTEGER` 欄位（保留原始 JSON 與壓縮 transcript bytes）。
   - **Schema 27（`#172074`）**：為 `context_engine_turn_outbox` 新增 `enqueue_sequence INTEGER PRIMARY KEY`（以既有 `rowid` 原地轉換，保留 `advancement_key` 唯一性與 FIFO 順序；若無 outbox 資料表則保持不建立）。
   - **執行時機**：Gateway 啟動開啟 Agent DB 時，於獨占維護交易內自動完成遷移並原子推進 `user_version = 27`。
3. **UI 與設定相容性注意事項（Caveats）**
   - Control UI 側邊欄個人捷徑（Personal navigation shortcuts）改用新儲存結構，舊釘選捷徑升級後不會自動帶入（其他設定不受影響，`#169447`）。
   - Plugin SDK 同步 SQLite/Session 呼叫標記為 Deprecated（遷移期限 2026-12-31，不影響內建 plugins）。

#### C. 重要相依套件變更（`package.json` / `pnpm-lock.yaml`）

- 新增 `pg` (`8.23.1`)、`@openclaw/proc-safe` (`0.4.2`)、`@resvg/resvg-js` (`2.6.2`)。
- 升級 `@openclaw/fs-safe` (`0.26.0 → 0.26.5`)、`@modelcontextprotocol/sdk` (`1.32.0 → 1.32.1`)、`openai` (`7.27.0 → 7.28.0`)、`undici` (`8.11.2 → 8.12.2`)、`@trycua/cua-driver` (`0.32.0 → 0.33.4`)、`@earendil-works/pi-tui` (`1.0.0 → 1.0.3`)。
- 移除 `koffi` (`3.3.2`)。
- Dockerfile 內 `OPENCLAW_BUN_IMAGE` 由 `1.4.2` 升至 `1.4.4`。

---

### 1.3 自訂 Commits 與衝突風險評估（Conflict Risk Assessment）

我們在 `my-config-v2026.10.9` 上共有 **4 個核心功能/配置 commits**（外加歷次升級之 `docs/worksheet-*.md` 歷史 commits）：

| 順序 | 原 Commit (`10.9`)            | 用途                                                                                                                   | `git merge-tree` 對 `10.10` 預檢結果                                                                                       |
| ---- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| 1    | `920e37d91b9`                 | Purge 官方 114 個 CI workflows，保留精簡 Matrix `docker-release.yml`                                                   | 🟢 直接執行 `find ... -delete` + `git checkout` 覆蓋（零衝突）                                                             |
| 2    | `2066fb0ed81`                 | 自訂 `Dockerfile` 層 + `embedding-provider.ts` (Gemini 4200ms 限速佇列) + `manager-embedding-ops.ts` (Gemini 併發鎖 1) | 🟡 `Dockerfile` 與 `embedding-provider.ts` 自動合併成功；僅 `manager-embedding-ops.ts` 1 行鄰近衝突                        |
| 3    | `f4a1700886b`                 | `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`                                        | 🟢 **零衝突**（自動合併 100% 乾淨）                                                                                        |
| 4    | `ad4d69aa06a` + `ab2e511669a` | **CJK Bigram Companion FTS 索引**（16 檔實作 + 1 檔文件，解決 2 字中文查詢 `textScore=0`）                             | 🟠 16 檔中 9 檔自動合併、**7 檔因上游 10.10 導入 `matchAny` 關鍵字展開與 Kysely 批次寫入而產生區塊衝突**（見下方逐檔對策） |

#### 🔍 衝突檔案逐一拆解與移植對策（預先定案）

##### (1) `extensions/memory-core/src/memory/manager-embedding-ops.ts`（Commit `2066fb0ed81`）

- **衝突原因**：上游將第 475 行由 `provider?.id === "ollama"` 改為 `provider?.id === "local" || provider?.id === "ollama"`。
- **解決方案**：保留上游 `"local"` 並合入 `"gemini"`：
  ```ts
  return provider?.id === "local" || provider?.id === "ollama" || provider?.id === "gemini"
    ? 1
    : EMBEDDING_INDEX_CONCURRENCY;
  ```

##### (2) CJK Bigram Companion FTS 索引（Commit `ad4d69aa06a`）在 `10.10` 的 7 個衝突檔與架構適配

上游 `10.10` 在記憶體檢索層做了三項重構，我們的 CJK Bigram patch 需精準對齊：

1. **`packages/memory-host-sdk/src/host/memory-schema-fts.ts` & `src/infra/database-engine/sqlite-memory-search-fragments.ts`**：
   - 上游將 `buildMemoryChunkFtsSchemaSql` 抽出至 `sqlite-memory-search-fragments.ts` 的 `buildSqliteMemoryBodyFtsSchema`，並由 `getSqliteMemorySearchFtsSchemas()` 匯出供 `AGENT_FTS_SCHEMAS`（SQLite FTS 完整性檢查）使用。
   - **對策**：在 `memory-schema-fts.ts` 保留 `MEMORY_INDEX_CJK_FTS_TABLE = "memory_index_chunks_cjk_fts"` 與 `ensureMemoryCjkBigramFtsSchema` / `rebuildMemoryCjkBigramFts`，並於 `sqlite-memory-search-fragments.ts` 的 `getSqliteMemorySearchFtsSchemas()` 註冊 `memory_index_chunks_cjk_fts`（`tokenize='unicode61'`），確保 Doctor 與啟動完整性檢查（`AGENT_FTS_SCHEMAS`）認得這張伴生表。
2. **`packages/memory-host-sdk/src/host/memory-schema.ts`**：
   - 上游在 `ensureMemoryIndexSchema` 新增了 in-process `admissionKey` 快取（`memory.index-schema:[...]`）。
   - **對策**：將 `Boolean(params.cjkBigramFts)` 納入 `admissionKey.name` 陣列，並在 `admitted` 快速路徑與首次建立路徑都確保 `memory_index_chunks_cjk_fts` 狀態一致。
3. **`extensions/memory-core/src/memory/keyword-query.ts`**：
   - 上游為 `planKeywordSearch` 新增了 `matchAny?: boolean` 與回傳欄位 `tokens: string[]`（供自然語言 fallback 使用）。
   - **對策**：保留上游 `matchAny` 與 `tokens` 回傳結構，並加上 `cjkBigram?: boolean` 與 `cjkBigramQuery: string | null`（當 `matchQuery === null` 且含 $\ge 2$ 字 Han 詞時，轉為 companion phrase query，並在 `matchAny` 模式下同樣支援）。
4. **`extensions/memory-core/src/memory/manager-chunk-writer.ts`**：
   - 上游將單筆 `createMemoryChunkWriter` 改為批次 Kysely 函式 `writeMemoryChunks(database, context, rows)`。
   - **對策**：在 `writeMemoryChunks` 結尾檢查 `cjkFtsEnabled`；若啟用，對 `rows` 以 prepared statement 依 `id` 查 `chunk_rowid` 並同步 `DELETE` + `INSERT` `encodeHanBigrams(row.chunk.text)` 至 `memory_index_chunks_cjk_fts`。
5. **`extensions/memory-core/src/memory/manager-source-index-kernel.ts`**：
   - 上游將刪除函式重構為 `clear(pathname, source)` 與 `deleteRemovedChunks(pathname, source, removedIds)`。
   - **對策**：在刪除 `memory_index_chunks` 前，若 `memoryTableExists(this.database, MEMORY_INDEX_CJK_FTS_TABLE)` 為真，先刪除對應 `chunk_rowid` 的 `memory_index_chunks_cjk_fts` 紀錄（含整檔 `clear` 與差量 `removedIds` 兩條路徑）。
6. **`extensions/memory-core/src/memory/manager-keyword-retrieval.ts` & `manager-search.ts` & `manager-sync-ops.ts`**：
   - 上游在 `manager-keyword-retrieval.ts` 簡化了 `rankingQuery` 參數並改用 `matchAny` fallback；`manager-sync-ops.ts` 行號微調。
   - **對策**：在 `buildKeywordSearchQuery` 傳入 `cjkBigramTable`，於 `manager-search.ts` 的 companion 查詢分支使用上游新版 `(params.ftsScore + lexicalBoost) / (1 + lexicalBoost)` 計分公式與 `params.query`，並在 `manager-sync-ops.ts` 的 `shadow.admitSchema` 傳入 `cjkBigramFts: this.settings.store.fts.cjk === "bigram"`。

---

### 1.4 記憶體與 Embedding 索引影響分析

- **Embedding 模型與輸入格式**：`gemini-embedding-001` 與 `resolveEmbeddingInputFormatVersion` **未變**。
- **Chunking 版本變更（`MEMORY_CHUNKING_VERSION: 5 → 6`）**：
  - 因上游 PR `#168867` 將獨立 Markdown 標題與後續段落合併，`MEMORY_CHUNKING_VERSION` 由 5 升為 6。
  - **行為預判**：
    1. 新 Pod 啟動後，索引檢查會回報 `code: "chunking_version", chunkingVersionOnly: true`。
    2. 搜尋期間不中斷：在背景重整完成前，會暫時以既有 keyword 索引提供服務（`serving the existing keyword index`）。
    3. **Cache 高命中率**：絕大多數未受「獨立標題」影響的 chunks，其 `chunk.hash` 完全不變，直接從 `memory_embedding_cache`（目前 3,317 筆）命中，**不發送** Gemini API 請求；只有因標題合併而改變文字邊界的少數 chunks 會透過我們的 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` 佇列與 `concurrency = 1` 安全重嵌。
    4. **鐵律**：升級後**絕對不要**手動跑 `openclaw memory index` / `memory search` / `agent --local`，讓 Gateway 單一行程獨占完成 `chunkingVersion 5 → 6` 的背景收斂。

---

### 1.5 線上環境現況盤點（2026-11-03 唯讀採樣）

```text
現行分支     : my-config-v2026.10.9 (HEAD ab2e511669a)
線上 Image   : ghcr.io/kuniakil/openclaw:2026.10.9-cjk-bigram.1
線上 Pod     : openclaw-gateway-56fd8d85fb-m7c87 (1/1 Running, RESTARTS 0, AGE 3d)
容器內版本   : OpenClaw 2026.10.9 / Node v24.22.1
資料目錄大小 : /home/node/.openclaw/agents 502M, /home/node/.openclaw/memory 15M
N100 磁碟    : /dev/nvme0n1p2 1.8T, 已用 498G, 可用 1.3T (29%)
既有備份盤點 :
  1. /root/backup-openclaw-20261031-cjk-bigram (510M，10/31 CJK Bigram 部署前完整快照)
  2. /home/kuniaki/backup-openclaw-20261030    (279M，10/30 v2026.10.9 升級前輕量快照)
連線方式     : Mac 透過 Kubeconfig + SSH `n100-rescue` (Oracle VPS FRP 通道) 連線正常
```

---

## Phase 2: 執行步驟（待使用者 Go-Sign 後執行）

### 2.0 前置確認

- [x] `git status -sb` 乾淨（位於 `my-config-v2026.10.9`）
- [x] 安全 fetch 官方 tag：`git fetch upstream refs/tags/v2026.10.10:refs/tags/upstream-v2026.10.10 --no-tags`
- [x] 驗證 `upstream-v2026.10.10^{commit}` = `7dc3350cb9f08fcf9a0af5c4845a20d5b2f1a8be`（與官方 Release Notes `release SHA` 完全一致）
- [x] 官方 Release Notes、Schema 遷移歷史（`state 20→22`、`agent 25→27`）與衝突清單審查完成
- [ ] **取得使用者 Go-Sign** → ✅ 已於 2026-11-03 取得

### 2.1 建立新分支 `my-config-v2026.10.10`

```bash
git checkout -b my-config-v2026.10.10 'upstream-v2026.10.10^{commit}'
```

- [x] 確認 base commit 為 `7dc3350cb9f0`、`package.json` version = `2026.10.10`

### 2.2 Purge 官方 Workflows 並覆蓋精簡版 `docker-release.yml`

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.10.9 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [x] 確認 `.github/workflows/` 僅留 `docker-release.yml` 1 檔（`workflow_dispatch` only，input 為 `tag`）

### 2.3 移植自訂 Commits 與解決衝突（保持線性歷史）

1. **Commit A — Dockerfile 自訂層 + Gemini 4200ms 限速佇列 + 索引併發鎖 1**：
   - Cherry-pick `2066fb0ed81`，解決 `manager-embedding-ops.ts` 單行衝突（保留 `"local" || "ollama" || "gemini"`）。
2. **Commit B — 自訂資產（Whisper wrapper / SSH entrypoint / TODO）**：
   - Cherry-pick `f4a1700886b`（預檢零衝突，確認 `0755` 權限保留）。
3. **Commit C — Companion CJK Bigram FTS 索引（`ad4d69aa06a` + `ab2e511669a`）**：
   - Cherry-pick 並依 **1.3 (2)** 對策完成 7 個檔案的 `10.10` 架構適配（Kysely `writeMemoryChunks`、`matchAny` 查詢計畫、`ensureMemoryIndexSchema` admissionKey、`sqlite-memory-search-fragments.ts` FTS schema 註冊）。
4. **Commit D — 歷次升級 Worksheets 文件歷史**：
   - 將 `my-config-v2026.10.9` 上的 `docs/worksheet-upgrade-openclaw-*.md` 帶入新分支並提交本次工作表。

- [x] Commit A 完成（Dockerfile + Gemini rate pacing + concurrency=1）
- [x] Commit B 完成（`assets/whisper`、`docker/entrypoint-ssh.sh`）
- [x] Commit C 完成（CJK Bigram Companion FTS 適配 `v2026.10.10`）
- [x] Commit D 完成（`docs/worksheet-upgrade-openclaw-*.md` 歷史與本工作表）
- [x] 確認 `git log --merges upstream-v2026.10.10..HEAD` 為 **0 merge commits**

> **實際衝突解決紀錄（2026-11-03）**：7 個衝突檔與工作表預估一致，實際對策如下：
>
> 1. `manager-embedding-ops.ts`：保留上游 `"local" || "ollama"` 並合入 `"gemini"`。
> 2. `keyword-query.ts`：保留上游 `matchAny` 與 `tokens` 回傳，加入 `cjkBigram` / `cjkBigramQuery`；
>    僅在 `matchQuery === null`（主索引無法排序）且含 ≥2 字 Han 詞時改走 companion。
> 3. `manager-chunk-writer.ts`：上游已改為批次 Kysely `writeMemoryChunks(database, context, rows)`；
>    於其結尾以 `syncMemoryCjkBigramRows()` 讀回 canonical 列（`chunk_rowid` + 文字）同步伴生表。
> 4. `manager-source-index-kernel.ts`：上游拆為 `clear()` 與 `deleteIds()`；
>    兩條路徑都在刪除 canonical 列**之前**先刪除對應 `chunk_rowid` 的伴生列。
> 5. `manager-search.ts`：上游移除 `rankingQuery`、改用 `matchAny`，計分公式改為
>    `(ftsScore + lexicalBoost) / (1 + lexicalBoost)`；companion 分支改用 `params.query` 與新公式。
> 6. `manager-sync-ops.ts`：`shadow.admitSchema()` 補上 `cjkBigramFts`。
> 7. `memory-schema-fts.ts`：上游抽出 `buildSqliteMemoryBodyFtsSchema`；
>    companion DDL 改用同一 builder，並在 `sqlite-memory-search-fragments.ts` 的
>    `getSqliteMemorySearchFtsSchemas()` 註冊，讓 Doctor／啟動完整性檢查認得伴生表。
> 8. 額外（工作表未列）：`ensureMemoryIndexSchema` 的 `admissionKey.name` 納入
>    `Boolean(params.cjkBigramFts)`，且 admitted 快速路徑也會校準伴生表狀態。

### 2.4 輕量本地驗證（Host Resource Protection — 不跑全庫 tsgo/vitest）

- [x] `git grep -q 'Custom: Install faster-whisper' HEAD -- Dockerfile` 命中
- [x] `git grep -n 'MIN_GEMINI_EMBEDDING_INTERVAL_MS' HEAD -- extensions/google/embedding-provider.ts` 命中（`:219` 定義、`:298` 套用）
- [x] `git grep -n 'MEMORY_INDEX_CJK_FTS_TABLE' HEAD -- packages/ extensions/ src/` 命中完整（33 處、8 檔）
- [x] 檢查 `assets/whisper` 與 `docker/entrypoint-ssh.sh` 權限皆為 `100755`

> ⚠️ **本地未跑重型 typecheck／vitest**（Mac 主機保護，見執行前提）。型別與行為驗證改由
> GitHub Actions 承載（見 2.5）。本地僅執行 `oxfmt --check`（通過）、`oxlint`（本地
> `node_modules` 為 10.9 版、缺 `eslint-plugin-solid`，故未能在本地執行）與
> `scripts/check-no-conflict-markers.mjs`（通過）。

### 2.5 Push 分支並由分支觸發 GHCR Build

```bash
git push -u origin my-config-v2026.10.10

gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.10.10 -f tag=v2026.10.10 -f platforms=all
```

- [x] 分支已 push 至 `origin`（`kuniakil/openclaw`，絕不 push `upstream`）
- [x] 觸發 `docker-release.yml` 成功（若遇 `HTTP 422 Actions has been disabled`，依 Hard Rule 8 至 `https://github.com/kuniakil/openclaw/actions` 點擊橫幅重新啟用）
- [x] 立即驗證 Run 參數（`event == workflow_dispatch`、`headBranch == my-config-v2026.10.10`、`headSha == 我們的 HEAD`）
  - Run `41660840410`：`event=workflow_dispatch`、`headBranch=my-config-v2026.10.10`、`headSha=dafade25ba7`
- [x] 派背景子代理執行 `gh run watch <run_id>`，等待 multi-arch (`amd64` + `arm64`) 建置完成
  - Run `41660840410` → **success**（11.5 分，`amd64` + `arm64` 雙腿皆綠）
- [x] 驗證 GHCR image tags 存在：`2026.10.10`、`v2026.10.10`、`2026.10.10-slim`、`latest`、`main`
  - 全部 OK
  - manifest 含 `linux/amd64` + `linux/arm64` ✅
  - **最終 digest（重建後）**：`sha256:6065e1a215328d686d01cdc585f1bc1c09663428bb0851264c71a36793ed8cdf`
    （重建前的 `sha256:9ec6f99a…` 已被覆寫；此 digest 即 Pod 的 imageID 基準）

> **型別／行為驗證結果（Run `41662476088` → success）**
>
> - `pnpm tsgo:core`（`src/**` + `packages/**`）✅
> - `pnpm tsgo:extensions:all`（extensions 專案 + 其 test 專案）✅
> - `vitest --config test/vitest/vitest.extension-memory.config.ts` 的 CJK 伴生索引測試 ✅
>   （`manager-search.cjk-bigram.test.ts` 全數通過：兩字 Han 查詢 BM25 排序 >
>   0、trigram 不可 match 的兩字詞可召回、單字維持未排序、無伴生表時退回
>   substring plan、伴生表隨 chunk writer 對齊、選項關閉時表被移除）
> - 第一次驗證 run `41660798478` 失敗僅因 workflow 設定
>   （`pnpm/action-setup` 不接受同時指定 `version:` 與 `packageManager`），非程式問題。
>
> **重建 image 的原因**：`Dockerfile` 用 `COPY . .`，而 `.dockerignore` 未排除 `.github/`，
> 故暫時 workflow 檔會進入 image 內容。為維持「分支 = image 來源」一致，移除暫時
> workflow 後重新 dispatch（Run `41663953929`，`headSha = b67469cb412`）覆寫 `2026.10.10` tags。

> **補充：型別／行為驗證改由 GitHub Actions 承載**（Mac 主機保護）。
> 由於 `docker-release.yml` 僅做 image build（`tsdown` 打包，不做完整 typecheck），
> 另建暫時 workflow `.github/workflows/upgrade-verification.yml`（`on: push` 觸發分支）跑
> `pnpm tsgo:core` + `pnpm tsgo:extensions:all` 與
> `vitest --config test/vitest/vitest.extension-memory.config.ts` 的 CJK 伴生索引測試。
> Run `41660798478`。驗證通過後會移除此暫時 workflow，回復「僅留 `docker-release.yml` 1 檔」。
>
> **最終狀態**：暫時 workflow 已於 commit `b67469cb412` 移除，`.github/workflows/` 僅留
> `docker-release.yml`。重建 run `41663953929`（`headSha = b67469cb412`）**success**
> （`prepare` / `build-and-push` amd64+arm64 / `merge` 四腿全綠）。

---

## Phase 3: 強制備份、K3s 部署與生產驗證

### 3.1 升級前強制備份（MANDATORY — 因 Schema `20→22` / `25→27` 不可逆）

```bash
# 1. Pre-flight：確認目前無並行 memory/agent 行程
kubectl -n openclaw exec deploy/openclaw-gateway -- sh -lc \
  "ps -eo pid,etime,cmd | grep -E 'openclaw memory|openclaw agent' | grep -v grep || true"

# 2. 於 N100 建立本次升級前完整一致備份（WAL-aware SQLite backup + rsync）
ssh n100-rescue "rsync -aH /data/services/openclaw/.openclaw/ /root/backup-openclaw-20261103/"
ssh n100-rescue "du -sh /root/backup-openclaw-20261103"
```

- [x] Pre-flight 檢查通過（無殘留 CLI 行程、無 429）
  - `ps` 無 `openclaw memory` / `openclaw agent` 行程；最近 3 分鐘 `[memory]` 事件 = 0；
    最近 30 分鐘 `RESOURCE_EXHAUSTED` = 0
- [x] `/root/backup-openclaw-20261103` 建立完成並確認 SQLite 檔案與 `openclaw.json` 完整
  - `rsync -aH -A -X` 全量複製 `/data/services/openclaw/.openclaw/` → **2.3G**
    （`agents` 501M、`workspace` 548M、`whisper-lib` 446M…；比 10/31 的 510M 大，因 workspace 成長）
  - **WAL-aware**：對每個 live SQLite 以 `sqlite3 ".backup"` 產生一致快照，並移除快照旁的
    `-wal`/`-shm`（快照本身已含 WAL 內容），再以 `chown/chmod --reference` 對齊原始權限
  - 驗證：`state/openclaw.sqlite` integrity=`ok` user_version=**20**；
    `agents/main/agent/openclaw-agent.sqlite` integrity=`ok` user_version=**25** ✅（升級前 schema）
  - 升級前記憶體索引基準：`memory_index_chunks` = 1336、`memory_index_chunks_cjk_fts` = 1336（已對齊）；
    `memory_index_meta_v1` = `chunkingVersion: 5`、`ftsTokenizer: trigram`、
    `embeddingInputFormatVersion: 0`、`model: gemini-embedding-001`、`vectorDims: 3072`
  - 線上設定確認：`memory.store.fts = { tokenizer: "trigram", cjk: "bigram" }`（伴生索引為啟用狀態）

### 3.2 Kustomize 部署至 N100 K3s

```bash
# 更新 ~/kubernetes/openclaw/overlays/n100/kustomization.yaml newTag: "2026.10.10"
kubectl apply -k ~/kubernetes/openclaw/overlays/n100
```

- [x] 更新 `~/kubernetes/openclaw/overlays/n100/kustomization.yaml` 的 `newTag` 為 `"2026.10.10"`
  - `kubectl kustomize` 渲染確認：`image: ghcr.io/kuniakil/openclaw:2026.10.10`
  - `kubectl diff -k`（對線上）**僅一處變更**：image tag
    `2026.10.9-cjk-bigram.1 → 2026.10.10`，其餘欄位零漂移
  - 註：Mac 目前無法直連 `192.168.31.72:6443`，改用 `n100-cloudflare-kubeconfig.yaml`
    （`https://k8s.3pm.lol`，同一叢集）執行 apply
- [x] 部署前 pre-flight 再次確認（apply 前 1 分鐘內採樣）
  - 無 `openclaw memory` / `openclaw agent` 行程；最近 3 分鐘 `[memory]` 事件 = 0；
    最近 30 分鐘 `RESOURCE_EXHAUSTED` = 0；部署中 image 仍為 `2026.10.9-cjk-bigram.1`
- [x] `kubectl apply -k ~/kubernetes/openclaw/overlays/n100`
  - 輸出：`deployment.apps/openclaw-gateway configured`，其餘資源皆 `unchanged`
- [x] 派背景子代理監看 `kubectl -n openclaw rollout status deploy/openclaw-gateway` 直至 `1/1 Running`、`RESTARTS 0`
  - 背景子代理觀察到第一個 Pod `...-m85rg` CrashLoopBackOff（exit 78，agent DB schema 25 未遷移）
  - 依上游升級路徑以 Doctor 完成遷移後，新 Pod `...-rlh4x` `1/1 Running`、`RESTARTS 0`、
    `RESOURCE_EXHAUSTED` = 0、imageID = manifest digest ✅（詳見 3.3）
- [x] 同步 `~/kubernetes` git commit & push（並同步 N100 `/home/kuniaki/kubernetes` checkout）
  - `~/kubernetes` commit `a7deb13` `chore(openclaw): bump gateway image to 2026.10.10` → push `origin/main` ✅
  - N100 `/home/kuniaki/kubernetes` 原為 `d082748`（`newTag: "2026.10.9"` 過期）；
    該主機的 git 無 GitHub 憑證（`could not read Username for 'https://github.com'`），
    故改以 `git bundle`（Mac 端 `git bundle create /tmp/my-k8s-main.bundle main`）
    傳遞後於主機端 `git fetch <bundle> main` + `git merge --ff-only`，
    已 fast-forward 至 `a7deb13`，`newTag: "2026.10.10"` ✅（未落地任何憑證）

### 3.3 啟動、Schema 遷移與功能驗證

> ⚠️ **實際遭遇：Gateway 不會自動遷移 agent DB，必須走 Doctor。**
> 第一個 `2026.10.10` Pod（`...-m85rg`）啟動即失敗並 CrashLoopBackOff（5 次，exit code **78**）：
>
> ```
> Agent main (/home/node/.openclaw/agents/main/agent/openclaw-agent.sqlite): OpenClaw agent database
> ... uses schema version 25; stop active agents and run openclaw doctor --fix to migrate session identities
> Sessions remain unavailable. Stop the Gateway, run "openclaw doctor --fix" to inspect and repair this agent
> database, and restart.
> [gateway] startup phase: cli.main.gateway-run-bootstrap 3575.1ms total=7778.9ms start=4203.7ms failed
> ```
>
> 這是上游刻意的安全設計（`docs/install/updating.md` 與
> `docs/reference/database-schemas/agent-schema-history.md` 明載：升級前必須停止 Gateway 與
> 所有 writer，再以新版本執行 `openclaw doctor --fix`）。**本次實際執行步驟**：
>
> 1. `kubectl -n openclaw scale deploy/openclaw-gateway --replicas=0`（停 Gateway，確認舊 Pod 消失）
> 2. 確認沒有其他行程持有 `openclaw-agent.sqlite`（掃 `/proc/*/fd` → 0 holder；
>    主機上其他 `node dist/index.js` 行程屬其他 Pod，使用完全不同的 DB `/app/config/db/db.sqlite3`）
> 3. 以同一 image／volumes／env／serviceAccount 建立一次性 Pod `openclaw-doctor-fix`，
>    command 覆寫為 `node dist/index.js doctor --fix`（`restartPolicy: Never`）
> 4. Doctor `Completed` exit=**0**，log：
>    `Upgraded agent database schema in .../openclaw-agent.sqlite: v25 -> v27.`
>    （Doctor 同時自存 pre-migration 備份 `*.pre-startup-migration-<uuid>.bak`）
> 5. `kubectl -n openclaw scale deploy/openclaw-gateway --replicas=1` → 新 Pod `...-rlh4x` 1/1 Running、RESTARTS 0
> 6. 驗證完畢後刪除一次性 doctor Pod（`openclaw-doctor-fix` 已 `Completed`，不持有狀態）

- [x] **版本與健康度**：`openclaw --version` = `OpenClaw 2026.10.10` ✅
  - `/health` → `{"ok":true,"status":"live"}` ✅（`wget` 不存在於 image，改用 `curl`）
  - Pod：`openclaw-gateway-85c7787c5f-rlh4x`、`1/1 Running`、`RESTARTS 0`
  - imageID = `ghcr.io/kuniakil/openclaw@sha256:6065e1a215328d686d01cdc585f1bc1c09663428bb0851264c71a36793ed8cdf`
    （= GHCR manifest digest）✅
- [x] **Schema 遷移驗證（`state 20 → 22`、`agent 25 → 27`）**：
  - `state.sqlite` `PRAGMA user_version` = **`22`**、`PRAGMA quick_check` = **`ok`** ✅
  - `openclaw-agent.sqlite` `PRAGMA user_version` = **`27`**、`PRAGMA quick_check` = **`ok`** ✅
  - 啟動 log：`ERROR` / `FATAL` / `CRITICAL` = **0**、`RESOURCE_EXHAUSTED` = **0** ✅
    （僅非致命警告：`MaxListenersExceededWarning`、4 則 `DEP_PLUGIN_SDK` deprecation、
    Doctor 提示 `legacy browser relay auth` / `groq`+`tavily` 退役日 / `completion --write-state` 建議）
- [x] **自訂工具鏈存活**：
  - `locale -a` 含 `en_US.utf8` / `zh_TW.utf8` ✅
  - `faster_whisper` **1.2.1**、**edge_tts 7.3.1** ✅（`python3 -c "import ..."` 驗證；
    驗證腳本原本用 `command -v` 判 Python 模組屬誤判，已更正）
  - `ffmpeg` OK、`rsync` OK ✅
  - `/usr/sbin/sshd` = **OpenSSH_9.2** ✅（不在 PATH，故 `command -v sshd` 為誤判）
  - `/usr/local/bin/whisper` 0755、`/app/docker/entrypoint-ssh.sh` **0755** ✅（`whisper --help` 可執行）
  - `MIN_GEMINI_EMBEDDING_INTERVAL_MS` 存在於 `/app/dist/embedding-provider-*.mjs` ✅
- [x] **Companion CJK Bigram FTS 與 Memory 狀態驗證（唯讀快照，不碰 live DB）**：
  - `memory_index_chunks` = **1336**、`memory_index_chunks_cjk_fts` = **1336** ✅ 對齊
  - 孤兒 companion 列（rowid 對不到 canonical chunk）= **0** ✅
  - `memory_vector_rebuild_v1` = `clean` ✅
  - **2 字中文召回對照（核心證據）**，以 `sqlite3 ".backup"` 一致快照查詢：
    | 索引                                           | 2 字詞「建議」 | 3 字詞對照組 |
    | ---------------------------------------------- | -------------- | ------------ |
    | `memory_index_chunks_fts`（trigram）           | **0 rows**     | 4 rows       |
    | `memory_index_chunks_cjk_fts`（伴生 bigram）   | **129 rows**   | —            |
    | 負向對照（語料不存在的 2 字詞）= **0 rows** ✅ |
  - **伴生索引 BM25 排序**：rank 1 `bm25=-3.627943`（`MEMORY.md`：`- **完整循環**：診斷 → 建議 → 等明確同意 → 才執行`）
    → 2 字詞可召回且**可排序**，不再是未排序的 LIKE fallback ✅
  - `chunkingVersion` 仍為 **5**（10.10 的 `MEMORY_CHUNKING_VERSION` = 6）：
    記憶體索引 `sync.intervalMinutes = 0`（無週期同步），同步由 `onSessionStart` / `onSearch` /
    watch 觸發，故 re-chunk 會在**下一次真實對話**時由 Gateway 自動進行
    （`manager-sync-ops.ts` 會以 `chunkingVersion: MEMORY_CHUNKING_VERSION` 重寫 meta）。
    **不得**用 CLI 另起行程觸發，避免撞 Gemini 15 RPM 配額。
- [ ] **真實訊息往返驗證**：
  - 確認一次真實對話往返（Telegram）正常收發無報錯
  - 同時觀察 `chunkingVersion` 是否收斂到 **6**、companion 表是否仍與 canonical 對齊

#### 3.3.1 Telegram 真實往返觸發的 re-chunk（2026-11-04 00:05）

使用者於 Telegram 下指令給 Gateway 做升級後檢查，該回合觸發了記憶體索引同步：

- `00:05:10.596` **Inbound message** `telegram:830338761 -> @N100_openclaw_mike_bot` (direct, 23 chars)
- `00:06:03.138` `agent turn milestone ... milestone=tool_execution_started totalMs=48951`

**re-chunk 收斂結果（live 唯讀）**：

| 項目                          | 升級前  | re-chunk 後                        |
| ----------------------------- | ------- | ---------------------------------- |
| `chunkingVersion`             | 5       | **6** ✅                           |
| `memory_index_chunks`         | 1336    | **1320**（version 6 邊界略有差異） |
| `memory_index_chunks_cjk_fts` | 1336    | **1320** ✅ 仍對齊                 |
| 孤兒 companion 列             | 0       | **0** ✅                           |
| `memory_vector_rebuild_v1`    | `clean` | `clean` ✅                         |
| `RESOURCE_EXHAUSTED`          | 0       | **0** ✅（Gemini 4200ms 限速有效） |

**re-chunk 後重新驗證伴生索引**（唯讀連線，未對 live DB 寫入）：

| 索引                                         | 2 字詞「建議」 |
| -------------------------------------------- | -------------- |
| `memory_index_chunks_fts`（trigram）         | **0 rows**     |
| `memory_index_chunks_cjk_fts`（伴生 bigram） | **129 rows**   |

- BM25 rank 1 `bm25=-3.608007` → `MEMORY.md`：`- **完整循環**：診斷 → 建議 → 等明確同意 → 才執行`
- 負向對照（語料不存在的 2 字詞）= **0 rows** ✅
- 結論：re-chunk 後伴生索引與 canonical 保持嚴格對齊，2 字中文召回與排序能力未受影響 ✅

### 3.4 備份生命週期收尾（需使用者授權）

- [ ] 彙整驗證結果與目前 N100 上的三份備份清單，主動詢問使用者是否清理舊備份：
  - `/home/kuniaki/backup-openclaw-20261030`（279M，10.9 升級前）
  - `/root/backup-openclaw-20261031-cjk-bigram`（510M，10.9 CJK Bigram 部署前）
  - `/root/backup-openclaw-20261103`（本次 10.10 升級前，因跨 Schema `20→22` / `25→27`，建議至少保留至確認無須回滾 10.9 為止）
- [ ] 更新本工作表所有勾選項並 commit push

---

## 🔄 回滾預案（Rollback Plan — 含 Schema 降級保護）

> ⚠️ 因 `v2026.10.10` 將 DB Schema 推進至 `state=22` / `agent=27`，若新 Pod 已啟動並修改 DB，**不可只改回舊 image tag**（舊版會拒絕 schema 22/27）。完整回滾步驟如下：

```bash
# 1. 先將副本數縮為 0，停止新版 Gateway 寫入
kubectl -n openclaw scale deploy/openclaw-gateway --replicas=0

# 2. 從升級前備份完整還原 .openclaw 資料目錄（含 schema 20/25 的 SQLite DBs）
ssh n100-rescue "rsync -aH --delete /root/backup-openclaw-20261103/ /data/services/openclaw/.openclaw/"

# 3. 將 kustomization.yaml 的 newTag 改回 "2026.10.9-cjk-bigram.1" 並套用
sed -i '' 's|newTag: "2026.10.10"|newTag: "2026.10.9-cjk-bigram.1"|' ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
kubectl apply -k ~/kubernetes/openclaw/overlays/n100
kubectl -n openclaw scale deploy/openclaw-gateway --replicas=1
kubectl -n openclaw rollout status deploy/openclaw-gateway
```
