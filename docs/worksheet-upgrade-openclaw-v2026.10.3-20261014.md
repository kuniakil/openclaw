# Upgrade Worksheet: openclaw → v2026.10.3

**Date:** 2026-10-14
**Current branch:** `my-config-v2026.10.2`（HEAD `497f63d5949`，與 origin 同步，工作樹乾淨）
**Target tag:** `v2026.10.3`（官方 SHA `59cb44796b0f1f0daa0e37af8b1495abb45d9bc1`）
**New branch:** `my-config-v2026.10.3`
**Release:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.3

> [!IMPORTANT]
>
> 1. **本地 `v2026.10.1` 與 `v2026.10.2` 是自訂 tag**（含我們的 patch）。官方 baseline 已 fetch：
>    - `refs/tags/upstream-v2026.10.1`（官方 10.1，SHA `250c0e30dcb1`）
>    - `refs/tags/upstream-v2026.10.2`（官方 10.2，SHA `b8952d477f0c`）
>    - `refs/tags/upstream-v2026.10.3`（官方 10.3，SHA `59cb44796b0f`）
> 2. 不可用本地 `v2026.10.2` 當 diff base（內含自訂 Dockerfile 層，會誤判衝突）。新分支必須從 `upstream-v2026.10.3` 開。
> 3. 完成後依 SOP 以 `git tag -f v2026.10.3` 將自訂 commit 指回官方 tag。
> 4. 禁止在 Mac 跑 `pnpm check:changed` / `tsgo` / `vitest` / `docker build`，一律交給 GitHub Actions。

---

## Phase 1: 分析結果（已完成）

### 1.1 官方 10.2 → 10.3 差異

| 項目                                                  | 10.2                | 10.3                            | 備註                                         |
| ----------------------------------------------------- | ------------------- | ------------------------------- | -------------------------------------------- |
| 規模                                                  | —                   | 618 files / 79 PRs / 90 commits | patch release，僅修復 + 小改                 |
| `package.json` version                                | 2026.10.2           | 2026.10.3                       |                                              |
| `openclaw.schemaVersions`                             | state 20 / agent 24 | **未變**                        | 無新 DB migration                            |
| Node / base image                                     | node:24-bookworm    | 不變                            |                                              |
| **Dockerfile（官方）**                                | —                   | 0 行變更                        | 結構未動，自訂層插入點（line ~437）仍存在    |
| `extensions/google/embedding-provider.ts`             | —                   | **未變**                        | ✅ 自訂 rate pacing patch 可直接 cherry-pick |
| `extensions/memory-core/.../manager-embedding-ops.ts` | —                   | **未變**                        | ✅ 自訂 1 行 patch 可直接 cherry-pick        |
| `pnpm-lock.yaml`                                      | —                   | 無變動                          |                                              |
| `apps/macos/...`（Swift）                             | —                   | 多項變更                        | 🟢 與 K3s Docker 部署無關                    |

### 1.2 官方 Release Notes 審查

**v2026.10.3 重點主題：Update/Doctor repairs · Mac setup · Conversation continuation · Muse Wonder · MiniMax M3.1 Flash Preview**

- **Breaking Changes：無**（patch release，僅 bugfix + 小功能）。
- **Deprecations：無**。
- **Dependency / Runtime Bumps：無**（Node、base image、schema 皆不變；無 `updateAdmissionProtocol` 變更）。
- **無資料庫 migration**：`schemaVersions.state = 20`，與 10.2 相同。
- **與我們部署相關的變更摘要**：
  - **Update / Doctor 修復（19 項）**：blocked updates recovery、FreeBSD package recovery、leftover updater copies 清理、candidate checks with older updaters、pnpm service commands、Windows service accounts、busy state databases、recovery copies before repairs 等。**注意：官方強制「fixed updater 必須先安裝」才能享用部分修復**，我們的 Docker 容器重建 = 全新安裝，自動包含。
  - **Messaging（3 項）**：channel tools after restart、messages already being sent、steered conversations after restart。我們的 Telegram 與 Discord 部署會受惠於 #170252（restart recovery）。
  - **Memory（1 項）**：`MEMORY.md` / `memory.md` 合併時 malformed UTF-8 不再被替換為 replacement characters。我們的工作區使用 UTF-8 locale，可正常運作。
  - **Native Apps（3 項）**：Mac app 連線 / 憑證更新 / 復原畫面修復。**與 K3s Docker 部署無關**。
  - **Models and Providers（11 項）**：
    - **Muse Wonder**（Meta）新增模型 + max thinking。Spark 1.3 Standard 仍為預設。
    - **MiniMax M3.1 Flash Preview**：Token Plan 或 MiniMax Code 用戶可選用，支援 low/medium/high/xhigh/max 思考力度，**預設 max effort**（含 saved off / adaptive 選擇）。
    - **MiniMax OAuth sign-in renewal**：過期 token 會自動在原區域端點 refresh。**首次登入仍需 `openclaw models auth login --provider minimax-portal` 一次**（我們已登入）。
    - **Replies after native compaction / Interrupted ChatGPT replies**：對話可從 saved history 接續。
    - **Codex follow-up messages / Switching back to OpenAI / Claude CLI session tools**：工具與 session 生命週期改善。
    - **DeepSeek replies and tool actions / IPv6 provider fallback / Copilot prompt capacity**：網路與 provider 邊界改善。
  - **Automations and Scheduling（1 項）**：unchanged one-shot jobs 不再產生冗餘備份。
  - **Plugins and Integrations（7 項）**：blocked local plugin settings、oc-path UTF-8、webhook callbacks during upgrades、native plugin catalogs、commands on paired nodes、Codex plugin compatibility、plugin package repairs。**Codex plugin compatibility**（#170306）會自動偵測低於 2026.9.7 的外部 Codex 並提示更新；我們使用的是隨容器升級的核心 plugin，自動合規。
  - **Security and Privacy（1 項）**：saved sign-ins during Doctor repairs — `auth-credential-semantics` 不會因 legacy auth file unreadable 而被丟棄。
  - **Quality-of-Life（1 項）**：restart with unreachable cloud worker — 可延後停止並回報。
  - **Other Bug Fixes（1 項）**：deleting unfinished conversation — 紀錄 cancellation 後才停止回覆。

**結論：對我們 K3s Docker 部署，零 breaking change、零手動 migration、零 plugin 手動介入。風險低。**

### 1.3 自訂 patch 清單（`my-config-v2026.10.2` 內，與官方 10.3 比對）

| Commit        | 檔案                                                                                                                     | 內容                                                                                                  | 10.3 衝突風險                                                                                                  |
| ------------- | ------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `4d7638af983` | `.github/workflows/*`（多檔）                                                                                            | 刪除官方 CI、覆蓋 `docker-release.yml` Matrix 版                                                      | 🟢 從 10.3 base 重新套用                                                                                       |
| `2c47b3a16c4` | `Dockerfile`（+46 行）、`extensions/google/embedding-provider.ts`、`extensions/memory-core/.../manager-embedding-ops.ts` | 自訂層（locale / rsync / faster-whisper / edge-tts / ffmpeg / openssh-server）+ embedding rate pacing | 🟢：Dockerfile 插入點（line ~437）未變；embedding-provider.ts / manager-embedding-ops.ts 與 10.2/10.3 完全相同 |
| `17ed80a261c` | `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`                                          | 自訂資產                                                                                              | 🟢 新檔，無衝突                                                                                                |

**結論：3 個自訂 commit 預期全部可線性 cherry-pick，無衝突。**

### 1.4 與官方 10.3 的 79 PR 統計摘要

- `fix(update)` ~22 項（核心修復）
- `fix(doctor)` ~6 項
- `fix(minimax)` 2 項（M3.1 Flash Preview、OAuth renewal）
- `feat(meta)` 1 項（Muse Wonder）
- `fix(minimax)` ...、其他 provider 改進 8 項
- `fix(plugins)` 2 項
- `fix(codex)` 1 項
- `fix(nodes)` 2 項
- `fix(macos/mac)` 3 項（不影響 K3s）
- `fix(cron/automations)` 1 項
- `fix(release/ci)` 多項（**僅上游發布 CI**，與我們的 Docker build 無關）
- `fix(anthropic)` 2 項（Claude CLI session tools）

---

## Phase 2: 執行步驟（已完成至 2.5 ✅）

### 2.0 前置

- [x] 確認 `git status -sb` 乾淨（僅未追蹤的本 worksheet）
- [x] 確認三個 upstream baseline tag 已 fetch
  - `upstream-v2026.10.1` commit `e178c39e9aae`
  - `upstream-v2026.10.2` commit `b8952d477f0c`（與官方一致）
  - `upstream-v2026.10.3` commit `59cb44796b0f`（**與官方 release SHA 完全一致** ✅）

### 2.1 建立新分支

```bash
git checkout -b my-config-v2026.10.3 upstream-v2026.10.3
```

- [x] 建立完成，HEAD = `59cb44796b0f`（官方 10.3 基線）

### 2.2 Purge 官方 workflows 並覆蓋 Matrix `docker-release.yml`

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.10.2 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [x] 官方 111 個 workflows → 僅剩 `docker-release.yml`（191 行 Matrix 版）
- [x] commit `cd47e1efda1`（111 files changed, +149 / −64,893）

### 2.3 Cherry-pick 自訂 commits（保留線性歷史與自訂層）

- [x] `cd47e1efda1` — purge commit 由 2.2 直接建立（略過 cherry-pick `4d7638af983`，保留單一 purge commit）
- [x] `64ce0d05c9e` — `chore: upgrade to v2026.9.7; restore custom Dockerfile layer, scripts, rate pacing, and TODOs`（來源 `2c47b3a16c4`）
  - ✅ **零衝突**：Dockerfile / `embedding-provider.ts` / `manager-embedding-ops.ts` 全部套用成功
- [x] `884f17a1fe1` — `fix(docker): restore assets/whisper and docker/entrypoint-ssh.sh for v2026.9.8`（來源 `17ed80a261c`）
  - ✅ **零衝突**：3 個新檔案（whisper 0755 / entrypoint-ssh.sh 0755 / TODO 0644）
- [x] `d8d9185dd39` / `29f229be77d` / `691ff91b814` / `23b1d15c50f` — 保留 10.1 / 10.2 歷史升級紀錄 worksheet（皆零衝突）

> 全部使用 `git cherry-pick -x`（保留來源 SHA 追溯）。

### 2.4 輕量本地驗證（無重型 CI）— 全部通過 ✅

- [x] `git diff upstream-v2026.10.3 HEAD -- Dockerfile` = **+46 行 / 0 行刪除**（純附加 patch）
- [x] `grep -n 'Custom:' Dockerfile` 顯示 4 個自訂段落：
  - line 437 `# Custom: Generate UTF-8 locales and install rsync`
  - line 456 `# Custom: Install faster-whisper, edge-tts, and ffmpeg for audio TTS/STT pipelines`
  - line 472 `# Custom: Audio STT CLI wrapper for fast-whisper`
  - line 476 `# Custom: SSH server support for Zeabur deployment`
- [x] `ls .github/workflows` 只剩 `docker-release.yml`
- [x] `package.json` version = `2026.10.3`
- [x] `test -f assets/whisper && test -f docker/entrypoint-ssh.sh` 通過（皆為 executable）
- [x] `git diff upstream-v2026.10.3 HEAD -- . ':!.github'` 僅顯示預期自訂資產：
  ```
  Dockerfile                                    |  46 +++
  TODO-docker-build-rsync-utf8.md               |  38 +++
  assets/whisper                                |  41 +++
  docker/entrypoint-ssh.sh                      |  32 ++
  docs/worksheet-upgrade-openclaw-v2026.10.1-*   | 326 +++
  docs/worksheet-upgrade-openclaw-v2026.10.2-*   | 111 +++
  extensions/google/embedding-provider.ts       | 139 ++--
  extensions/memory-core/.../manager-embedding-ops.ts |   2 +-
  ```
- [x] **線性歷史驗證**：`git log --merges upstream-v2026.10.3..HEAD` = 0 個 merge commit

### 2.5 更新本 worksheet 勾選並 commit

- [x] commit message：`docs: add v2026.10.3 upgrade worksheet and mark Phase 2 preparation completed`

### 2.6 Push 分支

```bash
git push -u origin my-config-v2026.10.3
```

- [x] 完成：`origin/my-config-v2026.10.3` = `70e5834dd4ee`（與 local HEAD 一致）

### 2.7 使用者確認 build 後（已完成 ✅）

> [!NOTE]
>
> **觸發機制修正**：我們的 Matrix `docker-release.yml` 是 **`workflow_dispatch` 專用**（`on:` 只有 `workflow_dispatch`，沒有 `push:` / `tags:`）。
> 舊 worksheet 寫「push tag 會觸發」並不正確——`git push tag` **不會** 觸發建置，必須手動 dispatch。
> 驗證依據：`gh run view 38263121081`（10.2 那次）顯示 `event: workflow_dispatch`、`headBranch: v2026.10.2`。

**Step 1 — 將 tag 指向自訂 commit**

```bash
git tag -f v2026.10.3 HEAD        # 原為 annotated tag → 官方 59cb44796b0f
git push -f origin v2026.10.3
```

- [x] `v2026.10.3` 轉為 lightweight tag → `70e5834dd4ee`（與 10.1 / 10.2 型態一致）
- [x] `git ls-remote --tags origin v2026.10.3` = `70e5834dd4ee` ✅

**Step 2 — 手動觸發建置**

```bash
gh workflow run docker-release.yml --repo kuniakil/openclaw \
  --ref v2026.10.3 -f tag=v2026.10.3 -f platforms=all
```

- [x] **Run ID：`38483327335`**
- [x] `event: workflow_dispatch` · `headBranch: v2026.10.3` · `headSha: 70e5834dd4ee` ✅
- [x] 無重複 / 錯誤 run 需要取消（`gh run list` 僅此一筆 in_progress）
- [x] 目標 image：`ghcr.io/kuniakil/openclaw:2026.10.3`（另含 `v2026.10.3`、`-slim`、`latest`、`main` 等連動 tag）

**Step 3 — 建置結果：成功 ✅**

- [x] **Run `38483327335` conclusion: `success`**（全部 4 個 job 綠燈）
  - `prepare` → success
  - `build-and-push (linux/amd64)` → success
  - `build-and-push (linux/arm64)` → success
  - `merge` → success
- [x] `docker buildx imagetools inspect ghcr.io/kuniakil/openclaw:2026.10.3` 驗證 multi-arch：
  ```
  MediaType: application/vnd.oci.image.index.v1+json
  Digest:    sha256:ac45487f97e0432b88b022922df31b900c790339b585473b13288d89824fb8af
    → linux/amd64  sha256:bb19376cf3b0d1171d1258459945432eb66a337238b9601fd8051bb4269ba057
    → linux/arm64  sha256:ab36210762c2b7d13d8834bf0e0d2d1a304db75aa540958af155cf1756fab5db
  ```

> [!IMPORTANT]
>
> **Tag 與分支不同步是預期行為**：`v2026.10.3` tag 固定在 `70e5834dd4ee`（實際建置 image 的程式碼），
> 而 `my-config-v2026.10.3` 分支後續推進到 `e996e651857`（僅新增 docs commit `record build trigger`）。
> docs 變更不影響 image 內容，兩者一致。

---

## Phase 3: 部署與驗證（已全數通過 ✅）

### 3.1 依 `docker-image-rebuild` SOP 更新 `~/kubernetes` kustomize image tag

- [x] 更新 `~/kubernetes/openclaw/overlays/n100/kustomization.yaml`：`2026.10.2` → `2026.10.3`
- [x] `git -C ~/kubernetes status -sb` 確認僅 `kustomization.yaml` 變更（乾淨的 `main` 上只有這一筆）

### 3.2 K3s rollout，確認 Pod Ready、Gateway 啟動無 Doctor 錯誤

- [x] **備份** `/data/services/openclaw` → `/root/backup-openclaw-20261014`
  - rsync 完成：17G / **148,732 檔案**（source 與 backup 檔案數、大小完全一致 ✅）
  - **已於驗證通過後刪除**（2026-10-14，Phase 5.2）——本次部署確認健康，
    且 10.2→10.3 `schemaVersions` 未變（state 20 / agent 24）無 DB 遷移，無回滾價值。
  - 磁碟已回收 17G。
- [x] `kubectl apply -k ~/kubernetes/openclaw/overlays/n100` → `successfully rolled out`
- [x] 新 Pod：`openclaw-gateway-6655df6486-zsvbk`，`1/1 Running`，`RESTARTS 0`
- [x] Deployment image 確認為 `ghcr.io/kuniakil/openclaw:2026.10.3`
- [x] **17 個 plugins 全部載入**（anthropic, canvas, cua-computer, device-pair, file-transfer, geolocation, github, google, linux-node, memory-core, microsoft, ollama, openai, talk-voice, tavily, telegram, xai）
- [x] Gateway `ready`，Telegram polling 啟動

> [!NOTE]
>
> **啟動期間出現的瞬時警告（皆已自動恢復，非缺陷）**：
>
> 初次啟動時 agent DB 的 5 秒前景 startup budget 到期，出現：
> `cron maintenance failed`、`memory-core: dreaming startup cleanup failed`、
> `chat metadata refresh failed`、`[SECRETS_DEGRADED] cold route`。
>
> 系統按設計於背景完成準備後自行恢復：
>
> ```
> 07:38:25 [state/agent-admission] agent database recovered after background inspection and preparation
> ```
>
> 恢復後無任何新錯誤。屬於已知的冷啟動競態，非升級失敗，**不需手動執行 `openclaw doctor --fix`**。

### 3.3 確認自訂功能（與 10.2 對齊）— 全數通過 ✅

- [x] `locale -a` 顯示 `C.utf8` / **`en_US.utf8`** / **`zh_TW.utf8`**
- [x] `whisper` → `/usr/local/bin/whisper`
- [x] `edge-tts` → `/usr/local/bin/edge-tts`
- [x] `ffmpeg` → `/usr/bin/ffmpeg`
- [x] `rsync` → `/usr/bin/rsync`
- [x] `sshd` → `/usr/sbin/sshd`
- [x] `/app/docker/entrypoint-ssh.sh` → `OK executable`
- [x] `faster_whisper.__version__` = **1.2.1**
- [x] `edge_tts.__version__` = **7.2.8**
- [x] 環境變數正確：`LANG=C.UTF-8 LC_ALL=C.UTF-8 PYTHONPATH=/usr/local/lib/faster-whisper`

### 3.4 確認運行版本

- [x] 容器內 `/app/package.json` → `"version": "2026.10.3"`
- [x] `openclaw --version` → `OpenClaw 2026.10.3`

### 3.5 端到端功能驗證（真實訊息往返）

- [x] Telegram 真實收發完整走一趟：
  ```
  07:39:25 [telegram] Inbound message telegram:830338761 -> @N100_openclaw_mike_bot (direct, 10 chars)
  07:39:39 [model-fetch] provider=minimax api=anthropic-messages model=MiniMax-M3 status=200
  07:39:43 [agent-turn-timing] milestone=tool_execution_started totalMs=15449
  07:40:03 [telegram] outbound send ok chatId=830338761 messageId=2628 operation=sendMessage
  ```
  證明：收訊息 → 呼叫模型（HTTP 200）→ 執行工具 → 回覆送出，**全鏈路正常**。

### 3.6 回滾備案

- [x] 備份已於驗證通過後刪除（見 3.2）；本次無 schema 遷移，無回滾需求
- [x] 若將來需回滾：`kubectl -n openclaw set image deployment/openclaw-gateway gateway=ghcr.io/kuniakil/openclaw:<prev>`
      資料不需還原（10.2→10.3 無 DB 遷移），舊 DB 可直接被新版使用

### 3.7 更新本 worksheet 全部勾選並 commit

- [x] commit 到 `my-config-v2026.10.3` 並 push
- [x] `~/kubernetes` kustomization 變更 commit + push

---

## 🔖 關鍵參考

- **官方 Release Notes:** https://docs.openclaw.ai/releases/2026.10.3
- **官方 Changelog (raw):** https://raw.githubusercontent.com/openclaw/openclaw/v2026.10.3/CHANGELOG/2026.10.3.md
- **Image digest:** `sha256:ac45487f97e0432b88b022922df31b900c790339b585473b13288d89824fb8af`
- **Build Run:** https://github.com/kuniakil/openclaw/actions/runs/38483327335
- **GHCR image:** `ghcr.io/kuniakil/openclaw:2026.10.3`
- **K3s 部署:** `~/kubernetes/openclaw/overlays/n100/`
- **Backup 路徑:** `/root/backup-openclaw-20261014`（部署前建立，17G / 148,732 檔案，已驗證）
- **SOP 來源：** `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`、`docker-image-rebuild/SKILL.md`
- **上一版 worksheet:** `docs/worksheet-upgrade-openclaw-v2026.10.2-20261012.md`

---

## 📌 本次升級待辦教訓（供下次參考）

### 發布模型決策（2026-10-14，kuniaki 確認）

往後採用**分支觸發**模型，已寫入 `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`
與 `~/.pi/agent/skills/docker-image-rebuild/SKILL.md`：

```
my-config-v<version> 分支  ←  官方版本 + 我們所有 custom commits（持續往前）
        │
        └─ dispatch build（--ref 分支 + -f tag）─→ image: <version>
                                                       ↑
                                    未來 rebuild 會覆蓋成更新的程式碼（預期行為）
```

| 項目                        | 結論                                                            |
| --------------------------- | --------------------------------------------------------------- |
| build 來源                  | `--ref my-config-v<version>`（分支）                            |
| image 名稱                  | `-f tag=v<version>` → 與官方版本同名 `2026.10.3`                |
| 是否需要 force-push git tag | **不需要**（build 只讀分支）                                    |
| 未來加 commit 後 rebuild    | 重跑同一指令，`2026.10.3` image 被新版程式碼覆蓋 ← **預期行為** |

**與本次做法的差異**：本次（10.3）已 force-push `v2026.10.3` → `70e5834dd4ee`，
且實際由 tag 觸發（headSha 已驗證為我們的 commit）。**保持現狀、不重來**。
下次升級（10.4 起）改用分支觸發。

**已保留的 git tag 語意**：「官方 v2026.10.3 + 我們 custom commits 的**當下快照**」。
日後分支繼續前進時，除非再次 force-push，否則 tag 不會動。

### 其他待辦教訓

1. **Matrix `docker-release.yml` 只認 `workflow_dispatch`**，`git push tag` **不會**觸發建置。
   舊 worksheet 的「push tag 就會觸發」說法錯誤。正確流程：

   ```bash
   gh workflow run docker-release.yml --repo kuniakil/openclaw \
     --ref my-config-v<version> -f tag=v<version> -f platforms=all
   ```

   派發後務必用 `gh run view <id> --json event,headBranch,headSha` 驗證觸發參數。

2. **Input 名稱是 `tag` 不是 `tag_name`**。寫錯會被靜默忽略 → branch `--ref` 下 `TAG` 落到
   `latest` → **build 成功但沒有版本 tag**。這是最容易踩的坑。

3. **官方 tag 是 annotated、我們自訂 tag 是 lightweight**。
   本地 fetch 上游時會自動產生 annotated `v2026.10.3`（指向官方 commit），注意覆蓋。

4. **不要用本地 `v2026.x.y` tag 當 diff base**（含自訂 patch，會誤判大量衝突）。
   一律另 fetch `upstream-v<version>`：

   ```bash
   git fetch upstream refs/tags/v<version>:refs/tags/upstream-v<version> --no-tags
   git rev-parse upstream-v<version>^{commit}   # ref 本身是 annotated tag object，要加 ^{commit}
   ```

   `git fetch upstream --tags` 會因為本地 tag 是自訂的而全部被 reject。

5. **冷啟動瞬時警告不代表失敗**。agent DB 5 秒 startup budget 到期會出現
   `cron maintenance failed` / `chat metadata refresh failed` / `[SECRETS_DEGRADED]`，
   看到 `agent database recovered after background inspection and preparation` 即已恢復。
   驗證健康度要看**後續真實流量**（本次以 Telegram 收發往返證明），不要只看啟動期錯誤。
