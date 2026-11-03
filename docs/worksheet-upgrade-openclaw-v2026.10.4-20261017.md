# Upgrade Worksheet: openclaw → v2026.10.4

**Date:** 2026-10-17
**Current branch:** `my-config-v2026.10.3`（HEAD `533997a21b5`）
**Target tag:** `v2026.10.4`（官方 SHA `383c124cc32ffee3f8e56f549b88da94d269a4af`）
**New branch:** `my-config-v2026.10.4`
**Release:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.4

> [!IMPORTANT]
>
> 1. **本地 `v2026.10.1/2/3` 都是自訂 tag**（含我們的 patch）。官方 baseline 已 fetch：
>    - `refs/tags/upstream-v2026.10.3`（官方 10.3，SHA `59cb44796b0f`）
>    - `refs/tags/upstream-v2026.10.4`（官方 10.4，SHA `383c124cc32f`）
> 2. **不可用本地 `v2026.10.3` 當 diff base**（內含自訂 Dockerfile 層，會誤判衝突）。
>    新分支必須從 `upstream-v2026.10.4` 開。
> 3. **本次使用分支觸發模型**（承襲 10.3 worksheet 決策），**不** force-push git tag。
>    Build 直接讀 `my-config-v2026.10.4`，`tag=` 僅命名 image。
> 4. 禁止在 Mac 跑 `pnpm check:changed` / `tsgo` / `vitest` / `docker build`，一律交給 GitHub Actions。

---

## Phase 1: 分析結果

### 1.1 官方 10.3 → 10.4 差異

| 項目                                                  | 10.3                | 10.4                            | 備註                                 |
| ----------------------------------------------------- | ------------------- | ------------------------------- | ------------------------------------ |
| `package.json` version                                | 2026.10.3           | 2026.10.4                       |                                      |
| `openclaw.schemaVersions`                             | state 20 / agent 24 | **未變（state 20 / agent 24）** | ✅ 無新 DB migration                 |
| Node / base image                                     | node:24-bookworm    | 不變                            |                                      |
| 規模（不含 `.github/workflows`）                      | —                   | **425 files / 9617+/2048-**     | stability patch，bugfix 為主         |
| 規模（含 workflows）                                  | —                   | 431 files / 9708+/2097-         |                                      |
| **Dockerfile（官方）**                                | —                   | 0 行變更                        | ✅ 自訂層插入點未動                  |
| `extensions/google/embedding-provider.ts`             | —                   | 0 行變更                        | ✅ 自訂 rate pacing 直接 cherry-pick |
| `extensions/memory-core/.../manager-embedding-ops.ts` | —                   | 0 行變更                        | ✅ 自訂 1 行 patch 直接 cherry-pick  |
| `pnpm-lock.yaml`                                      | —                   | 無變動                          |                                      |
| `apps/macos/...`（Swift）                             | —                   | 多項變更                        | 🟢 與 K3s Docker 部署無關            |

### 1.2 官方 Release Notes 審查

**v2026.10.4 Highlights**：

- **The Gateway keeps running after the computer sleeps or the system clock jumps**, instead of restarting itself because its ownership heartbeat looked stale. (#170790)
- **Gateway shutdown and restart no longer hang** on a stalled transcript worker or in-flight session lifecycle events. (#170493, #170555)
- **Tlon group DMs no longer treat other participants as the owner**, closing an owner-impersonation path. (#165801)
- **Headless browser pages keep responding to clicks** while a site waits for a passkey. (#170857)
- **Manual `/compact` settles the active run** before compacting instead of aborting it and dropping the pending request. (#166163)

**Changes**：**「Stability patch for 2026.10.3 with no new features or configuration changes.」**（官方明確標示）

**Fixes 完整分類（與我們部署相關者 ⭐）**：

| 類別                | 重點                                                                                        | 我們是否受影響                                                      |
| ------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| Gateway ⭐          | ownership heartbeat、transcript-worker shutdown、session lifecycle publication、worker heap | 我們重啟時不再 hang；Linux system clock 跳動不再誤觸 ownership 重啟 |
| Updates / Doctor ⭐ | agent DB snapshot 標記、success summary 結構、Linux systemd user manager 清理               | 我們自己跑 `openclaw update` 時更順；Linux runtime dirs 清理更穩    |
| OpenAI provider     | reasoning models on api.openai.com Completions routes 400 → 修復                            | 若使用 OpenAI reasoning 受益                                        |
| MCP ⭐              | OAuth loopback redirect URI 無 port                                                         | 我們有用 MCP，OAuth 流程更穩                                        |
| Tailscale ⭐        | 啟動中斷會停 serve process、local access 在 tailnet 拒絕時仍可用、Doctor 檢查啟動前置       | 若有啟用 Tailscale Serve 直接受益                                   |
| macOS               | app recovery 保留較新 Gateway、LaunchAgent bootstrap                                        | 🟢 與 K3s Docker 部署無關                                           |
| Control UI ⭐       | delayed heartbeats 不再強制 reconnect、`/compact` settle active run                         | 我們日常用 control UI 操作 Gateway                                  |
| Telegram ⭐         | polling workers resolve in both source and package builds                                   | 我們的 Telegram bot 受益                                            |
| Discord ⭐          | agent consults keep working after voice changes                                             | 若有 Discord bot 受益                                               |
| Feishu              | config hot-reload 不再 orphan 對話綁定                                                      | 若有 Feishu 受益                                                    |
| IRC                 | 長非 ASCII 回覆不再丟失                                                                     | 若用 IRC 受益                                                       |
| Sessions            | POSIX path aliases（`/tmp` vs `/private/tmp`）不再重啟 channel                              | macOS 環境受益，K3s Linux 不直接受影響                              |
| Browser             | passkey 等待期間可點擊                                                                      | 若用 browser-headless 受益                                          |
| Tlon                | group DM 不再把作者當 owner                                                                 | 若用 Tlon 受益                                                      |
| Release / CI        | npm publish pagination、Linux hosted runner credentials、ratchet large baseline             | 🟢 與我們 Docker build 無關                                         |

**Breaking Changes / Deprecations / Dependency Bumps：皆無**。

**Schema migration：無**（`schemaVersions` 雙版本都不變）。**對我們的 K3s 部署，零手動 migration、零 plugin 手動介入、零回滾風險**。

### 1.3 自訂 patch 清單（`my-config-v2026.10.3` 內，與官方 10.4 比對）

| Commit        | 檔案                                                                                                                  | 內容                                                                                                  | 10.4 衝突風險                                                                                         |
| ------------- | --------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `cd47e1efda1` | `.github/workflows/*`（多檔）                                                                                         | 刪除官方 111 個 CI workflows、覆蓋 `docker-release.yml` 為 191 行 Matrix 版                           | 🟢 從 10.4 base 重新套用（先 purge → 再覆蓋）                                                         |
| `64ce0d05c9e` | `Dockerfile`（+46）、`extensions/google/embedding-provider.ts`、`extensions/memory-core/.../manager-embedding-ops.ts` | 自訂層（locale / rsync / faster-whisper / edge-tts / ffmpeg / openssh-server）+ embedding rate pacing | 🟢 **零衝突**：Dockerfile 0 行變更、embedding-provider.ts 0 行變更、manager-embedding-ops.ts 0 行變更 |
| `884f17a1fe1` | `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`                                       | 自訂資產                                                                                              | 🟢 純新檔，0 行衝突                                                                                   |

**結論：3 個 functional 自訂 commit 預期全部可線性 cherry-pick。**

### 1.4 衝突交叉比對

```bash
comm -12 <(git diff --name-only upstream-v2026.10.3..my-config-v2026.10.3 | grep -v '^\.github/workflows/' | sort -u) \
         <(git diff --name-only upstream-v2026.10.3 upstream-v2026.10.4 | sort -u)
# → (空集合)
```

**非 `.github/workflows/` 的 custom commit 與 upstream 10.3→10.4 改動的檔案交集為空。**

`.github/workflows/` 的交集（`ci.yml` 等 6 檔）按 SOP 全部 purge 重建，不計為衝突。

### 1.5 風險評估：低 ✅

| 風險類型    | 等級  | 原因                                                                     |
| ----------- | ----- | ------------------------------------------------------------------------ |
| Schema 中斷 | 🟢 無 | state 20 / agent 24 皆未變，無 DB migration                              |
| 自訂 patch  | 🟢 無 | 所有 custom file 在 10.3 → 10.4 之間 0 行變更                            |
| 行為相容性  | 🟢 無 | 「Stability patch with no new features or configuration changes」        |
| Plugin      | 🟢 無 | 我們隨容器升級的核心 plugin，自動合規                                    |
| Channel     | 🟢 低 | Telegram / Discord / Tailscale / MCP / Browser 全是 bugfix，受惠而非受損 |
| 部署中斷    | 🟢 低 | Pod restart 期間能力降低；過往 3 次升級都在 ~30s 內恢復                  |

---

## Phase 2: 執行步驟

### 2.0 前置（已完成 ✅）

- [x] 確認 `git status -sb` 乾淨（僅未追蹤的本 worksheet）
- [x] 確認 `my-config-v2026.10.3` 與 origin 同步
  ```bash
  git fetch origin my-config-v2026.10.3
  ```
  local HEAD = `origin/my-config-v2026.10.3` = `533997a21b5dd117`
- [x] 確認 baseline tag 已 fetch
  ```bash
  git fetch upstream refs/tags/v2026.10.4:refs/tags/upstream-v2026.10.4 --no-tags
  git rev-parse upstream-v2026.10.4^{commit}
  # 383c124cc32ffee3f8e56f549b88da94d269a4af ✅ 與官方 release SHA 完全一致
  ```
- [x] 確認 K3s 目前 deployment 為 `2026.10.3`，pod 穩定
  ```
  openclaw-gateway-6655df6486-zsvbk   1/1   Running   0     3d
  ghcr.io/kuniakil/openclaw:2026.10.3
  ```
- [x] 既有 backup 盤點：`/root/backup-openclaw-*` → **無任何殘留**（10.3 收尾時已回收 17G）

### 2.1 建立新分支（從 upstream 10.4 基線）— 已完成 ✅

```bash
git checkout -b my-config-v2026.10.4 upstream-v2026.10.4
```

- [x] 新分支 HEAD = `383c124cc32f`（官方 10.4 基線）
- [x] `package.json` version = `2026.10.4`

### 2.2 Purge 官方 workflows 並覆蓋 Matrix `docker-release.yml` — 已完成 ✅

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.10.3 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [x] 官方 **111** 個 workflows → 僅剩 `docker-release.yml`
- [x] 覆蓋後為 **191 行** Matrix 版
- [x] 確認 `on:` 只有 `workflow_dispatch`，dispatch input 名稱 = **`tag`**（非 `tag_name`）
- [x] commit `dc57728a96918817`（110 files changed, +191 / −64,893）

### 2.3 Cherry-pick 自訂 commits（保留線性歷史）— 已完成 ✅

```bash
git cherry-pick -x 64ce0d05c9e   # 自訂 Dockerfile + embedding rate pacing
git cherry-pick -x 884f17a1fe1   # 自訂 assets/whisper + entrypoint-ssh.sh + TODO
```

- [x] `64ce0d05c9e` → `bdbc9be309a`：**零衝突**（3 files, +125 / −62）
- [x] `884f17a1fe1` → `d094c9ee84e`：**零衝突**（3 files, +111；whisper 0755 / entrypoint-ssh.sh 0755 / TODO 0644）
- [x] 另帶過 10.3 分支上剩餘 **11 個純 docs commits**（`d8d9185dd39` … `533997a21b5`），
      全部只動 `docs/worksheet-upgrade-openclaw-*.md`，保留 10.1/10.2/10.3 升級歷史
- [x] 最終 commit 歷史（14 個，**0 個 merge commit**）：
  ```
  358a3ed1604 docs: record full backup cleanup and lifecycle policy
  82d120615b7 docs: record backup cleanup after verification (no schema migration in 10.2->10.3)
  12b5d72ed9b docs: record branch-dispatch release model decision for future upgrades
  ef218b3e685 docs: complete v2026.10.3 Phase 3 verification with K3s deployment results
  112309f1d9b docs: record v2026.10.3 build success (run 38483327335, digest ac45487f)
  08c8bad4651 docs: record v2026.10.3 docker build trigger (run 38483327335)
  ea14b7c2dfc docs: add v2026.10.3 upgrade worksheet and mark Phase 2 preparation completed
  e1d390da085 docs: complete Phase 3 verification and update v2026.10.2 upgrade worksheet
  e677d8e0ccd docs: add v2026.10.2 upgrade worksheet and mark Phase 2 preparation completed
  b25e50c7a89 docs: mark Phase 3 verification as completed with K3s deployment results
  2505ec21f57 docs: add v2026.10.1 upgrade worksheet
  d094c9ee84e fix(docker): restore assets/whisper and docker/entrypoint-ssh.sh for v2026.9.8
  bdbc9be309a chore: upgrade to v2026.9.7; restore custom Dockerfile layer, scripts, rate pacing, and TODOs
  dc57728a969 chore: purge official CI workflows; use optimized matrix docker-release.yml
  ```

### 2.4 輕量本地驗證（無重型 CI）— 全部通過 ✅

```bash
# 1. Dockerfile 自訂層驗證
git diff upstream-v2026.10.4 HEAD --stat -- Dockerfile
grep -n '^# Custom:' Dockerfile
```

- [x] `Dockerfile` = **+46 行 / 0 行刪除**（純附加 patch）
- [x] 4 個 `# Custom:` 段落位置完全未變：
  - line 437 `# Custom: Generate UTF-8 locales and install rsync`
  - line 456 `# Custom: Install faster-whisper, edge-tts, and ffmpeg for audio TTS/STT pipelines`
  - line 472 `# Custom: Audio STT CLI wrapper for fast-whisper`
  - line 476 `# Custom: SSH server support for Zeabur deployment`

```bash
# 2. 自訂資產 + entrypoint
ls -la assets/whisper docker/entrypoint-ssh.sh
```

- [x] `assets/whisper` = `-rwxr-xr-x`（1611 bytes）executable
- [x] `docker/entrypoint-ssh.sh` = `-rwxr-xr-x`（938 bytes）executable

```bash
# 3. Workflow 只剩我們的 Matrix 版
ls .github/workflows
```

- [x] 僅 `docker-release.yml` 單檔

```bash
# 4. 版本號 + schema
python3 -c "import json;d=json.load(open('package.json'));print(d['version'], d['openclaw']['schemaVersions'])"
```

- [x] `2026.10.4` · `{'state': 20, 'agent': 24}`

```bash
# 5. 線性歷史
git log --merges upstream-v2026.10.4..HEAD
```

- [x] **0** 個 merge commit

```bash
# 6. 完整 diff vs upstream 10.4（排除 workflows）
git diff upstream-v2026.10.4 HEAD --stat -- ':!.github'
```

- [x] 僅預期資產（9 files, +1056 / −62）：
  ```
  Dockerfile                                                  |  46 +++
  TODO-docker-build-rsync-utf8.md                             |  38 ++
  assets/whisper                                              |  41 +++
  docker/entrypoint-ssh.sh                                    |  32 ++
  docs/worksheet-upgrade-openclaw-v2026.10.1-20261011.md      | 326 +++
  docs/worksheet-upgrade-openclaw-v2026.10.2-20261012.md      | 111 +++
  docs/worksheet-upgrade-openclaw-v2026.10.3-20261014.md      | 383 +++
  extensions/google/embedding-provider.ts                     | 139 ++--
  extensions/memory-core/src/memory/manager-embedding-ops.ts   |   2 +-
  ```

> 與 10.3 升級時的 diff **逐字一致** → 自訂層在 10.4 完全相容。

### 2.5 更新本 worksheet 勾選並 commit — 已完成 ✅

```bash
git add docs/worksheet-upgrade-openclaw-v2026.10.4-20261017.md
git commit -m "docs: add v2026.10.4 upgrade worksheet and mark Phase 2 preparation completed"
```

- [x] commit `dcecf3688c0`（1 file, +404）

### 2.6 Push 分支 — 已完成 ✅

```bash
git push -u origin my-config-v2026.10.4
```

- [x] `origin/my-config-v2026.10.4` = `dcecf3688c0190f965e23e926a4099d5fbe4fafc`（與 local HEAD 一致）

### 2.7 觸發 build（分支觸發模型）— 🛑 BLOCKED

> [!IMPORTANT]
>
> **不 force-push git tag**。我們的 Matrix `docker-release.yml` 為 `workflow_dispatch` 專用，
> `--ref` 指向分支、`-f tag` 命名 image。tag 不影響 build。

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.10.4 -f tag=v2026.10.4 -f platforms=all
```

- [x] 分支已就緒，`--ref my-config-v2026.10.4` 與 `-f tag=v2026.10.4` 參數正確
- [x] 🛑 **初次 BLOCKED：`HTTP 422: Actions has been disabled for this repository.`** → 已於步驟 2.7.1 解除

#### 診斷時間線

1. **2026-10-16 23:46 UTC** — 首次發現 422
2. 使用者於 `/settings/actions` 完整 Save 所有設定 → **仍為 422**
   （設定層本來就是 `enabled: true`，**按錯地方** — 停用不由 permissions 端點管理）
3. 清除全部 Actions cache（317 筆 / 12.26 GB → 0）→ **仍為 422**，cache 假設**推翻**
4. **決定性測試**：dispatch 不存在的 workflow → **404**；dispatch 我們的 → **422**
   → 確認 repo 層級 Actions 停用，位於 repo 設定之上
5. **找到根因**：抓取 `/actions` 頁面 HTML，比中 GitHub 的橫幅字串
   > "Workflows are not currently being run on this fork **due to the scale of GitHub Actions usage**.
   > A repository maintainer can choose to re-enable these."

#### 根因：GitHub 的 fork Actions 用量自動停用

| 問題                 | 答案                                                                                                                                                                 |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 為什麼 API 查不到？  | 此停用**不由** `actions/permissions` 端點管理，API 仍回 `enabled: true`。所有 API 探測都會誤導                                                                       |
| 為什麼沒有通知信？   | GitHub **不寄信**，只有 Actions 頁面橫幅                                                                                                                             |
| 為什麼 Save 沒用？   | 停用橫幅與啟用按鈕在 **`/actions`（執行頁）**，不是 `/settings/actions`                                                                                              |
| 是 2000 分鐘限制嗎？ | **不是。** ① GitHub 官方文件：public repository 的標準 GitHub-hosted runner **免費且無限制**；2000 分鐘僅適用 private repo。② 觸發條件是 **fork 的用量規模**，非計費 |

**外部佐證**：`StartupBros-com/better-ccflare#463` 記錄完全相同的症狀與 API 探測結果，
最後由 maintainer 點 Actions 頁面橫幅按鈕恢復。我們的診斷表與該記錄逐項吻合。

#### 排除清單（皆已實測推翻）

| 假設                           | 驗證方法                                                       | 結果        |
| ------------------------------ | -------------------------------------------------------------- | ----------- |
| 分支／ref 問題                 | 改用 `ref: v2026.10.3`                                         | ❌ 仍 422   |
| workflow 定義不存在            | workflow list `active` + default branch 有 `workflow_dispatch` | ❌          |
| token 權限不足                 | scopes 齊全、admin: true                                       | ❌          |
| 帳號層級停用                   | 對照組 `kuniakil/n8n` **204 成功**                             | ❌          |
| fork 身份本身                  | 對照組 fork `kuniakil/hermes-web-ui` **204 成功**              | ❌          |
| Actions 服務故障               | githubstatus.com `operational`                                 | ❌          |
| 暫時性                         | 重試 3 次                                                      | ❌ 全 422   |
| Cache 超額（12.26 GB > 10 GB） | 清除全部 317 筆 → 0                                            | ❌ **推翻** |
| 帳號停用                       | `suspended_at: None`、無通知                                   | ❌          |
| 公開 repo 計費                 | 三 repo 皆 public，對照組正常                                  | ❌          |
| **fork 用量規模**              | **頁面橫幅直接指明**                                           | ✅ **根因** |

#### 2.7.1 解除與觸發

- [x] 使用者點擊 `/actions` 頁面橫幅的重新啟用按鈕
- [x] 重試 dispatch → **HTTP 204**

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref my-config-v2026.10.4 -f tag=v2026.10.4 -f platforms=all
```

- [x] **Run ID：`38984685525`**（14 分 18 秒）
- [x] `event: workflow_dispatch` · `headBranch: my-config-v2026.10.4` · `headSha: 330c6b60a62` ✅（**我們的** commit，非官方 `383c124cc32f`）
- [x] 4 個 job 全綠：`prepare` / `build-and-push (amd64)` / `build-and-push (arm64)` / `merge`
- [x] **保留 GHA buildx cache**（使用者決定：下次被停用再手動點掉）

#### 備援路線（已不需要，保留記錄）

| 路線                | 可行性           | 說明                                                       |
| ------------------- | ---------------- | ---------------------------------------------------------- |
| N100 主機本地 build | ❌ 不可行        | 無 docker / buildx / nerdctl / buildctl / podman / kaniko  |
| Mac 本機 build      | ⚠️ 違反 SOP      | OrbStack daemon 未啟動；SOP 禁止在 Mac 本機跑 docker build |
| 等待 GitHub 解除    | ⏳ 前例約 1 個月 | **不需要了**，橫幅按鈕立即恢復                             |

### 2.8 Build 結果驗證（待 blocker 解除後執行）

```bash
for t in 2026.10.4 v2026.10.4 2026.10.4-slim latest main; do
  docker buildx imagetools inspect ghcr.io/kuniakil/openclaw:$t >/dev/null 2>&1 \
    && echo "$t OK" || echo "$t MISSING"
done
```

- [x] 全部 5 個 tag 存在：`2026.10.4` ✅ `v2026.10.4` ✅ `2026.10.4-slim` ✅ `latest` ✅ `main` ✅
- [x] **Build Run**：https://github.com/kuniakil/openclaw/actions/runs/38984685525
- [x] **Multi-arch digest**：`sha256:13422f1ec6a77bc7e3838691a2ec66e62fdbcccccfafe973e40c251921523d04`
  - `linux/amd64` → `sha256:0ac39d6443cb1440a484e4bbc3ddaba33c574135ff381e629ec25cb8798a9ba9`
  - `linux/arm64` → `sha256:4aa1d5bfd53228e449793d9c64e5a68acbd76bb7ce45735fb18755b73d693c2f`

---

## Phase 3: 部署與驗證（已全數通過 ✅）

### 3.1 備份決策

- [x] `schemaVersions` 未變（state 20 / agent 24）→ **無 DB migration 風險**
- [x] 既有 backup 盤點：`/root/backup-openclaw-*` → **無殘留**
- [x] 使用者同意**跳過新備份**（同10.3 決策；回滾只需 `kubectl set image`，資料不需還原）

### 3.2 K3s 部署

- [x] `~/kubernetes/openclaw/overlays/n100/kustomization.yaml`：`2026.10.3` → `2026.10.4`（單檔單行）
- [x] `kubectl apply -k` → `deployment.apps/openclaw-gateway configured`
- [x] `kubectl rollout status` → **successfully rolled out**
- [x] 新 Pod：`openclaw-gateway-84dfdfdfcc-78cmz`，`1/1 Running`，`RESTARTS 0`
- [x] Image digest 與 build 完全一致：
      `ghcr.io/kuniakil/openclaw@sha256:13422f1ec6a77bc7e3838691a2ec66e62fdbcccccfafe973e40c251921523d04`
- [x] **17 個 plugins 全部載入**（anthropic, canvas, cua-computer, device-pair, file-transfer,
      geolocation, github, google, linux-node, memory-core, microsoft, ollama, openai,
      talk-voice, tavily, telegram, xai）
- [x] Gateway `ready`（32.3s），Telegram polling 啟動
- [x] **無 10.3 那次的冷啟動競態警告**（無 `cron maintenance failed` / `chat metadata refresh failed`）

### 3.3 運行版本

- [x] 容器內 `/app/package.json` → `2026.10.4`
- [x] `openclaw --version` → `OpenClaw 2026.10.4`
- [x] `/health` → **200**（容器內 18789 與 service 皆通過）

### 3.4 自訂功能存活 — 全數通過 ✅

- [x] `locale -a`：`C.utf8` / **`en_US.utf8`** / **`zh_TW.utf8`**
- [x] `whisper` → `/usr/local/bin/whisper`
- [x] `edge-tts` → `/usr/local/bin/edge-tts`
- [x] `ffmpeg` → `/usr/bin/ffmpeg`
- [x] `rsync` → `/usr/bin/rsync`
- [x] `sshd` → `/usr/sbin/sshd`
- [x] `/app/docker/entrypoint-ssh.sh` → OK executable
- [x] `faster_whisper.__version__` = **1.2.1**
- [x] `edge_tts.__version__` = **7.3.1**（10.3 為 7.2.8 → 上游 10.4 自行升級，非我們的改動）
- [x] 環境變數：`LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONPATH=/usr/local/lib/faster-whisper`

### 3.5 端到端真實訊息往返 — 通過 ✅

```
08:29:22 [telegram] Inbound message telegram:830338761 -> @N100_openclaw_mike_bot (direct, 6 chars)
08:29:25 [telegram] outbound send ok chatId=830338761 messageId=2630 operation=sendMessage
08:30:10 [telegram] Inbound message telegram:830338761 -> @N100_openclaw_mike_bot (direct, 10 chars)
08:30:12 [agent/embedded] code-mode: cataloged 110 tools behind exec/wait
08:30:23 [model-fetch] response provider=minimax api=anthropic-messages model=MiniMax-M3 status=200 elapsedMs=6617
08:30:26 [auto-reply/agent-turn-timing] milestone=tool_execution_started totalMs=14842
08:30:42 [model-fetch] response ... status=200 elapsedMs=5470
08:30:46 [model-fetch] response ... status=200 elapsedMs=3194
08:31:09 [model-fetch] response ... status=200 elapsedMs=7772
```

收訊息 → 工具執行 → 多輪模型呼叫（全部 HTTP 200）→ 回覆送出，**全鏈路正常**。

> 註：啟動日誌顯示 `agent model: minimax/MiniMax-M2.5`，但實際對話走 `MiniMax-M3`。
> 原因是 `/home/node/.openclaw/openclaw.json` 的 `.agents.entries.main.model` 為M2.5，
> 而該 session 有user model override（日誌顯示 `configured fallbacks disabled by user model override`）。
> **這是升級前就有的持久設定，非 10.4 造成。**

### 3.6 記憶體壓力警告 — 已調查，判定無害 ⚠️→✅

E2E 期間出現一次：

```
08:31:04 [diagnostics/memory] memory pressure: level=warning reason=rss_threshold
  rss=2.1 GiB threshold=2.09 GiB thresholdRatio=100.5% workerCount=20
```

調查結論 — **非 10.4 回歸**：

| 檢查                                | 結果                                                                     |
| ----------------------------------- | ------------------------------------------------------------------------ |
| 記憶體壓力診斷碼 10.3 → 10.4        | **零變更**（門檻邏輯完全相同）                                           |
| `worker-heap-flag.mjs`（10.4 新增） | 我們 `NODE_OPTIONS` 為空、cmdline 無 heap flag → **該程式碼不會觸發**    |
| Pod 資源限制                        | **無設定**（`limits=` 空、`memory.max = max`）→ 門檻是內部建議值，非強制 |
| 警告是否重複                        | **未重複**（累計仍為 1 次）                                              |
| 當前 cgroup 記憶體                  | 2498 → 2414 → 2414 MiB，**穩定無增長**                                   |
| 節點可用記憶體                      | 31 GB 總 / 15.5 GB available                                             |

判定：E2E 測試本身（4 輪 agent turn、20 個 worker、多次模型呼叫）造成的瞬間 RSS 尖峰，
門檻未設定在任何強制機制上，且未持續。**無需處理。**

### 3.7 收尾

- [x] `~/kubernetes` commit `eb2d504` + push 到 `main`
- [x] 本 worksheet Phase 3 記錄完成

### 3.6 回滾備案

```bash
kubectl -n openclaw set image deployment/openclaw-gateway \
  gateway=ghcr.io/kuniakil/openclaw:2026.10.3
```

資料**不需還原**（`schemaVersions` 未變，舊 image 可直接用現有 DB）。

## 🔖 關鍵參考

- **官方 Release Notes:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.4
- **官方 Changelog:** https://raw.githubusercontent.com/openclaw/openclaw/v2026.10.4/CHANGELOG/2026.10.4.md
- **官方 release SHA:** `383c124cc32ffee3f8e56f549b88da94d269a4af`
- **Image:** `ghcr.io/kuniakil/openclaw:2026.10.4`
- **Image digest:** `sha256:13422f1ec6a77bc7e3838691a2ec66e62fdbcccccfafe973e40c251921523d04`
- **Build Run:** https://github.com/kuniakil/openclaw/actions/runs/38984685525（success）
- **K3s 部署:** `~/kubernetes/openclaw/overlays/n100/`
- **SOP 來源：** `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`、`~/.pi/agent/skills/docker-image-rebuild/SKILL.md`
- **上一版 worksheet:** `docs/worksheet-upgrade-openclaw-v2026.10.3-20261014.md`

---

## 📌 本次升級特色

1. **這是迄今最乾淨的一次升級**：
   - `schemaVersions` 不變（無 DB 風險）
   - 自訂 patch 0 行衝突
   - 官方明示「Stability patch with no new features or configuration changes」
   - 全程 git diff intersection（除 workflows）為空

2. **首個完全採用分支觸發模型的升級**：
   - 從 10.3 沿襲下來的決策，本次不再 force-push `v2026.10.4` git tag
   - 預期 build 出 image tag = `2026.10.4`、git tag 維持不動或另立輕量紀錄
   - 驗證：`gh run view` 顯示 `headBranch=my-config-v2026.10.4`、`headSha=<我們的 commit>`

3. **可選的 backup 簡化**：
   - 與 10.3 schema 完全相同，理論上**不需要**新備份
   - 但仍徵詢使用者確認（符合 backup 生命週期政策的「自動提示、主動確認」原則）
