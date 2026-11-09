# OpenClaw v2026.11.2 升級工作表（2026-11-09）

> 目標：由 `my-config-v2026.11.1`（線上 image `ghcr.io/kuniakil/openclaw:2026.11.1`）對齊官方 `v2026.11.2`
> （tag SHA `b556fdf457b026574bf0f1e7b4914b15f3f179ce`，已 fetch 為 `refs/tags/upstream-v2026.11.2`）。
> 保留自訂 Docker 層、Gemini 限速 patch、CJK bigram FTS 索引、精簡 Matrix `docker-release.yml`、線性歷史。
> 本檔為規劃書；取得 Go-Sign 前不做任何修改。

## 🚦 Go-Sign Gate

- [ ] 使用者明確核准執行 Phase 2
- [ ] 確認備份方式（建議項；schema 未變）
- [ ] 不在 Mac 跑重型 CI / docker build（全交 GitHub Actions）
- [ ] 升級期間不另起 `openclaw memory index/search/reset`、`agent --local`（避免雙行程撞 Gemini 配額）
- [ ] 10+ 分鐘等待（`gh run watch`、rollout）派給背景子代理

> [!NOTE]
> 🟢 **這是 patch 級小升級**
>
> 1. `schemaVersions` 不變：`state 22 / agent 27` → **無不可逆遷移**，不需 doctor 縮容流程。
> 2. 官方 Release Notes **沒有 Breaking Changes 章節**；Node engines 不變（`>=24.16.0 <25 || >=26.1.0`）。
> 3. `Dockerfile`、`docker/`、`pnpm-lock.yaml` 上游零變更；`package.json` 僅 version + 新增 `release:watch` script。
> 4. 衝突檢查：我們自訂檔 ∩ 上游變更 = 6 個官方 workflow（本來就 purge）+ `docs/reference/memory-config.md`（上游只在「Custom provider ids」段新增 Azure 說明，我們改的是別處 → 預期可自動合併，若衝突兩段都保留）。
> 5. 記憶體 embedding：上游僅新增 `packages/memory-host-sdk/src/host/azure-api-version-request.*` 與 `embeddings-remote-fetch.ts` 3 行（Azure api-version）；`extensions/google/embedding-provider.ts`、模型、輸入格式皆未變 → **不重建索引**。

---

## Phase 1: 分析結果

### 1.1 版本差異

| 項目                   | v2026.11.1                    | v2026.11.2                | 處置                  |
| ---------------------- | ----------------------------- | ------------------------- | --------------------- |
| 規模                   | —                             | 959 files, +21,255 −5,112 | 中型修正集（115 PRs） |
| schemaVersions         | state 22 / agent 27           | 同                        | 🟢 無遷移             |
| Node engines           | `>=24.16.0 <25 \|\| >=26.1.0` | 同                        | 🟢                    |
| Dockerfile / pnpm-lock | —                             | 零變更                    | 🟢 自訂層零衝突       |
| 發布日                 | —                             | 2026-11-08                | stable，非 prerelease |

### 1.2 官方 Release Notes 重點（與我們相關）

- **Privacy／trust**：設定 secrets、對話內容、tool error 不再寫入診斷 log；MCP grant 在 warm CLI turn 後釋放。
- **Gateway 可用性**：減少診斷擷取成本；Telegram 病態表格不再阻塞 Gateway；channel 啟動在 shutdown 時取消；schema-lease 暫時衝突可恢復。→ 我們唯一 channel 是 Telegram，直接受益。
- **Changes（唯一行為變更）**：診斷內容擷取現在限制 attribute／候選 payload 大小並省略過大圖片 → 只影響診斷，不限制 prompt／對話。
- **Model routing**：尊重關閉的 reasoning、tier 後綴、alias、quota reset 期間；OpenCode Go 端點故障時保留模型。
- **Memory**：recall context 有上限；接受 memory-search limit alias；Azure OpenAI embedding api-version 正確轉發（我們用 Gemini，不受影響）。
- **更新／Doctor**：避免 update self-fencing、FIFO hang；保留已設定的 plugin executable 與 env 參照。
- **Worker/DB**：多項 DB lifecycle 修正（quarantined cached read、held alias 偵測）—— 屬修正，非 schema 變更。
- **Deprecations / 手動遷移**：notes 未列。

### 1.3 自訂 patch 清單（由 `upstream-v2026.11.1..my-config-v2026.11.1` 帶入）

- [ ] Dockerfile 自訂層（locale、rsync、tini、faster-whisper、edge-tts、ffmpeg、openssh-server）
- [ ] `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`
- [ ] Gemini 限速 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`（`extensions/google/embedding-provider.ts`）
- [ ] CJK bigram companion FTS（`extensions/memory-core/src/memory/*`、`packages/memory-host-sdk/src/host/cjk-bigram.ts`、`memory-schema*.ts`、`src/agents/memory-search.ts`、`src/config/zod-schema.memory-search.ts` 等）
- [ ] `docs/reference/memory-config.md`（唯一非 workflow 的潛在衝突點）
- [ ] 歷史 worksheet（`docs/worksheet-upgrade-*`）
- [ ] 精簡 Matrix `docker-release.yml`

---

## Phase 2: 執行（Go-Sign 後）

### 2.1 備份與基線

- [ ] `git status` 乾淨；`git branch backup/my-config-v2026.11.1 origin/my-config-v2026.11.1`（若不存在）
- [ ] （建議）備份線上 PVC / `openclaw.json`（參考 `docker-image-rebuild` Phase 4.2）
- [ ] `git rev-parse upstream-v2026.11.2^{commit}` = `b556fdf457b0…`

### 2.2 建立新分支

- [ ] `git checkout -b my-config-v2026.11.2 upstream-v2026.11.2`

### 2.3 Purge workflows、覆蓋 docker-release.yml

- [ ] `find .github/workflows -type f ! -name 'docker-release.yml' -delete`
- [ ] `git checkout origin/my-config-v2026.11.1 -- .github/workflows/docker-release.yml`
- [ ] `git add .github/workflows && git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"`

### 2.4 移植自訂 commit

- [ ] `git log --oneline --no-merges upstream-v2026.11.1..origin/my-config-v2026.11.1`（確認清單；略過已被 revert 的暫時性 CI workflow 兩個 commit，或 cherry-pick 後再被 purge）
- [ ] 依序 `git cherry-pick`（跳過 workflow purge commit，因 2.3 已做）
- [ ] 若 `memory-config.md` 衝突：保留上游 Azure 段落 + 我們的 CJK bigram 段
- [ ] 驗證自訂層：`git grep -q 'Custom: Install faster-whisper' HEAD -- Dockerfile`
- [ ] 驗證限速：`git grep -n MIN_GEMINI_EMBEDDING_INTERVAL_MS HEAD -- extensions/google`
- [ ] 驗證 `assets/whisper`、`docker/entrypoint-ssh.sh` 存在

### 2.5 本地輕量驗證（禁重型 CI）

- [ ] `git status`、`git diff --check`
- [ ] `git diff upstream-v2026.11.2 --stat -- . ':!docs' ':!.github'` 僅含預期自訂檔
- [ ] 確認 workflow 只剩 `docker-release.yml` 且無 `push:`/`tags:` 觸發

### 2.6 建立新版 worksheet、推送

- [ ] 將本檔勾選狀態 commit：`docs: add v2026.11.2 upgrade worksheet`
- [ ] `git push -u origin my-config-v2026.11.2`（**不要推 tag**）

### 2.7 觸發建置（再次確認後）

- [ ] `grep -A6 workflow_dispatch: .github/workflows/docker-release.yml` 確認 input 名為 `tag`
- [ ] `bash
      gh workflow run docker-release.yml --repo kuniakil/openclaw \
        --ref my-config-v2026.11.2 -f tag=v2026.11.2 -f platforms=all
      `
- [ ] 驗證 run：`event=workflow_dispatch`、`headBranch=my-config-v2026.11.2`、`headSha` 為我們的 commit
- [ ] 若 HTTP 422 "Actions has been disabled" → 到 `https://github.com/kuniakil/openclaw/actions` 點 banner 重新啟用（勿清 cache、勿改 settings）
- [ ] （子代理）`gh run watch`；完成後 `docker buildx imagetools inspect` 檢查 `2026.11.2 v2026.11.2 2026.11.2-slim latest main`

### 2.8 部署（K3s，參考 `docker-image-rebuild`）

- [ ] 更新 `~/kubernetes` kustomize image tag → `2026.11.2`
- [ ] rollout，（子代理）`kubectl rollout status`
- [ ] 檢查 Pod 啟動、無 CrashLoop、Telegram 正常收發
- [ ] logs 確認無 `RESOURCE_EXHAUSTED`、無意外 re-chunk／全量 reindex
- [ ] 診斷 `rss_threshold` 警告僅觀察趨勢，不當作事故

---

## Phase 3: 收尾

- [ ] 勾完本工作表並 commit／push
- [ ] 回滾預案：`kustomize` image 改回 `2026.11.1`（schema 未變，可直接回退）
- [ ] 視需要以 `session-wrapup` 寫 post-mortem 發佈 WP

## 回滾預案

schema 未變 → 只需把 image tag 改回 `2026.11.1` 並 rollout；無需還原 DB。
