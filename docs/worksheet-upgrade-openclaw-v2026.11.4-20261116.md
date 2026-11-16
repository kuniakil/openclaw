# OpenClaw 升級工作表：v2026.11.3 → v2026.11.4

- 日期：2026-11-16
- 目前分支：`my-config-v2026.11.3`（HEAD `1c2ffa17c82`）
- 目標：`v2026.11.4`（發佈 2026-11-16，stable，非 prerelease）
  - upstream commit：`d843d6af39a42cd3c30084edbeabeece732fd93a`（`upstream-v2026.11.4`）
  - 前一版 baseline：`upstream-v2026.11.3` = `847611dcaa3bf0e2783335f961dd1fd0580e4d9f`
- 新分支：`my-config-v2026.11.4`
- 目標 Image：`ghcr.io/kuniakil/openclaw:2026.11.4`

---

## 🚦 Go-Sign Gate

- [x] Phase 1 完成官方 Release Notes、`schemaVersions` 與衝突乾跑分析
- [x] 使用者明確核准執行 Phase 2（Go-Sign）
- [x] 不在 Mac 本機跑重型 CI（`tsgo`/`vitest`）或本機 `docker build`（全交 GitHub Actions）
- [x] 升級期間不另起 `openclaw memory index/search/reset`、`agent --local`（避免雙行程撞 Gemini 配額）
- [x] 10+ 分鐘長等待（`gh run watch`、`kubectl rollout status`）一律派給背景子代理

---

## Phase 1: 分析結果

### 1.1 官方 Release Notes 與 Schema 檢查（99 PRs）

- **Breaking changes**：無。
- **schemaVersions**：`state: 22`、`agent: 27`，與 `v2026.11.3` **完全相同** → **無不可逆 migration**，可直接回退 image。
- **Runtime / 依賴**：`engines.node` 不變（`>=24.16.0 <25 || >=26.1.0`）；`@openclaw/fs-safe` `0.26.5 → 0.26.7`。
- **Dockerfile / docker/**：上游本次無變更。
- **重點更新**：
  - 大型對話與記憶匯出改為串流處理（`streamSessionEntry` / `prepareSessionIndexSource`）並以 `Float64Array` 暫存 publication 向量，防止 worker OOM。
  - 大型 store 啟動時先啟動 plugins 再掃描 active orphan，不載入無關歷史摘要。
  - Gateway 重啟保留未完成回覆；Telegram 投遞無法確認時發送不確定通知；Telegram inline button 點擊正確路由。
  - Gemini 非字串 tool schema 省略 `enum`，修正 boolean 參數相容性。

### 1.2 自訂 Patch 清單（由 `upstream-v2026.11.3..my-config-v2026.11.3` 移植）

- `605cf3c8f06`：精簡 Matrix `.github/workflows/docker-release.yml`（並清除其餘官方 workflows）
- `2fe158be6d6`（原 `743a32579ed`）：Dockerfile 自訂層（locale、rsync、tini、faster-whisper、edge-tts、ffmpeg、openssh-server）+ Gemini 限速 `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 4200` + Gemini index concurrency = 1
- `d442939fd66`（原 `c107ec620a1`）：`assets/whisper`、`docker/entrypoint-ssh.sh`、`TODO-docker-build-rsync-utf8.md`
- `403fa5afb14`（原 `1f2edb73c27`）：CJK bigram companion FTS 索引（17 檔）
- `652dab92b65`（原 `e5af37ef4c4`）：`docs/reference/memory-config.md` CJK bigram 文件
- `58c1af585bb`：歷史升級工作表（`docs/worksheet-upgrade-openclaw-v2026.*.md`）

### 1.3 衝突風險評估（`git merge-tree` 乾跑驗證）

| 檔案                                                                         | 上游是否也改                  | 乾跑結果           | 處置                                                                           |
| :--------------------------------------------------------------------------- | :---------------------------- | :----------------- | :----------------------------------------------------------------------------- |
| `.github/workflows/*`（74 檔）                                               | 是                            | modify/delete      | 預期；於 Step 2.3 直接刪除並覆蓋為我們的 Matrix `docker-release.yml`           |
| `extensions/memory-core/src/memory/manager-embedding-ops.ts`                 | 是（L600+ 串流 session 匯出） | **自動無衝突合併** | Cherry-pick 後人工檢視 `resolveIndexConcurrency`（L474）與 `prepareIndexEntry` |
| 其餘所有自訂檔（含 CJK bigram 18 檔、`Dockerfile`、`embedding-provider.ts`） | 否（0 變更）                  | 零衝突             | 直接依序 `git cherry-pick`                                                     |

### 1.4 Memory Embedding 重建判斷

- `extensions/google/embedding-provider.ts` 未變、模型未變、`schemaVersions` 未變。
- `session-files.ts` 串流重構具等價性測試保證（`manager-session-export-equivalence.test.ts`），chunk hash 不變。
- **預設不重建索引、不 reset cache**；部署後觀察 Gateway log 確認無意外全量 reindex 與無 `RESOURCE_EXHAUSTED`。

---

## Phase 2: 執行步驟（取得 Go-Sign 後）

### 2.1 備份與基線確認

- [x] 確認 `git status -sb` 乾淨
- [x] 建立本地分支備份：`git branch -f backup/my-config-v2026.11.3 origin/my-config-v2026.11.3`
- [x] 確認 `git rev-parse upstream-v2026.11.4^{commit}` = `d843d6af39a42cd3c30084edbeabeece732fd93a`
- [x] 盤點 N100 既有備份（`/root/backup-openclaw-20261112-v2026.11.3` 2.4G）並建立本次執行期備份 `/root/backup-openclaw-20261116-v2026.11.4`（2.4G，僅備份 `/data/services/openclaw/.openclaw/`）

### 2.2 建立新分支

- [x] `git checkout -b my-config-v2026.11.4 upstream-v2026.11.4`

### 2.3 Purge 官方 Workflows 並覆蓋 Matrix `docker-release.yml`

- [x] `find .github/workflows -type f ! -name 'docker-release.yml' -delete`
- [x] `git checkout origin/my-config-v2026.11.3 -- .github/workflows/docker-release.yml`
- [x] `git add .github/workflows && git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"`（`605cf3c8f06`）

### 2.4 移植自訂 Commits 與歷史工作表

- [x] `git cherry-pick 743a32579ed c107ec620a1 1f2edb73c27 e5af37ef4c4`（零衝突完成）
- [x] 檢視 `extensions/memory-core/src/memory/manager-embedding-ops.ts` 合併結果（`provider?.id === "gemini"` 併發=1 完整保留，上游 L600+ 串流匯出無衝突）
- [x] 從 `origin/my-config-v2026.11.3` 檢出 `docs/worksheet-upgrade-openclaw-v2026.*.md` 歷史工作表並 commit（`58c1af585bb`）
- [x] 驗證自訂層：`git grep -q 'Custom: Install faster-whisper' HEAD -- Dockerfile`
- [x] 驗證 Gemini 限速：`git grep -n MIN_GEMINI_EMBEDDING_INTERVAL_MS HEAD -- extensions/google/embedding-provider.ts`（L219, L298）
- [x] 驗證 `assets/whisper`、`docker/entrypoint-ssh.sh` 存在且具執行權限

### 2.5 本地輕量驗證（嚴禁重型 CI / 本機 docker build）

- [x] `git status -sb`、`git diff --check`（僅既有的 `docker-release.yml` / `entrypoint-ssh.sh` 尾隨空白，無程式碼異常）
- [x] `git diff upstream-v2026.11.4 --stat -- . ':!docs' ':!.github'` 確認僅含預期 23 個自訂檔案
- [x] 確認 `.github/workflows/` 只剩 `docker-release.yml` 且僅有 `workflow_dispatch` 觸發

### 2.6 Commit Worksheet 並推送分支至 Fork (`origin`)

- [x] `git add docs/worksheet-upgrade-openclaw-v2026.11.4-20261116.md && git commit -m "docs: add v2026.11.4 upgrade worksheet"`
- [x] 確認 `origin` 為 `https://github.com/kuniakil/openclaw.git` 後執行：`git push -u origin my-config-v2026.11.4`（**不推 git tag**）

### 2.7 觸發 GHCR Matrix Build 與監控

- [x] `grep -A6 workflow_dispatch: .github/workflows/docker-release.yml` 確認 dispatch input 為 `tag`
- [x] 觸發建置：
      `gh workflow run docker-release.yml --repo kuniakil/openclaw --ref my-config-v2026.11.4 -f tag=v2026.11.4 -f platforms=all`
- [x] 驗證觸發之 Run：`event=workflow_dispatch`、`headBranch=my-config-v2026.11.4`、`headSha` 為我們的 commit（`b7688d751ec`）、Run ID: `43867859308`（`https://github.com/kuniakil/openclaw/actions/runs/43867859308`）
- [x] 無觸發 HTTP 422 Actions auto-disable
- [x] **派發背景子代理**執行 `gh run watch 43867859308 --repo kuniakil/openclaw`（`prepare`、`amd64`、`arm64`、`merge` 全部 `success`）
- [x] Build 完成後以 `docker buildx imagetools inspect` 驗證 tags：`2026.11.4`、`v2026.11.4`、`2026.11.4-slim`、`latest`、`main`（皆指向 multi-arch index `sha256:f8f267af822cd201e36d06ca4cb249ba9ebb1db294aee6cd3b1af9c1e8f36ce5`）

### 2.8 K3s 部署與滾動驗證

- [x] 更新 `~/kubernetes/openclaw/overlays/n100/kustomization.yaml` 的 `newTag` 為 `"2026.11.4"`
- [x] 執行 `kubectl apply -k ~/kubernetes/openclaw/overlays/n100`
- [x] **派發背景子代理**監控 `kubectl rollout status deployment/openclaw-gateway -n openclaw`（`successfully rolled out`）
- [x] 驗證 Pod `openclaw-gateway-694894b6b7-g5qkc` 為 `1/1 Running`（`RESTARTS 0`）、`openclaw --version` 為 `OpenClaw 2026.11.4`、自訂工具鏈（`faster-whisper 1.2.1`、`/usr/local/bin/whisper`、`/usr/local/bin/edge-tts`、`/usr/bin/ffmpeg`、`/usr/bin/rsync`、`/usr/bin/tini`、`/usr/sbin/sshd`、`/app/docker/entrypoint-ssh.sh`、`en_US.utf8`/`zh_TW.utf8`）正常
- [x] 檢查 Gateway logs：20 plugins 正常載入、Telegram `@N100_openclaw_mike_bot` 啟動輪詢，無 `RESOURCE_EXHAUSTED` (429)、無 401/403 embedding 錯誤、無意外全量 reindex，無 `rss_threshold` 警告

---

## Phase 3: 收尾與清理

- [x] 更新並 commit/push 本工作表完成狀態（含 `~/kubernetes` repo 的 image tag 變更）
- [x] 完成 Telegram 實機升級後檢查（`openclaw-upgrade-check` A–K 16 項全數通過；memory chunks 1434→1459 增量同步且 `fts == cjk_fts == 1459`；0 429、0 reindex、cgroup 2.03–2.14 GiB）
- [x] 依使用者指示刪除舊備份 `/root/backup-openclaw-20261112-v2026.11.3`（2.4G），保留本次備份 `/root/backup-openclaw-20261116-v2026.11.4`（2.4G；N100 `/` 剩餘 `1.1T` / `36%` used）
- [x] 升級後設定修復與環境清理：
  - 備份 `openclaw.json` 至 `openclaw.json.bak-20261116-m31`，將 `agents.defaults.model.primary` 與 `agents.entries.main.model` 切換為 `minimax/MiniMax-M3.1-Flash-Preview`（保留 `minimax/MiniMax-M3`），移除將於 2026-11-18 下架的 `M2.5`/`M2.5-Highspeed`/`M2.7`
  - 透過 `openclaw cron edit` 綁定 `Memory Dreaming Promotion`（`c870fbf5-4d9b-4773-8e51-eef8c62beaad`）至 `minimax/MiniMax-M3.1-Flash-Preview@minimax:default`（寫入 `inferenceBinding`）
  - 刪除舊隔離目錄 `agent.legacy-1788937203594` 與舊手機 session `agent:main:node-57c547526410`
  - 短暫縮容 Gateway 至 0 啟動 `openclaw-maintenance` Pod 執行 `openclaw doctor --fix --non-interactive --yes`（正規化 1 筆 legacy session delivery 欄位並更新 4 個內建 plugins 至 `2026.11.4`），並清除 3 筆 142–145 天前失敗的 Telegram dead-letters
  - 恢復上線後新 Pod `openclaw-gateway-694894b6b7-f864f` 為 `1/1 Running`（`RESTARTS 0`），日誌確認 `agent model: minimax/MiniMax-M3.1-Flash-Preview (thinking=max, fast=off)`，Doctor 複驗與 dead-letters 清零通過，同步更新至 `/root/backup-openclaw-20261116-v2026.11.4`

## 回滾預案（Rollback Plan）

- 本次 `schemaVersions` 未變（`state: 22 / agent: 27`）→ 若新版異常，直接將 `~/kubernetes/openclaw/overlays/n100/kustomization.yaml` 的 `newTag` 改回 `"2026.11.3"` 並執行 `kubectl apply -k ~/kubernetes/openclaw/overlays/n100` 即可無損回退（亦有 `/root/backup-openclaw-20261116-v2026.11.4` 2.4G 完整 `.openclaw/` 備份兜底）。
