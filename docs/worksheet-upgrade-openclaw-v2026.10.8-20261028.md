# Upgrade Worksheet: openclaw → v2026.10.8

**Date:** 2026-10-28
**Current branch:** `my-config-v2026.10.7`（HEAD `cbf04c8b7d5`）
**Target tag:** `v2026.10.8`（官方 SHA `dc2523e5a5c7a309517fd7fa834add938231d526`）
**New branch:** `my-config-v2026.10.8`
**Release:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.8

> [!IMPORTANT]
>
> ## 本次是「零 schema 變更、零衝突」的純 patch 升級，但**代碼規模是 10.7 的兩倍**
>
> 1. **無 schema migration。** `openclaw.schemaVersions` 維持 **`state 20 / agent 25`**，
>    `src/state/openclaw-*-db-contract.ts` 兩個契約檔 **diff 為空**；
>    `openclaw-agent-db-schema.ts` / `openclaw-state-db-schema.ts` 亦無變動，
>    diff 內 **無任何新增 `CREATE TABLE`**（僅測試 fixture）。
>    → 不需要 `openclaw doctor --fix`；**回滾只要改 image tag**（10.7 與 10.8 同為 agent schema 25）。
> 2. **無 Node 下限變動、無 base image 變動。** `engines.node` 仍是 `>=24.22.1 <25 || >=26.12.1`；
>    上游 `Dockerfile` 對 10.7→10.8 **diff 為空**（`node:24.22.1-bookworm` digest 完全相同）
>    → 我們的自訂層（locale / rsync / faster-whisper / edge-tts / ffmpeg / openssh-server）**可原封帶過**。
> 3. **衝突交叉比對結果為空（0 個檔案）**—— 這次連 `docs/` 與 `.github/` 都納入比對，仍是空。
>    我們自訂修改的 6 個非 docs 檔，上游 10.7→10.8 **逐一 diff 都是 0 行**。
> 4. **不需要重建記憶體 embedding 索引**（schema / embedding 模型 / embedding 輸入格式版本皆未變）。
>    **絕對不要**為了驗證而清空 embedding cache —— 那是 10.6 配額事故的根因。
> 5. **plugin 目錄清單完全相同**（176 → 176，逐項 diff 相同）→ plugin 數維持 17，無新 plugin。
>
> **本次要留意的 3 件事**
>
> - ⚠️ **fork 的 Actions 自動停用風險逼近上限**：fork 累計 workflow runs 已達 **484**
>   （10.4 就是因為 ~480 這個量級被 GitHub 自動停用而拿到 HTTP 422）。
>   dispatch 若回 422，**唯一有效的動作**是開 `https://github.com/kuniakil/openclaw/actions`
>   點橫幅重新啟用；**不要**清 cache / 改 settings / 重試。
> - ⚠️ **上游 Google provider 的 SSE 解析被重構**（新增 `extensions/google/transport-stream-sse.ts`，
>   `transport-stream.ts` −203 行）。我們聊天用 MiniMax、embedding 用 Gemini，
>   而 `extensions/google/embedding-provider.ts` **上游未動**，所以 **Gemini 限速 patch 不受影響**；
>   但 Phase 3 仍要 grep 確認 patch 存活。
> - 🟡 **Telegram 預設帳號 secret 契約改變**（`hasImplicitDefaultAccount`）：
>   這是修「新增具名帳號後預設帳號 token 被清掉」的 **正向** 修補，正好保護我們的 root-level `botToken`。
>   升級後必須做一次真實訊息往返確認 bot 仍會回覆。

---

> [!IMPORTANT]
>
> 1. **本地 `v2026.10.x` 都是自訂 tag**（含我們的 patch）。官方 baseline 已 fetch：
>    - `refs/tags/upstream-v2026.10.8`（官方 10.8，SHA `dc2523e5a5c7`）
>    - `refs/tags/upstream-v2026.10.7`（官方 10.7，SHA `157d8c2bc3ea`）
> 2. **不可用本地 `v2026.10.7` 當 diff base**。新分支必須從 `upstream-v2026.10.8` 開。
> 3. **使用分支觸發模型**（承襲 10.3～10.7 決策），**不** force-push git tag。
> 4. 禁止在 Mac 跑 `pnpm check:changed` / `tsgo` / `vitest` / `docker build`，一律交給 GitHub Actions。
> 5. **備份不強制**（無 schema 變更 → 回滾 = 改 image tag），但既有 10.7 備份仍在保留期內，需先盤點（見 2.0）。

---

## Phase 1: 分析結果

### 1.1 官方 10.7 → 10.8 差異

| 項目                            | 10.7                           | 10.8                              | 備註                                               |
| ------------------------------- | ------------------------------ | --------------------------------- | -------------------------------------------------- |
| `package.json` version          | 2026.10.7                      | **2026.10.8**                     | 唯一 `package.json` 變更                           |
| `openclaw.schemaVersions`       | state 20 / agent 25            | **state 20 / agent 25（不變）**   | 🟢 **無 migration**，回滾 = 改 image tag           |
| `OPENCLAW_AGENT_SCHEMA_VERSION` | 25                             | **25（不變）**                    | 🟢 契約檔 diff 為空                                |
| `OPENCLAW_STATE_SCHEMA_VERSION` | 20                             | **20（不變）**                    | 🟢                                                 |
| `engines.node`                  | `>=24.22.1 <25 \|\| >=26.12.1` | **不變**                          | 🟢 線上已是 24.22.1                                |
| `packageManager`                | pnpm 12.15.0                   | pnpm 12.15.0（不變）              | 🟢 corepack 自動取得                               |
| `@openclaw/fs-safe`             | 0.26.0                         | **0.26.0（不變）**                | 🟢 10.7 已升過，本次無相依變動                     |
| `pnpm-lock.yaml`                | —                              | **diff = 0**                      | 🟢 **零相依變動**，build 可重用 cache              |
| Dockerfile                      | —                              | **上游 diff 為空**                | 🟢 自訂層零風險帶過，base image digest 相同        |
| `extensions/` 目錄數            | 176                            | **176（清單逐項相同）**           | 🟢 plugin 數維持 17，無新 plugin                   |
| `extensions/` 變更檔數          | —                              | 373                               | 🟡 含 Google SSE 重構 + 12 個擴充套件的新增檔      |
| `.github/workflows/` 變更       | —                              | **0（上游 .github 完全未動）**    | 🟢 但上游仍是 114 個 workflow → **仍要全部 purge** |
| `src/` 變更檔數                 | —                              | 544                               | 🟡 10.7 的 2 倍                                    |
| **變更規模**                    | —                              | **1139 files / +33,016 / −6,100** | 🟡 官方標示 patch 版，但代碼量是 10.7 的兩倍       |
| 上游 commits                    | —                              | 188                               | 🟢 官方貢獻紀錄：162 個 PR                         |

### 1.2 官方 Release Notes 審查（v2026.10.8）

官方定位：修補型 release（8 個 Highlights 主題 + 1 個 Changes + 4 個 Fixes），**無 breaking change 宣稱**、
**無 Deprecations**、**無 schema 遷移要求**。

**與我們 K3s Docker 部署直接相關者 ⭐**：

- **Startup and database resilience（#182615, #182446, #182385）** —
  「startup work 不再繼承已關閉的 SQLite reader scope（models / chat metadata / channel replies 保持可用）」
  ＋「agent database 啟動期間的暫時性 lock 競爭會重試」。
  → **正好對應我們 10.6 / 10.7 觀察到的 stale lease 與 slow SQLite transaction hold**，
  這是本次最實用的修復之一。
- **Updates that finish and recover（#180668, #181695, #181141, #181596, #181456, #182850, #180174）** —
  一般性的 post-update Doctor 失敗會重新啟動 Gateway；孤立的 maintenance worker 不再卡住所有 CLI 指令。
  → 🟢 我們走 image 部署不走 package swap，但「孤立 worker 不再卡住 CLI」對我們日常 `openclaw` CLI 有意義。
- **Conversations keep accepting messages（#181992, #178888, #181871, #181300, #182219）** —
  被殺掉的 run 釋放 restart-recovery fence；被中斷的 child session 在 Gateway 重啟後可恢復；
  **inbound message 在 reply runtime 無法發送時不再無限重試**。
  → 🟢 直接改善我們的 Telegram 收訊可靠性（10.7 曾觀察到 ingress retry policy 大改）。
- **Auth and providers（#180280 等）** —
  「rate-limited profile 的冷卻時間只維持到 provider 要求的長度」。
  → 🟢 **正對 10.6 的 MiniMax Token Plan 429 額度問題**：以前會被鎖住數小時，現在只鎖到 provider 要求的時間。
- **Doctor recovery（#181941, #181804, #180414, #181618）** —
  Doctor 無法恢復 Gateway 時會印出失敗原因與啟動指令；agent 刪除日誌遺失後可恢復；
  **極大的 session 歷史恢復不會再爆 stack**（我們的 agent DB 已 249 MB）。
  → 🟢 我們 10.5 曾遇到 doctor --fix 後 agent 被 hold，這批修補是正向的。
- **Gateway stability and streaming（#178596, #183410, #182433 等）** —
  「每次 cold tool inventory 都讓 Gateway 記憶體成長」被修掉；archive worker 閒置 5 分鐘後釋放 heap。
  → 🟢 直接對應我們 10.6 起就在觀察的記憶體趨勢（目前 cgroup 已 2.67 GiB）。
- **Security hardening（#180880, #179880, #178742 等）** —
  allowlist 模式下 `test -v` 的 operand expansion 需審批；generic node invoke 拒絕 browser proxy 指令；
  sandbox 子行程無法執行 host CLI backend。
  → 🟡 我們 `tools.exec` 未設定 → 預設 security = `full`、mode = `full` → allowlist 路徑不生效，
  但 code-mode 的 exec/wait 仍走同一 policy，**Phase 3 需觀察一次 exec 行為**。
- **Channels（Telegram 預設帳號 token 保留 #183618 等）** —
  Telegram / Mattermost 預設帳號在新增具名帳號後仍保留 token 與 secret。
  → 🟢 **正向**：我們正是 root-level `botToken` 的單一預設帳號，這個修補直接保護我們。
- **Windows exec and plugins / Provider and model continuity / Voice and meetings** —
  與本部署（Linux 容器、MiniMax、無 voice）無關，僅記錄。

**Changes**：Fresh OpenAI setup 的 first-run model metadata 不再限制 model picker（與我們無關）。

**Deprecations / Breaking Changes / 遷移要求**：**無**。
`schemaVersions`、DB 契約常數、DB schema 檔、`pnpm-lock.yaml` 全部未動 → **不需要 migration script、不需要 doctor --fix**。

**官方 release notes 中的已知告警（與我們無關但記錄）**：
Android APK skipped（`apps/android/version.json` 仍是 2026.8.2，release train 是 2026.10.8）。

### 1.3 上游已知未結案 issue（**非本次迴歸**，僅供 Phase 3 判讀時對照）

| Issue                                      | 影響                                                                                                                    |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| #185578 Gateway heap floor 只增不減        | 10.7 起存在的上游記憶體議題 → Phase 3 記憶體觀察要以**趨勢**判斷，不以單次數值定罪                                      |
| #185902 `openclaw memory index` 被 SIGTERM | 會留下數百 MB 的 orphaned shadow DB → **強化「本次絕不跑 memory index」**                                               |
| #185946 update verifier 在 trusted-proxy   | 只影響 `openclaw update`（npm 路徑）與 `gateway.auth.mode="trusted-proxy"`；我們是 **token 模式 + image 部署** → 不適用 |

### 1.4 自訂 patch 清單（`my-config-v2026.10.7` 內）

| Commit                            | 檔案                                                                                                                  | 內容                                                                 |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- |
| `79f0dd1d1b1`                     | `.github/workflows/*`（官方 114 檔 → 只留 1 檔）                                                                      | 刪除官方 workflows、覆蓋 `docker-release.yml` 為 Matrix 版（191 行） |
| `eb32eb0318c`（源 `a586fa6afdc`） | `Dockerfile`（+46）、`extensions/google/embedding-provider.ts`、`extensions/memory-core/.../manager-embedding-ops.ts` | 自訂層 + Gemini Free Tier rate pacing + gemini 索引併發鎖 1          |
| `6581f174900`（源 `678a32fdcd1`） | `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`                                       | 自訂資產（0755）                                                     |
| 31 個 docs commits                | `docs/worksheet-upgrade-openclaw-*.md`                                                                                | 保留 10.1～10.7 升級歷史                                             |

### 1.5 衝突交叉比對 —— 🟢 **零衝突**（含 docs 與 workflows 的完整比對）

```bash
comm -12 <(git diff --name-only upstream-v2026.10.7 my-config-v2026.10.7 | sort -u) \
         <(git diff --name-only upstream-v2026.10.7 upstream-v2026.10.8 | sort -u)
```

**結果：空（0 個檔案）。**（比 10.7 升級時更嚴格：那次排除了 `docs/` 與 `.github/`）

我們自訂修改的 6 個非 docs 檔，**上游 10.7→10.8 逐一 diff 都是 0 行**：

| 檔                                                           | 上游 10.7→10.8 diff | 判定      |
| ------------------------------------------------------------ | ------------------- | --------- |
| `Dockerfile`                                                 | **0 行**            | 🟢 零衝突 |
| `extensions/google/embedding-provider.ts`                    | **0 行**            | 🟢 零衝突 |
| `extensions/memory-core/src/memory/manager-embedding-ops.ts` | **0 行**            | 🟢 零衝突 |
| `assets/whisper`                                             | **0 行**            | 🟢 零衝突 |
| `docker/entrypoint-ssh.sh`                                   | **0 行**            | 🟢 零衝突 |
| `TODO-docker-build-rsync-utf8.md`                            | **0 行**            | 🟢 零衝突 |

#### ① `Dockerfile` —— 🟢 上游 diff 為空

```bash
git diff upstream-v2026.10.7 upstream-v2026.10.8 -- Dockerfile   # → 0 行
diff <(git show upstream-v2026.10.7:Dockerfile | grep '^ARG OPENCLAW_.*IMAGE') \
     <(git show upstream-v2026.10.8:Dockerfile | grep '^ARG OPENCLAW_.*IMAGE')   # → IDENTICAL
```

我們的自訂層是檔尾追加（4 個 `# Custom:` 段落），上游完全沒動這個檔 → cherry-pick 必然零衝突。
`ENV NODE_ENV=production` 在上游 10.8 仍位於 line 440（我們分支上是 486）→ 追加位置不變。

#### ② `extensions/google/embedding-provider.ts` —— 🟢 上游未改

我們的 Gemini rate pacing（`geminiEmbeddingQueue` / `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` /
`executePaced`）原樣保留。上游這次改的是 `transport-stream.ts`（聊天 SSE），
**不是** embedding provider。**驗收**：升級後容器內 grep 仍有命中。

#### ③ `extensions/memory-core/src/memory/manager-embedding-ops.ts` —— 🟢 上游未改

我們那 1 行 `provider?.id === "gemini" ? 1 : ...` 原樣保留。**驗收**：diff 對基線仍為剛好 1 行。

#### ④ `extensions/memory-core/src/migration/doctor-memory-sidecar.ts` —— 🟡 上游有動，但我們沒改這個檔

上游讓 memory sidecar migration 的 warning 標記為 `recoverable`（失敗的匯入保留來源供日後修復）。
只在 `doctor --fix` 路徑生效；本次不做 doctor --fix → 無影響，但 Phase 3 的 doctor 檢查要記錄是否出現新警告。

#### ⑤ `src/config/sessions/paths.ts` + `doctor-relative-session-store.ts` —— 🟡 上游有動，但我們無相對路徑設定

上游把**相對** session store 路徑的解析基準從「工作目錄」改成「state 目錄」（#182444），
並新增 Doctor 的 relative-session-store 修復。
我們的 `openclaw.json` **沒有** `session.store`、**沒有** `agents.defaults.sessionStore` → 一律走預設
（state 目錄下的 per-agent 路徑）→ **不觸發**。Phase 3 僅確認 `openclaw sessions list` 正常。

#### ⑥ `.github/workflows/` —— 🟢 按 SOP purge 重建

上游 10.7→10.8 的 `.github/` **完全未動**（仍是 114 個 workflow）。
**全部 purge**，用 `my-config-v2026.10.7` 的 Matrix 版覆蓋 `docker-release.yml`，**不 merge 官方變更**。

### 1.6 記憶體 embedding —— 🟢 **不需重建**

```bash
git diff upstream-v2026.10.7 upstream-v2026.10.8 -- packages/memory-host-sdk/ \
  extensions/memory-core/src/memory/embeddings.ts extensions/google/embedding-provider.ts \
  extensions/memory-core/src/memory/manager-embedding-ops.ts
# → 空
```

`extensions/memory-core/` 本次只動 2 檔（`package.json` 版本號、`doctor-memory-sidecar.ts`），
**不涉及 embedding 輸入格式、不涉及 embedding 模型、不涉及 schema**。
→ 索引與快取繼續沿用。**本次升級絕不執行** `openclaw memory index` / `memory reset` /
`memory search`（會觸發 embedding → 有 429 配額風險；限速是每行程一份）。

### 1.7 風險評估：**低**（與 10.7 同級，但代碼量兩倍 → 驗證不能省）

| 風險類型         | 等級      | 原因                                                                                    |
| ---------------- | --------- | --------------------------------------------------------------------------------------- |
| **Schema 中斷**  | 🟢 **無** | `state 20 / agent 25` 未變 → 不需 doctor、不需停機 migration、**回滾 = 改 image tag**   |
| Node runtime     | 🟢 無     | 下限未變，base image digest 未變，線上已是 24.22.1                                      |
| 自訂 patch       | 🟢 **零** | 交集為空（含 docs / workflows）→ 預期零衝突                                             |
| 相依             | 🟢 **零** | `pnpm-lock.yaml` diff = 0，無任何相依增刪                                               |
| 行為相容性       | 🟡 低     | Google SSE 重構（不影響我們路徑）、exec allowlist 收緊（預設 full 不觸發）              |
| Plugin           | 🟢 低     | 套件清單 176 → 176 不變 → plugin 數維持 17；3 個 plugin.json 有新增設定鍵（預設關閉）   |
| Telegram         | 🟡 低     | secret 契約改動 → 必須做真實訊息往返驗證                                                |
| 模型目錄         | 🟢 無     | 我們用 MiniMax-M2.5 / M3                                                                |
| Channel          | 🟡 低     | ingress retry policy 大改（新增 recovery 預算）→ 有正向修補，無行為破壞                 |
| 部署中斷         | 🟡 低     | 單 pod rollout；過往 7 次升級皆在 ~30s 內恢復，但本次 **DB admission / startup 有改動** |
| **Actions 停用** | 🟡 **中** | fork 累計 484 runs，逼近 ~480 自動停用量級 → 可能吃 422（處置方式已知，見 2.8）         |

### 1.8 線上現況盤點（2026-10-28 採樣）

```
image        : ghcr.io/kuniakil/openclaw:2026.10.7
pod          : openclaw-gateway-797c755676-8qdmz  1/1 Running  RESTARTS 0  AGE 34h
version      : OpenClaw 2026.10.7   (node v24.22.1)
plugins      : 17 (anthropic, canvas, cua-computer, device-pair, file-transfer, geolocation,
                  github, google, linux-node, memory-core, microsoft, ollama, openai,
                  talk-voice, tavily, telegram, xai)
agent DB     : user_version = 25, quick_check = ok, 249,049,088 B
state DB     : user_version = 20, quick_check = ok
memory       : chunks 2220 / sources 177 / fts 2220 / embedding_cache 3217
               （10.7 收工時為 2115 / 174 / 2115 / 3033 → 增量成長，非重建）
standing_intents : 0
sessions     : 6（agent:main:main、telegram:default:direct:830338761、3×cron、1×node）
近 30 分鐘   : RESOURCE_EXHAUSTED = 0、[memory] 事件 = 0
cgroup memory.current : 2,867,838,976 B（≈2.67 GiB；10.7 收工 1.79 GB → 上升中）
備份         : /home/kuniaki/backup-openclaw-20261026  267M（保留期至 ~2026-11-02）
磁碟         : / 1.8T 已用 581G（34%）
```

> [!NOTE]
> **記憶體趨勢**：10.7 收工 1.79 GB → 今日 2.67 GB。上游 10.8 正好修掉 #178596（cold tool inventory 記憶體成長）
> 與 #183410（archive worker 閒置釋放 heap），但上游 #185578（heap floor 只增不減）仍未結案。
> → Phase 3 以**多次取樣的趨勢**判斷，不以單次數值定罪。

---

## Phase 2: 執行步驟

### 2.0 前置檢查

- [x] `git status -sb` → `## my-config-v2026.10.7...origin/my-config-v2026.10.7`（工作區乾淨）
- [x] 官方 baseline tag 已 fetch
      `bash
    git fetch upstream refs/tags/v2026.10.8:refs/tags/upstream-v2026.10.8 --no-tags
    git rev-parse 'upstream-v2026.10.8^{commit}'   # dc2523e5a5c7a309517fd7fa834add938231d526
    `
      （與官方 release notes 內的 `release SHA: dc2523e5a5c7...` 一致）
- [x] `schemaVersions` 對比：`10.7 {state:20, agent:25}` == `10.8 {state:20, agent:25}` → **無 migration**
- [x] DB 契約檔 / DB schema 檔 diff 皆為空；diff 內無新增 `CREATE TABLE`（僅 test fixture）
- [x] `engines.node` 對比：`>=24.22.1…` → `>=24.22.1…`（不變）
- [x] `pnpm-lock.yaml` diff = 0（零相依變動）
- [x] 官方 Release Notes + `CHANGELOG/2026.10.8.md` 已審閱（無 breaking / 無 migration）
- [x] 衝突交叉比對（含 docs / workflows）→ **空**
- [x] Dockerfile 上游 diff → **空**；base image ARG digest → IDENTICAL
- [x] embedding 相關檔 diff → **空** → 不需重建索引
- [x] `extensions/` 目錄清單 176 == 176（逐項相同，無新 plugin）
- [x] 線上現況盤點（見 1.8）
- [x] 既有備份盤點（`backup-openclaw-20261026` 267M，保留期至 ~2026-11-02；磁碟 34%）
- [x] **備份決策：使用者已指定 (b) 輕量線上快照**（2026-10-28）

### 2.1 建立新分支（從 upstream 10.8 基線）

- [x] `git checkout -b my-config-v2026.10.8 'upstream-v2026.10.8^{commit}'`
- [x] HEAD = `dc2523e5a5c7`
- [x] `package.json` version = `2026.10.8`、`schemaVersions` = `{'state': 20, 'agent': 25}`、
      `engines.node` = `>=24.22.1 <25 || >=26.12.1`
- [x] 確認新分支上 `docs/worksheet-upgrade-openclaw-v2026.10.8-20261028.md` 仍存在（未追蹤檔會跟著 checkout 保留）

### 2.2 Purge 官方 workflows 並覆蓋 Matrix `docker-release.yml`

- [x] `find .github/workflows -type f ! -name 'docker-release.yml' -delete`（官方 114 個 workflow → 1）
- [x] `git checkout my-config-v2026.10.7 -- .github/workflows/docker-release.yml`
- [x] commit `21942a9a797`（114 files changed, +149 / −65,639）
- [x] 驗證：僅剩 `docker-release.yml`（**191 行**）；`on:` 只有 `workflow_dispatch`、input 名稱 = **`tag`**、
      `platforms` 預設 `all`（**不是** `tag_name`）

### 2.3 Cherry-pick 自訂 commits（保留線性歷史）

- [x] `git cherry-pick -x a586fa6afdc` → `e693812b9b0`：**零衝突**（3 files, +125 / −62）
- [x] `git cherry-pick -x 678a32fdcd1` → `ae70390a569`：**零衝突**（3 files, +111；whisper 0755 / entrypoint-ssh.sh 0755）
- [x] 帶過 `my-config-v2026.10.7` 的 **31 個純 docs commits**（`6581f174900..my-config-v2026.10.7` 整段），
      保留 10.1～10.7 升級歷史
- [x] 線性歷史：**0 merge commit**（`git log --merges upstream-v2026.10.8..HEAD` = 0）；分支共 34 個 commits

### 2.4 輕量本地驗證（無重型 CI）

- [x] `git diff 'upstream-v2026.10.8^{commit}' HEAD --stat -- Dockerfile` → **+46 / −0**（純附加）
- [x] 4 個 `# Custom:` 段落仍在 `ENV NODE_ENV=production`（486）**之前**（439 / 458 / 474 / 478）
- [x] base image ARG = `node:24.22.1-bookworm`（line 16）+ `node:24.22.1-bookworm-slim`（line 17），
      digest `sha256:6449e19d8184…`（未被覆寫）
- [x] `grep -n 'geminiEmbeddingQueue\|MIN_GEMINI_EMBEDDING_INTERVAL_MS'` → 有命中（218 / 219 / 295-303）
- [x] `manager-embedding-ops.ts` 對基線 diff 仍為 **1 行**（line 527，`|| provider?.id === "gemini"`）
- [x] `assets/whisper` / `docker/entrypoint-ssh.sh` → `-rwxr-xr-x`
- [x] `git diff 'upstream-v2026.10.8^{commit}' HEAD --stat -- ':!.github'` → 13 檔、+3316 / −62
      （Dockerfile 46 + TODO 38 + assets 41 + entrypoint 32 + 7 份 worksheet + 2 個功能檔）

### 2.5 備份（使用者已選 (b) 輕量線上快照）

- [x] **選 (b)：輕量線上快照** → `/home/kuniaki/backup-openclaw-20261028`（**294M**，496 個檔案）
  - [x] 用容器內 `node:sqlite` 的 `backup()`（module-level `backup(db, path)`）取 **7 個 live SQLite** 一致快照
        （WAL 安全；agent 249,724,928 B + state 16,068,608 B + quarantine + codex-home ×4）
  - [x] **7/7 快照 `PRAGMA quick_check` = ok**
  - [x] 快照 `user_version`：agent = **25** / state = **20** / quarantine = 2（與線上一致 → 確認無待 migration）
  - [x] 其餘 runtime 檔以 `cp -a` / `rsync` 帶走：`openclaw.json`、`openclaw.json.last-good`、
        `config-journal-fingerprint.key`、`credentials/`、`identity/`、`devices/`、`plugin-state/`、
        `plugins/`、`skills/`、`memory/`、`state/`（非 sqlite）、`workspace/`
  - [x] `state/` 內另含 live `openclaw.sqlite*` → **刪除**（避免與 `db/state/` 的一致快照重複且非一致）
  - [x] **排除**協調鎖 DB（generation-lock / generation-writer / reindex-lock / gateway locks）、
        `workspace/oracle-hunt`（524M git repo，可由 git 還原）、`workspace/worktrees`
  - [x] 快照檔案大小與來源一致（agent 249,724,928 B；state 16,068,608 B）
  - [x] 容器內暫存目錄 `/home/node/.openclaw/tmp/backup-20261028` 已刪除（不留 shadow 檔）
  - [x] 磁碟 `/` 581G / 1.8T（34%）不變

### 2.6 更新本 worksheet 並 commit

- [ ] `git add docs/worksheet-upgrade-openclaw-v2026.10.8-20261028.md` + commit

### 2.7 Push 分支

- [ ] `git push -u origin my-config-v2026.10.8`
- [ ] 確認 `origin/my-config-v2026.10.8` == local HEAD

### 2.8 觸發 build（分支觸發模型）

> [!IMPORTANT]
> **不 force-push git tag。** `--ref` 指向分支、`-f tag` 命名 image，tag 不影響 build。

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.10.8 -f tag=v2026.10.8 -f platforms=all
```

- [ ] dispatch 成功；若回 `HTTP 422 "Actions has been disabled for this repository"` →
      到 `https://github.com/kuniakil/openclaw/actions` 點橫幅重新啟用
      （**不要**清 cache / 改 settings / 重試；判定法見 SOP Hard Rule 8：
      dispatch 不存在的 workflow 回 404、dispatch 我們的 workflow 回 422 = GitHub 拒絕執行）
- [ ] `gh run list --workflow=docker-release.yml --limit 1 --json databaseId,event,headBranch,headSha,status`
  - `event` = `workflow_dispatch` ✅
  - `headBranch` = `my-config-v2026.10.8` ✅
  - `headSha` = **我們的** commit（非官方 `dc2523e5a5c7`）✅
- [ ] `gh run watch <run_id>` → conclusion: **success**（10.7 耗時 ~11 分鐘）
      （⭐ **必須派給背景子代理**，主迴圈不得阻塞）

### 2.9 Build 結果驗證

- [ ] 關鍵 tag 存在：`2026.10.8` ✅ `v2026.10.8` ✅ `2026.10.8-slim` ✅ `latest` ✅ `main` ✅
      （`latest` / `main` 由 merge job 依 `is_release=true` 一併推出，會覆蓋前版 → 正常行為）
- [ ] multi-arch manifest 確認含 amd64 + arm64

---

## Phase 3: 部署與驗證

### 3.1 K3s 部署

- [ ] **由 Mac 編輯** `~/kubernetes/openclaw/overlays/n100/kustomization.yaml`：`2026.10.7` → `2026.10.8`
      （Mac 為唯一編輯來源；N100 只部署不改 manifest）
- [ ] `kubectl kustomize` 預覽確認產出 `ghcr.io/kuniakil/openclaw:2026.10.8`
- [ ] **N100 端 manifest 先清掉本地未提交修改再同步**（N100 `~/kubernetes` 目前落後 origin/main，
      且 `openclaw/overlays/n100/kustomization.yaml` 有本地未提交 diff，會擋住 `git pull`）：
      `bash
    ssh n100 "cd ~/kubernetes && git checkout -- openclaw/overlays/n100/kustomization.yaml"
    `
- [ ] Mac commit + push `my-k8s` main → N100 `git pull origin main`（k3s-sync-ops 標準流程）
      （若改走 rsync 鏡像：`rsync -a --delete --exclude='hermes/overlays/n100/secrets.env' ~/kubernetes/ n100:~/kubernetes/`）
- [ ] `kubectl apply -k` → rollout status → 新 Pod `1/1 Running`、**RESTARTS 0**
- [ ] 三端一致：Mac manifest / N100 manifest / 線上 Pod 皆為 2026.10.8

#### 3.1.1 無 migration 驗證

- [ ] 啟動 log **無** `agent database remains degraded` / `MigrationRequired` / `schema version` /
      `dreaming startup cleanup failed` / `cron/maintenance fail`（grep = **0**）
- [ ] `openclaw doctor`（read-only）→ **Doctor complete**，error 級 grep = **0**
- [ ] 線上 agent DB `user_version` = **25**、state DB = **20**（未被升級改寫）；兩者 `PRAGMA quick_check` = **ok**
- [ ] 啟動後 15 分鐘內 log 無 error/warn/fail
- [ ] 確認**未出現**新的 relative-session-store / legacy-main-session 遷移警告（3.5 ⑤ 的風險點）

#### 3.1.2 Plugin 載入驗證

- [ ] **17 plugins**，與 10.7 相同（Gateway 啟動 log `http server listening (17 plugins: …)`）
- [ ] 無 admission 失敗、無 plugin 被 quarantine（上游 10.8 新增「啟動時修復 plugin host links」路徑 → 觀察）
- [ ] Telegram provider 啟動正常（`starting provider (@N100_openclaw_mike_bot)`、`isolated polling ingress started`）

#### 3.1.3 運行版本

- [ ] 容器內 `/app/package.json` → `2026.10.8`
- [ ] `openclaw --version` → `OpenClaw 2026.10.8`
- [ ] `node --version` → **v24.22.1**（下限未變，符合預期）
- [ ] `/health` → **200** `{"ok":true,"status":"live"}`

#### 3.1.4 行為變更觀察（10.8 新增）

- [ ] **Telegram 預設帳號 token 保留**：root-level `botToken` 在升級後仍生效
      （上游 #183618 修補的目標）→ 以 3.5 的真實訊息往返驗證
- [ ] **exec 行為**：code-mode 的 exec/wait 仍可正常執行，未出現新的 approval 阻擋
      （上游 #180880 讓 allowlist 模式的 `test -v` 需審批；我們預設 `full`，應不受影響）
- [ ] **agent DB 啟動**：無 stale lease / 無 `slow SQLite transaction hold` 警告
      （上游 #182615 / #182446 修的正是我們 10.6–10.7 觀察到的現象）
- [ ] `standing_intents` 表仍為 **0 列**
- [ ] `openclaw sessions list` 正常列出 6 個 session

#### 3.1.5 自訂功能存活

- [ ] `locale -a` → `C` / `C.utf8` / `POSIX` / **`en_US.utf8`** / **`zh_TW.utf8`**
- [ ] `whisper` → `/usr/local/bin/whisper`；`faster_whisper.__version__` = 1.2.1
- [ ] `edge-tts` → `/usr/local/bin/edge-tts`；`edge_tts.__version__` = 7.3.1
- [ ] `ffmpeg` → `/usr/bin/ffmpeg`；`rsync` → `/usr/bin/rsync`
- [ ] `/usr/sbin/sshd` 存在且 sshd 行程運行中
- [ ] `/app/docker/entrypoint-ssh.sh` → mode **0755**
- [ ] Doctor 仍偵測到自訂層：`Local STT auto-selection: whisper`
- [ ] 容器內 `extensions/google/embedding-provider.ts` 含 `MIN_GEMINI_EMBEDDING_INTERVAL_MS`（2 處命中）
      → Gemini rate pacing 存活，繼續保護配額
- [ ] 容器內 `extensions/memory-core/src/memory/manager-embedding-ops.ts` 含 `provider?.id === "gemini"`（1 處命中）
      → gemini 索引併發鎖 1 存活

### 3.2 記憶體索引狀態確認（**唯讀，不重建**）

- [ ] 五表計數與升級前**完全一致**（chunks **2220** / sources **177** / FTS **2220** / cache **3217**）
      → **未被重建、未被清空**
- [ ] 近 1 小時 `RESOURCE_EXHAUSTED` = **0**、`[memory]` 事件 = **0**（本次升級期間零 embedding 請求）
- [ ] 全程未執行 `openclaw memory index` / `memory search` / `memory reset` / `agent --local`

### 3.3 記憶體趨勢觀察（延續 10.6 / 10.7 觀察項）

- [ ] cgroup `memory.current` **多次取樣**（升級前 2.67 GiB → 升級後 3 次以上），判斷**趨勢**而非單點
- [ ] 上游 10.8 修了 #178596 / #183410；上游 #185578（heap floor 只增不減）仍未結案 → 不以此定罪
- [ ] 以**趨勢**判斷，不以單次 `rss_threshold` 警告升級為事故

### 3.4 回滾備案（本次可單純改 image tag 🟢）

```bash
kubectl -n openclaw set image deployment/openclaw-gateway \
  gateway=ghcr.io/kuniakil/openclaw:2026.10.7
kubectl -n openclaw rollout status deploy/openclaw-gateway
```

- [ ] 確認 10.7 與 10.8 同為 agent schema 25 → **不需要**還原 DB、不需要 doctor（保留路徑，未實際回滾）

### 3.5 Telegram 端到端真實訊息往返（必做，10.8 改動了 Telegram secret 契約）

- [ ] 使用者實際發訊到 `@N100_openclaw_mike_bot`
- [ ] log 出現 `Inbound message` → agent turn 啟動 → `model-fetch provider=minimax model=MiniMax-M3 status=200`
      → `outbound send ok`（`chatId=830338761`）
- [ ] 期間 `RESOURCE_EXHAUSTED` = **0**、`[memory]` 事件 = **0**

### 3.6 收尾 — k8s 三端同步 + 備份 lifecycle

- [ ] Mac commit + push 到 `my-k8s` main；N100 同步（git pull 或 rsync 鏡像），三端一致
- [ ] 備份 lifecycle：**驗證完提示使用者，等確認才刪**
  - 10.7 層 `/home/kuniaki/backup-openclaw-20261026`（267M）→ 保留期至 ~2026-11-02
  - 10.8 層 `/home/kuniaki/backup-openclaw-20261028`（若本次有做）→ 保留，10.8 升級前回滾用
  - 磁碟 `/` 現況 581G / 1.8T（34%）
- [ ] 確認無 `*.memory-reindex-*` orphaned shadow DB 殘留（上游 #185902 提醒）

### 3.7 未結案項（結轉）

- [ ] **跨行程限速技術債**（`geminiEmbeddingQueue` 為 module 層級狀態；根治需 lock file / SQLite 協調
      或改走 Gateway RPC）—— 上游未修，非本次迴歸
- [ ] **MiniMax Token Plan 額度**（2026-10-26 14:55 額度打滿）—— 上游 10.8 的 #180280 已把
      「rate-limited profile 鎖住數小時」修成「只鎖到 provider 要求的時間」→ 觀察 10.8 是否改善
- [ ] 上游 #185578（Gateway heap floor 只增不減）—— 上游議題，觀察中
- [ ] 上游 #185902（memory index SIGTERM 留下 orphan shadow DB）—— 不影響本部署（不跑 memory index）

---

## 🔖 關鍵參考

- **官方 Release Notes:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.8
- **官方 Changelog:** `CHANGELOG/2026.10.8.md`（上游 `upstream-v2026.10.8`）
- **官方 release SHA:** `dc2523e5a5c7a309517fd7fa834add938231d526`
- **Schema contract:** `src/state/openclaw-agent-db-contract.ts`（agent = 25）、`src/state/openclaw-state-db-contract.ts`（state = 20）—— 對 10.7 diff 皆為空
- **Image:** `ghcr.io/kuniakil/openclaw:2026.10.8`
- **Branch:** `my-config-v2026.10.8`
- **K3s 部署:** `~/kubernetes/openclaw/overlays/n100/`
- **資料路徑:** `/data/services/openclaw/.openclaw/`（`/home/kuniaki/openclaw` 為其 symlink）
- **SOP 來源:** `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`、`~/.pi/agent/skills/docker-image-rebuild/SKILL.md`、`~/.pi/agent/skills/k3s-sync-ops/SKILL.md`
- **上一版 worksheet:** `docs/worksheet-upgrade-openclaw-v2026.10.7-20261026.md`

---

## 📌 本次升級特色

1. **零衝突、零 schema 變更、零相依變動** —— 三條 git diff（migration / 衝突面 / embedding）全空，
   連 `docs/` 與 `.github/` 都納入比對仍是空。
2. **回滾 = 改 image tag**（同為 agent schema 25），不需要停機 migration、不需要 DB 還原。
3. **代碼量是 10.7 的兩倍**（1139 檔 / +33,016 行）→ 驗證步驟不能省，尤其是 Telegram 往返與記憶體趨勢。
4. **最實用的修復**：#182615 / #182446（SQLite reader scope + 啟動 lock 重試）、
   #178596 / #183410（記憶體成長與 archive worker）、#180280（rate-limit 冷卻）、
   #183618（Telegram 預設帳號 token 保留）—— 全部對應我們實際觀察到的問題。
5. **主要風險不在程式，在流程**：fork 的 GitHub Actions 累計 484 runs，逼近自動停用量級 → dispatch 可能吃 422。
