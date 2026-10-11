# Upgrade Worksheet: openclaw → v2026.10.1

**Date:** 2026-10-11
**Current branch:** `my-config-v2026.9.9`（HEAD `381cdbb4c77`）
**Current tag:** `v2026.9.9`（本地/origin 已 force 指向自訂 commit `7ead15321d2`；官方 9.9 SHA `bcfc88812a3` 不可直接 `rev-parse`，因 upstream 已 force-push 樹）
**Target tag:** `v2026.10.1`（官方 SHA `e178c39e9aae3fa440735217f9aef9574f286677`，已 `git fetch upstream v2026.10.1` 並 `git tag v2026.10.1 FETCH_HEAD` 驗證 = 一致 ✅）
**New branch:** `my-config-v2026.10.1`
**Why this upgrade matters:** 官方標記 Late Breaking（3,055 commits / 396 PRs / _2746 commits to main since this release_），是我們目前最大的升級。包含 state schema 19→20 的 Doctor migration。

> [!IMPORTANT]
>
> 1. **本地 `v2026.9.9` 是自訂 tag**；所有「官方 9.9→10.1 差異」以 `git diff bcfc88812a3..v2026.10.1` 為基線（但 `bcfc88812a3` 已不在 upstream main 上，仍能比對，是歷史 preserve）。
> 2. **`v2026.9.9^` 是上一個自訂 commit**，不要用它做 diff base（會把自家 patch 誤顯示為官方變更）。
> 3. **AGENTS.md「Updates always work」**：本地一鍵 image pull 不行；要走 K3s Deployment recreate + PVC 備份 + DB schema migration。

---

## 📋 Phase 1: Pre-Upgrade Analysis（已完成）

### 1.1 版本差異概覽（官方 → v2026.10.1）

| 項目                                       | 9.9              | 10.1                                                 | 備註                                                                                                               |
| ------------------------------------------ | ---------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| 官方 commits（自 9.9 tag 起）              | —                | **3,055**                                            | 遠大於 9.8→9.9 的 185 commits                                                                                      |
| PRs in range                               | —                | **396** + 5 shipped baseline exclusions (9.9 hotfix) |                                                                                                                    |
| `package.json version`                     | 2026.9.9         | **2026.10.1**                                        |                                                                                                                    |
| `openclaw.schemaVersions.state`            | 19               | **20**                                               | ⚠️ Doctor 將跑 migration；先備份 DB                                                                                |
| `openclaw.schemaVersions.agent`            | 24               | **24**                                               | 不變                                                                                                               |
| `@modelcontextprotocol/sdk`                | 1.31.0           | 1.31.0                                               | 不變                                                                                                               |
| Node engine / base image                   | node:24-bookworm | node:24-bookworm                                     | 不變                                                                                                               |
| **Dockerfile**                             | —                | +5 行                                                | 加 `copy-bootstrap-scripts.mjs` 與 `.runtime-bootstrap/scripts` / `guard-inventory-utils.mjs` COPY（位置 222/294） |
| **pnpm-lock.yaml**                         | —                | 多處                                                 | 跟隨 package.json，依官方更新                                                                                      |
| **`.github/workflows/docker-release.yml`** | 官方會更新       | 依 SOP 一律丟棄，用我們 Matrix 版                    |                                                                                                                    |

### 1.2 官方 Release Notes 審查

Release: https://github.com/openclaw/openclaw/releases/tag/v2026.10.1

#### 重點（與我們相關度高者）

- **Sessions / memory（⭐）**
  - Embedding cache 改為 bounded batches + oversized-row reporting（避 OOM）。
  - 完成 sessions 跨 registry 變更保留使用。
  - **Memory wiki status 不再 recompile 未變動的 vault**（減少工作）。
  - Auto-compaction small context window 後可恢復。
  - 移植既有 agents 至 local Claws。
- **Replies / media（⭐）**
  - 恢復 local video inline playback（影響 vs 我們）。
  - Speech-only 推論模式修正。
- **Updates / Doctor（⭐⭐ K3s 部署直接受影響）**
  - **「Updates always work」** 新增數項：rollback skip maintenance drain if Gateway stopped、update repair 不再亂動 live current handoff、triage 尊重 activation recovery pending。
  - **Recovered archives without leaving Gateways stopped** — 對我們 K3s 升級更穩。
  - **Imported retained session receipts and legacy entry state before SQLite migration** — 對 schema 19→20 重要。
  - **Completed October beta updater compatibility** — 我們目前在 beta 鏈之外，建議確認。
  - Doctor 行為改進：serving-verdict recovery、read-only managed config 仍可修、重複 probe 移除、successful cleanup 報進度不毀 JSON。
- **Cloud workers / Crabbox**：real failure surfaced、Linux lease enforced、worker-bundle download 與 bootstrap 重疊 — 我們 K3s 跑單機本地，影響有限。
- **Plugins / Codex / MCP**：plugin Doctor module 不再每次 config read 被 discard、保留 Bun package-import capture、減少 prerelease metadata requests、Codex 不再丟最後 token、Gemma 4 tool-call text 補回、Ollama Tool Search 修正。
- **Storage / memory**：remove large-store SQL-variable 失敗、release discarded transcript buffers、reduce transcript-worker memory。
- **Update recovery**：completed recovery 不再 block 後續 update、archival failures 變 warning、保留 service ownership 與 unfinished rollback checks。
- **Storage safety**：`updateAdmissionProtocol: 1` 仍為 1（在 10.1 package.json 中可見 — 沒有 bump）。
- **Worker deadlines** (`#167740`)：expired tasks 不再於 SQLite 留 queued callbacks。

#### Upcoming deprecations（影響我們 decisions）

- `session-manager-sync-persistence` warning 從 2026-10-01 起 — 我們 plugin 端需留意（如果有自寫 plugin）。
- `extension-session-sync-persistence` 同上。
- `provider-replay-sync-persistence` / `memory-session-sync-inventory` / `workspace-mutation-guard-callback` / `gateway-placement-sync-results` / `watched-sessions-sync-harness-context` 均已進入 warning phase — **bundled plugin readers 尚未搬遷完**前 aliases 仍可用。
- 多數 plugin-SDK compat aliases 已到 removal target 但 published plugin sweep 尚未完成 → 對我們影響：local Claws migration 不要假設 plugins 已搬完。

#### ⚠️ Known Issues / Caveats

- **schemaVersions state 19→20**：必須在升級前停舊 Pod 並備份 DB（PVC `openclaw-home` 上的 `state.db`）。Doctor 會跑 migration；migration 設計上是可恢復的，但預防勝於治療。
- Telegram/Discord 上游有修：**「delivered later messages without deferred-ingress stalls」、「Telegram photo albums 保持順序」、「Discord long model IDs selectable」** — 我們部署後手動冒煙測試。
- Claude Haiku 5.5 新支援 — 視需要更新 `openclaw.json` 的 model catalog。
- Windows / Android / Crabbox 變更與我們 K3s Linux Docker 無關。

### 1.3 自訂 Patch 清單（需移植）

| Commit SHA                                  | 內容                                                                                                               | 預期衝突          |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ----------------- |
| `085e6c9eadb`                               | v2026.9.7 升級：Dockerfile 自訂層 + Google embedding rate pacing mutex + memory-core gemini providerId concurrency | 🟡 中（見下）     |
| `868ee5c16ed`                               | v2026.9.8 補 `assets/whisper` + `docker/entrypoint-ssh.sh` + `TODO-docker-build-rsync-utf8.md`                     | 🟢 無（純新增檔） |
| `17f7aae4891`                               | purge 官方 workflows + 覆蓋精簡 Matrix `docker-release.yml`（重新套用，不 cherry-pick）                            | 🟢 無             |
| `7ead15321d2`、`be83ec3f6bc`、`381cdbb4c77` | 9.9 worksheet / CI run / Phase 3 docs — 本檔取代                                                                   | —                 |

#### 自訂 patch 衝突預估

| 檔案                                                         | 自訂改動                                                                        | 官方 9.9→10.1 改動                                                                                                                        | 物理重疊    | 處理                                                                                                                                                        |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Dockerfile`                                                 | 4 個 `# Custom:` 區塊（line 429-480ish）位於 `ENV NODE_ENV=production` **之前** | 新增 `copy-bootstrap-scripts.mjs`（line 222）與兩行 runtime COPY（line 294）                                                              | 🟢 不重疊   | 整段 `git cherry-pick` 套用即可                                                                                                                             |
| `extensions/google/embedding-provider.ts`                    | 自訂 mutex + `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`（line 262+）             | 重構型別簽名（line 1-100）                                                                                                                | 🟢 不重疊   | `git cherry-pick` 套用即可                                                                                                                                  |
| `extensions/memory-core/src/memory/manager-embedding-ops.ts` | 3 行改 `resolveMemoryIndexConcurrency` line 178（加入 `gemini` 條件）           | 🔴 **整個函式重構為 class method `getIndexConcurrency()`，line 592 等價位置 `provider?.id === "ollama" ? 1 : ...`；原 line 178 已不存在** | 🔴 **重寫** | `git cherry-pick` 會 conflict，**手動 reapply**：line 592 改為 `provider?.id === "ollama" \|\| provider?.id === "gemini" ? 1 : EMBEDDING_INDEX_CONCURRENCY` |
| `assets/whisper`                                             | 自訂檔                                                                          | 官方 v2026.10.1 **無此檔**                                                                                                                | 🟢          | 直接帶過去                                                                                                                                                  |
| `docker/entrypoint-ssh.sh`                                   | 自訂檔                                                                          | 官方 v2026.10.1 **無此檔**                                                                                                                | 🟢          | 直接帶過去                                                                                                                                                  |
| `TODO-docker-build-rsync-utf8.md`                            | 自訂 docs                                                                       | 官方無                                                                                                                                    | 🟢          | 直接帶過去                                                                                                                                                  |
| `.github/workflows/*`                                        | 僅留 `docker-release.yml`                                                       | 官方大量 workflows                                                                                                                        | 🟢          | 重新 purge + 覆蓋                                                                                                                                           |

### 1.4 衝突風險評估

| 風險                                                      | 等級  | 說明 / 對策                                                                                   |
| --------------------------------------------------------- | ----- | --------------------------------------------------------------------------------------------- |
| cherry-pick conflict on `manager-embedding-ops.ts`        | 🟡 中 | 已知 1 處 conflict，使用 `--3way` + `git rerere` 後手動 reapplied 邏輯到 line 592             |
| Dockerfile 自訂層漂移                                     | 🟢 低 | 套用即可，無 offset                                                                           |
| MCP SDK 沒 bump（仍 1.31.0）                              | 🟢 低 |                                                                                               |
| schemaVersions state 19→20 + Doctor migration             | 🟡 中 | **部署前備份 PVC；停舊 Pod 再起新 Pod**（K3s `strategy: Recreate`）                           |
| Plugin `agent-harness` / `Channel` API alias 移除 pending | 🟡 低 | 我們當前沒有自寫 plugin，但官方 bundled 之 `terminal/clawhub` 可能吃 alias — 觀察 Gateway log |
| Telegram / Discord 行為修                                 | 🟡 低 | 部署後手動冒煙                                                                                |
| macOS app 同步升級                                        | 🟢 —  | 與 Gateway 解耦，後續單獨更新                                                                 |
| `updateAdmissionProtocol` 仍 1                            | 🟢 —  |                                                                                               |
| Beta upstream 新 release（`v2026.10.1-beta.1/.2` 仍存在） | 🟢 —  | 我們直接追 stable，不走 beta                                                                  |
| Update / Doctor major refactor 風險                       | 🟡 中 | 若升級失敗可 `docker image pull ghcr.io/kuniakil/openclaw:2026.9.9` 退回；**配合 PVC 還原**   |

---

## 🚀 Phase 2: 執行步驟（⛔ 等待使用者 Go）

### Step 1: 確認官方 SHA 對齊

- [x] `git rev-parse v2026.10.1^{commit}` = `e178c39e9aae3fa440735217f9aef9574f286677`（= GitHub release page 標示）
- [x] `git cat-file -p v2026.10.1 | head -3` 顯示 tagger RomneyDa（GPG verified）
- [ ] 備份上游 9.9 SHA 標籤（防止本地覆蓋後失憶）：`git tag upstream-v2026.9.9 bcfc88812a3`（若已存在則跳過）

### Step 2: 建立新分支

```bash
git checkout v2026.10.1
git checkout -b my-config-v2026.10.1
git tag upstream-v2026.10.1 v2026.10.1
```

- [ ] HEAD = `e178c39e9aae3fa440735217f9aef9574f286677`
- [ ] 分支名 `my-config-v2026.10.1`

### Step 3: 清除官方 CI Workflows，覆蓋 docker-release.yml

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.9.9 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [ ] `.github/workflows/` 只剩 `docker-release.yml`
- [ ] `git diff my-config-v2026.9.9 -- .github/workflows` 為空

### Step 4: 移植 Dockerfile 自訂層 + scripts + TODO docs

**策略**：以 `085e6c9eadb` commit 為來源，先試 cherry-pick Dockerfile 部分；如果整個 cherry-pick 因為 `manager-embedding-ops.ts` 衝突卡住，改採分檔 `git apply --3way` 分段套用。

```bash
# 方法 A：先試整包 cherry-pick（預期 manager-embedding-ops.ts 衝突）
git cherry-pick 085e6c9eadb 868ee5c16ed 2>&1
# 若 conflict：見 Step 4b
```

#### Step 4a：Dockerfile + embedding-provider.ts 套用成功

繼續 Step 5。

#### Step 4b（若 4a conflict）— 手動處理 manager-embedding-ops.ts

```bash
# cherry-pick 停在 manager-embedding-ops.ts conflict
git checkout --theirs extensions/memory-core/src/memory/manager-embedding-ops.ts  # 取 10.1 版本
# 然後手動編輯 line 592，變成：
#   return provider?.id === "ollama" || provider?.id === "gemini"
#     ? 1
#     : EMBEDDING_INDEX_CONCURRENCY;
git add extensions/memory-core/src/memory/manager-embedding-ops.ts
git cherry-pick --continue
```

- [ ] Dockerfile 4 個 `# Custom:` 區塊存在於 `ENV NODE_ENV=production` 之前
- [ ] `assets/whisper` 存在於 repo root
- [ ] `docker/entrypoint-ssh.sh` 存在
- [ ] `extensions/google/embedding-provider.ts` 內含 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` 且 mutex queue 保留
- [ ] `extensions/memory-core/src/memory/manager-embedding-ops.ts` line 592（after pick）= gemini 條件保留

### Step 5: 補回 v2026.9.8 特定 patch（assets/whisper + docker/entrypoint-ssh.sh + TODO）

如 cherry-pick 已包含 `868ee5c16ed` 則跳過；否則：

```bash
git cherry-pick 868ee5c16ed
```

- [ ] `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md` 存在

### Step 6: 本地輕量驗證（⛔ 禁止 docker build / tsgo / vitest）

```bash
git status
git diff --check e178c39..HEAD
grep -nE "zh_TW|faster-whisper|openssh|tini|edge-tts|MIN_GEMINI_EMBEDDING_INTERVAL_MS|gemini" \
  Dockerfile extensions/google/embedding-provider.ts extensions/memory-core/src/memory/manager-embedding-ops.ts
git diff --stat e178c39..HEAD -- . ':!.github'
```

- [ ] 工作區乾淨
- [ ] 自訂差異僅含預期檔案（Dockerfile, TODO, assets/whisper, docker/entrypoint-ssh.sh, extensions 兩處）
- [ ] 無多餘 noise

### Step 7: 提交 worksheet 並 push 分支

```bash
git add docs/worksheet-upgrade-openclaw-v2026.10.1-20261011.md
git commit -m "docs: add v2026.10.1 upgrade worksheet"
git push origin my-config-v2026.10.1
```

- [ ] Push 成功

### Step 8: 觸發 Docker CI Build（再次確認）

```bash
git tag -f v2026.10.1
git push -f origin v2026.10.1
gh workflow run docker-release.yml --repo kuniakil/openclaw --ref my-config-v2026.10.1 -f tag=v2026.10.1 -f platforms=all
```

- [ ] CI 觸發並回報 Run ID
- [ ] 建置綠燈（amd64 & arm64）
- [ ] `ghcr.io/kuniakil/openclaw:2026.10.1` 可 pull

---

## 🛡 Step 9: K3s 部署前安全網（升級前必跑）

依 AGENTS.md「Updates always work」：

1. **備份 PVC**（`openclaw-home`，n100 上 `openclaw` namespace）：
   ```bash
   kubectl -n openclaw get pvc
   # 取得 openclaw-home 的 PV 名稱
   kubectl -n openclaw exec deploy/openclaw -- ls /home/node/.openclaw
   # 用 n100 上的 restic / rsync 備份到 NAS（具體指令見既有 SOP）
   ```
2. **快照 DB**：
   ```bash
   kubectl -n openclaw exec deploy/openclaw -- \
     sqlite3 /home/node/.openclaw/state.db ".backup /home/node/.openclaw/state.db.snapshot-9.9"
   kubectl -n openclaw cp openclaw/<pod>:/home/node/.openclaw/state.db.snapshot-9.9 /tmp/
   ```
3. **確認 Deployment strategy**：
   ```bash
   kubectl -n openclaw get deploy openclaw -o jsonpath='{.spec.strategy.type}'  # 應為 Recreate
   ```
4. **升級 image tag 至 2026.10.1**：
   ```bash
   kubectl -n openclaw set image deploy/openclaw \
     openclaw=ghcr.io/kuniakil/openclaw:2026.10.1 --record
   ```
5. **觀察**：
   - 啟動期間 Doctor 應自動跑 schema 19→20 migration → log 內見 `[doctor]` 字樣。
   - `/healthz` 應在重建後回 200。

- [ ] PVC 備份到位
- [ ] DB snapshot 留底
- [ ] Deployment strategy 為 Recreate
- [ ] image 升級完成
- [ ] Gateway Pod Ready
- [ ] `/healthz` 200

---

## ✅ Phase 3: Post-Upgrade

- [ ] Mac node app 同步更新至 2026.10.1（後續單獨操作）
- [ ] Smoke test 結果記錄至 worksheet（Pod status / healthz / memory corpus / Telegram roundtrip）
- [ ] 監控 30 分鐘無 schema migration 警告
- [ ] 清理本地暫存 tag（`upstream-v2026.10.1` 是否保留視後續需求）
- [ ] Session wrap-up 發布至 WordPress KB（`session-wrapup` skill）

---

## 📌 參考連結

- Release: https://github.com/openclaw/openclaw/releases/tag/v2026.10.1
- Compare 9.9→10.1: https://github.com/openclaw/openclaw/compare/v2026.9.9...v2026.10.1
- CHANGELOG preview: https://raw.githubusercontent.com/openclaw/openclaw/v2026.10.1/CHANGELOG/2026.10.1.md
- npm: https://www.npmjs.com/package/openclaw/v/2026.10.1
- 先前 v2026.9.9 worksheet: [`worksheet-upgrade-openclaw-v2026.9.9-20261010.md`](./worksheet-upgrade-openclaw-v2026.9.9-20261010.md)
- Fork: https://github.com/kuniakil/openclaw
