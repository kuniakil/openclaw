# Upgrade Worksheet: openclaw → v2026.10.2

**Date:** 2026-10-12
**Current branch:** `my-config-v2026.10.1`（HEAD `cd117fa6659`，與 origin 同步，工作樹乾淨）
**Target tag:** `v2026.10.2`（官方 SHA `b8952d477f0c932d8ddc6da5c89cab5a169b6ff1`）
**New branch:** `my-config-v2026.10.2`
**Release:** https://github.com/openclaw/openclaw/releases/tag/v2026.10.2

> [!IMPORTANT]
>
> 1. **本地 `v2026.10.1` 是自訂 tag**（`1296b175f0e`，含我們的 patch），不可當官方 diff base。官方基線已 fetch 到 `refs/upstream-tags/v2026.10.1`（官方 10.1）與 `refs/upstream-tags/v2026.10.2`。
> 2. 本地 `v2026.10.2` tag 目前 = 官方 SHA；完成後依 SOP 以 `git tag -f v2026.10.2` 指向自訂 commit。
> 3. 禁止在 Mac 跑 `pnpm check:changed` / `tsgo` / `vitest` / `docker build`，一律交給 GitHub Actions。

---

## Phase 1: 分析結果（已完成）

### 1.1 官方 10.1 → 10.2 差異

| 項目                                                                    | 10.1                  | 10.2                             | 備註                                                            |
| ----------------------------------------------------------------------- | --------------------- | -------------------------------- | --------------------------------------------------------------- |
| 規模                                                                    | —                     | 655 files（含 .github） / 85 PRs | patch release，僅修復 + 小改                                    |
| `package.json` version                                                  | 2026.10.1             | 2026.10.2                        |                                                                 |
| `package.json` files[]                                                  | —                     | 新增 `node-runtime-env.mjs`      | 新 runtime 檔，Dockerfile 需 COPY                               |
| `openclaw.schemaVersions` / `updateAdmissionProtocol`                   | state 20 / protocol 1 | **未變**                         | 無新 DB migration                                               |
| Node / base image                                                       | node:24-bookworm      | 不變                             |                                                                 |
| **Dockerfile（官方）**                                                  | —                     | +2 行                            | `COPY node-runtime-env.mjs`（runtime-assets 與最終 stage 各一） |
| `extensions/google/package.json`、`extensions/memory-core/package.json` | —                     | 僅版本號/依賴小改                |                                                                 |
| pnpm-lock.yaml                                                          | —                     | 無變動                           |                                                                 |

### 1.2 官方 Release Notes 審查

- **Breaking Changes：無**。
- **Deprecations：無**。
- **Dependency / Runtime Bumps：無**（Node、base image、schema 皆不變）。
- **Upgrade 注意事項**
  - 10.2 主打 **「從 stable 10.1 首次升級完整完成」**：in-place update 成功不再報錯；Windows、cloned-filesystem、private-Node update path 修正。K3s 容器重建部署影響有限，但 Doctor 行為改善。
  - **Doctor/update recovery**：不再卡在 residual legacy imports、stale Gateway lock、memory reindex lock、已移除 channel account 的 allowlist。
  - **預設行為變更（需留意）**：OpenAI 與 Anthropic **API-key route 預設改為 provider-native compaction**；primary auth profile cooling down 時 compaction 可恢復。
  - Secret redaction：跨 chunk 邊界的憑證現在會遮罩；大文字 redaction 變快。
  - Prompt-cache 穩定性（Anthropic checkpoint、tool result 位元組一致）。
  - Gateway 回應性：Control UI reconnect、大 plugin 換模型、catalog 載入不再凍結。
  - 其他修復：Telegram 串流回覆、Codex session、cron 執行失去 plugin registry、subagent/ACP 答案截斷、Bedrock custom provider region、egress proxy CA、macOS crash。
  - 與我們自訂功能相關：`memory_search` snake_case 參數修正（memory 路徑）；**無**官方變更觸及我們的 embedding patch 檔案。

### 1.3 自訂 patch 清單（`upstream 10.1..HEAD`，扣除 `.github`）

| 檔案                                                         | 內容                                                                           | 10.2 衝突風險                                                                          |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------- |
| `Dockerfile`                                                 | 自訂層 +46 行：locale、rsync、faster-whisper、edge-tts、ffmpeg、openssh-server | 🟡 低：官方只在 COPY 區塊加 2 行；自訂層位於 `/home/node/.config` 權限檢查之後，不重疊 |
| `assets/whisper`、`docker/entrypoint-ssh.sh`                 | 自訂資產                                                                       | 🟢 無（官方未動）                                                                      |
| `extensions/google/embedding-provider.ts`                    | embedding rate pacing                                                          | 🟢 官方 10.2 未改此檔                                                                  |
| `extensions/memory-core/src/memory/manager-embedding-ops.ts` | 同上（1 行）                                                                   | 🟢 官方 10.2 未改此檔                                                                  |
| `TODO-docker-build-rsync-utf8.md`、舊 worksheet              | 文件                                                                           | 🟢 無                                                                                  |
| `.github/workflows/`                                         | 僅 `docker-release.yml`（Matrix 版）                                           | 🟢 purge 後覆蓋                                                                        |

**結論：整體風險低，預期 cherry-pick 無衝突。**

---

## Phase 2: 執行步驟（已完成至 2.5）

- [x] **2.0 前置**：`git status -sb` 確認乾淨；確認官方 baseline tag。
- [x] **2.1 建立新分支**
  ```bash
  git checkout -b my-config-v2026.10.2 refs/upstream-tags/v2026.10.2
  ```
- [x] **2.2 Purge 官方 workflows 並覆蓋 Matrix docker-release.yml**
  ```bash
  find .github/workflows -type f ! -name 'docker-release.yml' -delete
  git checkout my-config-v2026.10.1 -- .github/workflows/docker-release.yml
  git add .github/workflows
  git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
  ```
- [x] **2.3 Cherry-pick 自訂 commits**（保留線性歷史與自訂層）
  - [x] `2c47b3a16c4` chore: upgrade to v2026.9.7；restore custom Dockerfile layer / scripts / rate pacing / TODOs
  - [x] `17ed80a261c` fix(docker): restore assets/whisper and docker/entrypoint-ssh.sh
  - [x] `be9e8b7f7ed` docs: add v2026.10.1 upgrade worksheet
  - [x] `b598019150d` docs: mark Phase 3 verification as completed with K3s deployment results
- [x] **2.4 輕量本地驗證**（無重型 CI）
  - [x] `git diff refs/upstream-tags/v2026.10.2 -- Dockerfile` 只顯示自訂層
  - [x] `grep -n node-runtime-env.mjs Dockerfile` 確認 2 筆保留完整
  - [x] `git diff --stat refs/upstream-tags/v2026.10.2 HEAD -- . ':!.github'` 僅含預期自訂資產
  - [x] `ls .github/workflows` 只有 `docker-release.yml`
  - [x] `package.json` version = `2026.10.2`
- [x] **2.5 更新本 worksheet 勾選並 commit**
- [ ] **2.6 Push 分支**：`git push origin my-config-v2026.10.2`
- [ ] **2.7 使用者確認 build 後**
  ```bash
  git tag -f v2026.10.2
  git push -f origin v2026.10.2
  ```
  觸發 `docker-release.yml` → `ghcr.io/kuniakil/openclaw:2026.10.2`；監控 build。

## Phase 3: 部署與驗證（Docker 建置成功後）

- [ ] 3.1 依 `docker-image-rebuild` SOP 更新 `~/kubernetes` kustomize image tag
- [ ] 3.2 K3s rollout，確認 Pod Ready、Gateway 啟動無 Doctor 錯誤
- [ ] 3.3 確認自訂功能：`whisper` CLI、`edge-tts`、locale（en_US/zh_TW）、sshd entrypoint、`rsync`、Google embedding 不觸發 rate limit
- [ ] 3.4 確認預設 compaction 變更（OpenAI/Anthropic API key route）未影響現有 agents
- [ ] 3.5 回滾備案：image tag 退回 `2026.10.1`（schema 未變，可直接回滾）
- [ ] 3.6 更新本 worksheet 全部勾選，並用 `doc-and-wp-publish` 寫 post-mortem（若有問題）
