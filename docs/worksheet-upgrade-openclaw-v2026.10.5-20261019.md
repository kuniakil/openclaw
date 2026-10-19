# Upgrade Worksheet: openclaw → v2026.10.5

**Date:** 2026-10-19
**Current branch:** `my-config-v2026.10.4`（HEAD `109b446d498`）
**Target tag:** `v2026.10.5`（官方 SHA `1b58cb9a1b4f4353e1add63c8506db4d890962e8`）
**New branch:** `my-config-v2026.10.5`
**Release:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.5

> [!CAUTION]
>
> ## ⚠️ 本次是「有 schema migration」的升級 — 與 10.1～10.4 全部不同
>
> `openclaw.schemaVersions`：**`agent` 24 → 25**（`state` 維持 20）。
>
> **後果,請先讀完再決定：**
>
> 1. **升級不可逆。** 10.5 首次啟動會改寫 agent SQLite（`openclaw-agent.sqlite`,目前 215 MB）:
>    對 `session_nodes` 的 `entry_valid` 與 `canonical_pending` trigger 群組做 drop/replace
>    （`src/state/openclaw-agent-canonical-validation-migration.ts`）。
> 2. **無法用 `kubectl set image` 回滾到 `2026.10.4`。** 10.4 在 admission 檢查
>    `userVersion !== OPENCLAW_AGENT_SCHEMA_VERSION`（24），看到 25 的 store 會拒絕服務。
>    官方 release notes 亦明列「give one actionable answer for state written by a newer release」。
> 3. **因此 Phase 3.0 的備份由「可跳過」升級為「強制」**（2.3 GB，`/data/services/openclaw/.openclaw/`）。
>    沒有備份就**沒有回滾路徑**。
> 4. 中間跳板不適用 — 我們是 `10.4 → 10.5` 相鄰升級,無中間版本可墊。

---

> [!IMPORTANT]
>
> 1. **本地 `v2026.10.x` 都是自訂 tag**（含我們的 patch）。官方 baseline 已 fetch：
>    - `refs/tags/upstream-v2026.10.4`（官方 10.4，SHA `383c124cc32f`）
>    - `refs/tags/upstream-v2026.10.5`（官方 10.5，SHA `1b58cb9a1b4f`）
> 2. **不可用本地 `v2026.10.4` 當 diff base**。新分支必須從 `upstream-v2026.10.5` 開。
> 3. **使用分支觸發模型**（承襲 10.3 / 10.4 決策），**不** force-push git tag。
> 4. 禁止在 Mac 跑 `pnpm check:changed` / `tsgo` / `vitest` / `docker build`，一律交給 GitHub Actions。

---

## Phase 1: 分析結果

### 1.1 官方 10.4 → 10.5 差異

| 項目                                                  | 10.4                          | 10.5                    | 備註                                                       |
| ----------------------------------------------------- | ----------------------------- | ----------------------- | ---------------------------------------------------------- |
| `package.json` version                                | 2026.10.4                     | 2026.10.5               |                                                            |
| `openclaw.schemaVersions`                             | state 20 / agent 24           | state 20 / **agent 25** | 🔴 **有 migration**                                        |
| `updateAdmissionProtocol`                             | —                             | 1                       | 🟢 新欄位                                                  |
| Node engine                                           | `>=24.16.0 <25 \|\| >=26.1.0` | 不變                    | 🟢 base image 沿用 `node:24-bookworm`                      |
| **變更規模**                                          | —                             | **23,713 files**        | 🔴 迄今最大的一次（官方把 DB 讀取全面搬到 worker threads） |
| **Dockerfile（官方）**                                | 464 行                        | 466 行（+34/−?）        | 🟡 **官方有改動**（見 1.4）                                |
| `extensions/google/embedding-provider.ts`             | —                             | 有改動（型別重構）      | 🟡 **衝突候選**（見 1.4）                                  |
| `extensions/memory-core/.../manager-embedding-ops.ts` | —                             | **大幅重構**            | 🟡 **衝突候選**（見 1.4）                                  |
| `extensions/x/`                                       | 不存在                        | **新增 bundled plugin** | 🟡 會自動載入 → 17 變 18 plugins                           |
| `pnpm-lock.yaml`                                      | —                             | 有變動                  | 🟢 隨 build 自動安裝                                       |
| `apps/macos/...`（Swift）                             | —                             | 有變更                  | 🟢 與 K3s Docker 部署無關                                  |

### 1.2 官方 Release Notes 審查

**v2026.10.5 Highlights**：

- **Updates finish and recover on their own** — `openclaw update` 跨裝置、跨檔案系統、pnpm 12、Windows
  elevation、macOS login shells 都能完成；會結清 stale handoff lease 與 package-activation journal，
  不再卡住安裝；busy / unhealthy Gateway 不再阻擋 update；`--no-restart` 現在誠實回報成功。
  (#164769, #165863, #166695, #167302, #169410, #170046, #172196, #172640, #173358, #173409, #174649, #171015)
- **Restart-safe conversations** — 被中斷的 turn、worktree 準備期間的第一則訊息、subagent 工作、
  deferred task 在 Gateway 重啟後恢復；使用者輸入與已提交 session 資料可跨越重啟、並行寫入與
  失敗發佈存活。 (#165333, #166042, #165184, #168650, #169144, #170161, #170223, #165502, #167570, #166010, #167662)
- **Faster, lighter Gateway** — session / transcript / history / metadata 讀取搬到 worker thread，
  每輪 SQLite 工作量大減；startup maintenance 改在 readiness 之後跑；**啟動記憶體回到 10.4 區間**。
  (#164744, #165470, #165614, #166587, #167194, #164779, #165028, #166041, #167278, #165993, #174718, #172392)
- **Reliable turns and subagents** — 從停滯 stream、重複 tool-call ID、過期 ChatGPT websocket、
  畸形 OpenAI / Google stream 中恢復。 (#165983, #167013, #165212, #167972, #166846, #168400, #173404, #173612)
- **X channel（新）** — 新的 X (Twitter) mentions channel plugin，支援 streaming、repository 問題的
  guest mode、強制 API 成本上限。 (#165138, #165337, #165354, #165351)
- **Voice calls** — 每通來電 brief、call report、live steering、callback、留言信箱偵測。 (#165716)
- **Smarter model pickers** — 各 provider 推薦模型排前面；**Claude / ChatGPT / Ollama 新模型不需等
  OpenClaw 发版即可出現**；Google 加入 Gemini 4 Argon 與 Gemini 3.8 Flash。 (#167370, #166737, #167658, #167387, #167463, #171852, #172339)
- **ClawHub in the Gateway** — 從 Gateway 瀏覽 / 搜尋 ClawHub plugins 與 skills，plugin 自動挑選
  你的 OpenClaw 支援的最新官方版本。 (#163459, #167485, #166588)

**Changes 中的 Breaking / 行為變更（與我們相關者 ⭐）**：

| #   | 變更                                                                                                                                                                                                           | 影響                                                                                                                                             |
| --- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1   | **Tool approval hooks** — 一般 hook 不能再改寫 trusted-inline-approved 的 tool 參數；轉換型 plugin 必須對最終參數另外申請 approval，否則呼叫被封鎖。migration 見 `docs/plugins/hooks/tool-policy.md` (#142700) | 🟡 我們**沒有自訂 hook**，隨容器升級的 bundled plugins 由官方維持合規。Phase 3 需確認工具審批流程未退化                                          |
| 2   | **Codex runtime compatibility** — plugin admission 拒絕低於 **2026.9.7** 的官方 Codex runtime，拒絕時仍可檢視但不會 import (#168930, #168748, #168749, #168977)                                                | 🟡 **需驗證**：我們的 agent 有 `codex-home/`（`state_5.sqlite` 等），若 Codex runtime < 2026.9.7 會被拒 → Phase 3.2 必須確認 plugin 數與載入狀態 |
| 3   | **Sessions** — 允許對 session 定向發送而不授予 transcript 存取權 (#164444)                                                                                                                                     | 🟢 能力收窄，無破壞                                                                                                                              |
| 4   | **Worker-local inference** — 新增原生 worker inference runtime，含 Gateway dispatch、client placement、必要的 worker policy / destination 檢查 (#158902 等 7 項)                                               | 🟢 我們未啟用 worker-local inference                                                                                                             |
| 5   | **Google** — Gemini 4 Argon 成為預設 Google **chat** 模型                                                                                                                                                      | 🟢 我們主模型是 MiniMax；**注意**：這只影響 chat model，我們用 Gemini 的是 **embedding**，模型不變                                               |
| 6   | **Device joins** — CLI / Control UI join 命令現在會安裝背景 node service (`--service --session-host`) (#168623)                                                                                                | 🟢 與 K3s 單 pod 部署無關                                                                                                                        |
| 7   | **X channel** — 新增 bundled plugin，含 Activity API streaming / backfill、guest mode、**GitHub 驗證過的 repository writer**、每日與每月 **X API 成本上限**                                                    | 🟡 會自動載入（未設定 = 不啟動）。新增對外通道，本質上是 attack surface 擴大 → Phase 3 確認它處於未啟用狀態                                      |

**Deprecations**：changelog 未列 blocking deprecation。`createSessionHeaderLink` 等
JavaScript-only `openclaw/plugin-sdk` facade 匯出仍標為 deprecated compatibility export（沿用 10.4 政策）。

**Dependency / Runtime Bumps**：Node engine 不變；`updateAdmissionProtocol: 1` 為新增欄位（非破壞）。
Docker base image 沿用 `node:24-bookworm`。

**Known Issues / Upgrade Caveats**：

- 🔴 **本次唯一的真實升級 caveat 就是 schema migration**（見文首 CAUTION）。
- 官方 10.5 自身 revert 了兩個 10.5 期間的 commit：
  `c3d21618840 Revert "perf(git): prevent agent-triggered automatic maintenance (#167443)"`
  與 `bbd850c4422 Revert "fix(codex): keep healthy app-server when Stop interrupts a session handoff (#173580)"`
  → **自動 maintenance 與 Codex app-server 的行為與 10.4 一致**，不需要我們額外配合。

### 1.3 自訂 patch 清單（`my-config-v2026.10.4` 內）

| Commit                            | 檔案                                                                                                                  | 內容                                                                                                                               |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `dc57728a969`                     | `.github/workflows/*`（110 檔）                                                                                       | 刪除官方 workflows、覆蓋 `docker-release.yml` 為 Matrix 版                                                                         |
| `bdbc9be309a`（源 `64ce0d05c9e`） | `Dockerfile`（+46）、`extensions/google/embedding-provider.ts`、`extensions/memory-core/.../manager-embedding-ops.ts` | 自訂層（locale / rsync / faster-whisper / edge-tts / ffmpeg / openssh-server）+ Gemini Free Tier rate pacing + gemini 索引併發鎖 1 |
| `d094c9ee84e`（源 `884f17a1fe1`） | `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`                                       | 自訂資產                                                                                                                           |
| 11 個 docs commits                | `docs/worksheet-upgrade-openclaw-*.md`                                                                                | 保留 10.1～10.4 升級歷史                                                                                                           |

### 1.4 衝突交叉比對 —— 🔴 本次不是乾淨升級

```bash
comm -12 <(git diff --name-only upstream-v2026.10.4..my-config-v2026.10.4 | grep -v '^\.github/workflows/' | sort -u) \
         <(git diff --name-only upstream-v2026.10.4 upstream-v2026.10.5 | sort -u)
```

**結果（3 個檔案,全中）：**

```
Dockerfile
extensions/google/embedding-provider.ts
extensions/memory-core/src/memory/manager-embedding-ops.ts
```

這與 10.1→10.2、10.2→10.3、10.3→10.4 的「交集為空」不同。逐檔處置計畫：

#### ① `Dockerfile` —— 🟢 預期乾淨,但必須驗證

- 官方 10.5 改動全在**前半段**（`workspace-deps` / `production-deps`，約 line 30–130）：
  plugin selection 現在也 stage `examples/`，`production-deps` 的 `pnpm install` 改用
  `--filter . --filter ./ui --filter './packages/*'` + 逐個 bundled plugin filter。
- 我們的自訂層是**檔尾追加**（anchor 在 `install -d ... /home/node/.config/openclaw` 區塊之後，
  10.5 的 line 434 仍在，10.4 也是同一個 anchor）。
- **處置**：正常 cherry-pick；若因行號位移報 conflict，確認 4 個 `# Custom:` 段落仍接在
  `ENV NODE_ENV=production` 之前即可。

#### ② `extensions/google/embedding-provider.ts` —— 🟠 預期小衝突,需手動重貼

- 官方 10.5 把 `GeminiEmbeddingClient` 從明確 object type 改成
  `Omit<RemoteEmbeddingClient, "fetchImpl"> & {...}`；並把 Gemini task prefix 表
  (`GEMINI_EMBEDDING_2_TASK_PREFIXES`) 抽到共用 helper `formatEmbeddingTaskText`。
  **這些都在檔案上半段（import 區 / type 宣告 / `buildGeminiEmbeddingRequest`）。**
- 我們的 rate pacing patch 包的是 `fetchGeminiEmbeddingPayload`（約 line 233 起）。
  **已逐行驗證 10.5 的 `fetchGeminiEmbeddingPayload` 結構與 10.4 完全一致**：
  同一個 `executeWithApiKeyRotation({provider:"google", transientRetry: providerOperationRetryConfig("read"), ...})`
  → `withRemoteHttpResponse({url, ssrfPolicy, ...})` → 同樣的 `res.clone()` / `createProviderHttpError` /
  `readProviderResponseErrorText` / `retryAfterMs` 邏輯。**pacing 的套接點仍然存在。**
- **處置**：若 cherry-pick conflict → 手工在新的 `fetchGeminiEmbeddingPayload` 外包上
  `geminiEmbeddingQueue`（`MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`），
  保留上游的 `executeWithApiKeyRotation` 原樣，僅把 `execute:` 整段換成 `executePaced`。
  **驗收**：`grep -n 'geminiEmbeddingQueue\|MIN_GEMINI_EMBEDDING_INTERVAL_MS'` 有命中，
  且 `executeWithApiKeyRotation` / `withRemoteHttpResponse` / `ssrfPolicy` 仍各出現一次。

#### ③ `extensions/memory-core/.../manager-embedding-ops.ts` —— 🟠 預期衝突,需手動重貼

- 官方 10.5 **大幅重構**此檔：
  - `runEmbeddingOperationWithTimeout` 抽到新檔 `paused-deadline.ts`
  - batch retry 改用 `runMemoryEmbeddingBatchTimeoutRetry`（policy 模組），移除本地
    `MemoryBatchRetryResult` / `runBatchWithFallback`
  - `activeProviderUses` 改用 `createDeferred()`（`openclaw/plugin-sdk/concurrency-runtime`）
  - `indexFile` / `prepareIndexEntry` 簽章由 `options: {source, content?}` 收斂為 `source: MemorySource`
  - session tombstone 檢查改由 `sourceDatabase.read({type:"session.current"})` 判定
- 我們的 patch 是 **`getIndexConcurrency()` 的 1 行**：
  ```diff
  -    return provider?.id === "ollama" ? 1 : EMBEDDING_INDEX_CONCURRENCY;
  +    return provider?.id === "ollama" || provider?.id === "gemini" ? 1 : EMBEDDING_INDEX_CONCURRENCY;
  ```
  **已驗證 10.5 line 527 仍是同一行、同一內容**，只是行號從 ~589 移到 527。
- **處置**：若 conflict → 手動在 10.5 的 `getIndexConcurrency()`（line 527 附近）重新加上
  `|| provider?.id === "gemini"`。**這是純 1 行、風險極低**，但必須手動做，因為周邊大段重構
  會讓 patch 的 context 對不上。
  **驗收**：`grep -n 'gemini' extensions/memory-core/src/memory/manager-embedding-ops.ts | grep getIndexConcurrency`
  或直接讀 line 527。

#### ④ `.github/workflows/` —— 🟢 按 SOP purge 重建

- 10.5 官方 workflow 有 21 檔變動（`ci.yml` +104、release-publish +113、新增
  `plugin-clawhub-recovery.yml` 等），另有新增 `.github/workflows/plugin-clawhub-*.yml`。
- **全部 purge**，用 `my-config-v2026.10.4` 的 Matrix 版覆蓋 `docker-release.yml`，不 merge 官方變更。

### 1.5 風險評估：中（10.1–10.4 首次非低風險）

| 風險類型        | 等級      | 原因                                                                                                                       |
| --------------- | --------- | -------------------------------------------------------------------------------------------------------------------------- |
| **Schema 中斷** | 🔴 **高** | `agent` 24 → 25，改寫 215 MB `openclaw-agent.sqlite` 的 trigger；**回滾到 10.4 image 會被拒**，必須有備份                  |
| 自訂 patch      | 🟠 中     | 3 個 functional 檔案全與上游重疊；`manager-embedding-ops.ts` 是 1 行手動重貼，`embedding-provider.ts` 需逐行確認套接點     |
| 行為相容性      | 🟠 中     | **不是** stability patch：新增 X channel plugin、hook tool-policy 行為變更、Codex runtime 版本門檻、worker-local inference |
| Plugin          | 🟡 待確認 | 新增 `extensions/x` → 17 變 18 個 bundled plugin；Codex runtime < 2026.9.7 會被 admission 拒絕                             |
| Hook 審批       | 🟡 待確認 | tool-policy 收緊（第 1 項 breaking）；我們無自訂 hook，但需確認實際審批未退化                                              |
| 模型目錄        | 🟢 無     | 僅 catalog 行為變化（推薦模型排序、新模型提前出現）；我們用 MiniMax，不受影響                                              |
| Channel         | 🟢 低     | Telegram / Discord / WhatsApp / IRC / Slack 全是 bugfix                                                                    |
| 部署中斷        | 🟢 低     | Pod restart 期間能力降低；過往 4 次升級都在 ~30s 內恢復                                                                    |

---

## Phase 2: 執行步驟

### 2.0 前置檢查

- [x] `git status -sb` 乾淨（`## my-config-v2026.10.4...origin/my-config-v2026.10.4`）
- [x] 官方 baseline tag 已 fetch
  ```bash
  git fetch upstream refs/tags/v2026.10.5:refs/tags/upstream-v2026.10.5 --no-tags
  git rev-parse 'upstream-v2026.10.5^{commit}'
  # 1b58cb9a1b4f4353e1add63c8506db4d890962e8
  ```
- [x] K3s 現況盤點（`ssh n100`）
  ```
  openclaw-gateway-7cc7d9f87f-jpmrs   1/1   Running   0   16h
  ghcr.io/kuniakil/openclaw:2026.10.4
  ```
- [x] Pod 實際掛載 = `/data/services/openclaw/.openclaw`（`/home/kuniaki/openclaw` 是它的 symlink，inode 相同）
- [x] 待備份資料量：`2.3G`；關鍵 DB：`openclaw-agent.sqlite` **215M**、`state/openclaw.sqlite` 16M
- [ ] ~~既有備份盤點 `/root/backup-openclaw-*`~~ → **⚠️ 此結論無效**：`ssh n100` 以 `kuniaki` 身分登入，
      `/root` 不可讀、無 passwordless sudo，所以「查不到」是**權限不足的空結果，不是真的沒有**。
      同樣的無效結論也存在於 10.4 worksheet。備份改放 `/home/kuniaki/`（同一顆 nvme，1.2T 可用）。

#### 2.0.1 Codex runtime 相容性調查（breaking #2）— 已結案：**不適用**

`src/plugins/official-runtime-plugins.ts` 的 `minimumCompatibleVersion: "2026.9.7"` 只作用於
`@openclaw/codex` 這個 **npm runtime plugin 套件**，且僅在「設定了 codex runtime → 觸發安裝該套件」時評估。

- [x] `openclaw.json`（8969 bytes）對 `codex` / `runtime` 的匹配數 = **0** → 從未設定 codex runtime
- [x] image 內 `/app/node_modules/@openclaw/` 只有 `ai`、`fs-safe`、`proxyline`，**沒有 `codex`**
- [x] 容器內無 `CODEX_HOME` 環境變數
- [x] `codex-home/` 僅為舊資料殘留，inert

→ **結論：該門檻對我們不生效，Phase 3.2 只需確認 plugin 數由 17 變 18。**

### 2.1 建立新分支（從 upstream 10.5 基線）

- [x] `git checkout -b my-config-v2026.10.5 'upstream-v2026.10.5^{commit}'`
- [x] HEAD = `1b58cb9a1b4f`
- [x] `package.json` version = `2026.10.5`、`schemaVersions` = `{'state': 20, 'agent': 25}`

### 2.2 Purge 官方 workflows 並覆蓋 Matrix `docker-release.yml`

- [x] `find .github/workflows -type f ! -name 'docker-release.yml' -delete`
- [x] `git checkout my-config-v2026.10.4 -- .github/workflows/docker-release.yml`
- [x] commit `315e33ba7f7`（112 files changed, +149 / −65,271）
- [x] 驗證：官方 **112** 個 workflows → 僅剩 `docker-release.yml`（**191 行** Matrix 版）
- [x] 驗證：`on:` 只有 `workflow_dispatch`、input 名稱 = **`tag`**、`platforms` 預設 `all`

### 2.3 Cherry-pick 自訂 commits（保留線性歷史）— ✅ **零衝突**

> **預期中的 2 處衝突都沒有發生。** git 三向 auto-merge 全部成功套用。
> 但 auto-merge 乾淨 ≠ 語意正確，因此 2.4 逐項驗證雙方改動都還在。

- [x] `git cherry-pick -x 64ce0d05c9e` → `534e0741e91`：**零衝突**（3 files, +125 / −62）
- [x] `git cherry-pick -x 884f17a1fe1` → `1b50e15d690`：**零衝突**（3 files, +111；whisper 0755 / entrypoint-ssh.sh 0755）
- [x] 帶過 10.4 分支的 **16 個純 docs commits**（`2505ec21f57^..109b446d498` 整段），
      全部只動 `docs/worksheet-upgrade-openclaw-*.md`，保留 10.1～10.4 升級歷史
- [x] 線性歷史：**19 commits / 0 merge commit**

### 2.4 輕量本地驗證（無重型 CI）— 全部通過 ✅

**① `Dockerfile`**

- [x] `git diff 'upstream-v2026.10.5^{commit}' HEAD --stat -- Dockerfile` → **+46 / −0**（純附加）
- [x] 4 個 `# Custom:` 段落在 line 439 / 458 / 474 / 478，全部位於 `ENV NODE_ENV=production`（486）**之前**

**② `extensions/google/embedding-provider.ts` — 雙方改動都在**

- [x] 我們的 pacing：`geminiEmbeddingQueue`（218）、`MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`（219）、
      `executePaced`（227）、串行鏈 + cooldown（295–303）
- [x] 上游 10.5 重構存活：`formatEmbeddingTaskText` import（6）+ 使用（132）、
      `Omit<RemoteEmbeddingClient, "fetchImpl">`（35）、`RemoteEmbeddingClient` type（13）
- [x] 上游 HTTP 路徑存活：`withRemoteHttpResponse`（238）、`ssrfPolicy: params.client.ssrfPolicy`（240）
- [x] 無懸空引用：`GEMINI_EMBEDDING_2_TASK_PREFIXES` / `SsrFPolicy` 皆已不存在
- [x] 3 個 SDK subpath 在 10.5 都存在：`memory-core-host-engine-embeddings` / `memory-core-host-secret` / `provider-http`

**③ `extensions/memory-core/.../manager-embedding-ops.ts`**

- [x] 對基線的 diff **剛好 1 行**：`provider?.id === "ollama" || provider?.id === "gemini" ? 1 : ...`（line 527）
- [x] 上游 10.5 重構存活：`createDeferred`、`formatEmbeddingModelInput`、`resolveEmbeddingInputFormatVersion`、
      `runMemoryEmbeddingBatchTimeoutRetry`、`from "./paused-deadline.js"`

**④ 其他**

- [x] `assets/whisper` / `docker/entrypoint-ssh.sh` → `-rwxr-xr-x`（0755）
- [x] `package.json` → `2026.10.5` · `{'state': 20, 'agent': 25}`
- [x] `git log --merges 'upstream-v2026.10.5^{commit}'..HEAD` → **0** 個 merge commit
- [x] `git diff 'upstream-v2026.10.5^{commit}' HEAD --stat -- ':!.github'` → 恰好 10 檔、+1545 / −62：
      `    Dockerfile                                                    |  46 ++
TODO-docker-build-rsync-utf8.md                               |  38 ++
assets/whisper                                                |  41 ++
docker/entrypoint-ssh.sh                                      |  32 ++
docs/worksheet-upgrade-openclaw-v2026.10.1-20261011.md        | 326 ++
docs/worksheet-upgrade-openclaw-v2026.10.2-20261012.md        | 111 ++
docs/worksheet-upgrade-openclaw-v2026.10.3-20261014.md        | 383 ++
docs/worksheet-upgrade-openclaw-v2026.10.4-20261017.md        | 489 ++
extensions/google/embedding-provider.ts                       | 139 ++---
extensions/memory-core/src/memory/manager-embedding-ops.ts     |   2 +-`

> 與 10.4 升級時的 diff 形狀逐字一致 → 自訂層在 10.5 完全相容。

### 2.4.1 強制備份（提前執行，schema migration 安全網）— ✅ 完成並驗證

> 因 `agent` schema 24 → 25，備份是唯一回滾路徑，故**提前到 build 之前**完成，不等到 deploy。

- [x] 方法 **A**：`sqlite3 .backup` 線上備份 API（正確處理 WAL）+ 其餘 rsync
- [x] 11 個 live SQLite 以線上備份 API 取得一致快照；`generation-lock` / `generation-writer` /
      `reindex-lock` 等協調鎖 DB 刻意排除（還原反而有害）
- [x] **11/11 快照 `PRAGMA quick_check` = ok**
- [x] **agent DB 快照深度 `PRAGMA integrity_check` = ok**
- [x] **快照 agent DB `user_version = 24`** → 對 10.4 是有效回滾目標（migration 前狀態）
- [x] live agent DB 仍為 `24`（升級前，未被污染）；state DB 快照 `user_version = 20`
- [x] 總計 **2.3G** @ `/home/kuniaki/backup-openclaw-20261019`

**已知缺口（已確認非關鍵）**：2 個 **root 擁有的舊 config 備份**因權限不足未複製 ——
`openclaw.json.backup-token-change`（6/27）、`openclaw.json.bak-20261002141658`（10/2）。
兩者皆為已被取代的舊快照；live `openclaw.json`（8969 bytes）**已成功複製**。
rsync dry-run 確認僅餘這 2 檔 + 2 個 runtime lock 檔（只差 timestamp，不值得備份）。

### 2.5 更新本 worksheet 並 commit

- [ ] `git add docs/worksheet-upgrade-openclaw-v2026.10.5-20261019.md`
- [ ] `git commit -m "docs: add v2026.10.5 upgrade worksheet"`

### 2.6 Push 分支

- [x] `git push -u origin my-config-v2026.10.5`
- [x] 確認 `origin/my-config-v2026.10.5` == local HEAD == `80331395d1a9ad0b708b6cc6f4b650a0befb0ca4`

### 2.7 觸發 build（分支觸發模型）— ✅ 成功，未遇 422

> [!IMPORTANT]
> **不 force-push git tag。** `--ref` 指向分支、`-f tag` 命名 image，tag 不影響 build。

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.10.5 -f tag=v2026.10.5 -f platforms=all
```

- [x] dispatch 成功（**無 422**，fork 的 Actions 未被用量啟發式停用）
- [x] `gh run list --workflow=docker-release.yml --limit 1 --json databaseId,event,headBranch,headSha,status` - `event` = `workflow_dispatch` ✅ - `headBranch` = `my-config-v2026.10.5` ✅ - `headSha` = `80331395d1a9ad0b708b6cc6f4b650a0befb0ca4` ✅
      （**我們的** commit，非官方 `1b58cb9a1b4f` — 已程式化比對確認）
- [x] **Run ID：`39177048878`**
- [x] `gh run watch` → **conclusion: success**，4 個 job 全綠（耗時 11m09s）：
  ```
  success  prepare                                        3s
  success  build-and-push (linux/amd64)                   10m26s
  success  build-and-push (linux/arm64)                   10m38s
  success  merge                                         17s
  ```
- [x] 保留 GHA buildx cache（既定決策）
- [x] Build Run：https://github.com/kuniakil/openclaw/actions/runs/39177048878

### 2.8 Build 結果驗證 — 全部通過 ✅

- [x] 5 個 tag 全部存在：`2026.10.5` ✅ `v2026.10.5` ✅ `2026.10.5-slim` ✅ `latest` ✅ `main` ✅
- [x] **Multi-arch digest**：`sha256:faaa138d2b3efffa8e689431f66cf9224b232989f88f64a2515ed599800fddcf`
  - `linux/amd64` → `sha256:96ad96909862a892ca0d2688b653c52ff8330d5653d6b59669b6274ae363575d`
  - `linux/arm64` → `sha256:df18a59fbaa9632c682c2655d1f84c065dda2400d63ca908a2c51fb9bed714a9`

---

## Phase 3: 部署與驗證

### 3.0 強制備份 🔴 MANDATORY（schema migration 導致不可回滾）— ✅ 已於 2.4.1 完成

> 因 `agent` schema 24 → 25，升級後 **無法** 用 `kubectl set image` 回滾到 10.4。
> 這一步是唯一的安全網。**已完成並驗證**（詳見 2.4.1）。

- [x] 備份位置：`/home/kuniaki/backup-openclaw-20261019`（2.3G）
      （非 SOP 寫的 `/root` — `kuniaki` 無法寫入 `/root`，且無法檢視其內容）
- [x] 11 個 live SQLite 一致快照，`quick_check` 11/11 ok
- [x] agent DB 快照 `integrity_check` = ok、`user_version = 24` → 對 10.4 是有效回滾目標
- [x] 已向使用者回報備份位置、大小與已知缺口（2 個 root 舊 config 備份）

### 3.1 K3s 部署

- [ ] `~/kubernetes/openclaw/overlays/n100/kustomization.yaml`：`2026.10.4` → `2026.10.5`
- [ ] `kubectl apply -k` → `deployment.apps/openclaw-gateway configured`
- [ ] `kubectl rollout status` → successfully rolled out
- [ ] 新 Pod `1/1 Running`、`RESTARTS 0`
- [ ] Image digest 與 2.8 記錄的一致
- [ ] `~/kubernetes` commit + push

### 3.2 Schema migration 與 plugin 載入驗證 ⭐ 本次重點

- [ ] 啟動日誌確認 agent DB migration 成功、無 `doctor --fix` 需求
- [ ] **agent DB `user_version` 已從 24 → 25**（migration 實際生效的證據）
- [ ] **plugin 數 = 18**（10.4 是 17），且 **新增 `x`**
- [ ] **每個 bundled plugin 都是 `active`**（Codex 門檻已於 2.0.1 確認不適用，此處只需看有無其他 admission 失敗）
- [ ] **`x` plugin 處於未設定 / 未啟用狀態**（不應有對外監聽或 API 呼叫）
- [ ] Gateway `ready`

### 3.2 Schema migration ⭐ 本次真正的關卡

> [!IMPORTANT]
> **計畫修正**：原以為 migration 會自動執行。**實際不會。**
> `assertCanonicalAgentPersistenceVersion`（`src/state/openclaw-agent-db-schema-read.ts:50`）是
> **讀取守門員**：當 `userVersion < OPENCLAW_AGENT_SCHEMA_VERSION` 就直接 throw，
> OpenClaw 刻意 fail closed，把 mutation 交給 Doctor（`src/commands/doctor-agent-database-*.ts`）。
>
> 症狀：套用新 image 後 Gateway 活著但 **sessions 全部不可用**：
>
> ```
> [state/agent-admission] agent database remains degraded agentId=main
>   reason="...uses schema version 24; stop active agents and run openclaw doctor --fix ..."
>   repairHint="Sessions remain unavailable. Stop the Gateway, run \"openclaw doctor --fix\" ... and restart."
> [cron/maintenance] Cron maintenance failed ...（每分鐘重複）
> [plugins] memory-core: dreaming startup cleanup failed for agent main ...
> ```
>
> **處置（已執行）**：停 Gateway → 一次性 Job 跑 `openclaw doctor --fix` → 重啟。
> Job manifest：`/tmp/openclaw-doctor-job.yaml`（同 image、同 hostPath 掛載、`envFrom: secrets-env`、
> 繞過 gateway entrypoint 直接跑 CLI、`backoffLimit: 0` 避免重試）。

- [x] `kubectl scale --replicas=0`，確認 DB 無持有者（`No resources found`）
- [x] Job `openclaw-doctor-fix-20261019` **succeeded:1**（62 秒）
- [x] 關鍵行：`Upgraded agent database schema in .../openclaw-agent.sqlite: v24 -> v25`
- [x] **agent DB `user_version` = 25** ✅
- [x] state DB `user_version` = 20（不變，符合預期）
- [x] `agent_databases` registry row **同步為 25** ✅（避免 agent 被 filter 掉）
- [x] agent DB `quick_check` = ok
- [x] 重啟後：`degraded` / `schema version 24` / `MigrationRequired` **全部消失**
- [x] `cron/maintenance` 不再失敗（先前每分鐘失敗）
- [x] memory-core dreaming 清理不再失敗
- [x] Doctor 另存**它自己的** pre-migration 備份（第二條獨立回滾路徑）：- `/home/node/.openclaw/agents/main/agent/openclaw-agent.sqlite.pre-startup-migration-<uuid>.bak` - `/home/node/.openclaw/state/openclaw.sqlite.pre-startup-migration-<uuid>.bak` - `/home/node/.openclaw.update-captures/doctor-<uuid>/manifest.json`
- [x] 只讀 `openclaw doctor` → **Doctor complete，無任何 error 級項目**

### 3.2.1 Plugin 載入驗證

- [x] **17 plugins**，與 10.4 **完全相同**：`anthropic, canvas, cua-computer, device-pair,
    file-transfer, geolocation, github, google, linux-node, memory-core, microsoft, ollama,
    openai, talk-voice, tavily, telegram, xai`
- [x] **`x` plugin 未載入** — 與原預期 18 個不同。該 channel plugin 需設定才啟用，
      未設定即不載入。**實務上比預期安全**（無新增對外通道）
- [x] 無任何 admission 失敗（Codex 門檻已於 2.0.1 確認不適用）

### 3.3 運行版本

- [x] 容器內 `/app/package.json` → `2026.10.5`
- [x] `openclaw --version` → `OpenClaw 2026.10.5`
- [x] `/health` → **200**
- [x] Pod：`openclaw-gateway-697b89c68f-cfbjw`，`1/1 Running`，`RESTARTS 0`
- [x] Image digest 與 2.8 記錄一致：`ghcr.io/kuniakil/openclaw@sha256:faaa138d2b3e...`

### 3.4 自訂功能存活 — 全數通過 ✅

- [x] `locale -a`：`C.utf8` / **`en_US.utf8`** / **`zh_TW.utf8`**
- [x] `whisper` → `/usr/local/bin/whisper`
- [x] `edge-tts` → `/usr/local/bin/edge-tts`
- [x] `ffmpeg` → `/usr/bin/ffmpeg`
- [x] `rsync` → `/usr/bin/rsync`
- [x] `sshd` → `/usr/sbin/sshd` 存在且 listener 運行中
      （⚠️ 非互動 shell 的 `PATH` 不含 `/usr/sbin`，故 `which sshd` 會 MISSING —— 那是 PATH 問題，非缺失）
- [x] `/app/docker/entrypoint-ssh.sh` → OK executable
- [x] `faster_whisper.__version__` = **1.2.1**
- [x] `edge_tts.__version__` = **7.3.1**
- [x] Doctor 亦偵測到自訂層：`Local STT auto-selection: whisper`

### 3.5 Gemini rate pacing 實機驗證 ⭐ 本次自訂 patch 的真實價值

- [ ] 觸發一次 memory embedding 索引，確認**無 429**
- [ ] 確認 `gemini` provider 索引併發為 1（我們的 1 行 patch 生效）
- [ ] 連續請求間隔觀察符合 ~4.2 s pacing

> 需真實 memory 索引流量才能驗證；待有實際 embedding 請求時補驗。

### 3.6 端到端真實訊息往返（Telegram）

- [x] `openclaw sessions list` 可讀出 session 與歷史 → **sessions 恢復**
      （`agent:main:teleg...338761`，`39k/200k`，MiniMax-M2.5）
- [ ] 收訊息 → 工具執行 → 多輪模型呼叫（全 200）→ 回覆送出（待使用者實測）
- [ ] **確認 hook tool-policy 收緊後，工具審批仍正常運作**（breaking #1）

### 3.7 記憶體趨勢觀察

- [ ] 官方宣稱「回到 10.4 區間」，對照 10.4 實測值（10.4 實測 2498 → 2414 → 2414 MiB）
- [x] 冷啟動後 cgroup memory = **774 MiB**（`811040768` bytes）→ 明顯低於 10.4 的 ~2.4 GB
- [x] 新 worker 架構確認生效：`sqlite-readonly-location.worker.js --openclaw-sqlite-readonly-child session`
- [x] 採**趨勢**判斷，不以單次 `rss_threshold` 警告升級為事故（見 SOP Phase 3）
- [x] 目前**無** `rss_threshold` 警告、無 `MaxListenersExceededWarning` 以外的異常

### 3.8 回滾備案（⚠️ schema 已 migration，回滾需還原備份）

```bash
# 1. 停 Gateway（doctor 與還原都必須）
kubectl -n openclaw scale deploy/openclaw-gateway --replicas=0

# 2. 清掉 migration 後的 sidecar，否則 SQLite 會 replay 比主檔更進度的 WAL
rm -f /data/services/openclaw/.openclaw/agents/main/agent/openclaw-agent.sqlite-wal{,m}
rm -f /data/services/openclaw/.openclaw/state/openclaw.sqlite-wal{,m}

# 3. 必須「兩個 DB 一起」還原 —— agent_databases registry 會記錄 schema_version，
#    且讀取端做精確比對過濾；只還原 agent DB 會讓 registry 與實際檔案不一致
cp /home/kuniaki/backup-openclaw-20261019/agents/main/agent/openclaw-agent.sqlite \
   /data/services/openclaw/.openclaw/agents/main/agent/openclaw-agent.sqlite
cp /home/kuniaki/backup-openclaw-20261019/state/openclaw.sqlite \
   /data/services/openclaw/.openclaw/state/openclaw.sqlite

# 4. 驗證（應為 24 / 20）
sqlite3 <agent-db> "PRAGMA quick_check; PRAGMA user_version;"
sqlite3 <state-db> "PRAGMA user_version;"

# 5. 改回 image 並恢復
kubectl -n openclaw set image deployment/openclaw-gateway \
  gateway=ghcr.io/kuniakil/openclaw:2026.10.4
kubectl -n openclaw scale deploy/openclaw-gateway --replicas=1
```

- [x] 把此限制寫入本 worksheet 的 Phase 3 結論
- [x] **現況：`user_version` 已為 25 → 單改 image tag 不再可行，必須走上述還原流程**
- [x] 另有 doctor 自存的 pre-migration `.bak` 可作第二選擇（位於同一 hostPath）

### 3.9 收尾

- [x] `~/kubernetes` commit `df98ea3`（`chore(openclaw): bump n100 image tag to 2026.10.5`）
- [ ] ⚠️ **`~/kubernetes` push 失敗**：`Invalid username or token. Password authentication is not supported`
      credential helper = `store`，推測 token 過期。僅本機 commit，**未推送**（`領先 1`）。
      未自行更動憑證（需使用者處理）。**不影響運行中的部署**（image 已在 in-cluster 生效）。
      ⚠️ 這可能也是為何該檔案自 `2026.8.2` 之後就沒再出現新 commit。
- [ ] 3.5 Gemini pacing 實機驗證（需真實 embedding 流量）
- [ ] 3.6 Telegram E2E 真實往返（需使用者發訊息）
- [ ] 3.7 記憶體長期趨勢
- [ ] 備份生命週期決策（驗證完成後回收或保留，寫明理由）
- [x] 本 worksheet Phase 3 核心項目完成

---

## 🔖 關鍵參考

- **官方 Release Notes:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.5
- **官方 Changelog:** https://raw.githubusercontent.com/openclaw/openclaw/v2026.10.5/CHANGELOG/2026.10.5.md
- **官方 release SHA:** `1b58cb9a1b4f4353e1add63c8506db4d890962e8`
- **Schema contract:** `src/state/openclaw-agent-db-contract.ts`（`OPENCLAW_AGENT_SCHEMA_VERSION = 25`）
- **Migration:** `src/state/openclaw-agent-canonical-validation-migration.ts`
- **Hook 行為變更 migration 說明:** `docs/plugins/hooks/tool-policy.md`
- **Image:** `ghcr.io/kuniakil/openclaw:2026.10.5`
- **K3s 部署:** `~/kubernetes/openclaw/overlays/n100/`
- **資料路徑:** `/data/services/openclaw/.openclaw/`（`/home/kuniaki/openclaw` 為其 symlink）
- **SOP 來源:** `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`、`~/.pi/agent/skills/docker-image-rebuild/SKILL.md`
- **上一版 worksheet:** `docs/worksheet-upgrade-openclaw-v2026.10.4-20261017.md`

---

## 📌 本次升級特色

1. **首次帶 schema migration，且 migration 不會自動跑。** `agent` 24 → 25。
   這是本次最大的計畫誤差：`assertCanonicalAgentPersistenceVersion` 是 fail-closed 讀取守門員，
   必須手動 `openclaw doctor --fix`。**下次遇到 schemaVersions 變動，應在 `kubectl apply` 之前
   就把 doctor --fix 排進部署序列**（停 Gateway → doctor → 啟動）。
2. **Codex 門檻實查後證實不適用** — `minimumCompatibleVersion: "2026.9.7"` 只作用於
   `@openclaw/codex` npm runtime plugin，且僅在設定了 codex runtime 時評估。我們未設定 → 提前結案。
3. **首次非零衝突，結果仍零衝突。** 3 個自訂功能檔案全部與上游 10.5 重疊，但三向 auto-merge 全部成功。
   關鍵是**逐項驗證雙方改動都在**（特別是 `manager-embedding-ops.ts`：上游大改後那 1 行仍精確對位）。
4. **`x` plugin 未載入**（17 plugins，與 10.4 相同）— channel plugin 需設定才啟用，比預期安全。
5. **記憶體大幅改善**：冷啟 cgroup memory **774 MiB**，對比 10.4 的 ~2.4 GB。呼應官方「回到 10.4 區間」宣稱。
6. **回滾成本永久升高**：schema 已 25，之後任何回退都要「停機 + 還原兩個 DB + 清 sidecar」，
   不再是改個 image tag 就好。完整程序已寫入 3.8。
7. **雙重回滾保險**：本次的 2.3G 驗證備份 + doctor 自存的 pre-migration `.bak`。
