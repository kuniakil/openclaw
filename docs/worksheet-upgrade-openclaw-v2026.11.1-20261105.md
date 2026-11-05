# OpenClaw v2026.11.1 升級工作表（2026-11-05）

> 目標：將現行線上與分支 `my-config-v2026.10.10`（線上 image `ghcr.io/kuniakil/openclaw:2026.10.10`）
> 對齊官方 `v2026.11.1`（release SHA `4ffdd2047d192dd65554de3c8c46c0e0197c6e2a`），
> 保留自訂 Docker 層、Gemini 限速 patch、**Companion CJK Bigram FTS 索引**、精簡 Matrix `docker-release.yml` 與線性歷史。
> 本檔在取得使用者 Go-Sign **之前**僅為規劃書；Phase 2 / Phase 3 的 checkbox 於核准後執行時勾選。

---

## 🚦 執行前提（Go-Sign Gate）

- [ ] **使用者已明確核准開始執行 Phase 2（Go-Sign）**
- [ ] **使用者已確認升級前備份方式**（🟢 **本次 `schemaVersions` 未變更（`state 22` / `agent 27` 不變）→ 無不可逆 DB Schema 遷移**；備份為**建議項**，主要保護設定檔與記憶體索引，不是 Schema 強制項。詳見 1.1 / 1.5 / 回滾預案）
- [ ] 升級期間不在 Mac 跑重型 CI（`pnpm check:changed` / `pnpm tsgo:all` / `vitest` / `docker build` 全交給 GitHub Actions）
- [ ] 升級期間**禁止**在 CLI 另起行程執行 `openclaw memory index` / `memory search` / `memory reset` / `agent --local`
      （⚠️ 本次 `MEMORY_CHUNKING_VERSION` 仍為 `6`、embedding 模型與輸入格式版本皆未變 → **預期不會觸發 re-chunk**；
      但上游 11.1 新增了 session 索引的 streaming 路徑（見 1.4），仍須避免雙行程撞 Gemini 15 RPM 配額）
- [ ] 任何 `gh run watch`（10+ 分鐘）或長等待一律派給背景子代理，主迴圈保持可回應

> [!NOTE]
> **🟢 本次升級的關鍵差異（相較 2026.10.10 升級）**
>
> 1. **無不可逆 DB Schema 遷移**：`openclaw.schemaVersions` 在 `v2026.10.10` 與 `v2026.11.1` **完全相同**
>    （`state: 22`、`agent: 27`）。線上 DB 的 `user_version` 已經是 `22` / `27`，**啟動時不需要 Doctor 遷移**，
>    也不需要「縮容 → doctor --fix → 擴容」流程（10.10 那次的 CrashLoopBackOff 不會重演）。
> 2. **記憶體索引不會重建**：`MEMORY_CHUNKING_VERSION` = `6`（未變）、`MEMORY_INDEX_PROVENANCE_VERSION` = `1`（未變）、
>    `resolveEmbeddingInputFormatVersion` = `v0`（未變）、embedding 模型 = `gemini-embedding-001`（未變）
>    → 依 SOP 規則**不重建 embedding 索引**。
> 3. **`Dockerfile` 上游零變更**（`git diff upstream-v2026.10.10 upstream-v2026.11.1 -- Dockerfile` 為空）
>    → 我們 46 行的自訂層可以零衝突套用。
> 4. **上游沒有動我們自訂 commit 修改的任何非 workflow 檔案**（15 個檔逐一驗證，diff 皆為空）
>    → 5 個自訂 commit 全部可乾淨 cherry-pick；唯一衝突是 8 個官方 workflow 檔的 modify/delete，而那些檔本來就要被 purge 掉。

---

## Phase 1: 升級前深度分析（Planning Phase）

### 1.1 官方 `v2026.10.10` → `v2026.11.1` 核心差異表

| 項目                                                   | `v2026.10.10`（現行基底）                  | `v2026.11.1`（目標版本）                        | 影響與處置                                                                                                         |
| ------------------------------------------------------ | ------------------------------------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| 官方 Release Tag SHA                                   | `7dc3350cb9f08fcf9a0af5c4845a20d5b2f1a8be` | `4ffdd2047d192dd65554de3c8c46c0e0197c6e2a`      | 已安全 fetch 至 `refs/tags/upstream-v2026.11.1`；**與官方 Release Notes 的 `release SHA` 完全一致** ✅             |
| `package.json` version                                 | `2026.10.10`                               | **`2026.11.1`**                                 | 版本號推進                                                                                                         |
| **`openclaw.schemaVersions`**                          | **`state: 22, agent: 27`**                 | **`state: 22, agent: 27`（不變）**              | 🟢 **無不可逆 Schema 遷移**；線上 DB 已經是 `22` / `27`，啟動不需 Doctor 遷移（見 1.2 B）                          |
| `openclaw.databaseEngines`                             | `["sqlite", "postgres"]`                   | **`["sqlite", "postgres"]`（不變）**            | 🟢 維持預設 SQLite                                                                                                 |
| `updateAdmissionProtocol`                              | `1`                                        | **`1`（不變）**                                 | 🟢                                                                                                                 |
| `engines.node`                                         | `>=24.16.0 <25 \|\| >=26.1.0`              | **`>=24.16.0 <25 \|\| >=26.1.0`（不變）**       | 🟢 容器內 Node 維持 `24.22.1-bookworm`                                                                             |
| `packageManager`                                       | `pnpm@12.15.0`（含 sha512 pin）            | **不變**                                        | 🟢                                                                                                                 |
| `Dockerfile`（上游）                                   | —                                          | **零變更**                                      | 🟢 我們的 46 行自訂層零衝突套用（實測 `git diff` 為空）                                                            |
| **`MEMORY_CHUNKING_VERSION`**                          | **`6`**                                    | **`6`（不變）**                                 | 🟢 **不觸發 re-chunk**，不重建 embedding 索引                                                                      |
| `MEMORY_INDEX_PROVENANCE_VERSION`                      | `1`                                        | **`1`（不變）**                                 | 🟢                                                                                                                 |
| `resolveEmbeddingInputFormatVersion`                   | `v0`（`gemini-embedding-001`）             | **不變**                                        | 🟢                                                                                                                 |
| `packages/memory-host-sdk/src/host/markdown-chunks.ts` | 單次 `chunkMarkdown()`                     | **重構為增量 `createMarkdownChunker()`**        | 🟡 **唯一會牽動 chunk 邊界的上游變更**；見 1.4 逐條比對                                                            |
| `packages/memory-host-sdk/src/host/session-files.ts`   | 同步 `materializeSessionArchiveForRead()`  | **改為 `await`（async）**                       | 🟡 session 讀取路徑改為非同步；上游針對此補了「memory indexing waits for archived transcript materialization」修正 |
| `extensions/` 目錄數                                   | `181`                                      | **`181`（不變）**                               | 🟢 無新增/刪除 extension                                                                                           |
| `.github/workflows/`                                   | `117` 個                                   | `117` 個（**8 檔變更**）                        | 🟢 Phase 2.2 一律 purge，覆蓋為我們的精簡 Matrix `docker-release.yml`                                              |
| `src/config/zod-schema*` / `types.ts`                  | —                                          | **零變更**                                      | 🟢 設定 schema 未動，線上 `openclaw.json` 應可直接沿用                                                             |
| `pnpm-lock.yaml`                                       | —                                          | **零變更**                                      | 🟢 無相依套件版本漂移                                                                                              |
| **變更規模**                                           | —                                          | **147 commits / 1,851 files / +65,379 −21,434** | 中型功能匯入（session/session-store 大改、Google Interactions、Doctor 遷移強化）                                   |

**Top-level 變更分佈**：`src/` 916、`extensions/` 442、`test/` 103、`docs/` 100、`apps/` 92、`ui/` 68、`scripts/` 55、`packages/` 36、`config/` 14、`.github/` 8。

---

### 1.2 官方 Release Notes 與 Schema 遷移審查（Mandatory Audit）

> 來源：`gh release view v2026.11.1 --repo openclaw/openclaw`（`publishedAt 2026-11-05T09:48:37Z`）+
> `CHANGELOG/2026.11.1.md`（upstream tag 內）。官方 release notes **沒有「Breaking Changes」章節**。

#### A. 與我們線上環境直接相關的重點

1. **Telegram／Discord／webhook 回覆可靠性提升**（`#179200`、`#179385`、`#179704`、`#189457`）
   → 我們唯一啟用的 channel 就是 Telegram（`channels.telegram.enabled = true`），此區塊是本次最直接的收益。
2. **Telegram 群組 allowlist 語意修正**（`#174787`）：「explicitly empty group allowlists remain empty instead of being repopulated」
   → 配合 1.2 B 的 Doctor 新遷移。
3. **Google Gemini Flash 文字模型在官方 AI Studio endpoint 預設改走 Interactions**（`#189395`）
   → **我們不受影響**，理由見下方「Google 路由影響評估」。
4. **Provider recovery 尊重 provider 指定的 rate-limit timing**（`#180280`）→ 對我們的 Gemini 限速 patch 是互補（上游改 backoff，我們改節流）。
5. **Session / memory 修正**（`#164442`、`#172970`、`#177937`、`#182091`、`#190182`、`#189284`、`#188450`、`#188483`、`#190690`）
   → 「memory indexing waits for archived transcript materialization」對應 `session-files.ts` 的 `await` 化，屬於修正不是破壞。
6. **Prompt caching 穩定性**（`#175309`、`#176167`）：session tool definitions 跨回合保持穩定 → 對我們 Minimax provider 的成本有正面影響。
7. **Doctor 遷移強化**（`#187443`、`#190665`、`#187192`、`#186305`）：無效 `heartbeat.activeHours` **改為回報而非移除**；headless 修復在跳過必要工作時**回傳失敗而非成功**。
8. **Secret egress**（`#179249`）：managed proxy 與 exported subprocess CA bundle 拒絕 emSign ECC G3 信任根；**更新後需重啟 Gateway**，獨立 trust store 的 client 需各自更新。
   → 我們在 K3s 容器內、以 Minimax/Gemini 為 provider，不依賴該 CA bundle；但**部署後本來就會重啟 Pod**，此項自動滿足。

#### B. Schema 遷移與破壞性變更審查結論

| 檢查項                                                        | 10.10 → 11.1 結果                                         | 判定           |
| ------------------------------------------------------------- | --------------------------------------------------------- | -------------- |
| `openclaw.schemaVersions`                                     | `state 22 / agent 27` → `state 22 / agent 27`（**相同**） | 🟢 無遷移      |
| 線上 `state/openclaw.sqlite` `user_version`                   | `22`（= 11.1 期望值）                                     | 🟢 已就緒      |
| 線上 `agents/main/agent/openclaw-agent.sqlite` `user_version` | `27`（= 11.1 期望值）                                     | 🟢 已就緒      |
| `MEMORY_CHUNKING_VERSION`                                     | `6` → `6`                                                 | 🟢 不 re-chunk |
| `MEMORY_INDEX_PROVENANCE_VERSION`                             | `1` → `1`                                                 | 🟢             |
| `resolveEmbeddingInputFormatVersion`                          | `v0` → `v0`                                               | 🟢             |
| embedding 模型                                                | `gemini-embedding-001` → 同                               | 🟢             |
| 設定 schema（`src/config/zod-schema*`）                       | 零變更                                                    | 🟢             |
| `engines.node` / `packageManager`                             | 零變更                                                    | 🟢             |
| Node / Bun base image digest                                  | 零變更                                                    | 🟢             |

> [!IMPORTANT]
> **結論：本次升級沒有不可逆的資料庫遷移。**
> 10.10 那次升級必須「縮容 → `doctor --fix` → 擴容」（因為 `state 20→22`、`agent 25→27`），
> 本次**不需要**。線上 DB 的 `user_version` 已經等於 11.1 的期望值，新 image 啟動時會直接通過 admission 檢查。

#### C. 新增的 Doctor 設定遷移（Group allowlist fallback）

上游 `docs/gateway/doctor/config-migrations.md` 新增一條遷移：對支援 legacy DM sender fallback 的 channel，
Doctor 會把 `allowFrom` 複製到**缺席**的 `groupAllowFrom`；**明確的清單（含 `[]`）一律保留**，
且在 account / channel / global `groupPolicy` 關閉群組時保持缺席。

> **我們的線上設定**：`channels.telegram.groupAllowFrom = ["830338761"]`（明確值）、
> `groupPolicy = "allowlist"`、`dmPolicy = "pairing"`。
> → 明確清單會被保留，**不會**被改寫或補值。**本次升級不需動作**，但部署後仍應以唯讀方式複查一次該欄位。

#### D. 相依套件 / 執行環境變更

- `package.json` 的 `dependencies` / `devDependencies` **零變更**；`pnpm-lock.yaml` **零變更**。
- 唯一 `package.json` 差異：`version` 欄位 + 一個新 script `release:approve`（上游發布流程用，與我們無關）。
- `Dockerfile` 上游零變更 → Node `24.22.1-bookworm`、Bun `1.4.4` digest 皆不變。

#### E. Google 路由影響評估（本次唯一需要「人肉確認」的行為變更）

上游 11.1 新增 `resolveGoogleModelApi()`：當 provider 是 `google`、模型 id 命中 Flash 文字模型樣式
（`/^gemini-(?:\d+(?:\.\d+)?-)?flash(?:-|$)/`）、且 base URL 是官方 AI Studio 時，api 由 `google-generative-ai` 改為 `google-interactions`。

我們的實際情況（逐一比對程式碼確認）：

| 面向               | 線上實況                                                                                                                                                                            | 是否受影響                  |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------- |
| 對話模型           | `agents.defaults.model.primary = minimax/MiniMax-M3`、`agents.entries.main.model = minimax/MiniMax-M2.5`                                                                            | 🟢 否（非 google provider） |
| 記憶體 embedding   | `memory.search.provider = "gemini"`、`model = gemini-embedding-001`                                                                                                                 | 🟢 否                       |
| embedding api 預設 | `extensions/google/embedding-provider.ts:442` `api: providerConfig?.api ?? "google-generative-ai"` — **上游 10.10→11.1 未變更此檔**                                                 | 🟢 否                       |
| 路由函式適用對象   | `resolveGoogleModelApi()` 只在 `provider === "google"` 且 `isGoogleFlashTextModelId()` 為真時改寫；`gemini-embedding-001` 不符合 Flash 樣式，也不走 provider catalog 的文字模型路徑 | 🟢 否                       |

> **結論：Gemini 我們只用於 embedding，embedding 的 api 預設值上游未動 → 本次不需任何設定調整。**
> 保留為「部署後抽查」項（見 3.3）。

---

### 1.3 自訂 Commits 與衝突風險評估（Conflict Risk Assessment）

#### A. 我們要移植的自訂 commit（相對 `upstream-v2026.10.10`）

| #   | Commit        | 內容                                                                                        | 檔案數 |
| --- | ------------- | ------------------------------------------------------------------------------------------- | ------ |
| A   | `fa0f5b1e452` | `chore: purge official CI workflows; use optimized matrix docker-release.yml`               | 126    |
| B   | `3cd4f832b1e` | `chore: upgrade to v2026.9.7; restore custom Dockerfile layer, scripts, rate pacing, TODOs` | 3      |
| C   | `8eb2843a91d` | `fix(docker): restore assets/whisper and docker/entrypoint-ssh.sh for v2026.9.8`            | 3      |
| D   | `dc04077ce26` | `feat(memory): add a Han bigram companion FTS index for two-character queries`              | 17     |
| E   | `43600ab893b` | `docs(memory): document the store.fts.cjk bigram companion index`                           | 1      |

（另有 8 個純文件／臨時 CI 記錄 commit，**不移植**：`0ae22fe2ac9`（10.10 工作表）、`2d906024733`/`dafade25ba7`/`396fb891eed`/`b67469cb412`（臨時升級驗證 workflow 及其移除，10.10 收尾時已刪除）、
`40cfe7013ab`、`0f4103635f0`、`bc5f10262bc`（10.10 事後記錄）。）

#### B. 衝突面分析（方法：檔案交集）

```bash
comm -12 <(git diff --name-only upstream-v2026.10.10..HEAD | grep -v '^\.github/workflows/' | grep -v '^docs/worksheet' | sort -u) \
         <(git diff --name-only upstream-v2026.10.10 upstream-v2026.11.1 | sort -u)
# → 輸出為空
```

**逐檔複驗**（我們修改的 15 個非 workflow 檔，上游 10.10→11.1 的 diff 行數**全部為 0**）：

`src/plugin-sdk/memory-core-host-engine-schema.ts`、`packages/memory-host-sdk/src/host/memory-schema.ts`、
`packages/memory-host-sdk/src/host/memory-schema-fts.ts`、`src/agents/memory-search.ts`、
`src/config/zod-schema.memory-search.ts`、`src/infra/database-engine/sqlite-memory-search-fragments.ts`、
`extensions/memory-core/src/memory/manager-search.ts`、`manager-sync-ops.ts`、`manager-db-kernel.ts`、
`manager-embedding-ops.ts`、`keyword-query.ts`、`manager-keyword-retrieval.ts`、`manager-publication-task.ts`、`manager.ts`、
`extensions/google/embedding-provider.ts`

> 唯一的重疊在 `.github/workflows/`：上游 11.1 修改了 8 個官方 workflow 檔
> （`ci.yml`、`full-release-validation.yml`、`install-smoke-reusable.yml`、`linux-app-release.yml`、
> `macos-release.yml`、`openclaw-live-and-e2e-checks-reusable.yml`、`openclaw-scheduled-live-checks.yml`、
> `plugin-npm-release.yml`），而我們的 purge commit 正好刪掉它們 → **modify/delete 衝突，預期且可解（接受刪除）**。

#### C. 實測證據：真實 cherry-pick 演練（`/tmp/oc-wfcheck`，已於分析後移除）

在 `upstream-v2026.11.1` 上依序 cherry-pick A→E：

| Commit          | 結果                                                                                                                                                                             |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| A `fa0f5b1e452` | **8 個 modify/delete 衝突**（上游 11.1 改過的那 8 個官方 workflow 檔）；`git rm` 8 檔 → `cherry-pick --continue` 成功；結果 `.github/workflows/` 僅剩我們的 `docker-release.yml` |
| B `3cd4f832b1e` | ✅ 零衝突（3 files changed）                                                                                                                                                     |
| C `8eb2843a91d` | ✅ 零衝突（3 files changed）                                                                                                                                                     |
| D `dc04077ce26` | ✅ 零衝突（17 files changed）                                                                                                                                                    |
| E `43600ab893b` | ✅ 零衝突（1 file changed）                                                                                                                                                      |

**演練後的自訂層存活驗證**：

- `Dockerfile` 相對 `upstream-v2026.11.1` 為 **+46 行純新增**（無刪改），內含
  `Custom: Generate UTF-8 locales and install rsync`、`Custom: Install faster-whisper, edge-tts, and ffmpeg`、
  `COPY assets/whisper /usr/local/bin/whisper`、`COPY --chmod=0755 docker/entrypoint-ssh.sh`、SSH server、`ENV LANG/LC_ALL/LANGUAGE`
- `extensions/google/embedding-provider.ts`：`MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` 存在（`:219` 定義、`:298` 套用）
- `extensions/memory-core/src/memory/manager-chunk-writer.ts`：`syncMemoryCjkBigramRows(database, rows)` 於 `writeMemoryChunks()` 結尾呼叫（`:153` 定義處 `:164`）
- `.github/workflows/` = 1 檔，`workflow_dispatch` only，input 名稱 `tag`

#### D. 我們自訂 commit 與上游 11.1 新行為的相容性（逐項判定）

| 我們的機制                                   | 上游 11.1 是否動到                                                                                                                           | 判定                  |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- |
| Gemini 4200ms 限速佇列                       | `extensions/google/embedding-provider.ts` **上游零變更**；`provider-models.ts` / `provider-registration.ts` 有改但與 embedding provider 無關 | 🟢 保留即可           |
| CJK companion 索引寫入 hook                  | `manager-chunk-writer.ts` **上游零變更**；session 新路徑最終仍走 `writeMemoryChunks`                                                         | 🟢 自動對齊（見 1.4） |
| CJK companion 刪除/清理                      | `manager-source-index-kernel.ts` **上游零變更**                                                                                              | 🟢                    |
| CJK companion schema 註冊                    | `memory-schema.ts` / `memory-schema-fts.ts` / `sqlite-memory-search-fragments.ts` **上游零變更**                                             | 🟢                    |
| `Dockerfile` 自訂層                          | 上游 `Dockerfile` 零變更                                                                                                                     | 🟢 零衝突             |
| `assets/whisper`、`docker/entrypoint-ssh.sh` | 上游未觸碰                                                                                                                                   | 🟢                    |

---

### 1.4 記憶體與 Embedding 索引影響分析

#### A. 判定「是否需要重建 embedding 索引」

| 觸發條件                                  | 10.10 → 11.1  | 結果 |
| ----------------------------------------- | ------------- | ---- |
| `openclaw.schemaVersions` 變更            | 否            | 🟢   |
| embedding 模型變更                        | 否            | 🟢   |
| `resolveEmbeddingInputFormatVersion` 變更 | 否（皆 `v0`） | 🟢   |
| `MEMORY_CHUNKING_VERSION` 變更            | 否（皆 `6`）  | 🟢   |
| `MEMORY_INDEX_PROVENANCE_VERSION` 變更    | 否（皆 `1`）  | 🟢   |

> **結論：本次不重建 embedding 索引**，不執行 `openclaw memory reset`，也不主動 force reindex。

#### B. 上游 11.1 的記憶體子系統變更（唯一需要仔細看的部分）

**變更 1 — `packages/memory-host-sdk/src/host/markdown-chunks.ts` 重構**

- 舊：`chunkMarkdown(content, chunking)` 一次性切整份文件。
- 新：抽出增量版 `createMarkdownChunker(chunking, onChunk)`，回傳 `{ appendLine(part, lineNo, endOfLine), flush() }`；
  `chunkMarkdown` 保留為相容 wrapper（逐行餵 `appendLine`）。
- **我們的擔心**：chunk 邊界若改變 → chunk text hash 改變 → `memoryChunkRowId()`（= `hashText(source:path:startLine:endLine:chunk.hash:model)`）改變
  → 舊 row 被視為新 chunk → 觸發重新 embedding。
- **上游自己的等價性證據**：`manager-session-index-preparation.test.ts` 以
  `expectedSessionChunks(source)`（走原本整份文件的 `prepareMemoryIndexChunks`）為 oracle，
  斷言 streaming 結果 `expect(chunks).toEqual(expectedSessionChunks(source))`
  （唯一差異是 streaming 會刪掉冗餘的 `chunk.embeddingInput`，而 embedding cache owner 會由 `chunk.text` 重建）。
  → **上游以測試保證 chunk 邊界與 text 不變**，hash 不變 → 不會 re-chunk。

**變更 2 — 新增 session 索引 streaming 路徑**

- 新檔 `extensions/memory-core/src/memory/manager-session-index-preparation.ts`：
  `sessionIndexPages()`（16KB frames、512 行 / 64KB 一頁）與 `prepareSessionIndexStream()`
  （在 `input.resetAtLine` 做 reset-boundary flush）。
- `manager-index.worker.ts` 新增 `prepare-session` task；`manager-cpu-worker-runtime.ts` 的 `MemoryIndexTask`
  union 新增 `{kind:"prepare-session"}`，且 `prepareMemoryIndexInWorker()` 對 `source === "sessions"` 改走 streaming 路徑。
- 目的：修正「七百萬行 session 會撐爆 512 MiB worker isolate」的上游問題。
- **與我們的相容性**：streaming 產出的 chunk 最終仍經
  `manager-source-index-kernel.ts` → `writeMemoryChunks(database, context, batch)`（上游該檔零變更）
  → 我們掛在 `writeMemoryChunks()` 結尾的 `syncMemoryCjkBigramRows()` **照舊觸發**；
  且我們的 hook 是「讀回 canonical `memory_index_chunks` 列再寫 companion 表」，不依賴 chunk 產生方式 → 🟢 **CJK 伴生索引維持對齊**。

**變更 3 — `packages/memory-host-sdk/src/host/session-files.ts`**

- `materializeSessionArchiveForRead()` 改為 async，在 `retryTransientMemoryRead()` 內 `await`。
- 對應上游修正「memory indexing waits for archived transcript materialization」。
- 對我們的影響：session 索引讀取會多一個 async 邊界；我們的 hook 不在這條路徑上 → 🟢。

**變更 4 — `extensions/memory-core/src/migration/doctor-memory-sidecar.ts`**

- 當 sidecar 遷移有 warnings 時，補上 `warningDisposition: "recoverable"`。
- 語意：這些 warnings 屬可復原（來源保留供日後修復），不是失敗。
- 對我們的影響：記憶體 sidecar 是我們的自訂套件，Doctor 報告語意改變而已 → 🟢（部署後留意 log 有無新 warning）。

#### C. 線上記憶體索引基準（2026-11-05 唯讀採樣，供部署後比對）

| 項目                          | 部署前實測值                                                                                                                                                                                                  |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `memory_index_chunks`         | **1,347**（`memory` 998、`sessions` 349）                                                                                                                                                                     |
| `memory_index_chunks_cjk_fts` | **1,347**（與 canonical 對齊 ✅）                                                                                                                                                                             |
| `memory_embedding_cache`      | 3,413                                                                                                                                                                                                         |
| `memory_index_meta_v1`        | `model=gemini-embedding-001`、`provider=gemini`、`chunkingVersion=6`、`provenanceVersion=1`、`embeddingInputFormatVersion=0`、`ftsTokenizer=trigram`、`chunkTokens=400`、`chunkOverlap=80`、`vectorDims=3072` |
| `memory_vector_rebuild_v1`    | `clean`                                                                                                                                                                                                       |
| `memory_index_state.revision` | 1,547,002                                                                                                                                                                                                     |

> 部署後應確認：`chunkingVersion` 仍為 `6`、兩張 chunks 表筆數仍相等、無大量新的 embedding 寫入（見 3.3）。

---

### 1.5 線上環境現況盤點（2026-11-05 唯讀採樣）

| 項目                   | 線上實測值                                                                                                                                                      |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 部署                   | `ghcr.io/kuniakil/openclaw:2026.10.10`，`Available=True`                                                                                                        |
| State DB               | `/home/node/.openclaw/state/openclaw.sqlite`；`schema_meta`：`primary=22`、`startup-migrations=3`、`state-migrations=3`                                         |
| Agent DB               | `/home/node/.openclaw/agents/main/agent/openclaw-agent.sqlite`；`primary=27`、另有 2 個 receipt 行                                                              |
| 對話模型               | `agents.defaults.model.primary = minimax/MiniMax-M3`；`agents.entries.main.model = minimax/MiniMax-M2.5`；`models.providers` 僅 `minimax`                       |
| 模型白名單             | `agents.defaults.modelPolicy`（4 個 minimax 模型）                                                                                                              |
| Workspace              | `/home/node/.openclaw/workspace`；`compaction` safeguard 設定存在                                                                                               |
| 記憶體設定             | `memory.search.provider = "gemini"`；`memory.store.fts = { tokenizer: "trigram", cjk: "bigram" }`                                                               |
| Telegram               | `enabled=true`、`dmPolicy=pairing`、`groupPolicy=allowlist`、`groupAllowFrom=["830338761"]`、`streaming.mode=progress`                                          |
| 其他 channel           | `discord.enabled=false`；`gemini.enabled=false`（chat channel）                                                                                                 |
| TTS                    | `microsoft` provider，speaker `zh-TW-HsiaoChenNeural`                                                                                                           |
| `openclaw.json` `meta` | `lastTouchedVersion = "2026.10.8"`、`migrations.modelPolicyAllowlist=true`、`utilityModelSeparation=true`                                                       |
| 部署 manifest          | `~/kubernetes/openclaw/overlays/n100/kustomization.yaml` → `newTag: "2026.10.10"`                                                                               |
| K8s 存取               | Mac **無法直連** `192.168.31.72:6443`；使用 `kubectl --context n100-cf`（`https://k8s.3pm.lol`，同一叢集）                                                      |
| Git remotes            | `origin`=`kuniakil/openclaw`（fork）、`upstream`=`openclaw/openclaw`（官方）、`n100`=ssh 內網 checkout                                                          |
| Fork Actions 狀態      | `GET /actions/permissions` → `{"enabled":true,"allowed_actions":"all"}`；workflows 皆 `active`。⚠️ 依 Hard Rule 8，**此 API 無法預判 422**，dispatch 時才見分曉 |

---

## Phase 2: 執行步驟（待使用者 Go-Sign 後執行）

### 2.0 前置確認

- [x] `git status -sb` 乾淨（位於 `my-config-v2026.10.10`，與 `origin/my-config-v2026.10.10` 同步）
- [x] 安全 fetch 官方 tag：`git fetch upstream refs/tags/v2026.11.1:refs/tags/upstream-v2026.11.1 --no-tags`
- [x] 驗證 `upstream-v2026.11.1^{commit}` = `4ffdd2047d192dd65554de3c8c46c0e0197c6e2a`（與官方 Release Notes `release SHA` 完全一致）
- [x] 官方 Release Notes / `CHANGELOG/2026.11.1.md` / `docs/gateway/doctor/config-migrations.md` / `docs/install/updating.md` 審查完成
- [x] `schemaVersions` 確認**未變更**（`state 22` / `agent 27`）→ 無不可逆遷移，備份非強制
- [x] 衝突面分析 + **真實 cherry-pick 演練**完成（見 1.3 C）
- [ ] **取得使用者 Go-Sign**

### 2.1 建立新分支 `my-config-v2026.11.1`

```bash
git checkout -b my-config-v2026.11.1 'upstream-v2026.11.1^{commit}'
```

- [ ] 確認 base commit = `4ffdd2047d1`、`package.json` version = `2026.11.1`

### 2.2 Purge 官方 Workflows 並覆蓋精簡版 `docker-release.yml`

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.10.10 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [ ] 確認 `.github/workflows/` 僅留 `docker-release.yml` 1 檔（`workflow_dispatch` only，input 名稱為 `tag`、第二個 input 為 `platforms`）

> 註：上游 11.1 的 `docker-release.yml` **本身零變更**，但上游改了 8 個其他官方 workflow；
> 我們整個 `.github/workflows/` 都會被 purge，因此最終只留我們那一版。

### 2.3 移植自訂 Commits 與解決衝突（保持線性歷史）

```bash
git cherry-pick fa0f5b1e452   # A: workflow purge + matrix docker-release.yml
git cherry-pick 3cd4f832b1e   # B: Dockerfile 自訂層 + Gemini 4200ms 限速 + 索引併發鎖
git cherry-pick 8eb2843a91d   # C: assets/whisper + docker/entrypoint-ssh.sh
git cherry-pick dc04077ce26   # D: Companion CJK Bigram FTS 索引
git cherry-pick 43600ab893b   # E: CJK 索引文件
```

- [ ] Commit A 完成 → **預期 8 個 modify/delete 衝突**（上游 11.1 改過的官方 workflow 檔）：
      `git rm` 該 8 檔 → `git cherry-pick --continue` → `.github/workflows/` 僅剩我們的 `docker-release.yml`
- [ ] Commit B 完成（零衝突）
- [ ] Commit C 完成（零衝突，`assets/whisper`、`docker/entrypoint-ssh.sh` 權限須為 `100755`）
- [ ] Commit D 完成（零衝突，17 檔）
- [ ] Commit E 完成（零衝突）
- [ ] 確認 `git log --merges upstream-v2026.11.1..HEAD` 為 **0 merge commits**

### 2.4 輕量本地驗證（Host Resource Protection — 不跑全庫 tsgo/vitest）

- [ ] `git grep -q 'Custom: Install faster-whisper' HEAD -- Dockerfile` 命中
- [ ] `git grep -n 'MIN_GEMINI_EMBEDDING_INTERVAL_MS' HEAD -- extensions/google/embedding-provider.ts` 命中
- [ ] `git grep -n 'syncMemoryCjkBigramRows' HEAD -- extensions/memory-core/src/memory/manager-chunk-writer.ts` 命中
- [ ] `git grep -n 'MEMORY_INDEX_CHUNKS_CJK_FTS_TABLE\|cjkBigram' HEAD -- packages/ extensions/ src/` 命中完整
- [ ] `git diff upstream-v2026.11.1 HEAD -- Dockerfile` 為 **純新增 46 行**、無刪改
- [ ] `git diff --stat upstream-v2026.11.1 HEAD -- .github/workflows/` 顯示只剩我們的 `docker-release.yml`
- [ ] 檢查 `assets/whisper` 與 `docker/entrypoint-ssh.sh` 權限皆為 `100755`
- [ ] `scripts/check-no-conflict-markers.mjs` 通過

> ⚠️ **本地不跑重型 typecheck／vitest**（Mac 主機保護，見執行前提）。型別與行為驗證交由 GitHub Actions 承載（見 2.5）。

### 2.5 Push 分支並由分支觸發 GHCR Build

```bash
git push -u origin my-config-v2026.11.1

gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.11.1 -f tag=v2026.11.1 -f platforms=all
```

- [ ] 分支已 push 至 `origin`（`kuniakil/openclaw`，**絕不 push `upstream`**，也不 push 任何 `v*` tag）
- [ ] dispatch 成功（若遇 `HTTP 422 Actions has been disabled`，依 Hard Rule 8 至
      `https://github.com/kuniakil/openclaw/actions` 點擊橫幅重新啟用；**不要**清 cache、不要改 repo settings）
- [ ] 立即驗證 Run 參數：`event == workflow_dispatch`、`headBranch == my-config-v2026.11.1`、`headSha == 我們的 HEAD`
- [ ] 派**背景子代理**執行 `gh run watch <run_id>`（build 10+ 分鐘，主迴圈不阻塞）
- [ ] 驗證 GHCR image tags 存在：`2026.11.1`、`v2026.11.1`、`2026.11.1-slim`、`latest`、`main`；
      manifest 含 `linux/amd64` + `linux/arm64`；記錄最終 digest

> **型別／行為驗證**：本次上游**沒有**動到我們自訂 commit 修改的任何非 workflow 檔（1.3 B 逐一驗證），
> 預期編譯與行為與 10.10 相同。若 `docker-release.yml` 的 build 失敗（`tsdown` 打包階段），
> 再依 10.10 的做法補一個臨時 `.github/workflows/upgrade-verification.yml`
> 跑 `pnpm tsgo:core` + `pnpm tsgo:extensions:all` + `vitest --config test/vitest/vitest.extension-memory.config.ts`，
> 驗證完隨即移除（回復「僅留 `docker-release.yml` 1 檔」）。

---

## Phase 3: 備份、K3s 部署與生產驗證

### 3.1 升級前備份（建議項；本次非 Schema 強制，但強烈建議）

> 🟢 本次 `schemaVersions` 未變更 → **不存在「舊版 binary 拒絕開啟新版 DB」的回滾障礙**。
> 但仍建議備份，理由：
> (a) 11.1 新增 Doctor 設定遷移（group allowlist fallback）會改寫 `openclaw.json`；
> (b) 記憶體索引（1,347 chunks / 3,413 embedding cache）重建成本高（Gemini 限速下 ~10 分鐘以上）；
> (c) 11.1 啟動後 `meta.lastTouchedVersion` 會變成 `2026.11.1`，之後若回滾到 10.10 binary，
> 舊 binary 會被 future-version guard 擋下破壞性設定動作（見回滾預案）。

```bash
# 1. Pre-flight：確認目前無並行 memory/agent 行程
kubectl --context n100-cf -n openclaw exec deploy/openclaw-gateway -- sh -lc \
  "ps -eo pid,etime,cmd | grep -E 'openclaw memory|openclaw agent' | grep -v grep || true"
kubectl --context n100-cf -n openclaw logs deploy/openclaw-gateway --since=3m 2>&1 | grep -c "\[memory\]"
kubectl --context n100-cf -n openclaw logs deploy/openclaw-gateway --since=30m 2>&1 | grep -c "RESOURCE_EXHAUSTED"

# 2. 於 N100 建立升級前完整一致備份（WAL-aware SQLite backup + rsync）
ssh n100-rescue "rsync -aH -A -X /data/services/openclaw/.openclaw/ /root/backup-openclaw-20261105/"
```

- [ ] Pre-flight 檢查通過（無殘留 CLI 行程、無 429）
- [ ] 備份建立完成並驗證：
  - 對每個 live SQLite 以 `sqlite3 ".backup"` 產生一致快照（快照已含 WAL 內容，移除旁邊 `-wal`/`-shm`），
    再以 `chown/chmod --reference` 對齊原始權限
  - `state/openclaw.sqlite` integrity=`ok`、user_version=**22**；
    `agents/main/agent/openclaw-agent.sqlite` integrity=`ok`、user_version=**27**
  - `openclaw.json` 完整（含 `meta.lastTouchedVersion`）
  - 記憶體索引基準記錄（見 1.4 C）已寫入本工作表

### 3.2 Kustomize 部署至 N100 K3s

```bash
# 更新 ~/kubernetes/openclaw/overlays/n100/kustomization.yaml newTag: "2026.11.1"
kubectl --context n100-cf apply -k ~/kubernetes/openclaw/overlays/n100
```

- [ ] 更新 `newTag` 為 `"2026.11.1"`；`kubectl kustomize` 渲染確認 image tag
- [ ] `kubectl diff -k`（對線上）**僅一處變更**：image tag `2026.10.10 → 2026.11.1`
- [ ] 部署前 pre-flight 再次採樣（無 memory/agent 行程、無 `[memory]` 事件、無 429）
- [ ] `kubectl apply -k` 輸出：`deployment.apps/openclaw-gateway configured`，其餘 `unchanged`
- [ ] 派**背景子代理**監看 `rollout status` 至 `1/1 Running`、`RESTARTS 0`
- [ ] 同步 `~/kubernetes` git commit & push（並同步 N100 `/home/kuniaki/kubernetes` checkout；
      該主機無 GitHub 憑證 → 沿用 `git bundle` 傳遞，不得落地任何憑證）

> **注意**：本次**不需要**「縮容 → `doctor --fix` → 擴容」流程（`state`/`agent` schema 未變更）。
> 若新 Pod 仍出現 exit code 78（schema 不符），代表實際 schema 與預期不符 → **立即停止並回報**，不要自行改 `user_version`。

### 3.3 啟動與功能驗證

- [ ] **版本與健康度**
  - `openclaw --version` = `OpenClaw 2026.11.1`
  - `/health` → `{"ok":true,"status":"live"}`
  - Pod `1/1 Running`、`RESTARTS 0`；`imageID` = GHCR manifest digest
  - 啟動 log：`ERROR` / `FATAL` / `CRITICAL` = 0、`RESOURCE_EXHAUSTED` = 0
- [ ] **Schema（唯讀確認未變）**
  - `state/openclaw.sqlite` `user_version` = **22**、`quick_check` = `ok`
  - `openclaw-agent.sqlite` `user_version` = **27**、`quick_check` = `ok`
  - `schema_meta` 的 `startup-migrations` / `state-migrations` 版本未被強制推進
- [ ] **自訂工具鏈存活**
  - `locale -a` 含 `en_US.utf8` / `zh_TW.utf8`
  - `python3 -c "import faster_whisper, edge_tts"` 成功；`ffmpeg`、`rsync` 可用
  - `/usr/sbin/sshd` 存在；`/usr/local/bin/whisper` 0755 可執行
  - `/app/dist/embedding-provider-*.mjs` 內含 `MIN_GEMINI_EMBEDDING_INTERVAL_MS`
- [ ] **記憶體索引未重建且 CJK 伴生索引對齊**（唯讀快照，不碰 live DB）
  - `memory_index_chunks` 與 `memory_index_chunks_cjk_fts` 筆數**仍相等**
  - `memory_index_meta_v1.chunkingVersion` 仍為 **6**、`embeddingInputFormatVersion` = 0、`provenanceVersion` = 1
  - `memory_embedding_cache` 筆數**未暴增**（若暴增 → 代表發生 re-chunk，需追查並套用限速）
  - 2 字中文召回對照：trigram 主索引對 2 字詞 = 0 rows、CJK bigram companion > 0 rows 且 BM25 可排序；負向對照 = 0 rows
- [ ] **設定未漂移**
  - `channels.telegram.groupAllowFrom` 仍為 `["830338761"]`、`groupPolicy` 仍為 `allowlist`
  - `channels.telegram.dmPolicy` 仍為 `pairing`
  - `agents.defaults.model.primary` 仍為 `minimax/MiniMax-M3`；`agents.entries.main.model` 仍為 `minimax/MiniMax-M2.5`
  - `memory.store.fts` 仍為 `{ tokenizer: "trigram", cjk: "bigram" }`
- [ ] **Gemini 路由抽查**：以唯讀方式確認 embedding 仍走 `google-generative-ai`（見 1.2 E），
      且記憶體搜尋（2 字詞）回應正常、無 provider 錯誤
- [ ] **真實訊息往返驗證**：由 Telegram 送一則真實訊息，確認 agent 回覆正常、
      記憶體召回（中文關鍵詞）正常、log 無 429

### 3.4 收尾

- [ ] 彙整驗證結果與備份清單，向使用者回報
- [ ] 依 10.10 的先例處理舊備份（**需使用者明確授權後才刪除**）
- [ ] 更新本工作表所有勾選項並 commit push
- [ ] 產出 postmortem 文件（`~/kubernetes/docs/`）

---

## 🔄 回滾預案（Rollback Plan）

> 🟢 **本次回滾比 10.10 簡單**：schema 未升版（`22` / `27` 皆與 10.10 相同）→
> 舊版 `2026.10.10` binary 可以直接開啟目前的 DB，**不需要**降版 schema 或還原 DB 快照。
> 唯一需處理的是 `openclaw.json` 的 `meta.lastTouchedVersion`（若 11.1 寫過設定，會變成 `2026.11.1`）。

```bash
# 1. 停止新版 Gateway 寫入
kubectl --context n100-cf -n openclaw scale deploy/openclaw-gateway --replicas=0

# 2.（僅在 11.1 已改寫設定時）還原升級前設定檔；或設定允許舊 binary 的破壞性動作
#    OPENCLAW_ALLOW_OLDER_BINARY_DESTRUCTIVE_ACTIONS=1
#    11.1 新增的 serviceMode 提示指向 docs.openclaw.ai/install/updating/rollback-and-recovery#downgrade
#    完整回滾（保守做法）：從 /root/backup-openclaw-20261105/ 還原 .openclaw 資料目錄
ssh n100-rescue "rsync -aH --delete /root/backup-openclaw-20261105/ /data/services/openclaw/.openclaw/"

# 3. 改回舊 image tag 並重新部署
sed -i '' 's|newTag: "2026.11.1"|newTag: "2026.10.10"|' ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
kubectl --context n100-cf apply -k ~/kubernetes/openclaw/overlays/n100
kubectl --context n100-cf -n openclaw scale deploy/openclaw-gateway --replicas=1
kubectl --context n100-cf -n openclaw rollout status deploy/openclaw-gateway
```

**回滾後檢查**：`openclaw --version` = `2026.10.10`；`user_version` 仍為 `22` / `27`；
`memory_index_chunks` 與 `memory_index_chunks_cjk_fts` 仍相等；Telegram 收發正常。

---

## 📌 分析階段結論摘要

1. **本次升級風險等級：低**（相較 10.10 的高風險）。
2. **無不可逆 Schema 遷移** → 不需 Doctor 遷移流程、不需 DB 還原才能回滾。
3. **不重建 embedding 索引**（chunking / provenance / 輸入格式 / 模型 四者皆未變）。
4. **自訂層 100% 存活**：`Dockerfile` 上游零變更、我們修改的 15 個非 workflow 檔上游零變更。
5. **唯一衝突**：8 個官方 workflow 檔的 modify/delete，預期且可解（接受刪除）。
6. **需在部署後抽查**：Google Interactions 預設路由（embedding 不受影響，但需實測確認）、
   Doctor group-allowlist 遷移未改寫我們的明確清單、記憶體索引未 re-chunk。
