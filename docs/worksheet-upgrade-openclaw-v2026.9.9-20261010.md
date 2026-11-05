# Upgrade Worksheet: openclaw → v2026.9.9

**Date:** 2026-10-10
**Current branch:** `my-config-v2026.9.8` (HEAD `32880e2e615`)
**Current tag:** `v2026.9.8`（本地/origin tag 已 force 指向自訂 commit `35791302bb8`；官方原 SHA `fc23bc864e45`）
**Target tag:** `v2026.9.9`（官方 release SHA `bcfc88812a35243893585dbeca87ca41b48272ca`，本地 fetch 後 `git rev-parse` 一致）
**New branch:** `my-config-v2026.9.9`

> [!IMPORTANT]
> 本地 `v2026.9.8` 是自訂 tag。所有「官方差異」比對必須用官方 SHA `fc23bc864e45`，不可用本地 tag，否則會把我們的自訂 commit 誤判為官方變更。

---

## 📋 Phase 1: Pre-Upgrade Analysis（已完成）

### 1.1 版本差異概覽（官方 `fc23bc864e45` → `v2026.9.9`）

| 項目                                   | v2026.9.8 | v2026.9.9                                                  |
| -------------------------------------- | --------- | ---------------------------------------------------------- |
| 官方 commits                           | —         | 185 commits / 112 PRs（1111 files，規模遠大於 9.8 hotfix） |
| package.json version                   | 2026.9.8  | 2026.9.9                                                   |
| `@modelcontextprotocol/sdk`            | 1.30.0    | 1.31.0                                                     |
| Node engine / schemaVersions           | —         | **未變**                                                   |
| Dockerfile / docker/                   | —         | **官方無變更** ✅                                          |
| `.github/workflows/docker-release.yml` | —         | 官方有改（+33 行）→ 依 SOP 一律丟棄，用我們的 Matrix 版    |
| pnpm-lock.yaml                         | —         | 有變更（跟隨 package.json）                                |

### 1.2 官方 Release Notes 審查（CHANGELOG/2026.9.9.md）

Release: https://github.com/openclaw/openclaw/releases/tag/v2026.9.9

#### Breaking Changes

- 無明列。

#### Deprecations

- 無新增。

#### Dependency / Runtime Bumps

- MCP SDK 1.30.0 → 1.31.0。無 Node / base image 變更。

#### 新功能

- Codex 模型清單新增 GPT-6.1 Sol；Anthropic / Claude CLI 支援 Claude Haiku 5.5。
- 修正 iMessage 漏回、舊排程 job 打斷新對話。
- Web UI：聊天捲動、對話標題重試、channel 對話歷史關聯等修正。

#### 升級 / 維運相關（⭐ 與 K3s 部署相關）

- ⭐ **Docker startup (#162305)**：修復舊 Linux host 上反覆拒絕未變動 DB 的升級迴圈；重試重用已驗證的 rollback backup。
- ⭐ **FUSE 儲存備份**：mtime 變動不再導致備份/還原失敗（若 PVC 為 NFS/FUSE 類有利）。
- ⭐ **Older memory databases**：Doctor 可完成舊 memory cache 升級，跳過過大/損毀 entry 並警告。官方建議 **DB 升級前停止使用該 DB 的程序並做已驗證備份**。
- ⭐ Failed-update recovery、Doctor 維護進度/Ctrl+C、session archive repair：Doctor 修復 session archive 後 **rollback 不會還原已提交的 archive 變更**。
- Windows / pnpm / npm 更新修復（不影響 Linux Docker）。

#### Known Issues / Caveats

- 無需手動 DB migration；schemaVersions 未變。但 Doctor 可能在啟動/升級時處理舊資料 → **部署前備份 PVC**。
- Telegram 整合檢查本次被 release owner waive（未跑）→ 部署後需手動冒煙測試（若有使用）。
- Android APK 跳過（與我們無關）。

### 1.3 自訂 Patch 清單（需移植）

| Commit                   | 內容                                                                                                                                                                                         |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| （重做，不 cherry-pick） | purge 官方 workflows + 覆蓋精簡 Matrix `docker-release.yml`（來源 `my-config-v2026.9.8`）                                                                                                    |
| `8c4c1a10734`            | v2026.9.7 升級：Dockerfile 自訂層、rate pacing（`extensions/google/embedding-provider.ts`、`extensions/memory-core/src/memory/manager-embedding-ops.ts`）、`TODO-docker-build-rsync-utf8.md` |
| `8c1fb861b18`            | 補回 `assets/whisper`、`docker/entrypoint-ssh.sh`                                                                                                                                            |
| （不移植）               | 先前 worksheet / CI run 記錄等 docs commits（本檔取代）                                                                                                                                      |

> 實際 cherry-pick 前先 `git log --oneline fc23bc864e45..HEAD -- . ':!docs' ':!.github'` 確認清單。

### 1.4 衝突風險評估

自訂檔案（vs 官方 9.8，排除 docs/.github）與官方 9.8→9.9 變更檔案的交集：**0 個檔案**（`comm -12` 比對）。

| 風險                                     | 等級    | 說明 / 對策                          |
| ---------------------------------------- | ------- | ------------------------------------ |
| cherry-pick 衝突                         | 🟢 極低 | 無重疊；Dockerfile 官方未動          |
| Rate pacing 語意衝突                     | 🟢 低   | 兩支檔案官方未改；cherry-pick 後確認 |
| 官方 docker-release.yml 變動             | 🟢 無   | 一律覆蓋為我們的版本                 |
| pnpm-lock / MCP SDK bump                 | 🟢 低   | 由 CI build 驗證                     |
| Doctor/DB 升級資料風險                   | 🟡 中   | 部署前備份 PVC；停舊 Pod 再起新 Pod  |
| Gateway lock 卡 rolling update（承 9.8） | 🟡 中   | 確認 Deployment `strategy: Recreate` |
| Telegram 未經官方驗證                    | 🟡 低   | 部署後手動冒煙                       |

---

## 🚀 Phase 2: 執行步驟（⛔ 等待使用者 Go）

### Step 1: 確認 tag

- [x] `git rev-parse v2026.9.9^{commit}` = `bcfc88812a35…`（已預檢通過）
- [x] 保存本地自訂 `v2026.9.8` 備份：`git tag upstream-v2026.9.8 fc23bc864e45`（供比對）

### Step 2: 建立新分支

```bash
git checkout v2026.9.9
git checkout -b my-config-v2026.9.9
```

- [x] HEAD = `bcfc88812a3`

### Step 3: 清除官方 CI Workflows，覆蓋 docker-release.yml

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.9.8 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [x] `.github/workflows/` 只剩 `docker-release.yml`
- [x] `git diff my-config-v2026.9.8 -- .github/workflows` 為空

### Step 4: 移植自訂 patch

```bash
git cherry-pick 8c4c1a10734 8c1fb861b18
```

- [x] Dockerfile：locale (en_US / zh_TW)、rsync、faster-whisper、edge-tts、ffmpeg、PYTHONPATH、openssh-server、`entrypoint-ssh.sh` COPY、tini、官方 ENTRYPOINT 保留
- [x] `assets/whisper`、`docker/entrypoint-ssh.sh` 存在
- [x] rate pacing patch 存在
- [x] 成功 cherry-pick 補回所有自訂修改

### Step 5: 本地輕量驗證（禁止 docker build / tsgo / vitest）

```bash
git status
git diff --check v2026.9.9..HEAD
grep -nE "zh_TW|faster-whisper|openssh|tini|edge-tts" Dockerfile
git diff --stat v2026.9.9..HEAD -- . ':!.github'
```

- [x] 工作區乾淨、自訂差異僅含預期 6 個檔案（Dockerfile, TODO, assets/whisper, docker/entrypoint-ssh.sh, extensions 兩處）

### Step 6: 加入 worksheet 並 push 分支

```bash
git add docs/worksheet-upgrade-openclaw-v2026.9.9-20261010.md
git commit -m "docs: add v2026.9.9 upgrade worksheet"
git push origin my-config-v2026.9.9
```

- [x] Push 成功

### Step 7: 觸發 Docker CI Build（再次確認）

```bash
git tag -f v2026.9.9
git push -f origin v2026.9.9
gh workflow run docker-release.yml --repo kuniakil/openclaw --ref my-config-v2026.9.9 -f tag=v2026.9.9 -f platforms=all
```

- [x] CI 觸發：[Run 38007217524](https://github.com/kuniakil/openclaw/actions/runs/38007217524)
- [x] 建置綠燈（amd64 & arm64 merge 成功，耗時 ~12m）
- [x] `ghcr.io/kuniakil/openclaw:2026.9.9` 可 pull（amd64/arm64 multi-arch）

---

## ✅ Phase 3: Post-Upgrade

- [x] K3s 更新 image tag / 手動 pull 最新 Docker image 測試成功
- [x] Gateway 正常啟動（Pod `c7564964d-s8tdr` 1/1 Running, 0 restarts）
- [x] Mac node app 同步更新至 2026.9.9 (build 2609000990)
- [x] 關鍵健康檢查與 Smoke Test 結果記錄：
  - `Pod status`：✅ 1/1 Running，0 restarts
  - `K3s nodes`：✅ n100 Ready 108d (v1.37.1+k3s1)
  - `Companion nodes`：✅ Mac (22h ago) 與 POCO (10m ago) 皆在線
  - `/healthz endpoint`：✅ HTTP 200（56ms）
  - `醫療影像`：✅ 6 張影像全部 1.2MB 完好保留
  - `醫療記憶檔`：✅ 結構完整，無損毀
- [x] 觀察與注意事項記錄：
  - GHCR pull 時間較長（約 16m，與 10/03 pattern 一致，為 GHCR CDN reset retry 所致）
  - 啟動時 liveness probe 失敗 1 次後即進入穩定 HTTP 200
  - `/home/node/.openclaw/bin/openclaw` symlink 失效，但不影響 PATH 執行（`openclaw nodes list` 等正常）
- [ ] 清理本地暫存 tag（`upstream-v2026.9.8`）
- [ ] Session wrap-up 發布至 WordPress KB

---

## 📌 參考連結

- Release: https://github.com/openclaw/openclaw/releases/tag/v2026.9.9
- Release notes: https://docs.openclaw.ai/releases/2026.9.9
- CHANGELOG: https://raw.githubusercontent.com/openclaw/openclaw/main/CHANGELOG/2026.9.9.md
- npm: https://www.npmjs.com/package/openclaw/v/2026.9.9
