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
git push origin my-config-v2026.10.3
```

### 2.7 使用者確認 build 後

```bash
git tag -f v2026.10.3
git push -f origin v2026.10.3
```

觸發 `docker-release.yml` → `ghcr.io/kuniakil/openclaw:2026.10.3`

---

## Phase 3: 部署與驗證（待 Go-Sign）

### 3.1 依 `docker-image-rebuild` SOP 更新 `~/kubernetes` kustomize image tag

- [ ] 更新 `~/kubernetes/openclaw/overlays/n100/kustomization.yaml` 至 `2026.10.3`
- [ ] `git -C ~/kubernetes diff --stat` 確認僅 kustomization.yaml 變更

### 3.2 K3s rollout，確認 Pod Ready、Gateway 啟動無 Doctor 錯誤

- [ ] **備份** `/data/services/openclaw` 至 `/root/backup-openclaw-20261014`（10.2 容器 + 資料大小約 17GB）
- [ ] `kubectl apply -k ~/kubernetes/openclaw/overlays/n100`
- [ ] `kubectl rollout status deployment/openclaw-gateway -n openclaw` 等待 Ready
- [ ] 確認 plugins 數量: 17 個（與 10.2 一致，無新失敗）
- [ ] 確認 Telegram polling 啟動無錯誤

### 3.3 確認自訂功能（與 10.2 對齊）

- [ ] `kubectl exec ... -- bash -c "locale -a"` 顯示 `en_US.utf8` / `zh_TW.utf8`
- [ ] `which whisper`、`which edge-tts`、`which ffmpeg`、`which rsync`、`which sshd` 全部存在
- [ ] `test -x /app/docker/entrypoint-ssh.sh` 通過
- [ ] `python3 -c "import faster_whisper; print(faster_whisper.__version__)"` 顯示已安裝版本
- [ ] `python3 -c "import edge_tts; print(edge_tts.__version__)"` 顯示已安裝版本

### 3.4 確認運行版本

- [ ] `kubectl exec ... -- cat /app/package.json | grep '"version"'` = `2026.10.3`
- [ ] `openclaw --version` = `2026.10.3`

### 3.5 回滾備案

- [ ] 驗證完好 → 無需回滾
- [ ] 若 Doctor 報錯：保留 `/root/backup-openclaw-20261014`，將 kustomize image tag 回退至 `2026.10.2`

### 3.6 更新本 worksheet 全部勾選並發布收工 post-mortem

---

## 🔖 關鍵參考

- **官方 Release Notes:** https://docs.openclaw.ai/releases/2026.10.3
- **官方 Changelog (raw):** https://raw.githubusercontent.com/openclaw/openclaw/v2026.10.3/CHANGELOG/2026.10.3.md
- **GHCR image:** `ghcr.io/kuniakil/openclaw:2026.10.3`
- **K3s 部署:** `~/kubernetes/openclaw/overlays/n100/`
- **Backup 路徑:** `/root/backup-openclaw-20261014`（部署前建立）
- **SOP 來源：** `~/.pi/agent/skills/agent-release-upgrade/SKILL.md`、`docker-image-rebuild/SKILL.md`
- **上一版 worksheet:** `docs/worksheet-upgrade-openclaw-v2026.10.2-20261012.md`
