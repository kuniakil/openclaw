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

- [ ] 分支已 push 至 `origin`（`kuniakil/openclaw`，絕不 push `upstream`）
- [ ] 觸發 `docker-release.yml` 成功（若遇 `HTTP 422 Actions has been disabled`，依 Hard Rule 8 至 `https://github.com/kuniakil/openclaw/actions` 點擊橫幅重新啟用）
- [ ] 立即驗證 Run 參數（`event == workflow_dispatch`、`headBranch == my-config-v2026.10.10`、`headSha == 我們的 HEAD`）
- [ ] 派背景子代理執行 `gh run watch <run_id>`，等待 multi-arch (`amd64` + `arm64`) 建置完成
- [ ] 驗證 GHCR image tags 存在：`2026.10.10`、`v2026.10.10`、`2026.10.10-slim`、`latest`、`main`

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

- [ ] Pre-flight 檢查通過（無殘留 CLI 行程、無 429）
- [ ] `/root/backup-openclaw-20261103` 建立完成並確認 SQLite 檔案與 `openclaw.json` 完整

### 3.2 Kustomize 部署至 N100 K3s

```bash
# 更新 ~/kubernetes/openclaw/overlays/n100/kustomization.yaml newTag: "2026.10.10"
kubectl apply -k ~/kubernetes/openclaw/overlays/n100
```

- [ ] 更新 `~/kubernetes/openclaw/overlays/n100/kustomization.yaml` 的 `newTag` 為 `"2026.10.10"`
- [ ] `kubectl apply -k ~/kubernetes/openclaw/overlays/n100`
- [ ] 派背景子代理監看 `kubectl -n openclaw rollout status deploy/openclaw-gateway` 直至 `1/1 Running`、`RESTARTS 0`
- [ ] 同步 `~/kubernetes` git commit & push（並同步 N100 `/home/kuniaki/kubernetes` checkout）

### 3.3 啟動、Schema 遷移與功能驗證

- [ ] **版本與健康度**：`openclaw --version` = `OpenClaw 2026.10.10`、`/health` = `200 OK`
- [ ] **Schema 遷移驗證（`state 20 → 22`、`agent 25 → 27`）**：
  - 檢查啟動 log 無 `MigrationRequired` / `quarantine` / `ERROR` / `FATAL`
  - 唯讀驗證 `state.sqlite` `PRAGMA user_version` = **`22`**、`agent.sqlite` `PRAGMA user_version` = **`27`**、`PRAGMA quick_check` = **`ok`**
- [ ] **自訂工具鏈存活**：
  - `locale -a` 含 `en_US.utf8` / `zh_TW.utf8`
  - `faster_whisper`、`edge_tts`、`ffmpeg`、`rsync`、`sshd`、`entrypoint-ssh.sh` (0755) 正常
  - Gemini 4200ms 限速常數與併發鎖存在於 `/app/dist/` 產物中
- [ ] **Companion CJK Bigram FTS 與 Memory 狀態驗證（遵守 `openclaw-embedding-ops`）**：
  - 確認 `sqlite_master` 中 `memory_index_chunks_cjk_fts` 存在且列數與 `memory_index_chunks` 對齊
  - 觀察 Gateway 背景 `chunkingVersion 5 → 6` 收斂情況（確認 `RESOURCE_EXHAUSTED` = 0）
  - 待背景索引靜止後，驗證 2 字中文查詢（如 `配置`、`數據`）`textScore > 0` 且排序第 1
- [ ] **真實訊息往返驗證**：
  - 確認一次真實對話往返（Telegram 或 Control UI）正常收發無報錯

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
