# OpenClaw 升級工作表：v2026.11.2 → v2026.11.3

- 日期：2026-11-12
- 目前分支：`my-config-v2026.11.2`（HEAD `629d8382392`）
- 目標：`v2026.11.3`（發佈 2026-11-10，非 prerelease）
  - upstream commit：`847611dcaa3bf0e2783335f961dd1fd0580e4d9f`（`upstream-v2026.11.3`）
  - 前一版 baseline：`upstream-v2026.11.2` = `b556fdf457b0…`
- 新分支：`my-config-v2026.11.3`

---

## Phase 1: 分析結果

### 1.1 官方 Release Notes（34 PR，維護/安全修補型）

- **Breaking changes**：無。notes 明載「No new configuration options or features」。
- **Deprecations / 手動遷移**：notes 未列。
- **Runtime 需求**：`engines.node` 不變（`>=24.16.0 <25 || >=26.1.0`）。
- **schemaVersions**：`state: 22`、`agent: 27`，與 11.2 **相同** → **無不可逆 migration**，可直接回退 image。
- **Dockerfile / docker-release.yml**：上游本次無變更。
- 重點：
  - 私有 subagent 完成結果不再串流到聊天回覆；子任務取消後交接不被舊 receipt 阻擋。
  - 未回應的 tool failure 會明確回報；provider 驗證卡住時於 run deadline 中止。
  - 憑證隔離：plugin 快取結果、Firecrawl、**embedding credentials 綁定其目的端**；env 憑證在 config 讀取時遮蔽；Signal／LSP 子行程不再繼承 Gateway secrets。
  - 更新流程：profile-backed update 認得自己的 lock；package-presence 檢查逾時可安全復原。
  - 啟動時模組檔案載入負擔降低；`/reset soft` 轉送至 Gateway。
  - **Memory provider**：`none` / `auto` / fallback `none` 不分大小寫。

### 1.2 自訂 patch（`upstream-v2026.11.2..my-config-v2026.11.2`）

- Dockerfile 自訂層（locale、rsync、tini、faster-whisper、edge-tts、ffmpeg、openssh-server）
- `assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`
- Gemini 限速 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200`
- CJK bigram companion FTS（memory-core、memory-host-sdk、`src/agents/memory-search.ts`、`zod-schema.memory-search.ts`）
- `docs/reference/memory-config.md`、歷史 worksheet、精簡 Matrix `docker-release.yml`

### 1.3 衝突風險（已用 `git merge-tree` 乾跑）

| 檔案                              | 上游是否也改                                                         | 乾跑結果      | 處置                       |
| --------------------------------- | -------------------------------------------------------------------- | ------------- | -------------------------- |
| `.github/workflows/ci.yml`        | 是                                                                   | modify/delete | 預期；purge 步驟已涵蓋     |
| `src/agents/memory-search.ts`     | 是（provider 大小寫、`isSameMemorySearchProvider`、inheritedRemote） | 自動合併      | cherry-pick 後人工 review  |
| `docs/reference/memory-config.md` | 是（大小寫句）                                                       | 自動合併      | 保留上游句 + 我們的 CJK 段 |

### 1.4 Memory embedding 重建判斷

- 上游 `extensions/memory-core/src/memory/embeddings.ts`、`packages/memory-host-sdk` 有變動，但內容為 provider 大小寫處理與 session-files 重構。
- `extensions/google/embedding-provider.ts` **未變** → Gemini 限速 patch 不受影響。
- schema 未變、模型未變 → **預設不重建索引、不 reset cache**。部署後觀察 log 是否出現意外全量 reindex。
- ⚠️ 憑證與目的端綁定的修正，部署後確認 Gemini embedding 仍可正常取得 key（無 401/403）。

---

## Phase 2: 執行（需 Go-Sign）

### 2.1 備份與基線

- [x] `git status` 乾淨
- [x] `git branch backup/my-config-v2026.11.2 origin/my-config-v2026.11.2`（若不存在）
- [ ] （建議）備份線上 PVC / `openclaw.json`（參考 `docker-image-rebuild` Phase 4.2）
- [x] `git rev-parse upstream-v2026.11.3^{commit}` = `847611dcaa3b…`

### 2.2 建立新分支

- [x] `git checkout -b my-config-v2026.11.3 upstream-v2026.11.3`

### 2.3 Purge workflows、覆蓋 docker-release.yml

- [x] `find .github/workflows -type f ! -name 'docker-release.yml' -delete`
- [x] `git checkout origin/my-config-v2026.11.2 -- .github/workflows/docker-release.yml`
- [x] `git add .github/workflows && git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"`

### 2.4 移植自訂 commit

- [x] `git log --oneline --no-merges upstream-v2026.11.2..origin/my-config-v2026.11.2`（確認清單；跳過 workflow purge commit）
- [x] 依序 `git cherry-pick`
- [x] review `src/agents/memory-search.ts`、`docs/reference/memory-config.md` 合併結果
- [x] `git grep -q 'Custom: Install faster-whisper' HEAD -- Dockerfile`
- [x] `git grep -n MIN_GEMINI_EMBEDDING_INTERVAL_MS HEAD -- extensions/google`
- [x] `assets/whisper`、`docker/entrypoint-ssh.sh` 存在

### 2.5 本地輕量驗證（禁重型 CI / 本機 docker build）

- [x] `git status`、`git diff --check`
- [x] `git diff upstream-v2026.11.3 --stat -- . ':!docs' ':!.github'` 僅含預期自訂檔
- [x] workflow 只剩 `docker-release.yml` 且無 `push:`/`tags:` 觸發

### 2.6 Worksheet、推送

- [x] commit：`docs: add v2026.11.3 upgrade worksheet`
- [x] `git push -u origin my-config-v2026.11.3`（**不推 tag**）

### 2.7 觸發建置（再次確認後）

- [x] `grep -A6 workflow_dispatch: .github/workflows/docker-release.yml` 確認 input 為 `tag`
- [x] `gh workflow run docker-release.yml --repo kuniakil/openclaw --ref my-config-v2026.11.3 -f tag=v2026.11.3 -f platforms=all`
- [x] 驗證 run：`event=workflow_dispatch`、`headBranch=my-config-v2026.11.3`、`headSha` 為我們的 commit (`8f97237a2e1`)
- [x] 若 HTTP 422 "Actions has been disabled" → 到 `https://github.com/kuniakil/openclaw/actions` 點 banner（已手動解除）
- [ ] （子代理）`gh run watch`（Run ID: 43207683257）；完成後 `docker buildx imagetools inspect` 檢查 `2026.11.3 v2026.11.3 2026.11.3-slim latest main`

### 2.8 部署（K3s，參考 `docker-image-rebuild`）

- [ ] 更新 `~/kubernetes` kustomize image tag → `2026.11.3`
- [ ] rollout（子代理 `kubectl rollout status`）
- [ ] Pod 啟動、無 CrashLoop、Telegram 正常收發
- [ ] logs 無 `RESOURCE_EXHAUSTED`、無 401/403 embedding 認證錯誤、無意外全量 reindex
- [ ] `rss_threshold` 警告僅看趨勢

---

## Phase 3: 收尾

- [ ] 勾完本工作表並 commit／push
- [ ] 視需要以 `session-wrapup` 寫 post-mortem 發佈 WP

## 回滾預案

schema 未變 → kustomize image tag 改回 `2026.11.2` 並 rollout；無需還原 DB。
