# OpenClaw 升級工作表：v2026.11.7 → v2026.11.8

- 日期：2026-11-24
- 目前分支：`my-config-v2026.11.7`（HEAD `59715c6ef85`）
- 目標：`v2026.11.8`（發佈 2026-11-24 11:54:30 UTC，stable，`npm dist-tags.latest`）
  - upstream commit：`2d4ab292114df2ab9670c91c9b846f701c565bd7`（`upstream-v2026.11.8`）
  - 前一版 baseline：`upstream-v2026.11.7` = `e31bbf056de321127988ec5c1a36ff1b59297de0`
- 新分支：`my-config-v2026.11.8`
- 目標 Image：`ghcr.io/kuniakil/openclaw:2026.11.8`
- 線上現況：`ghcr.io/kuniakil/openclaw:2026.11.7`，deploy `openclaw-gateway`（Pod `openclaw-gateway-7ff7bcfdd4-dkscb`，1/1 Running，RESTARTS 0，AGE 34h）
- 上游規模：**314 commits / 63 contributors**，**1313 files changed**（+31790 / −7264）

---

## 摘要（先讀這段）

| 項目                 | 結論                                                                                                                                                                                                                                           |
| :------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 目標版本             | `v2026.11.8`（stable、`npm dist-tags.latest = 2026.11.8`；`extended-stable=2026.10.33`、`beta=2026.11.10-beta.3` 不採用）                                                                                                                      |
| 升級性質             | **維護型升級**（314 commits，較 11.7 的 736 commits 明顯小；上游連續歷史，無分歧）                                                                                                                                                             |
| 不可逆點             | **無** — `schemaVersions` `state 36 → 36`、`agent 38 → 38` **完全未變**（§1.2）→ 不需強制備份即可回滾，且**不需 scale-0 / 維護 Pod / `doctor --fix`**                                                                                          |
| 自訂 patch 可移植性  | **21 個自訂 commit 全部可移植**；隔離 worktree 乾跑實測 **零衝突**（比 11.7 少一個真衝突）→ **無需改寫任何 patch**（§1.5）                                                                                                                     |
| 上游 breaking change | **本次無 breaking change 段落**（11.8 是維護 release，Changes 段落只寫「concentrates on the fixes below」）；上游改動全屬 fix 與內部重構                                                                                                       |
| ⚠️ **新的時間壓力**  | **41 項 compatibility record 到期日 = 2026-11-29**（距今 5 天）→ 我們的線上 config **命中其中 6 類**（`agents.defaults.model`、`memory.search`、`channels.telegram.dmPolicy/streaming`、`tts.*`、`gateway.bind`、`plugins.entries.*`）（§1.7） |
| 上游已知 bug 影響    | #202213（壓縮封存讀取）**11.8 仍未修**（§1.8）→ 延續性問題、非本次回歸                                                                                                                                                                         |
| Base image           | **不變**（node `24.22.1-trixie`）；`engines.node` 不變（§1.6）                                                                                                                                                                                 |
| CJK 策略決議         | **維持保留自訂 CJK Han Bigram 伴隨索引**；上游 11.8 **完全未觸碰**我們的 CJK 檔案（§1.9）                                                                                                                                                      |
| 記憶體索引重建       | **不需要**（schema / embedding 模型 / 輸入格式版本皆未變）（§1.10）                                                                                                                                                                            |
| Gemini 索引併發      | **不需改寫**：上游 11.8 仍支援 `inlineIndexConcurrency`，且未改我們的 adapter / provider 檔（§1.11）                                                                                                                                           |
| 目前狀態             | 🟢 **Phase 2 執行中**：分支 `my-config-v2026.11.8` 已建立（21/21 cherry-pick CLEAN、零衝突）、config baseline 已重新產生、12 項輕量驗證通過；待觸發 build 與部署                                                                               |

---

## 🚦 Go-Sign Gate

- [x] Phase 1 完成官方 Release Notes、`schemaVersions` 與**隔離 worktree 乾跑**分析
- [x] 隔離 worktree 乾跑：**21/21 cherry-pick 全部 CLEAN，零衝突**
- [x] 確認無 patch 需改寫（11.7 需要的 `inlineIndexConcurrency` 改寫在 11.8 **不適用**）
- [x] 不在 Mac 本機跑重型 CI（`tsgo`/`vitest`）或本機 `docker build`（全交 GitHub Actions）
- [x] 升級期間不另起 `openclaw memory index/search/reset`、`agent --local`（避免雙行程撞 Gemini 配額）
- [x] 10+ 分鐘長等待（`gh run watch`、`kubectl rollout status`）一律派給背景子代理
- [x] **使用者明確核准執行 Phase 2（Go-Sign）** — 2026-11-24 核准「Go：執行升級」；deprecation 遷移（§1.7）**另開工作**處理

---

## Phase 1: 分析結果

### 1.1 官方 Release Notes 摘要（314 commits，範圍 `e31bbf056de..2d4ab292114`）

Release：<https://github.com/openclaw/openclaw/releases/tag/v2026.11.8>

**供應鏈核對（三方一致）**

| 來源              | 值                                                                                                                                                                        |
| :---------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| GitHub Release    | release SHA `2d4ab292114df2ab9670c91c9b846f701c565bd7`                                                                                                                    |
| 本地 upstream tag | `git rev-parse upstream-v2026.11.8^{commit}` = `2d4ab292114df2ab9670c91c9b846f701c565bd7` ✅                                                                              |
| npm registry      | `openclaw@2026.11.8` integrity `sha512-uSuR2dNwRUFFRWX24aEl0zLYSbUhCS2qmEpfuIXehjbh1rEvuCvah9s+/1WBNJ8NQSbAX7xJxSXu7PW8tzYsdA==` — **與 release notes 公布值逐字相符** ✅ |

npm dist-tags：`latest = 2026.11.8`、`extended-stable = 2026.10.33`、`beta = 2026.11.10-beta.3`
→ 我們的 fork 跟 `latest` 線，與歷次升級（11.1 → 11.7）一致。

**Highlights（上游原文摘要）**

| 主題                    | 內容                                                                                                                                                                        |
| :---------------------- | :-------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Privacy and safety      | Signal view-once 附件不進 agent input、封鎖 workspace Azure 轉址、ClawHub 憑證反射遮蔽、Windows 命令換行注入拒絕（#196841, #202031, #187625, #190547）                      |
| Conversation continuity | Claude CLI 歷史與 warm follow-up 在 reset、message-tool 回覆、fallback、ACP 重啟後仍可用（#197536, #197735, #197295, #198426, #189500）                                     |
| Reliable answers        | Telegram 草稿中斷／推理／tool call／steering 後仍送出最終答案，不以 model notice 取代子答案、不重複回覆（#181508, #194896, #196769, #202540, #189852）                      |
| Dependable automations  | silent / 空 checklist 的 run 正確收尾、編輯過的 job 保留原對話、cron 用自己的 scratch 與投遞紀錄（#197618, #202390, #186833, #199197, #188848）                             |
| Safer, lighter upgrades | 避免重複複製資料庫、回收舊 runtime 與 snapshot、備份慢時仍保留完整 SQLite 復原擷取（#193941, #197833, #191196, #199654, #192406）                                           |
| Model access            | refreshable OAuth 模型可用、peer refresh 等待、MCP 登入在網路中斷時保留、worker 本地模型切換與 ChatGPT 版本協商恢復（#191789, #192906, #196055, #196414, #197507, #202427） |

**與我們部署直接相關的 Fixes**

- **Telegram routing / history**：private bound topic 留在自己的 ACP session、非 forum 群組回覆留在歷史、cached context 與 cron 通知回到擁有它們的 topic、模糊的最終送件重試（#190516, #189231, #195214, #192779）→ **有利**（我們的主要 channel）
- **Reliable answers / Command boundaries**：被中斷的草稿後仍送最終答案、空白 outbound 附件丟棄、`/queue` 字面提及不被吃掉（#181508, #188571, #189290, #188900, #189240）→ **有利**
- **Memory retention**：MEMORY.md compaction 保留 inline notes、Memory Core dreaming opt-out 在有其他 memory-slot owner 時仍生效、reindex 後回收磁碟、英文 object 問題恢復 deep recall（#164089, #188950, #197230, #191384）→ **有利**（我們的 dreaming 有設定）
- **Provider errors / retries**：空 tool-followup turn 重試、Muse 配額與登入錯誤可見、配額用盡不再短重試（#187769, #195148, #201997, #188290, #189716）→ **有利**
- **Worker inference**：infer model request 改走 state-owning Gateway、web-search 工具不再在推論前讓 turn 失敗（#197314, #194540, #198141）→ **有利**
- **Doctor / upgrade recovery**：inspection 保留有用 metadata、跳過無關擷取再 hash、pre-Doctor ledger 無法讀取時仍繼續更新（#202984, #192407, #193622）→ **有利**
- **Docker / Kubernetes**：保留 bundled-plugin SDK imports、build args 傳到正確的 Docker stage、config seeding 失敗時 K3s init 失敗（#181974, #193041, #198983）→ 見 §1.6（build-args 需檢查）

### 1.2 關鍵發現 A：`schemaVersions` 未變更 → **可逆升級**

```bash
git show upstream-v2026.11.7:package.json | python3 -c "import json,sys;print(json.load(sys.stdin)['openclaw']['schemaVersions'])"
# {'state': 36, 'agent': 38}
git show upstream-v2026.11.8:package.json | python3 -c "import json,sys;print(json.load(sys.stdin)['openclaw']['schemaVersions'])"
# {'state': 36, 'agent': 38}
```

`updateAdmissionProtocol = 1`、`updatePreflightProtocol = 1` 同樣未變。

**結論：與 11.6 → 11.7 相同，本次是可逆升級。**

- 不需要強制完整備份才能回滾（仍建議做，見 §2.1）
- 不需要 scale-0 / 維護 Pod / `doctor --fix`
- **不需要重建記憶體 embedding 索引**（§1.10）
- **回滾 = 改回 image tag**（Rollback Plan）

| 欄位           | 11.7                          | 11.8        | 變動       |
| :------------- | :---------------------------- | :---------- | :--------- |
| `version`      | `2026.11.7`                   | `2026.11.8` | 是（預期） |
| `engines.node` | `>=24.16.0 <25 \|\| >=26.1.0` | 同左        | 否         |

### 1.3 上游是否為分歧歷史

11.7 → 11.8 為**上游連續歷史**（`git merge-base --is-ancestor upstream-v2026.11.7 upstream-v2026.11.8` → YES），無需處理兩條分歧線。`upstream-v2026.11.8` 以 `refs/tags/v2026.11.8` 抓取（annotated tag object），`^{commit}` = `2d4ab292114`，與官方 release notes 公布 SHA 一致。

### 1.4 自訂 Patch 清單（`upstream-v2026.11.7..my-config-v2026.11.7`，共 23 個 commit）

| #     | Commit                                                                                                        | 內容                                                                                       | 可移植性                              |
| :---- | :------------------------------------------------------------------------------------------------------------ | :----------------------------------------------------------------------------------------- | :------------------------------------ |
| 1     | `d8ee0f37aa9`                                                                                                 | `chore:` purge 官方 CI workflows，改用自訂 Matrix `docker-release.yml`                     | ♻️ **重建**（不 cherry-pick）         |
| 2     | `b78f59f4267`                                                                                                 | `chore:` 自訂 Dockerfile 層 + Gemini 限速（`MIN_GEMINI_EMBEDDING_INTERVAL_MS`）            | ✅ 乾跑 CLEAN                         |
| 3     | `dbcd541cc2f`                                                                                                 | `fix(docker):` 恢復 `assets/whisper`、`docker/entrypoint-ssh.sh`                           | ✅ 乾跑 CLEAN                         |
| 4     | `35b8f27a7dd`                                                                                                 | `feat(memory):` CJK Han Bigram 伴隨 FTS 索引                                               | ✅ 乾跑 CLEAN（上游零觸碰）           |
| 5     | `25f7dcf231c`                                                                                                 | `docs:` 帶入歷史升級工作表                                                                 | ✅ 乾跑 CLEAN                         |
| 6–8   | `ba2e02e37ad` / `756b9e525d7` / `c37999eb055`                                                                 | `docs:` 11.5 工作表（Phase 2 記錄、部署結果、Telegram roundtrip）                          | ✅ 乾跑 CLEAN（依時間順序）           |
| 9–15  | `6127c440f05` / `97fd0cad39d` / `19ea7ab6549` / `3abcb398cda` / `1fb6ddabf4a` / `df0a260f005` / `2d5ec8c3e42` | `docs:` 11.6 工作表（建置/部署/預設模型切 MiniMax-M3/根因更正/結案）                       | ✅ 乾跑 CLEAN（依時間順序）           |
| 16    | `908d407bc16`                                                                                                 | `docs:` 記錄已核准清理 v2026.11.4 / v2026.11.5 備份                                        | ✅ 乾跑 CLEAN                         |
| 17    | `5637903f62c`                                                                                                 | `fix(memory):` Gemini 索引併發改用上游原生 `inlineIndexConcurrency`                        | ✅ 乾跑 CLEAN（**上游 11.8 仍支援**） |
| 18    | `622d0b757fd`                                                                                                 | `chore(docs):` 重新產生 v2026.11.7 的 config baseline                                      | ⏭️ **跳過**（改由 §2.5 重新產生）     |
| 19–23 | `9885aedc9a4` / `c189376e001` / `3869ec40dab` / `3e784504e54` / `59715c6ef85`                                 | `docs:` 11.7 工作表（建立、部署結果、結案、備份清理與 Telegram roundtrip、skill 自修紀錄） | ✅ 乾跑 CLEAN（依時間順序）           |

### 1.5 關鍵發現 B：衝突乾跑（**隔離 worktree 實測，非預測**）

在隔離的臨時 worktree（`/tmp/oc-11.8-dryrun`，based on `upstream-v2026.11.8`）實際執行 purge 重建 + 逐一 cherry-pick：

```
✅ 重建      purge official CI workflows（find -delete + 取 my-config-v2026.11.7 的 docker-release.yml）→ 只剩 1 個 workflow
✅ CLEAN     b78f59f4267  chore: upgrade to v2026.9.7; restore custom Dockerfile layer, scripts, rate pacing, and TODOs
✅ CLEAN     dbcd541cc2f  fix(docker): restore assets/whisper and docker/entrypoint-ssh.sh
✅ CLEAN     35b8f27a7dd  feat(memory): add CJK bigram companion FTS index
✅ CLEAN     25f7dcf231c / ba2e02e37ad / 756b9e525d7 / c37999eb055
✅ CLEAN     6127c440f05 / 97fd0cad39d / 19ea7ab6549 / 3abcb398cda / 1fb6ddabf4a / df0a260f005 / 2d5ec8c3e42
✅ CLEAN     908d407bc16
✅ CLEAN     5637903f62c  fix(memory): serialize Gemini embedding indexing via provider-declared inlineIndexConcurrency
✅ CLEAN     9885aedc9a4 / c189376e001 / 3869ec40dab / 3e784504e54 / 59715c6ef85
```

**結論：21/21 全部 CLEAN，零衝突。** 與 11.7（1 組真衝突）相比，本次**不需要改寫任何 patch**。

#### 交叉檢查（預測 vs 實測一致）

```bash
comm -12 <(git diff --name-only upstream-v2026.11.7 my-config-v2026.11.7 | sort -u) \
         <(git diff --name-only upstream-v2026.11.7 upstream-v2026.11.8 | sort -u)
```

命中 9 個檔案：

| 檔案                                                 | 判定                                                                 |
| :--------------------------------------------------- | :------------------------------------------------------------------- |
| 8 個 `.github/workflows/*.yml`（上游改過、我們已刪） | ❌ 假陽性 → purge 路徑下直接刪除，不需處理                           |
| **`Dockerfile`**                                     | ✅ **自動合併乾淨** → 上游 2 處新增與我們 4 層自訂層同時保留（§1.6） |

#### 合併後保留資產逐項驗證（乾跑實測）

```
Dockerfile: 4 個 "Custom:" 標記
  :450  # Custom: Generate UTF-8 locales and install rsync
  :469  # Custom: Install faster-whisper, edge-tts, and ffmpeg for audio TTS/STT pipelines
  :485  # Custom: Audio STT CLI wrapper for fast-whisper
  :489  # Custom: SSH server support for Zeabur deployment
Dockerfile: 上游 11.8 新增 RUN chmod 0755 /home/node（:440）保留 ✅
Dockerfile: 上游 11.8 新增 ARG OPENCLAW_BUNDLED_PLUGIN_DIR（production-deps stage）保留 ✅
assets/whisper（可執行）                ✅
docker/entrypoint-ssh.sh（可執行）      ✅
packages/memory-host-sdk/src/host/cjk-bigram.ts  ✅
extensions/google/embedding-provider.ts:226  MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200  ✅
extensions/google/memory-embedding-adapter.ts:38  inlineIndexConcurrency: 1  ✅
src/infra/database-engine/sqlite-search-schema.ts  cjk 命中 6 處  ✅
.github/workflows/  僅 docker-release.yml，與 my-config-v2026.11.7 逐字相同（diff = 0 行）  ✅
```

### 1.6 Dockerfile / base image

上游 11.7 → 11.8 **修改了 Dockerfile**（2 處，11.7→11.6 那次是 0 處）：

```diff
 FROM dependency-inputs AS production-deps
+ARG OPENCLAW_BUNDLED_PLUGIN_DIR
 RUN --mount=type=cache,id=openclaw-pnpm-store,...
...
+# Without this, install -d leaves /home/node/.config as root:root (issue #85968).
+RUN chmod 0755 /home/node
 RUN install -d -m 0755 -o node -g node /home/node/.config && ...
```

- **base image 不變**：`FROM` 行 11.7 / 11.8 逐字相同（node `24.22.1-trixie`、bun `1.4.4`）
- 上游改動位於 Dockerfile **中段**，我們的自訂層接在 **檔尾** → git 三方合併自動成功，**零衝突**
- 上游自己的 build（`docker-release-prepare.yml`）傳的 build-args 為 `GITHUB_ACTIONS / GIT_COMMIT / OPENCLAW_BUILD_TIMESTAMP / OPENCLAW_DOCKER_BUILD_VERSION / OPENCLAW_EXTENSIONS=diagnostics-otel,codex`；**沒有**傳 `OPENCLAW_BUNDLED_PLUGIN_DIR` → 使用 Dockerfile 預設值 `extensions`
- 我們的 Matrix workflow 傳的 build-args 是 `OPENCLAW_EXTENSIONS=diagnostics-otel,codex` → **與上游等價，無需修改 workflow** ✅
  （我們不傳 `OPENCLAW_DOCKER_BUILD_VERSION` / `GIT_COMMIT` 是既有差異，11.7 線上已驗證正常，11.8 不變）

### 1.7 ⚠️ 上游 compatibility deadline：41 項將於 **2026-11-29** 到期

這是 11.8 相對 11.7 **新增的主要風險面**：release notes 的「Upcoming deprecations」列出 41 項 compatibility record，其最早移除日期落在 2026-11-29（距今 5 天）。

**重要限定（release notes 原文）**：_「They remain present in this release; removal still requires the documented upgrade conditions and maintainer review.」_
→ **不是 11.8 移除，也不阻擋本次升級**；但到期日逼近，必須排入後續 `openclaw doctor` 遷移。

**我們的線上 config 命中項**（2026-11-24 於 N100 實測 `openclaw.json`）：

| 相容 record                                                                                          | 到期日     | 我們的 config（實測）                                                                                                   | 判定                                                                               |
| :--------------------------------------------------------------------------------------------------- | :--------- | :---------------------------------------------------------------------------------------------------------------------- | :--------------------------------------------------------------------------------- |
| `doctor-root-default-model`                                                                          | 2026-11-29 | `agents.defaults.model = { primary: "minimax/MiniMax-M3" }`                                                             | ⚠️ **命中**（另有 `agents.entries.main.model` 同步設定，遷移時須兩處一致）         |
| `doctor-memory-search-owner-consolidation`                                                           | 2026-11-29 | `memory.search = { provider: "gemini", store: { fts: { tokenizer: "trigram", cjk: "bigram" } } }`                       | ⚠️ **命中**（`cjk: "bigram"` 是我們的自訂鍵，遷移時**不可丟**）                    |
| `doctor-channel-dm-aliases` / `doctor-phase2-channel-dm-aliases`                                     | 2026-11-29 | `channels.telegram.dmPolicy`                                                                                            | ⚠️ **命中**（單一 channel 層級的 alias）                                           |
| `doctor-channel-streaming-aliases`                                                                   | 2026-11-29 | `channels.telegram.streaming`                                                                                           | ⚠️ **命中**                                                                        |
| `doctor-tts-top-level-owner` / `doctor-tts-provider-aliases` / `doctor-tts-speaker-selection-fields` | 2026-11-29 | `tts.provider = "microsoft"`、`tts.providers.microsoft.speakerVoice = "zh-TW-HsiaoChenNeural"`                          | ⚠️ **命中**（注意：官方別名清單寫的是 `edge` → `microsoft`，我們已用 `microsoft`） |
| `doctor-gateway-bind-host-aliases`                                                                   | 2026-11-29 | `gateway.bind = "lan"`                                                                                                  | ⚠️ **命中**（字串型 bind）                                                         |
| `doctor-bundled-plugin-load-paths`                                                                   | 2026-11-29 | `plugins.entries.*`（telegram, minimax, microsoft, memory-core, brave, groq, tavily, perplexity, browser, device-pair） | ⚠️ **命中**（persisted plugin registry）                                           |

**未命中**：`models.providers.*.models[].contextTokens`（我們的 minimax provider 未設 contextTokens）、`session.maintenance.pruneAfter`、`mcp.servers.*.transport`、`plugins.entries.*.config.webSearch`（我們的 brave/groq/tavily/perplexity `config` 皆為 null）、`tools.media.models`、`cron per-job delivery.to`。

**行動項（不阻擋本次升級）**：

- [ ] 升級完成、驗證通過後，另開一次 `openclaw doctor` 遷移工作（**需使用者授權**：涉及 config 變更）
- [ ] 遷移時**必須保留**：`memory.search.store.fts.cjk = "bigram"`（我們的自訂 CJK 鍵）與 `agents.defaults.model` / `agents.entries.main.model` 的一致性
- [ ] **不要**在本次升級中執行 `doctor --fix`（schema 未變 → 不需要；且 11.8 新增「Require repair consent before unattended plugin downloads」，避免順手改動 plugin）

### 1.8 上游已知問題（針對 11.7 → 11.8）

| Issue       | 標籤                  | 內容                                                                                                                                            | 對我們影響                                                                                                                                                                                                    |
| :---------- | :-------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **#202213** | bug / regression / P1 | 讀取壓縮 session 封存（`*.jsonl.zst`）在「明文 transcript > 壓縮檔 + 1 MiB」時拋 `ERR_BUFFER_TOO_LARGE`（修補 #192743 / #193548 **未進 11.8**） | ⚠️ **延續性問題，非本次回歸**：`git diff upstream-v2026.11.7 upstream-v2026.11.8 -- src/config/sessions/archive-compression.ts` 為空 → 11.7/11.8 程式碼逐字相同。線上 1 個超預算封存 → **非致命、無資料損毀** |
| **#203869** | bug / regression / P0 | Code Mode gRPC session closed / BrokenPipe（macOS App）                                                                                         | ⚠️ **待觀察**：macOS App 環境；我們的 Gateway 在 K3s。部署後 agent 回合出現 gRPC/BrokenPipe → 立即比對 11.7                                                                                                   |
| **#203911** | bug / regression / P2 | 檔案附件投遞失敗「Current-source media could not be staged」（Windows 10）                                                                      | ❌ 不適用：非 Windows                                                                                                                                                                                         |
| **#203041** | bug / regression / P1 | `plugins.slots.memory = memory-lancedb` 缺依賴 → 每輪 recall 拋錯（Windows）                                                                    | ❌ 不適用：我們用 `memory-core`（線上已驗證 20 plugins 正常載入）                                                                                                                                             |
| **#203495** | bug / regression / P2 | Android Claw App schema v24→v38 遷移卡住                                                                                                        | ❌ 不適用：非 Android                                                                                                                                                                                         |

### 1.9 CJK Han Bigram 伴隨索引：相容性驗證

我們的自訂 feature（`memory_index_chunks_cjk_fts`）在記憶體 FTS 排序層提供**兩字中文**的 BM25 可排序能力；上游 bigram 機制位於**關鍵字抽詞 / 查詢展開層**——兩者**互補，不是重複實作**（延續 11.5 / 11.6 / 11.7 的判定）。

| 檢查項目                                               | 結果                                                                                                                                                                                                                                                                                                                    |
| :----------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 上游 11.7→11.8 是否觸碰我們的 CJK 檔案                 | ❌ **全部未觸碰**（逐一驗證：`memory-schema.ts`、`memory-schema-base.ts`、`cjk-bigram.ts`、`sqlite-search-schema.ts`、`sqlite-memory-search-fragments.ts`、`keyword-query.ts`、`manager-search*.ts`、`zod-schema.memory-search.ts`、`src/agents/memory-search.ts`、`src/plugin-sdk/memory-core-host-engine-schema.ts`） |
| 上游 11.8 新增的 `164089-memory-mixed-block-companion` | 僅為 `config/test-lines-allocations/` 的行數配額檔，**不是** memory schema 裡的 companion FTS 表 → 與我們的自訂 companion index **不衝突**                                                                                                                                                                              |
| 上游 11.8 的 memory schema 改動                        | `extensions/memory-core/src/memory/manager-db.ts` **+3 行**（`retireSqliteDatabaseAdmissionForPath`，關閉後釋放 SQLite admission 描述子）→ 與我們的 CJK FTS 層**無交集**                                                                                                                                                |
| `src/memory-host-sdk/dreaming.ts`（+12 / −2）          | 非預設 memory-slot owner 且其 config 無 `dreaming` 鍵時，改回讀 Memory Core 的 dreaming 設定 → **我們的 `plugins.entries.memory-core.config.dreaming` 正是預設 owner，行為不變** ✅                                                                                                                                     |
| 合併結果（乾跑實測）                                   | `cjk-bigram.ts` 存在 ✅、`sqlite-search-schema.ts` cjk 命中 6 處 ✅、`memory.search.store.fts.cjk = "bigram"` 設定項仍在 ✅                                                                                                                                                                                             |
| 我們使用的 plugin-sdk export 路徑                      | 11.8 全部仍存在（乾跑合併後 grep 驗證）✅                                                                                                                                                                                                                                                                               |

### 1.10 記憶體 embedding 索引重建：**不需要**

| 判準                           | 檢查結果                                                                                             |
| :----------------------------- | :--------------------------------------------------------------------------------------------------- |
| `openclaw.schemaVersions` 變更 | ❌ 未變（state 36 / agent 38）                                                                       |
| embedding 模型變更             | ❌ 未變（上游未改 `extensions/google/embedding-provider.ts`；`DEFAULT_GEMINI_EMBEDDING_MODEL` 不變） |
| embedding 輸入格式版本變更     | ❌ 未變                                                                                              |
| 明確要清除 embedding 快取      | ❌ 無此需求                                                                                          |

→ **升級後索引與快取繼續沿用，不要主動 `openclaw memory index` 或 `memory reset`。**

### 1.11 Gemini 索引併發：**不需改寫**（與 11.7 相反）

11.7 需要把舊 hack 改寫成上游原生 `inlineIndexConcurrency`；**11.8 不需要**：

| 檢查項目                                      | 結果                                                                                                                                                                         |
| :-------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 上游 11.8 是否仍支援 `inlineIndexConcurrency` | ✅ `src/plugins/embedding-provider-types.ts:47`、`extensions/memory-core/src/memory/manager-embedding-policy.ts:26`、`extensions/ollama/src/memory-embedding-adapter.ts:106` |
| 上游 11.8 是否改動我們的 adapter              | ❌ 未觸碰 `extensions/google/memory-embedding-adapter.ts`                                                                                                                    |
| 上游 11.8 是否改動我們的 provider             | ❌ 未觸碰 `extensions/google/embedding-provider.ts`（限速 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` 原樣保留）                                                               |
| 乾跑合併後結果                                | ✅ `memory-embedding-adapter.ts:38` → `inlineIndexConcurrency: 1`；`embedding-provider.ts:226` → `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`                                   |

兩層保護維持不變、互補：

| 機制                                                                 | 層級                         | 作用                                         |
| :------------------------------------------------------------------- | :--------------------------- | :------------------------------------------- |
| `inlineIndexConcurrency: 1`（`memory-embedding-adapter.ts`）         | 索引工作層（job 併發）       | 索引工作序列化                               |
| `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`（`embedding-provider.ts`） | provider 請求層（HTTP 節奏） | 單一請求間隔 ≥ 4.2s（≈14 RPM < 15 RPM 額度） |

### 1.12 保留資產清單（乾跑後逐項驗證）

| 資產                                                                                    | 驗證結果                                                                |
| :-------------------------------------------------------------------------------------- | :---------------------------------------------------------------------- |
| `.github/workflows/` 僅 `docker-release.yml`                                            | ✅（上游 122 → 我們 1）                                                 |
| `docker-release.yml` 為我們的 Matrix 版                                                 | ✅ `workflow_dispatch` only，dispatch input 名為 **`tag`**、`platforms` |
| `Dockerfile` 自訂層（locales/rsync/tini/faster-whisper/edge-tts/ffmpeg/openssh-server） | ✅ 4 個 `Custom:` 標記保留                                              |
| 上游 11.8 Dockerfile 新增（`ARG OPENCLAW_BUNDLED_PLUGIN_DIR`、`chmod 0755 /home/node`） | ✅ 兩者皆保留（自動合併）                                               |
| `assets/whisper`、`docker/entrypoint-ssh.sh`                                            | ✅ 存在（含可執行位元）                                                 |
| `packages/memory-host-sdk/src/host/cjk-bigram.ts`                                       | ✅ 存在                                                                 |
| `extensions/memory-core/src/memory/manager-search.cjk-bigram.test.ts`                   | ✅ 存在                                                                 |
| `memory.search.fts.cjk = "bigram"` 設定選項                                             | ✅ 存在                                                                 |
| Gemini 限速 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`                                   | ✅ 存在（`embedding-provider.ts:226`）                                  |
| Gemini 索引併發                                                                         | ✅ 原樣保留（`inlineIndexConcurrency: 1`），**無需改寫**                |
| `package.json` version                                                                  | ✅ `2026.11.8`、schema `{state:36, agent:38}`                           |

### 1.13 環境前置（本機 pre-commit hook）

沿用 11.7 的處置：切換到新分支後**先跑 `pnpm install --frozen-lockfile`**，讓本機 `node_modules` 與 `pnpm-lock.yaml` 對齊，否則 pre-commit 的 line-cap ratchet 會因 `oxlint` 版本不符（lockfile 釘 `1.88.0`、本機曾為 `1.89.0`）而失敗。

> 乾跑中以 `git -c core.hooksPath=/dev/null cherry-pick` 執行，僅用於驗證補丁內容；**正式提交必須讓 hook 通過**。

---

## Phase 2: 執行步驟（取得 Go-Sign 後）

### 2.1 備份與基線確認

> ⚠️ **SSH 必須用 `root` 帳號**：git remote `n100` = `root@192.168.31.72`。

**📌 升級前基準（2026-11-24 於 N100 線上實測，部署後逐項比對）**

| 指標                          | 11.7 基準（2026-11-24 實測）                                                                               |
| :---------------------------- | :--------------------------------------------------------------------------------------------------------- |
| `memory_index_chunks`         | **1692**                                                                                                   |
| `memory_index_chunks_fts`     | **1692**                                                                                                   |
| `memory_index_chunks_cjk_fts` | **1692**                                                                                                   |
| `session_transcript_fts`      | **2085**                                                                                                   |
| `cron_jobs`                   | 1 筆：`c870fbf5-4d9b-4773-8e51-eef8c62beaad` / `Memory Dreaming Promotion` / enabled=1 / payload=agentTurn |
| cgroup 記憶體                 | **2.45 GiB**（2,454,134,784 bytes）                                                                        |
| 磁碟                          | 總 1.8T / 已用 666G / 可用 **1.1T**（39% used）                                                            |
| 既有備份                      | `/root/backup-openclaw-20261123-pre-v2026.11.7` = **2.5G**                                                 |
| Pod                           | `openclaw-gateway-7ff7bcfdd4-dkscb`，1/1 Running，RESTARTS **0**，AGE 34h                                  |
| 映像                          | `ghcr.io/kuniakil/openclaw:2026.11.7`                                                                      |

```bash
# 盤點既有備份（勿重複佔空間）
ssh root@192.168.31.72 "du -sh /root/backup-openclaw-* 2>/dev/null || echo '無既有備份'"

# 本次 rollback 備份（schema 未變 → 非強制，但建議做，成本低）
ssh root@192.168.31.72 "rsync -aH /data/services/openclaw/.openclaw/ /root/backup-openclaw-$(date +%Y%m%d)-pre-v2026.11.8/"
ssh root@192.168.31.72 "du -sh /root/backup-openclaw-$(date +%Y%m%d)-pre-v2026.11.8"
ssh root@192.168.31.72 "df -h / | tail -1"

# Mac 端異地備份（沿用既有目錄 /Users/mlee/openclaw-backups/）
#   內容：openclaw.json、openclaw.sqlite.gz、openclaw-agent.sqlite.gz
```

> 本次 schema 未變更（§1.2）→ 備份**非強制**（11.4→11.5 那次才是）。仍建議做。
> 若要冷備份，先 `kubectl -n openclaw scale deploy/openclaw-gateway --replicas=0` 再 rsync，完成後 scale 回 1。
> **既有 11.7 備份（2.5G）先保留**，待 11.8 驗證通過後再問使用者是否清理。

**✅ 執行結果（2026-11-24）**

| 項目         | 結果                                                                                                      |
| :----------- | :-------------------------------------------------------------------------------------------------------- |
| N100 熱備份  | `/root/backup-openclaw-20261124-pre-v2026.11.8` = **2.5G** ✅                                             |
| N100 磁碟    | 總 1.8T / 已用 669G / 可用 **1.1T**（39% used）✅                                                         |
| 既有備份     | `/root/backup-openclaw-20261123-pre-v2026.11.7`（2.5G）**保留未動**，待 11.8 驗證通過後再問使用者是否清理 |
| Mac 異地備份 | ⏳ 待補（§Phase 3 前執行）                                                                                |

### 2.2 建立新分支（從官方 baseline 開，不要從本地 `v*` tag）

```bash
cd /Users/mlee/openclaw
git fetch upstream refs/tags/v2026.11.8:refs/tags/upstream-v2026.11.8 --no-tags
git rev-parse upstream-v2026.11.8^{commit}   # 必須 = 2d4ab292114df2ab9670c91c9b846f701c565bd7
git checkout -b my-config-v2026.11.8 upstream-v2026.11.8
```

### 2.3 Purge 官方 Workflows 並覆蓋 Matrix `docker-release.yml`

**採用「重建 purge commit」路徑（零衝突，與 11.5 / 11.6 / 11.7 做法一致）**：

```bash
# 上游 11.8 有 122 個 workflow；只留我們的 Matrix docker-release.yml
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.11.7 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

### 2.4 移植自訂 commits（順序敏感）

```bash
# 先讓 pre-commit hook 能跑：讓 node_modules 與 lockfile 對齊（§1.13）
pnpm install --frozen-lockfile

git cherry-pick b78f59f4267   # ✅ 自訂 Dockerfile 層 + Gemini 限速
git cherry-pick dbcd541cc2f   # ✅ assets/whisper + entrypoint-ssh.sh
git cherry-pick 35b8f27a7dd   # ✅ CJK bigram（零衝突）
git cherry-pick 25f7dcf231c ba2e02e37ad 756b9e525d7 c37999eb055   # ✅ 歷史 + 11.5 文件
git cherry-pick 6127c440f05 97fd0cad39d 19ea7ab6549 3abcb398cda \
              1fb6ddabf4a df0a260f005 2d5ec8c3e42                   # ✅ 11.6 文件（依時間順序）
git cherry-pick 908d407bc16   # ✅ 備份清理紀錄
git cherry-pick 5637903f62c   # ✅ Gemini inlineIndexConcurrency（上游 11.8 仍支援）
# 跳過 622d0b757fd（11.7 的 config baseline）→ 改由 §2.5 重新產生
git cherry-pick 9885aedc9a4 c189376e001 3869ec40dab 3e784504e54 59715c6ef85   # ✅ 11.7 文件（依時間順序）
```

> **與 11.7 最大的不同：本次沒有任何 `--ours` / `--theirs` 的人工解衝突步驟。** 若真的出現衝突 → **停下回報**，不要自行猜測解法（乾跑已證明應為零衝突）。

**✅ 執行結果（2026-11-24）**

| 步驟                             | 結果                                                                                              |
| :------------------------------- | :------------------------------------------------------------------------------------------------ |
| `pnpm install --frozen-lockfile` | 2.9s 完成；`node_modules/oxlint` = **1.88.0**（與 lockfile 釘選版一致）→ pre-commit hook 正常 ✅  |
| 新分支                           | `my-config-v2026.11.8` @ `2d4ab292114`（官方 baseline）✅                                         |
| Purge workflows                  | 上游 **122 → 1**（`docker-release.yml`）；與 `my-config-v2026.11.7` **逐字相同**（diff = 0 行）✅ |
| cherry-pick 21 個自訂 commits    | ✅ **全部 CLEAN，零衝突**（與乾跑完全一致；無任何人工解衝突步驟）                                 |

### 2.5 重新產生 config baseline

```bash
# 生成檔不可手改
pnpm config:docs:gen      # = node --import ./scripts/tsx.mjs scripts/generate-config-doc-baseline.ts --write
pnpm config:docs:check    # 驗證：OK docs/.generated/config-baseline.sha256 and docs/.generated/config-baseline.counts.json
git add docs/.generated/
git commit -m "chore(docs): regenerate config baseline for v2026.11.8"
```

> 預期 counts 會因上游 11.8 新增設定項而變動（上游新增數十個 `config/test-lines-allocations/2026-11-8-*.txt`）→ **以重新產生的數值為準並記錄**。

**✅ 執行結果（2026-11-24）**

| 項目                   | 結果                                                                                                                     |
| :--------------------- | :----------------------------------------------------------------------------------------------------------------------- |
| `pnpm config:docs:gen` | 重新產生 `.sha256`（counts.json **未變**）；`--check` → **OK** ✅                                                        |
| counts.json 實測值     | `core 2581 / channel 4003 / plugin 4859` — **與 11.7 完全相同**（上游 11.8 未新增設定 schema 鍵）✅                      |
| `.sha256` 變動         | `config-baseline.json` / `.core.json` / `.plugin.json` 三個 digest 變動（上游描述文字更新）；`.channel.json` **不變** ✅ |
| commit                 | `411cfa7a8b9` `chore(docs): regenerate config baseline for v2026.11.8` ✅                                                |

### 2.6 本地輕量驗證（嚴禁重型 CI / 本機 docker build）

```bash
git status -sb
git log --oneline upstream-v2026.11.8..HEAD

ls .github/workflows/                        # 必須只剩 docker-release.yml
grep -c 'Custom:' Dockerfile                # 必須 = 4
grep -n 'chmod 0755 /home/node' Dockerfile   # 上游 11.8 新增，必須存在
grep -n 'MIN_GEMINI_EMBEDDING_INTERVAL_MS' extensions/google/embedding-provider.ts
grep -n 'inlineIndexConcurrency' extensions/google/memory-embedding-adapter.ts
grep -n 'cjk' src/config/zod-schema.memory-search.ts
grep -n -B3 -A3 'cjkBigramFts' packages/memory-host-sdk/src/host/memory-schema.ts
grep -n -A6 'workflow_dispatch:' .github/workflows/docker-release.yml   # input 必須是 tag
python3 -c "import json;d=json.load(open('package.json'));print(d['version'], d['openclaw']['schemaVersions'])"
git diff my-config-v2026.11.7 -- .github/workflows/docker-release.yml   # 必須為空（workflow 未改動）
```

**🚫 絕對不做**：`pnpm check:changed`、`pnpm tsgo:all`、`vitest`、本機 `docker build`（macOS 資源保護，見 skill Hard Rule 7）。

**✅ 執行結果（2026-11-24）— 12/12 通過**

| #   | 檢查                                         | 結果                                                                                |
| :-- | :------------------------------------------- | :---------------------------------------------------------------------------------- |
| 1   | `.github/workflows/`                         | 只有 `docker-release.yml` ✅                                                        |
| 2   | `Dockerfile` 的 `Custom:` 數量               | **4** ✅                                                                            |
| 3   | 上游 11.8 新增                               | `RUN chmod 0755 /home/node`（:440）、`ARG OPENCLAW_BUNDLED_PLUGIN_DIR`（:32/:62）✅ |
| 4   | Gemini 限速                                  | `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`（`embedding-provider.ts:226`）✅          |
| 5   | Gemini 索引併發                              | `inlineIndexConcurrency: 1`（`memory-embedding-adapter.ts:38`）✅                   |
| 6   | CJK schema 選項                              | `cjk: z.literal("bigram").optional()`（`zod-schema.memory-search.ts:66`）✅         |
| 7   | CJK FTS schema 串接                          | `cjkBigramFts` 於 `memory-schema.ts:157 / 448 / 608` 三處 ✅                        |
| 8   | workflow dispatch input                      | `tag` + `platforms`，`workflow_dispatch` only ✅                                    |
| 9   | version / schema                             | `2026.11.8`、schema `{state:36, agent:38}` ✅                                       |
| 10  | workflow 與 11.7 相同                        | diff = **0 行**（UNCHANGED）✅                                                      |
| 11  | `assets/whisper`、`docker/entrypoint-ssh.sh` | 存在且具可執行位元 ✅                                                               |
| 12  | `cjk-bigram.ts` 與其測試檔                   | 存在 ✅                                                                             |

### 2.7 提交工作表並推送分支

```bash
git add docs/worksheet-upgrade-openclaw-v2026.11.8-20261124.md
git commit -m "docs: add v2026.11.8 upgrade worksheet"
git push -u origin my-config-v2026.11.8
```

### 2.8 觸發 GHCR Matrix Build 與監控

> **Go-Sign 後才執行。** 輸入名稱為 **`tag`**（OpenClaw）；workflow 只有 `workflow_dispatch`，**不要 push tag**。

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.11.8 -f tag=v2026.11.8 -f platforms=all

gh run list --workflow=docker-release.yml --limit 1 \
  --json databaseId,event,headBranch,headSha,status
```

**必須驗證**：`event` = `workflow_dispatch`、`headBranch` = `my-config-v2026.11.8`、`headSha` = **我們的 commit**（不得為上游 `2d4ab292114`）。

> **若回傳 `HTTP 422 "Actions has been disabled for this repository"`** → 見 skill Hard Rule 8：到 `https://github.com/kuniakil/openclaw/actions` 點 banner 上的重新啟用按鈕。**不要**清 cache、不要改 repo settings（已驗證為死路）。

`gh run watch`（10+ 分鐘）→ **派給背景子代理**，主迴圈保持可回應。

建置完成後確認 image tags 真的存在：

```bash
for t in 2026.11.8 v2026.11.8 2026.11.8-slim latest main; do
  docker buildx imagetools inspect ghcr.io/kuniakil/openclaw:$t >/dev/null 2>&1 \
    && echo "$t OK" || echo "$t MISSING"
done
```

### 2.9 K3s 部署與驗證

```bash
sed -i '' 's|newTag: ".*"|newTag: "2026.11.8"|' ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
cd ~/kubernetes && git add openclaw/overlays/n100/kustomization.yaml && git commit -m "chore(openclaw): bump image to 2026.11.8"

kubectl apply -k ~/kubernetes/openclaw/overlays/n100
kubectl -n openclaw rollout status deploy/openclaw-gateway --timeout=10m   # ← 派給背景子代理
kubectl -n openclaw get deploy openclaw-gateway -o jsonpath='{.spec.template.spec.containers[0].image}'
```

> ✅ **本次不需要 scale-0 / 維護 Pod / `doctor --fix`**（`schemaVersions` 不變 → 啟動不觸發 schema 遷移）。

**部署後實機驗證清單**（沿用 11.6 / 11.7 已驗證過的檢查項）

- [ ] `openclaw --version` = `OpenClaw 2026.11.8`（容器內 `node dist/index.js --version`）
- [ ] `kubectl -n openclaw get pods` → 1/1 Running，**RESTARTS 0**，無 CrashLoopBackOff；映像 = `ghcr.io/kuniakil/openclaw:2026.11.8`
- [ ] Pod log 開機無 `FATAL` / `schema migration` 錯誤（FATAL=0、schema migration=0）
- [ ] **自訂工具鏈存在**：`/usr/local/bin/whisper`、`/usr/local/bin/edge-tts`、`/usr/bin/ffmpeg`、`/usr/bin/rsync`、`/usr/bin/tini`、`/usr/sbin/sshd`、`/app/docker/entrypoint-ssh.sh`、`en_US.utf8` / `zh_TW.utf8`、`faster-whisper 1.2.1`
- [ ] Gateway logs：**20 plugins 正常載入**（anthropic, brave, canvas, cua-computer, device-pair, file-transfer, geolocation, github, google, linux-node, memory-core, microsoft, minimax, ollama, openai, perplexity, talk-voice, tavily, telegram, xai — **與 11.7 基準逐項相同**）；`loadFailedCount=0.0` / `registerFailedCount=0.0`；**429 = 0 / `RESOURCE_EXHAUSTED` = 0**；全量 reindex = 0
- [ ] **Memory 索引筆數對齊**：`memory_index_chunks` = `_fts` = `_cjk_fts` = **1692**（與升級前相同）；`session_transcript_fts` = **2085**（相同）
- [ ] **2 字中文查詢實測**（經 **Gateway 路徑**，非 CLI）：`memory_index_chunks_cjk_fts MATCH '設定'` 有筆且 bm25 分數有限、同一詞在主 trigram 索引回傳 0 筆 → 證明 CJK 伴隨索引仍生效
- [ ] **Gemini 索引併發 = 1 已生效**：整段期間 429 = 0、無 `RESOURCE_EXHAUSTED`
- [ ] Cron `Memory Dreaming Promotion` 維持 `inferenceBinding`、未中斷（job_id `c870fbf5-…`、enabled=1、payload=agentTurn，與升級前逐欄相同）
- [ ] Telegram 實機往返（收發、回覆）✅
- [ ] `openclaw doctor --non-interactive` → exit 0，Error 級 = 0
- [ ] cgroup 記憶體落在 11.7 基準區間（2.24–2.49 GiB），無單調攀升
- [ ] **11.8 觀察項**：Code Mode 無 gRPC / BrokenPipe（#203869 未觸發）
- [ ] **延續性已知問題（非本次回歸）**：`[usage-cost-cache] background refresh failed`（#202213，11.8 仍未修）→ 非致命、無資料損毀

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

# [8] CJK 伴隨索引底層驗證
ssh root@192.168.31.72 "sqlite3 -readonly /data/services/openclaw/.openclaw/agents/main/agent/openclaw-agent.sqlite \
  \"SELECT count(*) FROM memory_index_chunks_cjk_fts WHERE memory_index_chunks_cjk_fts MATCH '設定';\""
```

### 2.10 升級後**不要**做的事

- ❌ `openclaw memory index` / `memory reset`（schema、模型、格式皆未變 → 索引沿用）
- ❌ `openclaw memory search` / `agent --local` 與 Gateway 併發（雙行程撞 Gemini 配額）
- ❌ `openclaw update`（我們走 image 部署，內建 updater 與我們無關）
- ❌ 本次**不**執行 `doctor --fix`（§1.7 的 41 項到期遷移另開工作處理，需使用者授權）

---

## Phase 3: 收尾與清理

- [ ] 更新本工作表完成狀態並 commit / push
- [ ] 建立本版快照分支：`backup/my-config-v2026.11.8` → `origin/my-config-v2026.11.8`
- [ ] 產出 post-mortem 至 `~/kubernetes/docs/openclaw-v2026-11-8-upgrade-20261124.md`
- [ ] 更新 `~/kubernetes/docs/service-version-matrix.md`（openclaw 列 → `2026.11.8`）
- [ ] 備份清理（**需使用者明確核准後執行**）
- [ ] 保留 `my-config-v2026.11.7` 分支與 `origin` 對應分支（回滾用）
- [ ] 記錄待辦：§1.7 的 **2026-11-29 到期遷移**（41 項 compatibility record）；#202213 壓縮封存讀取仍待上游修復；#203869 Code Mode gRPC 觀察項

---

## 回滾預案（Rollback Plan）

本次 `schemaVersions` 未變更 → **回滾不需要資料庫降版遷移**，三種層級任選：

1. **只回滾 image**（最快，秒級）

   ```bash
   sed -i '' 's|newTag: ".*"|newTag: "2026.11.7"|' ~/kubernetes/openclaw/overlays/n100/kustomization.yaml
   kubectl apply -k ~/kubernetes/openclaw/overlays/n100
   kubectl -n openclaw rollout status deploy/openclaw-gateway --timeout=10m
   ```

2. **回滾分支**：改用 `my-config-v2026.11.7` 重新觸發 build → 覆寫 `2026.11.7` image tag

3. **回滾資料**（僅在狀態異常時）：

   ```bash
   ssh root@192.168.31.72 "rsync -aH --delete /root/backup-openclaw-<date>-pre-v2026.11.8/ /data/services/openclaw/.openclaw/"
   ```

   → 需先停 Pod，避免寫入競爭。

> 與 11.5 / 11.6 / 11.7 一致：schema 未變 → **改回 image tag 即完成回滾**，不需要維護 Pod。

---

## 已知風險（Go-Sign 前請確認）

| #   | 風險                                                                                    | 等級 | 緩解                                                                               |
| :-- | :-------------------------------------------------------------------------------------- | :--- | :--------------------------------------------------------------------------------- |
| 1   | **41 項 compatibility record 於 2026-11-29 到期**，我們命中 7 類（§1.7）                | 中   | 不阻擋本次升級（record 在 11.8 仍存在）；升級後另開 doctor 遷移工作（需授權）      |
| 2   | 314 commits 大幅變更引入未預期行為                                                      | 中   | 依 §2.9 逐項實機驗證；先備份以便快速回滾                                           |
| 3   | 本機 `node_modules` 與 lockfile 不同步 → pre-commit hook 失敗                           | 中   | §1.13 / §2.4：切分支後先 `pnpm install --frozen-lockfile`                          |
| 4   | 上游 11.8 改了 Dockerfile（`ARG OPENCLAW_BUNDLED_PLUGIN_DIR`、`chmod 0755 /home/node`） | 中   | 乾跑已驗證自動合併、兩者皆保留（§1.6）；§2.6 逐項 grep 複驗                        |
| 5   | 上游改了我們的自訂 memory 檔案導致語意衝突                                              | 低   | 逐一 grep 驗證：上游 11.8 **完全未觸碰**我們 8 個 CJK / Gemini 檔案（§1.9、§1.11） |
| 6   | #203869 Code Mode gRPC / BrokenPipe（macOS App 回報）                                   | 低   | 部署後觀察 agent 回合；若出現立即比對 11.7                                         |
| 7   | #202213 壓縮封存讀取（11.8 仍未修）                                                     | 低   | 延續性問題、非回歸；線上 1 個超預算封存 → 非致命、無資料損毀                       |
| 8   | `config-baseline.sha256` 手改產生錯誤 digest                                            | 低   | 一律用 `pnpm config:docs:gen` 重新產生，不手改                                     |
| 9   | 我們的 plugin-sdk 新增 export（4 個符號）可能撞上游 API 基線測試                        | 低   | 與 11.6 / 11.7 相同狀況（線上已驗證運作正常）；我們分支無上游 CI                   |
| 10  | 誤在本機跑重型 CI 導致 macOS 凍結                                                       | 低   | 只跑 §2.6 的輕量檢查；編譯/測試全交 GitHub Actions                                 |
| 11  | 升級期間誤開 CLI embedding 指令 → 雙行程撞 Gemini 配額                                  | 低   | §2.10 禁止清單；升級期間不執行任何 `openclaw memory *`                             |

---

## 簽核

- [x] Phase 1 分析完成（含隔離 worktree 乾跑），**零未解衝突**
- [ ] 使用者 Go-Sign（執行 Phase 2，含部署 + 驗證）
- [ ] Phase 2 完成（build + deploy + 驗證）
- [ ] Phase 3 收尾完成
