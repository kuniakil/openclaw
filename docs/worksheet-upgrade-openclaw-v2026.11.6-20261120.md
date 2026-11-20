# OpenClaw 升級工作表：v2026.11.5 → v2026.11.6

- 日期：2026-11-20
- 目前分支：`my-config-v2026.11.5`（HEAD `da6b7d190a1`）
- 目標：`v2026.11.6`（發佈 2026-11-19 17:26 UTC，stable，非 prerelease，`gh release list` 標記 `Latest`）
  - upstream commit：`06afb10d3272cc9deaf38ca6a3b7b839d5935638`（`upstream-v2026.11.6`）
  - 前一版 baseline：`upstream-v2026.11.5` = `e13cf15ece9bbd969b7362927c315362c90c97ff`
- 新分支：`my-config-v2026.11.6`
- 目標 Image：`ghcr.io/kuniakil/openclaw:2026.11.6`
- 線上現況：`ghcr.io/kuniakil/openclaw:2026.11.5`，deploy `openclaw-gateway`（1/1 Running，150d），ctx `n100`，ns `openclaw`
- 上游規模：406 commits / 386 PRs / 157 contributors，2917 files changed（+98814 / −25232）

---

## 摘要（先讀這段）

| 項目                 | 結論                                                                                                                                                                            |
| :------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 目標版本             | `v2026.11.6`（stable，Latest；`isPrerelease=false`、`isDraft=false`）                                                                                                           |
| 升級性質             | **中型功能升級**（406 commits；上游 11.5 → 11.6 為連續歷史，非分歧）                                                                                                            |
| 不可逆點             | **無** — `schemaVersions` `state 36 → 36`、`agent 38 → 38` **完全未變**（§1.2）→ 不需要強制備份即可回滾，且**不需要 scale-0 / 維護 Pod / `doctor --fix`**（§2.9）               |
| 自訂 patch 可移植性  | **8 個自訂 commit 全部可移植**；乾跑實測僅 **2 組衝突**（6 個 workflow 刪除衝突 + 1 個生成檔內容衝突），且 purge 步驟可改用「重建 purge commit」路徑 → **實作時零衝突**（§1.5） |
| 上游 breaking change | **0 明確標記**；`docs/install/updating.md` +207 行全屬**內建 updater 路徑**（systemd / git update / candidate doctor），我們走 GHCR image 部署 → **不適用**（§1.7）             |
| 上游已知 bug 影響    | **1 項需確認但實測無影響**：#202213 壓縮 session 封存讀取回歸（`ERR_BUFFER_TOO_LARGE`）；線上 **0 個 `.jsonl.zst`、0 個 `.jsonl`** → 不受影響（§1.8）                           |
| Base image           | **trixie → trixie**（上游 11.5→11.6 未改 Dockerfile）→ 我們的 46 行自訂層 **零衝突**（§1.6）                                                                                    |
| CJK 策略決議         | **維持保留自訂 CJK Han Bigram 伴隨索引**；乾跑已驗證自動合併成功，同時保留上游 `lifetime: "process"` 與我們的 `cjkBigramFts` admission key（§1.9）                              |
| 記憶體索引重建       | **不需要**（schema / embedding 模型 / 輸入格式版本皆未變）（§1.10）                                                                                                             |
| 目前狀態             | Phase 1 完成（分析 + 乾跑 + 線上實查），**等待 Phase 2 Go-Sign**（尚未建立分支、未推送、未觸發建置、未動線上）                                                                  |

---

## 🚦 Go-Sign Gate

- [x] Phase 1 完成官方 Release Notes、`schemaVersions` 與衝突乾跑分析
- [x] **CJK Han Bigram 伴隨索引策略確認：維持保留自訂實作**（乾跑已驗證零衝突、自動合併正確）
- [x] 確認線上無壓縮 session 封存（#202213 回歸無影響）
- [x] 不在 Mac 本機跑重型 CI（`tsgo`/`vitest`）或本機 `docker build`（全交 GitHub Actions）
- [x] 升級期間不另起 `openclaw memory index/search/reset`、`agent --local`（避免雙行程撞 Gemini 配額）
- [x] 10+ 分鐘長等待（`gh run watch`、`kubectl rollout status`）一律派給背景子代理
- [x] 使用者明確核准執行 Phase 2（Go-Sign）— 2026-11-20 已核准「完整執行（含部署上線）」

---

## Phase 1: 分析結果

### 1.1 官方 Release Notes 摘要（406 commits，範圍 `e13cf15ece9b..06afb10d327`）

Release：<https://github.com/openclaw/openclaw/releases/tag/v2026.11.6>（發佈 2026-11-19 17:26:46 UTC）
Changelog：`CHANGELOG/2026.11.6.md`（上游 tag 內，223 行）
Release SHA：`06afb10d3272cc9deaf38ca6a3b7b839d5935638`（與 `upstream-v2026.11.6` rev-parse **一致**）

**供應鏈核對（三方一致）**

| 來源              | 值                                                                                                                                                                     |
| :---------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GitHub Release    | release SHA `06afb10d3272cc9deaf38ca6a3b7b839d5935638`                                                                                                                 |
| 本地 upstream tag | `git rev-parse upstream-v2026.11.6^{commit}` = `06afb10d3272cc9deaf38ca6a3b7b839d5935638`                                                                              |
| npm registry      | `openclaw@2026.11.6` integrity `sha512-4MGjAMv8QlVrul3ZbCu8KjM7GhXfLdLzf0IrsO5QZ8LC3oYkduqs2rZiZpPDmTRpT6kXYke/OVaWrB+YmhBHLw==` — **與 release notes 公布值逐字相符** |

npm dist-tags：`latest = 2026.11.6`、`extended-stable = 2026.10.33`、`beta = 2026.11.10-beta.1`
→ 我們的 fork 跟的是 `latest` 線（2026.11.x），與歷次升級（11.1→11.5）一致；`beta` 線不採用。

**Highlights（上游原文摘要）**

| 主題                    | 內容                                                                                                                                      |
| :---------------------- | :---------------------------------------------------------------------------------------------------------------------------------------- |
| Smoother upgrades       | 橋接 2026.11.5 updater 到現行 release 路徑；Windows 上正確驗證 staged plugin 依賴（#200662, #200595）                                     |
| Resilient conversations | 設定編輯期間 subagent / background turn 續跑；Gateway 重啟中斷傳送時仍交付最終答案（#200516, #200553）                                    |
| Lighter Gateway         | 降低啟動記憶體壓力與常駐記憶體；延後載入未用憑證 runtime；plugin tool discovery 不再阻塞 Gateway（#191272, #198194, #188033）             |
| Reliable long turns     | 保留 append-only provider history、Responses tool-argument 原始位元組、長 tool-heavy Claude CLI 回合最終回覆（#197874, #200020, #200501） |
| Conversation continuity | compaction 期間保留已載入的聊天歷史；iOS Talk turn 可超過原本 30 秒上限（#199534, #163474）                                               |

**Fixes（與我們部署相關者）**

- Credential handling：設定讀取時遮蔽 inline 環境變數憑證；保留 SecretRef-backed skill API key（#190618, #200539）→ 我們有用 SecretRef，**有利**
- Safe configuration writes：寫入前保留 malformed UTF-8 設定來源；pre-update 寫入被中斷時保留 rollback snapshot（#194181, #189946）→ **有利**
- Session storage：大型 rewind 不再耗盡共用 DB worker；慢速 history 讀取不再阻塞 transcript 寫入（#198786, #187989）→ **有利**
- Large file reads：不再整份載入檔案（#186992）→ 記憶體/工具行為改善
- Automation continuity：chat identifier 變更時排程自動化仍續跑（#200396）
- Channel messages：Discord user mention / Slack、Feishu、Zalo 多行指令引號保留（#200053, #190730）

### 1.2 關鍵發現 A：`schemaVersions` 未變更 → **可逆升級**

```bash
git show upstream-v2026.11.5:package.json | python3 -c "import json,sys;print(json.load(sys.stdin)['openclaw']['schemaVersions'])"
# {'state': 36, 'agent': 38}
git show upstream-v2026.11.6:package.json | python3 -c "import json,sys;print(json.load(sys.stdin)['openclaw']['schemaVersions'])"
# {'state': 36, 'agent': 38}
```

**結論：`state` 與 `agent` schema 版本都沒有變動。** 與 11.4 → 11.5（state 22→36、agent 27→38）那次不可逆升級不同，本次：

- 不需要強制完整備份才能回滾（但仍建議做，見 §2.1）
- 不需要等待上游 11.6 之外的 schema 遷移
- **不需要重建記憶體 embedding 索引**（見 §1.10）

其他版本欄位：

| 欄位           | 11.5                          | 11.6        | 變動       |
| :------------- | :---------------------------- | :---------- | :--------- |
| `version`      | `2026.11.5`                   | `2026.11.6` | 是（預期） |
| `engines.node` | `>=24.16.0 <25 \|\| >=26.1.0` | 同左        | 否         |

### 1.3 上游是否為分歧歷史

11.5 → 11.6 為 **上游連續歷史**（406 commits 直接接續），無需像 11.4 → 11.5 那樣處理兩條分歧線。我們的 `upstream-v2026.11.6` 直接以 `refs/tags/v2026.11.6` 抓取，`^{commit}` = `06afb10d327`，與官方 release notes 公布 SHA 一致。

### 1.4 自訂 Patch 清單（`upstream-v2026.11.5..my-config-v2026.11.5`，共 8 個 commit）

| #   | Commit        | 內容                                                                   | 可移植性               |
| :-- | :------------ | :--------------------------------------------------------------------- | :--------------------- |
| 1   | `54f3a4620d4` | `chore:` purge 官方 CI workflows，改用自訂 Matrix `docker-release.yml` | ⚠️ 需解 6 個刪除衝突   |
| 2   | `562e54571d8` | `chore:` 恢復自訂 Dockerfile 層、scripts、Gemini 限速、TODOs           | ✅ 乾跑乾淨            |
| 3   | `fd9ad44850a` | `fix(docker):` 恢復 `assets/whisper`、`docker/entrypoint-ssh.sh`       | ✅ 乾跑乾淨            |
| 4   | `6b3ea289f00` | `feat(memory):` CJK Han Bigram 伴隨 FTS 索引                           | ⚠️ 需解 1 個生成檔衝突 |
| 5   | `27caf4f284a` | `docs:` 帶入歷史升級工作表                                             | ✅ 乾跑乾淨            |
| 6   | `5912a401dcf` | `docs:` 新增 v2026.11.5 升級工作表                                     | ✅ 乾跑乾淨            |
| 7   | `3a2946e82cc` | `docs:` 記錄 v2026.11.5 部署與驗證結果                                 | ✅ 乾跑乾淨            |
| 8   | `da6b7d190a1` | `docs:` 記錄 Telegram roundtrip 與 1483 DB 驗證                        | ✅ 乾跑乾淨            |

### 1.5 關鍵發現 B：衝突乾跑（**實測，非預測**）

在隔離的臨時 worktree（`/tmp/oc-upgrade-dryrun`，已於分析後移除）以 `upstream-v2026.11.6` 為基底，逐一 cherry-pick 上述 8 個 commit：

```
⚠️  CONFLICT 54f3a4620d4  chore: purge official CI workflows; use optimized matrix docker-release.yml
      RESOLVED(delete, purge intent): .github/workflows/ci.yml
      RESOLVED(delete, purge intent): .github/workflows/full-release-validation.yml
      RESOLVED(delete, purge intent): .github/workflows/openclaw-repo-e2e-reusable.yml
      RESOLVED(delete, purge intent): .github/workflows/package-acceptance.yml
      RESOLVED(delete, purge intent): .github/workflows/plugin-npm-release.yml
      RESOLVED(delete, purge intent): .github/workflows/plugin-prerelease.yml
✅ CLEAN     562e54571d8  chore: upgrade to v2026.9.7; restore custom Dockerfile layer, scripts, rate pacing, and TODOs
✅ CLEAN     fd9ad44850a  fix(docker): restore assets/whisper and docker/entrypoint-ssh.sh for v2026.9.8
⚠️  CONFLICT 6b3ea289f00  feat(memory): add CJK bigram companion FTS index for two-character queries
      RESOLVED(take upstream, regenerate later): docs/.generated/config-baseline.sha256
✅ CLEAN     27caf4f284a  docs: carry over historical upgrade worksheets
✅ CLEAN     5912a401dcf  docs: add v2026.11.5 upgrade worksheet and record Phase 2 prep
✅ CLEAN     3a2946e82cc  docs: record v2026.11.5 deployment and verification results
✅ CLEAN     da6b7d190a1  docs: record Telegram roundtrip and 1483 DB verification in v2026.11.5 worksheet
```

**衝突組 1 — 6 個 workflow（modify/delete）**：上游 11.5→11.6 修改了 6 個我們在 commit #1 刪掉的 workflow。

```
.github/workflows/ci.yml
.github/workflows/full-release-validation.yml
.github/workflows/openclaw-repo-e2e-reusable.yml
.github/workflows/package-acceptance.yml
.github/workflows/plugin-npm-release.yml
.github/workflows/plugin-prerelease.yml
```

→ **解法：保留刪除**（`git rm`）。上游 121 個 workflow → 我們維持 **僅 `docker-release.yml`**（已於乾跑後驗證 `ls .github/workflows/` 只有一個檔案）。

**衝突組 2 — `docs/.generated/config-baseline.sha256`（內容衝突）**：這是**生成檔**（digest 對應未追蹤的 `config-baseline*.json`）。合併後的正確值取決於合併後的樹 → **必須重新產生**，不可手改（見 §2.5）。

> `docs/.generated/config-baseline.counts.json` **未衝突**（上游 11.6 的 counts 與 11.5 相同：`core 2579 / channel 4003 / plugin 4889`；我們的 CJK 變更把它改成 `core 2581 / channel 4003 / plugin 4859` → **我們的值正確**，上游未動）。

#### 交叉檢查（預測 vs 實測一致）

```bash
comm -12 <(git diff --name-only upstream-v2026.11.5 my-config-v2026.11.5 | grep -v '^\.github/workflows/' | sort -u) \
         <(git diff --name-only upstream-v2026.11.5 upstream-v2026.11.6 | sort -u)
# docs/.generated/config-baseline.sha256
# packages/memory-host-sdk/src/host/memory-schema.ts
# scripts/pr-lib/wrapper-components.txt
# src/infra/update-candidate-state.inventory.test.ts
```

- `wrapper-components.txt`：我們加 1 行（`packages/memory-host-sdk/src/host/cjk-bigram.ts`），上游加 ~25 行於**不同區段** → 自動合併 ✅
- `update-candidate-state.inventory.test.ts`：我們改第 ~547 行（integrity_check 排序），上游在第 ~48 行**新增**測試 → 自動合併 ✅
- `memory-schema.ts`：**預測會衝突，實測自動合併成功且結果正確**（見 §1.9）

### 1.6 Dockerfile / base image

上游 11.5 → 11.6 **未修改 Dockerfile**（`git diff --stat upstream-v2026.11.5 upstream-v2026.11.6 -- Dockerfile` 為空）。

我們的 Dockerfile 與上游 11.6 的差異 **只有 46 行自訂層**（`git diff --stat upstream-v2026.11.6 my-config-v2026.11.5 -- Dockerfile` = `46 insertions`），且 base image 兩版皆為 trixie：

```
FROM ${OPENCLAW_NODE_TRIXIE_IMAGE} AS workspace-deps
...
FROM ${OPENCLAW_NODE_TRIXIE_SLIM_IMAGE} AS base-runtime
```

乾跑後驗證自訂層完整保留：

```
Dockerfile: 4 個 "Custom:" 標記
  :448  # Custom: Generate UTF-8 locales and install rsync
  :467  # Custom: Install faster-whisper, edge-tts, and ffmpeg for audio TTS/STT pipelines
  :487  # Custom: SSH server support for Zeabur deployment
  :521  ENTRYPOINT ["tini", "-s", "--", "node", "/app/docker-entrypoint.mjs"]
```

### 1.7 上游 breaking change / 升級注意事項

- Changelog 內**無** `breaking` / `deprecate` / `removed` / `migration` 標記（grep 為空）。
- `docs/install/updating.md` 11.5→11.6 **+207 行**，內容全部屬於**內建 updater 流程**：systemd 服務恢復、Git-source update、`candidate doctor`、update lease、pre-update config snapshot、Ctrl-C 訊號轉發等。
  → **我們不使用 `openclaw update`**（我們部署預先建好的 GHCR image + Kustomize），這些條目對我們**不適用**。唯一通用的是「讀取設定時遮蔽 inline 憑證」與「寫入設定保留 rollback snapshot」，兩者都對我們有利。
- `extensions/memory-core/package.json` peerDep 升為 `openclaw: >=2026.11.6`（我們從 11.6 tag 起分支，自動取得正確值）。
- `extensions/google/package.json` 僅版本號 bump；`extensions/google/embedding-provider.ts` 上游**未改** → 我們的限速 patch 不需調整。

### 1.8 上游已知問題（針對 11.5 → 11.6）

| Issue       | 標籤                  | 內容                                                                                                                                                                                                                        | 對我們影響                                                                                                                                               |
| :---------- | :-------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **#202213** | bug / regression / P1 | 11.6 讀取壓縮 session 封存（`*.jsonl.zst`）在「明文 transcript 大於壓縮檔 + 1 MiB」時拋 `ERR_BUFFER_TOO_LARGE`；修補 PR #192743 只在 main、**未進任何 stable**（已用 `git log --grep=192743 upstream-v2026.11.6` 確認為空） | **無影響**：線上實查 `find /home/node/.openclaw -name '*.jsonl.zst'` = **0**、`-name '*.jsonl'` = **0** → 我們用 SQLite transcript，不產生也不讀壓縮封存 |
| #202467     | bug                   | Control UI 在 WebKit（Linux app）開 Sessions 篩選選單時凍結                                                                                                                                                                 | **不適用**：我們是 K3s Docker + macOS Control UI，無 Linux app                                                                                           |
| #202314     | bug                   | macOS 上 process supervisor wrapper 與 stdio MCP server 未回收                                                                                                                                                              | **不適用**：我們的 Gateway 在 K3s；Mac 上若有本地 Gateway 才需留意                                                                                       |
| #202405     | bug                   | HTTP pool shutdown fallback 留下 active stream 與 Node 存活（11.5 / 11.6）                                                                                                                                                  | **可能**：影響 Gateway 關閉時序 → rollout 時觀察 Pod 收尾是否乾淨（§2.9）                                                                                |
| #202250 等  | bug                   | `update migration-plan` / `candidate-doctor` / `package-update` 失敗                                                                                                                                                        | **不適用**：屬內建 updater 路徑                                                                                                                          |

> ⚠️ 若日後我們開始使用壓縮 session 封存（`session-archive` 冷層），**必須先等 #192743 進 stable**，否則大型封存讀取會失敗。建議記為待辦。

### 1.9 CJK Han Bigram 伴隨索引：相容性驗證（**本版最重要的技術點**）

我們的自訂 feature 在 `packages/memory-host-sdk/src/host/memory-schema.ts` 的 memory index schema admission key 上加了一個元素；上游 11.6 在**同一個物件**上新增了 `lifetime: "process"`。

**上游 11.6 的改動**（`git diff upstream-v2026.11.5 upstream-v2026.11.6 -- packages/memory-host-sdk/src/host/memory-schema.ts`）：

```diff
     schemaDependent: true,
+    lifetime: "process",
     read: readMemoryIndexSchemaAdmission,
```

**我們的改動**：在 admission key 陣列尾端加入 `Boolean(params.cjkBigramFts)`，並在 `ensureMemoryIndexSchema` 內呼叫 `ensureMemoryCjkBigramFtsSchema`。

**乾跑後的合併結果（已驗證，兩者並存）**：

```ts
// packages/memory-host-sdk/src/host/memory-schema.ts:156-161
      params.ftsTokenizer ?? "unicode61",
      Boolean(params.cjkBigramFts),     // ← 我們的
    ])}`,
    schemaDependent: true,
    lifetime: "process",                // ← 上游的
    read: readMemoryIndexSchemaAdmission,
```

**上游新測試是否會被我們破壞？** 上游 11.6 新增 `packages/memory-host-sdk/src/host/memory-schema-admission.test.ts`（11.5 已有此檔，11.6 改寫），其嚴格斷言「admission 重用時**零** schema SQL」：

```ts
const schemaSql =
  /sqlite_(?:schema|master)|pragma_(?:table|index|foreign_key)|\bPRAGMA\s+...|\b(?:CREATE|ALTER|DROP)\s+(?:TABLE|INDEX|TRIGGER|VIRTUAL)\b/iu;
expect(schema).toEqual([]); // reused 時必須為空
```

我們的 CJK 停用路徑會執行 `isTablePresent(db, MEMORY_INDEX_CJK_FTS_TABLE)`，其 SQL 為：

```sql
SELECT 1 FROM memory_index_chunks_cjk_fts LIMIT 0
```

→ **不匹配**上游的 `schemaSql` regex（不含 `sqlite_master` / `PRAGMA` / `CREATE` / `DROP`）。
→ **結論：我們的 feature 不會讓上游新測試失敗。** 這是本次升級唯一有實質回歸風險的點，已排除。

**其他 CJK 檔案安全性**（上游 11.5→11.6 均未觸碰，乾跑皆 CLEAN）：

```
src/config/zod-schema.memory-search.ts      （`cjk: z.literal("bigram").optional()` 保留）
src/agents/memory-search.ts
src/infra/database-engine/sqlite-search-schema.ts
src/infra/database-engine/sqlite-memory-search-fragments.ts
extensions/memory-core/src/memory/manager.ts
extensions/google/embedding-provider.ts     （MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200 保留）
```

#### 與上游 bigram 機制的關係：**互補，不是重複實作**（避免雙重 owner）

上游 11.6 確實有 `bigram` 字樣，但**位於不同層**：

| 機制                                                                             | 層級                        | 作用                                                                  |
| :------------------------------------------------------------------------------- | :-------------------------- | :-------------------------------------------------------------------- |
| 上游 `extensions/memory-core/src/memory/tokenize.ts`（CJK bigram/unigram 分詞）  | 關鍵字抽詞 / Jaccard 相似度 | 把 CJK 切出 bigram 與 unigram 詞元，用於**關鍵字覆蓋比對**            |
| 上游 `packages/memory-host-sdk/src/host/query-expansion.ts`（`extractKeywords`） | 查詢展開                    | 產出關鍵字；trigram 模式會跳過日文漢字 bigram                         |
| **我們的 CJK 伴隨索引**（`memory_index_chunks_cjk_fts`）                         | **FTS 排序層**              | 主索引（trigram）**無法排序**兩字查詢時，改由伴隨 FTS5 表做 BM25 排序 |

上游 11.5→11.6 **未修改** `keyword-query.ts` 與 `query-expansion.ts` → 我們的擴充層與上游彼此獨立，**無 owner 衝突、無重複實作**。

#### 上游 PR #193815 狀態

```bash
gh pr view 193815 --repo openclaw/openclaw --json state,mergedAt,author
# state=OPEN  mergedAt=null  author=kuniakil
```

→ 該 PR **仍未合併**，上游 11.6 `git grep -i 'bigram'` 也只命中 keyword-extraction 檔案，**沒有** companion FTS index。
→ 結論：**我們的自訂實作仍是必要且唯一的 owner**，維持保留（延續 11.5 的方案 B 決議）。

### 1.10 記憶體 embedding 索引重建：**不需要**

依 `agent-release-upgrade` skill 的判準逐項檢查：

| 判準                           | 檢查結果                                                         |
| :----------------------------- | :--------------------------------------------------------------- |
| `openclaw.schemaVersions` 變更 | ❌ 未變（state 36 / agent 38）                                   |
| embedding 模型變更             | ❌ 未變（`extensions/google/embedding-provider.ts` 上游未改）    |
| embedding 輸入格式版本變更     | ❌ 未變（`resolveEmbeddingInputFormatVersion` 相關檔案上游未改） |
| 明確要清除 embedding 快取      | ❌ 無此需求                                                      |

→ **升級後索引與快取繼續沿用，不要主動 `openclaw memory index` 或 `memory reset`。**

### 1.11 保留資產清單（乾跑後逐項驗證）

| 資產                                                                                    | 驗證結果                                                   |
| :-------------------------------------------------------------------------------------- | :--------------------------------------------------------- |
| `.github/workflows/` 僅 `docker-release.yml`                                            | ✅（上游 121 → 我們 1）                                    |
| `docker-release.yml` 為我們的 Matrix 版                                                 | ✅ `workflow_dispatch` only，dispatch input 名為 **`tag`** |
| `Dockerfile` 自訂層（locales/rsync/tini/faster-whisper/edge-tts/ffmpeg/openssh-server） | ✅ 4 個 `Custom:` 標記保留                                 |
| `assets/whisper`                                                                        | ✅ 存在                                                    |
| `docker/entrypoint-ssh.sh`                                                              | ✅ 存在                                                    |
| `packages/memory-host-sdk/src/host/cjk-bigram.ts`                                       | ✅ 存在                                                    |
| `memory.search.fts.cjk = "bigram"` 設定選項                                             | ✅ 存在（`src/config/zod-schema.memory-search.ts:66`）     |
| Gemini 限速 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`                                   | ✅ 存在（`extensions/google/embedding-provider.ts:226`）   |
| `package.json` version                                                                  | ✅ `2026.11.6`                                             |

---

## Phase 2: 執行步驟（取得 Go-Sign 後）

### 2.1 備份與基線確認

> ⚠️ **SSH 必須用 `root` 帳號**：`/root` 權限為 `drwx------ root root`，`kuniaki` 帳號讀寫 `/root` 會被拒（`sudo -n` 亦失敗）。git remote `n100` = `root@192.168.31.72`，直接用它即可。

```bash
# 盤點既有備份（本次已有 2 份，勿重複佔空間）
ssh root@192.168.31.72 "du -sh /root/backup-openclaw-* 2>/dev/null || echo '無既有備份'"
# 既有：/root/backup-openclaw-20261116-v2026.11.4 (2.4G)
#       /root/backup-openclaw-20261117-pre-v2026.11.5 (2.4G)

# 建立本次 rollback 備份（只備不可取代的執行期狀態）
ssh root@192.168.31.72 "rsync -aH /data/services/openclaw/.openclaw/ /root/backup-openclaw-$(date +%Y%m%d)-pre-v2026.11.6/"
ssh root@192.168.31.72 "du -sh /root/backup-openclaw-$(date +%Y%m%d)-pre-v2026.11.6"

# 核對 N100 磁碟餘量（上次基準：總 1.8T / 已用 637G / 可用 1.1T）
ssh root@192.168.31.72 "df -h / | tail -1"

# Mac 端異地備份關鍵 DB（沿用既有目錄 /Users/mlee/openclaw-backups/）
#   內容：openclaw.json、openclaw.sqlite.gz、openclaw-agent.sqlite.gz
#   驗證：gzip -t *.gz
```

> 本次 schema 未變更（§1.2）→ 備份**非強制**（11.4→11.5 那次才是）。但仍建議做，成本低、可回滾。
> 熱備份需含 `-wal` / `-shm`；若要冷備份，先 `kubectl -n openclaw scale deploy/openclaw-gateway --replicas=0` 再 rsync，完成後 scale 回 1。

**✅ 執行結果（2026-11-20）**

| 項目                                    | 結果                                                                                             |
| :-------------------------------------- | :----------------------------------------------------------------------------------------------- |
| N100 熱備份                             | `/root/backup-openclaw-20261120-pre-v2026.11.6` = **2.7G** ✅                                    |
| N100 磁碟                               | 總 1.8T / 已用 647G / 可用 **1.1T**（38% used）✅                                                |
| Mac 異地備份（一致化 `.backup` + gzip） | `/Users/mlee/openclaw-backups/openclaw-pre-v2026.11.6-20261120.tar.gz` = 185M，`gzip -t` 通過 ✅ |
| 既有備份盤點                            | `20261116-v2026.11.4` (2.4G)、`20261117-pre-v2026.11.5` (2.4G) — 保留待觀察期後再問使用者        |
| 舊版快照分支                            | `backup/my-config-v2026.11.5` → `origin/my-config-v2026.11.5` (`da6b7d190a1`) ✅                 |

### 2.2 建立新分支（從官方 baseline 開，不要從本地 `v*` tag）

```bash
cd /Users/mlee/openclaw
git fetch upstream refs/tags/v2026.11.6:refs/tags/upstream-v2026.11.6 --no-tags
git rev-parse upstream-v2026.11.6^{commit}   # 必須 = 06afb10d3272cc9deaf38ca6a3b7b839d5935638
git checkout -b my-config-v2026.11.6 upstream-v2026.11.6
```

### 2.3 Purge 官方 Workflows 並覆蓋 Matrix `docker-release.yml`

**採用「重建 purge commit」路徑（零衝突，與 11.5 做法一致）**：

```bash
# 上游 11.6 有 121 個 workflow；只留我們的 Matrix docker-release.yml
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.11.5 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

> 這條路徑**不需要處理任何衝突**，產生的 tree 與乾跑中「cherry-pick purge commit + 6 個 `git rm`」的結果完全相同（已驗證：最終只剩 `docker-release.yml`）。
> 替代路徑（若想保留原 commit 歷史）：`git cherry-pick 54f3a4620d4` → 6 個 workflow 會是 modify/delete 衝突，**一律 `git rm`（保留刪除）**：
>
> ```bash
> for f in $(git diff --name-only --diff-filter=U); do git rm --quiet -- "$f"; done
> git add -A && git cherry-pick --continue
> ```

**接著移植其餘自訂 commits（順序重要：Dockerfile → assets → CJK → docs）**：

```bash
git cherry-pick 562e54571d8   # ✅ 乾淨（Dockerfile 自訂層、Gemini 限速、TODOs）
git cherry-pick fd9ad44850a   # ✅ 乾淨（assets/whisper、docker/entrypoint-ssh.sh）
```

### 2.4 移植 CJK 與文件 commits

```bash
git cherry-pick 6b3ea289f00   # ⚠️ 僅 docs/.generated/config-baseline.sha256 衝突
git cherry-pick 27caf4f284a   # ✅（帶入歷史工作表）
git cherry-pick 5912a401dcf   # ✅
git cherry-pick 3a2946e82cc   # ✅
git cherry-pick da6b7d190a1   # ✅
```

**`config-baseline.sha256` 衝突解法：** 取上游版本先讓 cherry-pick 通過，**隨後於 §2.5 重新產生**（生成檔不可手改）：

```bash
git checkout --theirs -- docs/.generated/config-baseline.sha256
git add docs/.generated/config-baseline.sha256 && git cherry-pick --continue
```

> 我們的 CJK commit `6b3ea289f00` 已是**適配 agent v38 的版本**（11.5 當時已手工合併過 `manager-search-types.ts`），因此與 11.5 升級時「PR #193815 原始 commit 有 3 個衝突」的情況不同 → 本次乾跑僅 1 個生成檔衝突。
> 上游 PR #193815 目前仍 **OPEN**（`author=kuniakil`），我們的自訂實作仍是唯一 owner。

### 2.5 重新產生 config baseline（生成檔）

```bash
pnpm config:docs:gen      # = node --import ./scripts/tsx.mjs scripts/generate-config-doc-baseline.ts --write
pnpm config:docs:check    # 驗證：OK docs/.generated/config-baseline.sha256 and docs/.generated/config-baseline.counts.json
git add docs/.generated/
git commit -m "chore(docs): regenerate config baseline for v2026.11.6"
```

> 合併後預期 counts：`core 2581 / channel 4003 / plugin 4859`（= 上游 11.6 的 2579/4003/4889 + 我們 CJK 的 +2 core / −30 plugin）。若重新產生後數值不同，以重新產生的為準並記錄。

### 2.6 本地輕量驗證（嚴禁重型 CI / 本機 docker build）

```bash
git status -sb
git log --oneline upstream-v2026.11.6..HEAD

# 必須只剩一個 workflow
ls .github/workflows/

# 自訂層與 CJK 仍在
grep -c 'Custom:' Dockerfile
grep -n 'MIN_GEMINI_EMBEDDING_INTERVAL_MS' extensions/google/embedding-provider.ts
grep -n 'cjk' src/config/zod-schema.memory-search.ts
grep -n 'cjkBigramFts' packages/memory-host-sdk/src/host/memory-schema.ts

# 上游 11.6 的 admission 概念與我們的並存
grep -n -A2 'schemaDependent: true' packages/memory-host-sdk/src/host/memory-schema.ts | head -5

# 版本與 schema
python3 -c "import json;d=json.load(open('package.json'));print(d['version'], d['openclaw']['schemaVersions'])"

# workflow dispatch input 名稱（必須是 tag，不是 tag_name）
grep -A6 'workflow_dispatch:' .github/workflows/docker-release.yml
```

**✅ 執行結果（2026-11-20）**

| 步驟                                       | 結果                                                                                                                  |
| :----------------------------------------- | :-------------------------------------------------------------------------------------------------------------------- |
| 新分支                                     | `my-config-v2026.11.6` @ `06afb10d327`（官方 baseline），`version=2026.11.6`，`schemaVersions={state:36,agent:38}` ✅ |
| Purge workflows                            | 上游 121 → **1**（`docker-release.yml`）；`on:` 僅 `workflow_dispatch`，input 名為 `tag` ✅                           |
| cherry-pick `562e54571d8`（Dockerfile 等） | ✅ CLEAN                                                                                                              |
| cherry-pick `fd9ad44850a`（assets/SSH）    | ✅ CLEAN                                                                                                              |
| cherry-pick `6b3ea289f00`（CJK bigram）    | ⚠️ 僅 `docs/.generated/config-baseline.sha256` 衝突 → 取上游版佔位，隨後重新產生 ✅                                   |
| cherry-pick 4 個 docs commits              | ✅ 全部 CLEAN                                                                                                         |
| `pnpm config:docs:gen`                     | 重新產生 `.sha256` + `.counts.json`；`--check` **OK** ✅                                                              |
| counts.json 實測值                         | `core 2581 / channel 4003 / plugin 4859` — **與預期完全一致**（上游 11.6 的 2579/4003/4889 + 我們 CJK 的 +2/−30）✅   |
| 保留資產驗證                               | Dockerfile 4 個 `Custom:` 層 + trixie base ✅；`cjk: "bigram"` 設定鍵 ✅；限速 4200ms ✅；gemini 併發鎖 ✅            |
| `memory-schema.ts` 合併結果                | 上游 `lifetime: "process"` **與** 我們 `Boolean(params.cjkBigramFts)` 並存（L156–160）✅                              |
| `git diff --check`                         | 僅 `docker-release.yml` / `entrypoint-ssh.sh` 的既有尾端空白（**11.5 分支同樣存在 → 非本次引入**）⚠️ 可接受           |

**🚫 絕對不做**：`pnpm check:changed`、`pnpm tsgo:all`、`vitest`、本機 `docker build`（macOS 資源保護，見 skill Hard Rule 7）。

### 2.7 提交工作表並推送分支

```bash
git add docs/worksheet-upgrade-openclaw-v2026.11.6-20261120.md
git commit -m "docs: add v2026.11.6 upgrade worksheet"
git push -u origin my-config-v2026.11.6
```

### 2.8 觸發 GHCR Matrix Build 與監控

> **Go-Sign 後才執行。** 輸入名稱為 **`tag`**（OpenClaw）；workflow 只有 `workflow_dispatch`，**不要 push tag**。

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.11.6 -f tag=v2026.11.6 -f platforms=all

gh run list --workflow=docker-release.yml --limit 1 \
  --json databaseId,event,headBranch,headSha,status
```

**必須驗證**：`event` = `workflow_dispatch`、`headBranch` = `my-config-v2026.11.6`、`headSha` = **我們的 commit**（不得為上游 `06afb10d327`）。

**若回傳 `HTTP 422 "Actions has been disabled for this repository"`** → 見 skill Hard Rule 8：到 `https://github.com/kuniakil/openclaw/actions` 點 banner 上的重新啟用按鈕。**不要**清 cache、不要改 repo settings（已驗證為死路）。

`gh run watch`（10+ 分鐘）→ **派給背景子代理**，主迴圈保持可回應。

建置完成後確認 image tags 真的存在：

```bash
for t in 2026.11.6 v2026.11.6 2026.11.6-slim latest main; do
  docker buildx imagetools inspect ghcr.io/kuniakil/openclaw:$t >/dev/null 2>&1 \
    && echo "$t OK" || echo "$t MISSING"
done
```

### 2.9 K3s 部署與驗證

```bash
# 更新 overlay image tag（並 commit ~/kubernetes repo）
sed -i '' 's|newTag: ".*"|newTag: "2026.11.6"|' ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
cat ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
cd ~/kubernetes && git add openclaw/overlays/n100/kustomization.yaml && git commit -m "chore(openclaw): bump image to 2026.11.6"

kubectl apply -k ~/kubernetes/openclaw/overlays/n100
kubectl -n openclaw rollout status deploy/openclaw-gateway --timeout=10m   # ← 派給背景子代理
kubectl -n openclaw get deploy openclaw-gateway -o jsonpath='{.spec.template.spec.containers[0].image}'
```

> ✅ **本次不需要 scale-0 / 維護 Pod / `doctor --fix`**（11.5 那次需要，是因為 schema 22→36 / 27→38 不可逆遷移）。本次 `schemaVersions` 不變 → **一般 rollout 即可**，Gateway 啟動時不會觸發 schema 遷移。
> 唯讀驗證 DB 筆數（不需要停機）：
>
> ```bash
> kubectl -n openclaw exec deploy/openclaw-gateway -- node -e "…SELECT count(*) FROM memory_index_chunks / _fts / _cjk_fts…"
> ```

**部署後實機驗證**（沿用 11.5 升級已驗證過的檢查項）

- [ ] `openclaw --version` = `OpenClaw 2026.11.6`
- [ ] `kubectl -n openclaw get pods` → `openclaw-gateway` 1/1 Running，**RESTARTS 0**，無 CrashLoopBackOff
- [ ] Pod log 開機無 `FATAL` / `schema migration` 錯誤
- [ ] **自訂工具鏈存在**：`faster-whisper 1.2.1`、`/usr/local/bin/whisper`、`/usr/local/bin/edge-tts`、`/usr/bin/ffmpeg`、`/usr/bin/rsync`、`/usr/bin/tini`、`/usr/sbin/sshd`、`/app/docker/entrypoint-ssh.sh`、`en_US.utf8` / `zh_TW.utf8`
- [ ] sshd 在 trixie 上可正常啟動（`/usr/sbin/sshd -f /home/node/.openclaw/ssh-etc/sshd_config -D`）
- [ ] Gateway logs：**20 plugins 正常載入**、Telegram bot 輪詢啟動、**無 429 / `RESOURCE_EXHAUSTED`**、**無意外全量 reindex**、**無 `rss_threshold` 警告**
- [ ] **Memory 索引筆數對齊**：`memory_index_chunks` == `_fts` == `_cjk_fts` == session 表（四表皆應為 **1483**，11.5 Telegram roundtrip 後的基準）
- [ ] **2 字中文查詢實測**：經 **Gateway 路徑**（`openclaw agent`，非 CLI）查詢雙字詞（如「配置」「設定」），確認 `textScore > 0` 且維持 BM25 可排序 → **CJK bigram 伴隨索引仍生效**
- [ ] Cron 排程（如 `Memory Dreaming Promotion`）維持 `inferenceBinding` 綁定且未中斷
- [ ] **比對升級前後的 cron／automation 清單**：確認無新增、重複或遺失
- [ ] Telegram 實機往返（收發、回覆、審批 topic 隔離）
- [ ] `openclaw doctor --non-interactive` **Error 級 = 0**（僅預期容器內無 systemd busctl 提示）
- [ ] 記憶體 cgroup 觀察（上次基準 **2.03–2.14 GiB**；11.6 重點是降常駐記憶體，應持平或更低）
- [ ] Pod 收尾乾淨（觀察 #202405：HTTP pool shutdown 可能留下 Node 存活）

**兩項已知踩坑（沿用 11.5 經驗）**

- ⚠️ **PID 已變**：trixie 容器內 Gateway **不再是 PID 7** → 不要用 `ps -o rss= -p 7` 採樣，改為動態取樣實際 Gateway 行程。
- ⚠️ **`heartbeat-main` cron**（`d602b11f-e70c-4674-9090-0e58bffb9c4f`）：因 state v30 folding 導致每 30 分鐘失敗一次（11.5 遺留）。11.6 恰有「Doctor 以 cron startup recovery owner 恢復中斷的 legacy heartbeat run」修正 → **先觀察是否已自動恢復**；仍失敗再 `openclaw cron edit d602b11f-e70c-4674-9090-0e58bffb9c4f --disable`。

**升級後 24 小時內追加確認**

- [ ] 確認 cron 持續觸發（上游 #200629：worker 遺失後排程會靜默停擺，需重啟 Gateway）

### 2.10 升級後**不要**做的事

- ❌ `openclaw memory index` / `memory reset`（schema、模型、格式皆未變 → 索引沿用）
- ❌ `openclaw memory search` / `agent --local` 與 Gateway 併發（雙行程撞 Gemini 配額）
- ❌ `openclaw update`（我們走 image 部署，內建 updater 與我們無關）

---

## Phase 3: 收尾與清理

- [ ] 更新本工作表完成狀態並 commit / push（`docs/worksheet-upgrade-openclaw-v2026.11.6-20261120.md`）
- [ ] 建立本版快照分支：`git branch -f backup/my-config-v2026.11.6 origin/my-config-v2026.11.6`
- [ ] 產出 post-mortem 至 `~/kubernetes/docs/openclaw-v2026-11-6-upgrade-20261120.md`（對齊 `openclaw-v2026-11-5-upgrade-20261118.md` 格式：§1 任務背景與目標 / §2 前置分析與關鍵決策 / §3 建置、遷移與部署步驟 / §4 實機驗證結果與待補項目），必要時發佈至 WordPress 知識庫
- [ ] 更新 `~/kubernetes/docs/service-version-matrix.md`
- [ ] **備份清理須先問使用者**：觀察期 3–5 天後，才詢問是否刪除 `/root/backup-openclaw-20261116-v2026.11.4`（2.4G）與 `/root/backup-openclaw-20261117-pre-v2026.11.5`（2.4G）（**不可自動刪**）
- [ ] 保留 `my-config-v2026.11.5` 分支與 `origin` 對應分支（回滾用）
- [ ] 記錄待辦：若日後啟用壓縮 session 封存，需等上游 #192743 進 stable（§1.8）

---

## 回滾預案（Rollback Plan）

本次 `schemaVersions` 未變更 → **回滾不需要資料庫降版遷移**，三種層級任選：

1. **只回滾 image**（最快，秒級）

   ```bash
   sed -i '' 's|newTag: ".*"|newTag: "2026.11.5"|' ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
   kubectl apply -k ~/kubernetes/openclaw/overlays/n100
   kubectl -n openclaw rollout status deploy/openclaw-gateway --timeout=10m
   ```

2. **回滾分支**：改用 `my-config-v2026.11.5` 重新觸發 build → 覆寫 `2026.11.5` image tag

3. **回滾資料**（僅在狀態異常時）：

   ```bash
   ssh root@192.168.31.72 "rsync -aH --delete /root/backup-openclaw-20261120-pre-v2026.11.6/ /data/services/openclaw/.openclaw/"
   ```

   → 需先停 Pod，避免寫入競爭。

> ⚠️ 回滾影像時若資料已被 11.6 寫入新格式，因 schema 版本未變，舊版應仍可讀；但若發現讀取異常，以備份還原為準。
>
> ✅ **與 11.5 不同的關鍵簡化**：11.5 的回滾必須「scale-0 → 維護 Pod → `doctor --fix` → scale-1」（因為 11.4→11.5 是不可逆 schema 遷移，改回 image tag **不等於**回滾）。本次 schema 未變 → **改回 image tag 即完成回滾**，不需要維護 Pod。

---

## 已知風險（Go-Sign 前請確認）

| #   | 風險                                                    | 等級 | 緩解                                                                |
| :-- | :------------------------------------------------------ | :--- | :------------------------------------------------------------------ |
| 1   | CJK admission key 與上游 `lifetime: "process"` 同一物件 | 中   | **已於乾跑驗證自動合併正確**（兩者並存），§1.9                      |
| 2   | 上游 11.6 新測試與我們的 CJK 停用路徑互斥               | 中   | **已排除**：我們的 `SELECT 1 FROM ... LIMIT 0` 不匹配其 regex，§1.9 |
| 3   | 6 個 workflow 刪除衝突誤判為「保留上游」                | 低   | 解法固定為 `git rm` 保留刪除；乾跑後驗證僅剩 1 個 workflow          |
| 4   | `config-baseline.sha256` 手改產生錯誤 digest            | 低   | 一律用 `pnpm config:docs:gen` 重新產生，不手改                      |
| 5   | 11.6 壓縮封存讀取回歸 #202213                           | 低   | 線上 0 封存 → 無影響；若日後啟用需等 #192743 進 stable              |
| 6   | #202405 HTTP pool shutdown 影響 Pod 收尾                | 低   | rollout 後觀察 Pod 是否乾淨退出                                     |
| 7   | 大量上游變更（406 commits）引入未預期行為               | 中   | 依 §2.9 逐項實機驗證；先備份以便快速回滾                            |
| 8   | 誤在本機跑重型 CI 導致 macOS 凍結                       | 低   | 只跑 §2.6 的輕量檢查；編譯/測試全交 GitHub Actions                  |

---

## 簽核

- [x] Phase 1 分析完成，無未解衝突
- [x] 使用者 Go-Sign（執行 Phase 2）— 2026-11-20
- [ ] Phase 2 完成（build + deploy + 驗證）
- [ ] Phase 3 收尾完成
