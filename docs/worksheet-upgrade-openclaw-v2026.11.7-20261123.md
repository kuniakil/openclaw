# OpenClaw 升級工作表：v2026.11.6 → v2026.11.7

- 日期：2026-11-23
- 目前分支：`my-config-v2026.11.6`（HEAD `116497f95a4`）
- 目標：`v2026.11.7`（發佈 2026-11-23 01:33:51 UTC，stable，非 prerelease，npm `latest`）
  - upstream commit：`e31bbf056de321127988ec5c1a36ff1b59297de0`（`upstream-v2026.11.7`）
  - 前一版 baseline：`upstream-v2026.11.6` = `06afb10d3272cc9deaf38ca6a3b7b839d5935638`
- 新分支：`my-config-v2026.11.7`
- 目標 Image：`ghcr.io/kuniakil/openclaw:2026.11.7`
- 線上現況：`ghcr.io/kuniakil/openclaw:2026.11.6`，deploy `openclaw-gateway`（Pod `openclaw-gateway-66b77656b5-jvqst`，1/1 Running，RESTARTS 0，AGE 2d12h）
- 上游規模：**736 commits / 72 contributors**，**3014 files changed**（+93721 / −25175）

---

## 摘要（先讀這段）

| 項目                    | 結論                                                                                                                                                                   |
| :---------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 目標版本                | `v2026.11.7`（stable、`npm dist-tags.latest`；`extended-stable=2026.10.33`、`beta=2026.11.10-beta.1` 不採用）                                                          |
| 升級性質                | **大型功能升級**（736 commits，較 11.6 的 406 commits 多約八成；上游 11.6 → 11.7 為連續歷史）                                                                          |
| 不可逆點                | **無** — `schemaVersions` `state 36 → 36`、`agent 38 → 38` **完全未變**（§1.2）→ 不需強制備份即可回滾，且**不需 scale-0 / 維護 Pod / `doctor --fix`**（§2.9）          |
| 自訂 patch 可移植性     | **17 個自訂 commit 全部可移植**；隔離 worktree 乾跑實測**僅 1 組真衝突**（`manager-embedding-ops.ts`），解法為「丟棄舊 hack、改用上游 API」（§1.5、§1.11）             |
| 上游 breaking change    | **3 項明確標記的 Plugin SDK breaking change**（§1.7）→ 全部只影響 **SDK 消費者**；我們的自訂程式碼未使用任何一項，bundled extensions 上游已一併遷移 → **對我們無影響** |
| 上游已知 bug 影響       | **無新增重大影響**；#202213（壓縮封存讀取）**在 11.7 仍未修復**（§1.8）→ 非本次回歸，維持既有處置                                                                      |
| Base image              | **trixie → trixie**（上游 11.6→11.7 未改 Dockerfile）→ 我們的 46 行自訂層 **零衝突**（§1.6）                                                                           |
| CJK 策略決議            | **維持保留自訂 CJK Han Bigram 伴隨索引**；乾跑實測 CJK commit **零衝突**、合併結果與上游 11.7 並存（§1.9）                                                             |
| 記憶體索引重建          | **不需要**（schema / embedding 模型 / 輸入格式版本皆未變）（§1.10）                                                                                                    |
| ⚠️ 唯一需要重寫的 patch | **Gemini 索引併發鎖**：上游 11.7 重構了 embedding 併發解析機制 → 我們舊的 hack 失效，改用上游原生 `inlineIndexConcurrency`（§1.11）                                    |
| 目前狀態                | Phase 1 完成（Release Notes + `schemaVersions` + 隔離乾跑）。**等待 Phase 2 Go-Sign**（尚未建立分支、未推送、未觸發建置、未動線上）                                    |

---

## 🚦 Go-Sign Gate

- [x] Phase 1 完成官方 Release Notes、`schemaVersions` 與**隔離 worktree 乾跑**分析
- [x] CJK Han Bigram 伴隨索引策略確認：**維持保留自訂實作**（乾跑實測零衝突）
- [x] Gemini 索引併發策略確認：改用上游 `inlineIndexConcurrency: 1`（§1.11）
- [x] 不在 Mac 本機跑重型 CI（`tsgo`/`vitest`）或本機 `docker build`（全交 GitHub Actions）
- [x] 升級期間不另起 `openclaw memory index/search/reset`、`agent --local`（避免雙行程撞 Gemini 配額）
- [x] 10+ 分鐘長等待（`gh run watch`、`kubectl rollout status`）一律派給背景子代理
- [ ] **使用者明確核准執行 Phase 2（Go-Sign）**

---

## Phase 1: 分析結果

### 1.1 官方 Release Notes 摘要（736 commits，範圍 `06afb10d327..e31bbf056de`）

Release：<https://github.com/openclaw/openclaw/releases/tag/v2026.11.7>

**供應鏈核對（三方一致）**

| 來源              | 值                                                                                                                                                                        |
| :---------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| GitHub Release    | release SHA `e31bbf056de321127988ec5c1a36ff1b59297de0`                                                                                                                    |
| 本地 upstream tag | `git rev-parse upstream-v2026.11.7^{commit}` = `e31bbf056de321127988ec5c1a36ff1b59297de0` ✅                                                                              |
| npm registry      | `openclaw@2026.11.7` integrity `sha512-6x49d02jEj8jjQAEkSZpyX8BCNnJLLCV3IHUTxQuN+OEJepo7RODk8JHURivefy+WZMqzvsyp+p8DlZUQnub6w==` — **與 release notes 公布值逐字相符** ✅ |

npm dist-tags：`latest = 2026.11.7`、`extended-stable = 2026.10.33`、`beta = 2026.11.10-beta.1`
→ 我們的 fork 跟 `latest` 線，與歷次升級（11.1 → 11.6）一致。

**Highlights（上游原文摘要）**

| 主題                     | 內容                                                                                                       |
| :----------------------- | :--------------------------------------------------------------------------------------------------------- |
| Conversation recovery    | Gateway 重啟後可恢復被中斷的回覆與子代理結果，不遺失待處理工作（#198905, #201544, #200924, #200967）       |
| Reliable automations     | 排程失敗可由擁有者對話修復；「已恢復／刻意略過」與「真正失敗」可區分（#161007, #201638, #152165, #194276） |
| Smoother updates         | 更新流程能跨過 schema 變更、忙碌的資料庫與保留的復原狀態完成（#201600, #201463, #201545, #201330）         |
| Responsive Gateway       | 慢速檔案系統操作、大型復原包、頁面擷取期間仍維持聊天與就緒檢查可回應（#191236, #201248, #200623, #200925） |
| Browser pairing          | 以 Gateway 主機核准的短碼配對另一瀏覽器（#191513, #200905）                                                |
| Current ChatGPT catalogs | 免等下一版 OpenClaw 即可發現新訂閱模型（#201130, #201493）— **與我們無關（我們不用 ChatGPT）**             |

**與我們部署直接相關的 Fixes**

- **Compaction**：配額錯誤後改用設定的 fallback、避免誤判的 post-compaction stall abort（#194813, #194722, #198029）→ **有利**（我們 11.6 曾有 context 壓力 → 429 的問題）
- **Memory and knowledge**：embedding timeout 後可恢復索引ing、支援本機 Ollama hostname、Knowledge 寫入中斷可恢復（#191556, #191479, #193116, #198146）→ **有利**
- **Subagent results**：子代理結果維持附著於發起它的回合、單一子代理投遞失敗不會拖垮同儕結果（#200873, #201563, #195275）→ **有利**
- **Telegram**：大型媒體上傳完成、回覆控件在替代投遞失敗時保留、附件下載失敗仍回覆（#151923, #193948, #200682）→ **有利**（我們的主要 channel）
- **Configuration and Doctor**：symlinked state root 的守護寫入、還原回報的截斷設定（#155538, #201501, #190194）→ **有利**
- **Knowledge search**：以過期措辭仍可找到現行紀錄、Unicode 等價關鍵字正規化比對（#193742, #195092）→ 實作於 `extensions/knowledge`，**與我們的 memory-core CJK 索引無關**（§1.9）

### 1.2 關鍵發現 A：`schemaVersions` 未變更 → **可逆升級**

```bash
git show upstream-v2026.11.6:package.json | python3 -c "import json,sys;print(json.load(sys.stdin)['openclaw']['schemaVersions'])"
# {'state': 36, 'agent': 38}
git show upstream-v2026.11.7:package.json | python3 -c "import json,sys;print(json.load(sys.stdin)['openclaw']['schemaVersions'])"
# {'state': 36, 'agent': 38}
```

其他 protocol 欄位同樣未變：`updateAdmissionProtocol = 1`、`updatePreflightProtocol = 1`（11.6 / 11.7 一致）。

**結論：與 11.5 → 11.6 相同，本次是可逆升級。**

- 不需要強制完整備份才能回滾（仍建議做，見 §2.1）
- 不需要 scale-0 / 維護 Pod / `doctor --fix`
- **不需要重建記憶體 embedding 索引**（§1.10）

| 欄位           | 11.6                          | 11.7        | 變動       |
| :------------- | :---------------------------- | :---------- | :--------- |
| `version`      | `2026.11.6`                   | `2026.11.7` | 是（預期） |
| `engines.node` | `>=24.16.0 <25 \|\| >=26.1.0` | 同左        | 否         |

### 1.3 上游是否為分歧歷史

11.6 → 11.7 為**上游連續歷史**（736 commits 直接接續），無需處理兩條分歧線。`upstream-v2026.11.7` 直接以 `refs/tags/v2026.11.7` 抓取，`^{commit}` = `e31bbf056de`，與官方 release notes 公布 SHA 一致。

### 1.4 自訂 Patch 清單（`upstream-v2026.11.6..my-config-v2026.11.6`，共 17 個 commit）

| #   | Commit        | 內容                                                                   | 可移植性                                  |
| :-- | :------------ | :--------------------------------------------------------------------- | :---------------------------------------- |
| 1   | `709a79955d7` | `chore:` purge 官方 CI workflows，改用自訂 Matrix `docker-release.yml` | ♻️ **重建**（不 cherry-pick）             |
| 2   | `837933bed1b` | `chore:` 自訂 Dockerfile 層、Gemini 限速、Gemini 索引併發鎖、TODOs     | ⚠️ 1 個衝突（`manager-embedding-ops.ts`） |
| 3   | `b8ad2ba5a21` | `fix(docker):` 恢復 `assets/whisper`、`docker/entrypoint-ssh.sh`       | ✅ 乾跑乾淨                               |
| 4   | `5edf654fdda` | `feat(memory):` CJK Han Bigram 伴隨 FTS 索引                           | ✅ 乾跑**零**衝突                         |
| 5   | `874a24d5522` | `docs:` 帶入歷史升級工作表（9.9 – 11.5）                               | ✅ 乾跑乾淨                               |
| 6   | `63ff5a248fd` | `docs:` 11.5 工作表（Phase 2 記錄）                                    | ✅ 乾跑乾淨                               |
| 7   | `28f2fb4bdfd` | `docs:` 11.5 部署與驗證結果                                            | ✅ 乾跑乾淨                               |
| 8   | `f910e5d1c31` | `docs:` 11.5 Telegram roundtrip 與 DB 驗證                             | ✅ 乾跑乾淨                               |
| 9   | `26b5ed7c7b7` | `chore(docs):` 重新產生 11.6 的 config baseline                        | ⏭️ **跳過**（改為 §2.5 重新產生）         |
| 10  | `79203a001f3` | `docs:` 11.6 工作表（Phase 2 記錄）                                    | ✅ 乾跑乾淨                               |
| 11  | `abe7c9b6f84` | `docs:` 11.6 升級前基準與驗證指令                                      | ✅ 乾跑乾淨                               |
| 12  | `247ec2f9d1b` | `docs:` 11.6 部署結果與封存誤判更正                                    | ✅ 乾跑乾淨                               |
| 13  | `76137a0187a` | `docs:` 11.6 工作表定稿（Phase 3）                                     | ✅ 乾跑乾淨（**順序敏感**，見 §1.5）      |
| 14  | `c5d976a5a78` | `docs:` 預設模型切換 MiniMax-M3 與切換後驗證                           | ✅ 乾跑乾淨                               |
| 15  | `48a537668cc` | `docs:` 11.6 根因更正為 session context 壓力並記錄 compaction          | ✅ 乾跑乾淨                               |
| 16  | `9beaf066414` | `docs:` 11.6 工作表結案                                                | ✅ 乾跑乾淨                               |
| 17  | `116497f95a4` | `docs:` 記錄已核准清理 v2026.11.4 / v2026.11.5 備份                    | ✅ 乾跑乾淨                               |

### 1.5 關鍵發現 B：衝突乾跑（**隔離 worktree 實測，非預測**）

在隔離的臨時 worktree（`/tmp/oc-11.7-dryrun`，分析後已 `git worktree remove`）以 `upstream-v2026.11.7` 為基底，實際執行 purge 重建 + 逐一 cherry-pick：

```
✅ 重建      purge official CI workflows（find -delete + 取 11.6 分支的 docker-release.yml）→ 只剩 1 個 workflow
⚠️  CONFLICT 837933bed1b  chore: upgrade to v2026.9.7; restore custom Dockerfile layer, scripts, rate pacing, and TODOs
      RESOLVED(take upstream, re-implement intent): extensions/memory-core/src/memory/manager-embedding-ops.ts
✅ CLEAN     b8ad2ba5a21  fix(docker): restore assets/whisper, docker/entrypoint-ssh.sh
✅ CLEAN     5edf654fdda  feat(memory): add CJK bigram companion FTS index（**零衝突**）
✅ CLEAN     874a24d5522 / 63ff5a248fd / 28f2fb4bdfd / f910e5d1c31 / 79203a001f3 / abe7c9b6f84
✅ CLEAN     247ec2f9d1b / 76137a0187a / c5d976a5a78 / 48a537668cc / 9beaf066414 / 116497f95a4
```

**衝突組 1（唯一真衝突）— `extensions/memory-core/src/memory/manager-embedding-ops.ts`（modify/modify）**

上游 11.7 把併發解析抽成 `resolveMemoryIndexConcurrency(batch, runtime)`（`manager-embedding-policy.ts`），我們的舊 hack 是直接改 `getIndexConcurrency()`：

```diff
  protected getIndexConcurrency(): number {
+   const runtime = this.syncProviderGeneration
+     ? this.syncProviderGeneration.kind === "semantic" ? this.syncProviderGeneration.runtime : undefined
+     : this.providerRuntime;
+   return resolveMemoryIndexConcurrency(this.batch, runtime);
-   if (this.batch.enabled) { return this.batch.concurrency; }
-   const provider = this.syncProviderGeneration ? this.syncProviderGeneration.provider : this.provider;
-   return provider?.id === "local" || provider?.id === "ollama" || provider?.id === "gemini"
-     ? 1 : EMBEDDING_INDEX_CONCURRENCY;
```

→ **解法：保留上游版本（`git checkout --ours`），把我們的意圖改寫到上游原生機制**（§1.11）。**不可**保留舊版檔案（會整個回退上游 11.7 的重構）。

**順序敏感性（乾跑發現）**：11.6 的 8 個文件 commit 必須**依時間順序** cherry-pick（`79203a001f3` → `abe7c9b6f84` → `247ec2f9d1b` → `76137a0187a` → …）。若把 `76137a0187a` 排在 `247ec2f9d1b` 之前，會在同一份工作表產生 **modify/modify 衝突**（已在乾跑中復現並修正）。

#### 交叉檢查（預測 vs 實測一致）

```bash
comm -12 <(git diff --name-only upstream-v2026.11.6 my-config-v2026.11.6 | sort -u) \
         <(git diff --name-only upstream-v2026.11.6 upstream-v2026.11.7 | sort -u)
```

命中 12 個檔案，其中：

| 檔案                                                             | 判定                                                |
| :--------------------------------------------------------------- | :-------------------------------------------------- |
| 8 個 `.github/workflows/*.yml`（上游改過、我們已刪）             | ❌ 假陽性 → purge 路徑下直接刪除，不需處理          |
| `docs/.generated/config-baseline.sha256`                         | ⏭️ 生成檔 → §2.5 重新產生，不手改                   |
| `docs/reference/memory-config.md`                                | ✅ 雙方改不同段落 → 自動合併（CJK commit 乾跑乾淨） |
| `scripts/pr-lib/wrapper-components.txt`                          | ✅ 雙方在不同區段各加行 → 自動合併                  |
| **`extensions/memory-core/src/memory/manager-embedding-ops.ts`** | ⚠️ **唯一真衝突**（§1.5、§1.11）                    |
| `src/infra/update-candidate-state.inventory.test.ts`             | ✅ 上游未在 11.7 觸碰 → 無衝突                      |

### 1.6 Dockerfile / base image

上游 11.6 → 11.7 **未修改 Dockerfile**（`git diff --stat upstream-v2026.11.6 upstream-v2026.11.7 -- Dockerfile` 為空），base image 兩版皆為 trixie。

乾跑後驗證自訂層完整保留：

```
Dockerfile: 4 個 "Custom:" 標記
  :448  # Custom: Generate UTF-8 locales and install rsync
  :467  # Custom: Install faster-whisper, edge-tts, and ffmpeg for audio TTS/STT pipelines
  :483  # Custom: Audio STT CLI wrapper for fast-whisper
  :487  # Custom: SSH server support for Zeabur deployment
```

### 1.7 上游 breaking change（11.7 首次有明確標記）

官方 Release Notes 的 **Changes** 段落列出 **3 項 breaking Plugin SDK change**（皆來自 #175837）：

| #   | Breaking change                                                                                                                                                                                                      | 影響面            |
| :-- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------------- |
| 1   | `setActiveEmbeddedRun(...)` 註冊改由 host 提供的 `runAttempt` callback 處理；未經 admission 的註冊回報 `SESSION_CONTROLLER_ADMISSION_REQUIRED`                                                                       | Plugin SDK 消費者 |
| 2   | 以 `dispatchGatewayMethod`（`openclaw/plugin-sdk/gateway-method-runtime`）取代可變的 `chatAbortControllers` / `chatQueuedTurns`；plugin manifest 需宣告 `contracts.gatewayMethodDispatch: ["authenticated-request"]` | Plugin SDK 消費者 |
| 3   | `AgentTurnStartOwner.observe()` 欄位由 `expiresAtMs` 改為 `startDeadlineAtMs`（**無相容別名**）；見 `docs/plugins/sdk-migration.md`                                                                                  | Plugin SDK 消費者 |

**對我們的判定：無影響。**

- 我們的 fork **沒有自訂 plugin / extension**（自訂變更只落在 memory-core、memory-host-sdk、database-engine、Dockerfile）
- 上述 3 項屬 **SDK 對外契約**變更，上游 bundled extensions 已於同一個 release 一併遷移（`git grep setActiveEmbeddedRun upstream-v2026.11.7` 命中的是上游自己的已遷移程式碼）
- 我們自訂程式碼**未引用** `setActiveEmbeddedRun` / `chatAbortControllers` / `chatQueuedTurns` / `expiresAtMs`（已 grep 驗證；唯一命中是我們文件中的文字描述）

其他 API 破壞性變更的連帶影響：

- 上游 11.7 從 `package.json` exports **移除** `./plugin-sdk/codex-client-version-runtime`（新增 `./plugin-sdk/memory-core-host-transcript-stats`）→ 我們的程式碼未引用被移除的那個 ✅
- 我們自訂檔案使用的 9 個 plugin-sdk export 路径（`memory-core-host-engine-{schema,storage,indexing,knn}`、`database-engine-worker-runtime`、`sqlite-worker-runtime`、`string-coerce-runtime`、`text-utility-runtime`、`error-runtime`）在 11.7 **全部仍存在** ✅（已逐一驗證）

`docs/install/updating.md` 11.6→11.7 +100 行，全部屬**內建 updater 流程**（我們走預先建好的 GHCR image + Kustomize）→ **不適用**。

### 1.8 上游已知問題（針對 11.6 → 11.7）

| Issue       | 標籤                  | 內容                                                                                                                                                                                                    | 對我們影響                                                                                                                                                                                                                                                                  |
| :---------- | :-------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **#202213** | bug / regression / P1 | 11.6 讀取壓縮 session 封存（`*.jsonl.zst`）在「明文 transcript > 壓縮檔 + 1 MiB」時拋 `ERR_BUFFER_TOO_LARGE`；修補 #192743 / #193548 **未進 11.7**（已 `git log --grep` 於 `upstream-v2026.11.7` 驗證） | ⚠️ **延續性問題，非本次回歸**：`git diff upstream-v2026.11.6 upstream-v2026.11.7 -- src/config/sessions/archive-compression.ts` 為空 → 讀取預算程式碼 11.6/11.7 逐字相同。線上 21 個 `.zst`、1 個超預算 → **非致命、無資料損毀**（錯誤訊息明寫 "the archive is unchanged"） |
| **#203911** | bug / regression / P2 | 檔案附件投遞失敗「Current-source media could not be staged」（Windows 10 環境）                                                                                                                         | ❌ 不適用：非 Windows，且我們用 Telegram 文字/媒體路徑正常                                                                                                                                                                                                                  |
| **#203869** | bug / regression / P0 | Code Mode gRPC session closed / BrokenPipe（macOS App）                                                                                                                                                 | ⚠️ **待觀察**：macOS App 環境；我們的 Gateway 在 K3s。若部署後 agent 回合出現 gRPC/BrokenPipe → 立即回報並比對 11.6                                                                                                                                                         |
| **#203041** | bug / regression / P1 | `plugins.slots.memory = memory-lancedb` 缺依賴 → 每輪 recall 拋錯拖慢主執行緒（Windows）                                                                                                                | ❌ 不適用：我們用 `memory-core`（11.6 線上已驗證 20 plugins 正常載入）                                                                                                                                                                                                      |
| **#203495** | bug / regression / P2 | Android Claw App schema v24→v38 遷移卡住                                                                                                                                                                | ❌ 不適用：非 Android                                                                                                                                                                                                                                                       |
| **#202250** | bug / regression / P3 | `update migration-plan` 因無法提供 candidate digest 而拒絕                                                                                                                                              | ❌ 不適用：內建 updater 路徑（§1.7）                                                                                                                                                                                                                                        |

### 1.9 CJK Han Bigram 伴隨索引：相容性驗證

我們的自訂 feature（`memory_index_chunks_cjk_fts`）在記憶體 FTS 排序層提供**兩字中文**的 BM25 可排序能力；上游 bigram 機制位於**關鍵字抽詞 / 查詢展開層**——兩者**互補，不是重複實作**（延續 11.5 / 11.6 的判定）。

| 檢查項目                                      | 結果                                                                                                                                                                                                                                                                                                      |
| :-------------------------------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 上游 11.6→11.7 是否觸碰我們的 CJK 檔案        | ❌ 全部未觸碰（`memory-schema.ts`、`memory-schema-base.ts`、`cjk-bigram.ts`、`sqlite-search-schema.ts`、`sqlite-memory-search-fragments.ts`、`keyword-query.ts`、`manager-search*.ts`、`zod-schema.memory-search.ts`、`src/agents/memory-search.ts`、`src/plugin-sdk/memory-core-host-engine-schema.ts`） |
| 上游新增的 knowledge search 改動位置          | `extensions/knowledge/src/retrieval.ts`（#193742）— **不同子系統**，不影響 memory-core FTS 層                                                                                                                                                                                                             |
| `memory-schema.ts` 合併結果                   | 上游 `lifetime: "process"` 與我們 `Boolean(params.cjkBigramFts)` **並存**（乾跑驗證）✅                                                                                                                                                                                                                   |
| 我們使用的 9 個 plugin-sdk export 路径        | 11.7 全部仍存在 ✅                                                                                                                                                                                                                                                                                        |
| 上游 PR #193815（社群版 companion index）狀態 | 我們的自訂實作仍是唯一 owner；維持保留                                                                                                                                                                                                                                                                    |

### 1.10 記憶體 embedding 索引重建：**不需要**

| 判準                           | 檢查結果                                                                                             |
| :----------------------------- | :--------------------------------------------------------------------------------------------------- |
| `openclaw.schemaVersions` 變更 | ❌ 未變（state 36 / agent 38）                                                                       |
| embedding 模型變更             | ❌ 未變（`DEFAULT_GEMINI_EMBEDDING_MODEL` 不變，上游未改 `extensions/google/embedding-provider.ts`） |
| embedding 輸入格式版本變更     | ❌ 未變                                                                                              |
| 明確要清除 embedding 快取      | ❌ 無此需求                                                                                          |

→ **升級後索引與快取繼續沿用，不要主動 `openclaw memory index` 或 `memory reset`。**

> 上游 11.7 的 memory 改動（`manager-embedding-policy.ts`、embedding timeout 復原）**不會**改變既有索引的內容格式。

### 1.11 ⚠️ 本次唯一需要重寫的 patch：Gemini 索引併發鎖（上游 API 演進）

我們的舊 patch（`manager-embedding-ops.ts`）把 Gemini 的索引併發壓到 1，因為 **Gemini 免費層僅 15 RPM**。上游 11.7 改了併發解析機制，舊 hack 若照抄會**回退上游重構**。

**上游 11.7 的原生機制**（`src/plugins/embedding-provider-types.ts`）：

```ts
export type EmbeddingProviderRuntime = {
  id: string;
  ...
  /** Positive safe integer cap on simultaneous non-batch indexing jobs; omit for the host default. */
  inlineIndexConcurrency?: number;
}
```

`resolveMemoryIndexConcurrency(batch, runtime)`（`extensions/memory-core/src/memory/manager-embedding-policy.ts`）：

```ts
export function resolveMemoryIndexConcurrency(batch, runtime): number {
  if (batch.enabled) return batch.concurrency;
  const declared = runtime?.inlineIndexConcurrency;
  return declared !== undefined && Number.isSafeInteger(declared) && declared > 0 ? declared : 4;
}
```

**上游自己對本地 provider 就是這樣做的**（既有先例）：

| Provider                      | 宣告位置                                                 | 值                          |
| :---------------------------- | :------------------------------------------------------- | :-------------------------- |
| Ollama                        | `extensions/ollama/src/memory-embedding-adapter.ts`      | `inlineIndexConcurrency: 1` |
| llama.cpp                     | `extensions/llama-cpp/src/embedding-provider.runtime.ts` | `inlineIndexConcurrency: 1` |
| OpenAI-compatible（loopback） | `src/plugins/openai-compatible-embedding-provider.ts`    | `inlineIndexConcurrency: 1` |

**我們的解法（乾跑已驗證可套用）**：在 Gemini 的記憶體 embedding adapter 宣告 `inlineIndexConcurrency: 1`——**上游原生 API、單一 owner、不碰上游重構後的檔案**：

```diff
--- a/extensions/google/memory-embedding-adapter.ts
+++ b/extensions/google/memory-embedding-adapter.ts
@@
       runtime: {
         id: "gemini",
+        // Custom: Gemini's free tier allows only 15 embedding requests/minute, so index
+        // serially instead of the host default of 4 concurrent jobs.
+        inlineIndexConcurrency: 1,
         cacheKeyData: {
```

**保留不動的部分**：`extensions/google/embedding-provider.ts` 的 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` 請求間隔限速（上游 11.6→11.7 **未改這個檔案** → 乾跑乾淨）。兩者互補：

| 機制                                              | 層級                         | 作用                                         |
| :------------------------------------------------ | :--------------------------- | :------------------------------------------- |
| `inlineIndexConcurrency: 1`（改寫後）             | 索引工作層（job 併發）       | 索引工作序列化                               |
| `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`（保留） | provider 請求層（HTTP 節奏） | 單一請求間隔 ≥ 4.2s（≈14 RPM < 15 RPM 額度） |

> ⚠️ `inlineIndexConcurrency` 只在 **非 batch** 路徑生效（`batch.enabled` 時仍走 `batch.concurrency`）——**與我們 11.6 的行為完全一致**（舊 hack 同樣在 `batch.enabled` 時先回傳 `batch.concurrency`）。

### 1.12 保留資產清單（乾跑後逐項驗證）

| 資產                                                                                    | 驗證結果                                                   |
| :-------------------------------------------------------------------------------------- | :--------------------------------------------------------- |
| `.github/workflows/` 僅 `docker-release.yml`                                            | ✅（上游 121 → 我們 1）                                    |
| `docker-release.yml` 為我們的 Matrix 版                                                 | ✅ `workflow_dispatch` only，dispatch input 名為 **`tag`** |
| `Dockerfile` 自訂層（locales/rsync/tini/faster-whisper/edge-tts/ffmpeg/openssh-server） | ✅ 4 個 `Custom:` 標記保留                                 |
| `assets/whisper`、`docker/entrypoint-ssh.sh`                                            | ✅ 存在（含可執行位元）                                    |
| `packages/memory-host-sdk/src/host/cjk-bigram.ts`                                       | ✅ 存在                                                    |
| `extensions/memory-core/src/memory/manager-search.cjk-bigram.test.ts`                   | ✅ 存在                                                    |
| `memory.search.fts.cjk = "bigram"` 設定選項                                             | ✅ 存在                                                    |
| Gemini 限速 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`                                   | ✅ 存在（`embedding-provider.ts:226`）                     |
| Gemini 索引併發                                                                         | ♻️ **改寫**為 `inlineIndexConcurrency: 1`（§1.11）         |
| 11.6 工作表最終內容與 11.6 分支 HEAD **逐字相同**                                       | ✅ `diff -q` 相同                                          |
| `package.json` version                                                                  | ✅ `2026.11.7`                                             |

### 1.13 環境前置（本機 pre-commit hook）

乾跑時發現 **pre-commit hook 失敗**，原因與我們的程式碼無關，而是**本機 node_modules 與 lockfile 不同步**：

```
[line-cap-ratchet] resolving missing packages from scripts/pr tooling root /Users/mlee/openclaw
Installed line-cap-ratchet dependency 'oxlint' has version 1.89.0; this checkout requires 1.88.0.
[pre-commit] line-cap growth ratchet failed
```

- `pnpm-lock.yaml` 釘 `oxlint@1.88.0`（11.6 / 11.7 皆同），但本機 `node_modules/oxlint` 實際為 `1.89.0` → ratchet 判定「缺版本」→ 自動安裝仍得到 1.89.0 → 失敗
- **Phase 2 處置**：切換到新分支後先跑 `pnpm install --frozen-lockfile`（同時也是 §2.5 重新產生 config baseline 的前提）
- 乾跑中以 `--no-verify` 提交僅用於驗證補丁內容；**正式提交必須讓 hook 通過**

---

## Phase 2: 執行步驟（取得 Go-Sign 後）

### 2.1 備份與基線確認

> ⚠️ **SSH 必須用 `root` 帳號**：git remote `n100` = `root@192.168.31.72`。

```bash
# 盤點既有備份（勿重複佔空間）
ssh root@192.168.31.72 "du -sh /root/backup-openclaw-* 2>/dev/null || echo '無既有備份'"
# 目前保留：/root/backup-openclaw-20261120-pre-v2026.11.6 (2.7G)
#          /root/backup-openclaw-20261121-precompaction (238M)

# 本次 rollback 備份（schema 未變 → 非強制，但建議做，成本低）
ssh root@192.168.31.72 "rsync -aH /data/services/openclaw/.openclaw/ /root/backup-openclaw-$(date +%Y%m%d)-pre-v2026.11.7/"
ssh root@192.168.31.72 "du -sh /root/backup-openclaw-$(date +%Y%m%d)-pre-v2026.11.7"
ssh root@192.168.31.72 "df -h / | tail -1"

# Mac 端異地備份（沿用既有目錄 /Users/mlee/openclaw-backups/）
#   內容：openclaw.json、openclaw.sqlite.gz、openclaw-agent.sqlite.gz
```

> 本次 schema 未變更（§1.2）→ 備份**非強制**（11.4→11.5 那次才是）。仍建議做。
> 若要冷備份，先 `kubectl -n openclaw scale deploy/openclaw-gateway --replicas=0` 再 rsync，完成後 scale 回 1。

**✅ 執行結果（2026-11-23）**

| 項目                                    | 結果                                                                                                                                                                         |
| :-------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 升級前基準（11.6 線上實測）             | `memory_index_chunks` = `_fts` = `_cjk_fts` = **1657**；`session_transcript_fts` = **2050**；`cron_jobs` = 1 筆（`Memory Dreaming Promotion`, enabled=1, payload=agentTurn） |
| N100 熱備份                             | `/root/backup-openclaw-20261123-pre-v2026.11.7` = **2.5G** ✅                                                                                                                |
| N100 磁碟                               | 總 1.8T / 已用 664G / 可用 **1.1T**（39% used）✅                                                                                                                            |
| Mac 異地備份（sqlite `.backup` + gzip） | `openclaw-agent-pre-v2026.11.7-20261123.gz` = 187M、`openclaw-state-pre-v2026.11.7-20261123.gz` = 3.9M；`gzip -t` 雙雙通過 ✅                                                |
| Mac 設定副本                            | `openclaw.json-pre-v2026.11.7-20261123` → JSON 驗證 VALID ✅                                                                                                                 |
| 既有備份盤點                            | `20261120-pre-v2026.11.6` (2.7G)、`20261121-precompaction` (238M) — 保留待觀察期後再問使用者                                                                                 |

### 2.2 建立新分支（從官方 baseline 開，不要從本地 `v*` tag）

```bash
cd /Users/mlee/openclaw
git fetch upstream refs/tags/v2026.11.7:refs/tags/upstream-v2026.11.7 --no-tags
git rev-parse upstream-v2026.11.7^{commit}   # 必須 = e31bbf056de321127988ec5c1a36ff1b59297de0
git checkout -b my-config-v2026.11.7 upstream-v2026.11.7
```

### 2.3 Purge 官方 Workflows 並覆蓋 Matrix `docker-release.yml`

**採用「重建 purge commit」路徑（零衝突，與 11.5 / 11.6 做法一致）**：

```bash
# 上游 11.7 有 121 個 workflow；只留我們的 Matrix docker-release.yml
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.11.6 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

### 2.4 移植自訂 commits（順序敏感）

```bash
# 先讓 pre-commit hook 能跑：讓 node_modules 與 lockfile 對齊（§1.13）
pnpm install --frozen-lockfile

git cherry-pick 837933bed1b   # ⚠️ manager-embedding-ops.ts 衝突 → 保留上游版本
git cherry-pick b8ad2ba5a21   # ✅
git cherry-pick 5edf654fdda   # ✅（CJK，零衝突）
git cherry-pick 874a24d5522 63ff5a248fd 28f2fb4bdfd f910e5d1c31   # ✅ 文件歷史
git cherry-pick 79203a001f3 abe7c9b6f84 247ec2f9d1b 76137a0187a \
                c5d976a5a78 48a537668cc 9beaf066414 116497f95a4      # ✅ 11.6 文件（依時間順序）
# 跳過 26b5ed7c7b7（11.6 的 config baseline）→ 改由 §2.5 重新產生
```

**✅ 執行結果（2026-11-23）**

| 步驟                                    | 結果                                                                                                          |
| :-------------------------------------- | :------------------------------------------------------------------------------------------------------------ |
| `pnpm install --frozen-lockfile`        | 38.8s 完成；`node_modules/oxlint` 由 **1.89.0 → 1.88.0**（回到 lockfile 釘選版）→ pre-commit hook 恢復正常 ✅ |
| 新分支                                  | `my-config-v2026.11.7` @ `e31bbf056de`（官方 baseline）✅                                                     |
| Purge workflows                         | 上游 121 → **1**（`docker-release.yml`）；`on:` 僅 `workflow_dispatch`，input 名為 `tag` ✅                   |
| cherry-pick `837933bed1b`               | ⚠️ 唯一衝突 `manager-embedding-ops.ts` → `git checkout --ours` 保留上游重構 ✅                                |
| cherry-pick `b8ad2ba5a21`               | ✅ CLEAN                                                                                                      |
| cherry-pick `5edf654fdda`（CJK bigram） | ✅ CLEAN（**零衝突**，與乾跑一致）                                                                            |
| cherry-pick 12 個文件 commits           | ✅ 全部 CLEAN（依時間順序）                                                                                   |

**`manager-embedding-ops.ts` 衝突解法：**

```bash
git checkout --ours -- extensions/memory-core/src/memory/manager-embedding-ops.ts
git add extensions/memory-core/src/memory/manager-embedding-ops.ts
git cherry-pick --continue
```

> ⚠️ cherry-pick 語意：`--ours` = 目前分支（= 上游 11.7 版本）→ 這正是我們要的（**不可**用 `--theirs`，那會整個回退上游重構）。

### 2.5 改寫 Gemini 索引併發（§1.11）+ 重新產生 config baseline

```bash
# (a) Gemini 索引併發：套用上游原生 inlineIndexConcurrency
#     檔案：extensions/google/memory-embedding-adapter.ts
#     在 runtime: { id: "gemini", ... } 內加入 inlineIndexConcurrency: 1（含 Custom 註解）

# (b) 重新產生 config baseline（生成檔不可手改）
pnpm config:docs:gen      # = node --import ./scripts/tsx.mjs scripts/generate-config-doc-baseline.ts --write
pnpm config:docs:check    # 驗證：OK docs/.generated/config-baseline.sha256 and docs/.generated/config-baseline.counts.json
git add docs/.generated/
git commit -m "chore(docs): regenerate config baseline for v2026.11.7"
```

> 預期 counts 會因上游 11.7 新增設定項而變動（上游 11.6 的 `core 2579 / channel 4003 / plugin 4889` 加上我們 CJK 的 `+2 core / −30 plugin`）→ **以重新產生的數值為準並記錄**。

**✅ 執行結果（2026-11-23）**

| 項目                       | 結果                                                                                                                                                                       |
| :------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Gemini 索引併發改寫        | `extensions/google/memory-embedding-adapter.ts` 加入 `inlineIndexConcurrency: 1`（commit `5637903f62c`）✅                                                                 |
| `pnpm config:docs:gen`     | 重新產生 `.sha256` + `.counts.json`；`--check` → **OK** ✅                                                                                                                 |
| counts.json 實測值         | `core 2581 / channel 4003 / plugin 4859` — **與 11.6 完全相同**（上游 11.7 未新增設定 schema 鍵）✅                                                                        |
| `manager-embedding-ops.ts` | 與上游 11.7 **逐字相同**（`git diff` = 0 行）✅ → 上游重構完整保留                                                                                                         |
| 保留資產驗證               | workflow 1 個 ✅、Dockerfile 4 個 `Custom:` ✅、限速 4200ms ✅、`inlineIndexConcurrency: 1` ✅、`cjk: "bigram"` ✅、version `2026.11.7` / schema `{state:36, agent:38}` ✅ |

### 2.6 本地輕量驗證（嚴禁重型 CI / 本機 docker build）

```bash
git status -sb
git log --oneline upstream-v2026.11.7..HEAD

ls .github/workflows/                        # 必須只剩 docker-release.yml
grep -c 'Custom:' Dockerfile                # 必須 = 4
grep -n 'MIN_GEMINI_EMBEDDING_INTERVAL_MS' extensions/google/embedding-provider.ts
grep -n 'inlineIndexConcurrency' extensions/google/memory-embedding-adapter.ts
grep -n 'cjk' src/config/zod-schema.memory-search.ts
grep -n -B3 -A3 'cjkBigramFts' packages/memory-host-sdk/src/host/memory-schema.ts
grep -n -A6 'workflow_dispatch:' .github/workflows/docker-release.yml   # input 必須是 tag
python3 -c "import json;d=json.load(open('package.json'));print(d['version'], d['openclaw']['schemaVersions'])"
git diff upstream-v2026.11.7 --stat -- extensions/memory-core/src/memory/manager-embedding-ops.ts  # 必須為空
```

**🚫 絕對不做**：`pnpm check:changed`、`pnpm tsgo:all`、`vitest`、本機 `docker build`（macOS 資源保護，見 skill Hard Rule 7）。

### 2.7 提交工作表並推送分支

```bash
git add docs/worksheet-upgrade-openclaw-v2026.11.7-20261123.md
git commit -m "docs: add v2026.11.7 upgrade worksheet"
git push -u origin my-config-v2026.11.7
```

### 2.8 觸發 GHCR Matrix Build 與監控

> **Go-Sign 後才執行。** 輸入名稱為 **`tag`**（OpenClaw）；workflow 只有 `workflow_dispatch`，**不要 push tag**。

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.11.7 -f tag=v2026.11.7 -f platforms=all

gh run list --workflow=docker-release.yml --limit 1 \
  --json databaseId,event,headBranch,headSha,status
```

**必須驗證**：`event` = `workflow_dispatch`、`headBranch` = `my-config-v2026.11.7`、`headSha` = **我們的 commit**（不得為上游 `e31bbf056de`）。

> **若回傳 `HTTP 422 "Actions has been disabled for this repository"`** → 見 skill Hard Rule 8：到 `https://github.com/kuniakil/openclaw/actions` 點 banner 上的重新啟用按鈕。**不要**清 cache、不要改 repo settings（已驗證為死路）。

`gh run watch`（10+ 分鐘）→ **派給背景子代理**，主迴圈保持可回應。

建置完成後確認 image tags 真的存在：

```bash
for t in 2026.11.7 v2026.11.7 2026.11.7-slim latest main; do
  docker buildx imagetools inspect ghcr.io/kuniakil/openclaw:$t >/dev/null 2>&1 \
    && echo "$t OK" || echo "$t MISSING"
done
```

### 2.9 K3s 部署與驗證

```bash
sed -i '' 's|newTag: ".*"|newTag: "2026.11.7"|' ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
cd ~/kubernetes && git add openclaw/overlays/n100/kustomization.yaml && git commit -m "chore(openclaw): bump image to 2026.11.7"

kubectl apply -k ~/kubernetes/openclaw/overlays/n100
kubectl -n openclaw rollout status deploy/openclaw-gateway --timeout=10m   # ← 派給背景子代理
kubectl -n openclaw get deploy openclaw-gateway -o jsonpath='{.spec.template.spec.containers[0].image}'
```

> ✅ **本次不需要 scale-0 / 維護 Pod / `doctor --fix`**（`schemaVersions` 不變 → 啟動不觸發 schema 遷移）。

**📌 升級前基準（部署前在 11.6 線上實測，部署後逐項比對）**

| 指標                          | 11.6 基準（2026-11-23 升級前實測）                                               |
| :---------------------------- | :------------------------------------------------------------------------------- |
| `memory_index_chunks`         | **1657**                                                                         |
| `memory_index_chunks_fts`     | **1657**                                                                         |
| `memory_index_chunks_cjk_fts` | **1657**                                                                         |
| `session_transcript_fts`      | **2050**                                                                         |
| `cron_jobs`                   | 1 筆：`c870fbf5-…` / `Memory Dreaming Promotion` / enabled=1 / payload=agentTurn |
| 閒置記憶體                    | ~2.24–2.49 GiB（11.6 compact 後）                                                |
| 載入 plugins                  | 20 個                                                                            |

**部署後實機驗證清單**（沿用 11.6 已驗證過的檢查項）

- [ ] `openclaw --version` = `OpenClaw 2026.11.7`
- [ ] `kubectl -n openclaw get pods` → 1/1 Running，**RESTARTS 0**，無 CrashLoopBackOff
- [ ] Pod log 開機無 `FATAL` / `schema migration` 錯誤
- [ ] **自訂工具鏈存在**：`/usr/local/bin/whisper`、`/usr/local/bin/edge-tts`、`/usr/bin/ffmpeg`、`/usr/bin/rsync`、`/usr/bin/tini`、`/usr/sbin/sshd`、`/app/docker/entrypoint-ssh.sh`、`en_US.utf8` / `zh_TW.utf8`、`faster-whisper 1.2.1`
- [ ] Gateway logs：**20 plugins 正常載入**、**429 = 0 / `RESOURCE_EXHAUSTED` = 0**、無意外全量 reindex、無 `rss_threshold` 警告
- [ ] **Memory 索引筆數對齊**：`memory_index_chunks` = `_fts` = `_cjk_fts`（與基準一致或增加），`session_transcript_fts` ≥ 2002
- [ ] **2 字中文查詢實測**（經 **Gateway 路徑**，非 CLI）：`memory_index_chunks_cjk_fts MATCH '配置'` → 有命中且 bm25 分數有限；同一詞在主 trigram 索引回傳 0 筆（證明伴隨索引仍在排序層）
- [ ] **Gemini 索引併發 = 1 已生效**：索引/召回期間無 429（`inlineIndexConcurrency: 1`）
- [ ] Cron `Memory Dreaming Promotion` 維持 `inferenceBinding`、未中斷；比對升級前後 cron 清單無新增/重複/遺失
- [ ] Telegram 實機往返（收發、回覆、審批 topic 隔離）
- [ ] `openclaw doctor --non-interactive` → **Error 級 = 0**
- [ ] 記憶體 cgroup：無單調攀升
- [ ] Pod 收尾乾淨
- [ ] **11.7 新增觀察**：Code Mode 是否出現 gRPC / BrokenPipe（#203869 觀察項）

**驗證指令（可直接貼上執行）**

```bash
# [1] 版本
kubectl -n openclaw exec deploy/openclaw-gateway -- node dist/index.js --version

# [2] 自訂工具鏈
kubectl -n openclaw exec deploy/openclaw-gateway -- sh -lc \
  "which whisper edge-tts ffmpeg rsync tini sshd; \
   ls -la /app/docker/entrypoint-ssh.sh; \
   locale -a | grep -E 'en_US|zh_TW'; \
   python3 -c 'import faster_whisper,sys; print(\"faster-whisper\", faster_whisper.__version__)'"

# [3] Memory 索引筆數（容器無 sqlite3 → 讀 N100 hostPath 的同一份 DB，唯讀）
ssh root@192.168.31.72 "sqlite3 -readonly /data/services/openclaw/.openclaw/agents/main/agent/openclaw-agent.sqlite \
  \"SELECT 'chunks',count(*) FROM memory_index_chunks \
    UNION ALL SELECT 'fts',count(*) FROM memory_index_chunks_fts \
    UNION ALL SELECT 'cjk_fts',count(*) FROM memory_index_chunks_cjk_fts \
    UNION ALL SELECT 'session_fts',count(*) FROM session_transcript_fts;\""

# [4] Cron 清單
ssh root@192.168.31.72 "sqlite3 -readonly -separator ' | ' /data/services/openclaw/.openclaw/state/openclaw.sqlite \
  \"SELECT job_id, name, enabled, payload_kind FROM cron_jobs ORDER BY name;\""

# [5] cgroup 記憶體
kubectl -n openclaw exec deploy/openclaw-gateway -- sh -lc \
  "cat /sys/fs/cgroup/memory.current 2>/dev/null || cat /sys/fs/cgroup/memory/memory.usage_in_bytes"

# [6] Doctor
kubectl -n openclaw exec deploy/openclaw-gateway -- node dist/index.js doctor --non-interactive

# [7] Pod 狀態與 image
kubectl -n openclaw get pods -l app=openclaw-gateway
kubectl -n openclaw get deploy openclaw-gateway -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### 2.10 升級後**不要**做的事

- ❌ `openclaw memory index` / `memory reset`（schema、模型、格式皆未變 → 索引沿用）
- ❌ `openclaw memory search` / `agent --local` 與 Gateway 併發（雙行程撞 Gemini 配額）
- ❌ `openclaw update`（我們走 image 部署，內建 updater 與我們無關）

---

## Phase 3: 收尾與清理

- [ ] 更新本工作表完成狀態並 commit / push
- [ ] 建立本版快照分支：`backup/my-config-v2026.11.7` → `origin/my-config-v2026.11.7`
- [ ] 產出 post-mortem 至 `~/kubernetes/docs/openclaw-v2026-11-7-upgrade-20261123.md`（對齊 `openclaw-v2026-11-6-upgrade-20261120.md` 格式）
- [ ] 更新 `~/kubernetes/docs/service-version-matrix.md`（openclaw 列 → `2026.11.7`）
- [ ] 備份清理（需使用者明確核准後執行；保留本次升級前備份 + 觀察期）
- [ ] 保留 `my-config-v2026.11.6` 分支與 `origin` 對應分支（回滾用）
- [ ] 記錄待辦：#202213 壓縮封存讀取仍待上游 #192743 / #193548 進 stable（§1.8）；#203869 Code Mode gRPC 觀察項

---

## 回滾預案（Rollback Plan）

本次 `schemaVersions` 未變更 → **回滾不需要資料庫降版遷移**，三種層級任選：

1. **只回滾 image**（最快，秒級）

   ```bash
   sed -i '' 's|newTag: ".*"|newTag: "2026.11.6"|' ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
   kubectl apply -k ~/kubernetes/openclaw/overlays/n100
   kubectl -n openclaw rollout status deploy/openclaw-gateway --timeout=10m
   ```

2. **回滾分支**：改用 `my-config-v2026.11.6` 重新觸發 build → 覆寫 `2026.11.6` image tag

3. **回滾資料**（僅在狀態異常時）：

   ```bash
   ssh root@192.168.31.72 "rsync -aH --delete /root/backup-openclaw-<date>-pre-v2026.11.7/ /data/services/openclaw/.openclaw/"
   ```

   → 需先停 Pod，避免寫入競爭。

> ✅ 與 11.5 不同的關鍵簡化（延續 11.6）：schema 未變 → **改回 image tag 即完成回滾**，不需要維護 Pod。

---

## 已知風險（Go-Sign 前請確認）

| #   | 風險                                                             | 等級 | 緩解                                                                |
| :-- | :--------------------------------------------------------------- | :--- | :------------------------------------------------------------------ |
| 1   | Gemini 索引併發 patch 必須改寫（上游 API 演進）                  | 中   | **已於乾跑驗證**：改用上游原生 `inlineIndexConcurrency: 1`（§1.11） |
| 2   | 11.6 的 8 個文件 commit 順序錯誤會產生衝突                       | 低   | §2.4 已列出正確順序；順序來自乾跑實測                               |
| 3   | 本機 `node_modules` 與 lockfile 不同步 → pre-commit hook 失敗    | 中   | §1.13 / §2.4：切分支後先 `pnpm install --frozen-lockfile`           |
| 4   | 736 commits 大幅變更引入未預期行為                               | 中   | 依 §2.9 逐項實機驗證；先備份以便快速回滾                            |
| 5   | #203869 Code Mode gRPC / BrokenPipe（macOS App 回報）            | 低   | 部署後觀察 agent 回合；若出現立即比對 11.6                          |
| 6   | #202213 壓縮封存讀取（11.7 仍未修）                              | 低   | 延續性問題、非回歸；線上 1 個超預算封存 → 非致命、無資料損毀        |
| 7   | `config-baseline.sha256` 手改產生錯誤 digest                     | 低   | 一律用 `pnpm config:docs:gen` 重新產生，不手改                      |
| 8   | 我們的 plugin-sdk 新增 export（4 個符號）可能撞上游 API 基線測試 | 低   | 與 11.6 相同狀況（線上已驗證運作正常）；我們分支無上游 CI           |
| 9   | 誤在本機跑重型 CI 導致 macOS 凍結                                | 低   | 只跑 §2.6 的輕量檢查；編譯/測試全交 GitHub Actions                  |

---

## 簽核

- [x] Phase 1 分析完成（含隔離 worktree 乾跑），無未解衝突
- [ ] 使用者 Go-Sign（執行 Phase 2）
- [ ] Phase 2 完成（build + deploy + 驗證）
- [ ] Phase 3 收尾完成
