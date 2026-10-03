# Upgrade Worksheet: openclaw → v2026.9.8

**Date:** 2026-10-03  
**Operator:** kuniakil  
**Current branch:** `my-config-v2026.9.7` (HEAD `71c63583a87`)  
**Current tag:** `v2026.9.7`（本地/origin tag 已 force 指向自訂 commit `e412c398a1d`；官方原 tag 暫存為本地 `upstream-v2026.9.7`）  
**Target tag:** `v2026.9.8`（release SHA `fc23bc864e4553c2d215e479eeec47b67a0bf943`，已驗證與 tag 一致）  
**New branch:** `my-config-v2026.9.8`

---

## 📋 Phase 1: Pre-Upgrade Analysis（已完成）

### 1.1 版本差異概覽

| 項目                       | 現在 (v2026.9.7)                             | 目標 (v2026.9.8)                                              |
| -------------------------- | -------------------------------------------- | ------------------------------------------------------------- |
| 官方 commits               | —                                            | 58 commits / 43 PRs（純 hotfix）                              |
| package.json version       | 2026.9.7                                     | 2026.9.8                                                      |
| Node engine / pnpm         | 未變                                         | 未變                                                          |
| Dockerfile（官方）         | —                                            | **無變更** ✅                                                 |
| ENTRYPOINT                 | `tini -s -- node /app/docker-entrypoint.mjs` | 未變                                                          |
| DB schema（state / agent） | 19 / 24                                      | **未變**（diff 中無 SCHEMA_VERSION 變動）                     |
| package.json scripts       | —                                            | 新增 `release:clawhub-recovery`（release 用，不影響 runtime） |
| 主要變動目錄               | —                                            | extensions 30.6%、src/gateway 10.8%、src/agents 8%            |

### 1.2 官方 Release Notes 審查（CHANGELOG/2026.9.8.md）

> [!NOTE]
> 官方明示：**"No intentional capability changes; this release is a focused reliability and recovery hotfix."**

#### Breaking Changes

- 無。

#### Deprecations

- 無新增。（v2026.9.7 標記的 2026-10-01 SDK deprecation 仍適用；我們是純 runtime 映像，不受影響。）

#### Dependency / Runtime Bumps

- 無 Node/Bun/base image 變更。部分 extension `package.json` 依賴小幅更新（google、memory-core、memory-lancedb、memory-wiki）。

#### 重要修復（與我們 K3s 部署相關者標 ⭐）

- ⭐ **Gateway 容器單一擁有者啟動 (#160193)**：`startGatewayServer` 現在一律先 `acquireGatewayLock`（lock timeout 5 分鐘）。若 K3s Deployment 用 `RollingUpdate` + 共用 PVC，新 Pod 可能等舊 Pod 釋放 lock 才會起來。
- ⭐ Update/Doctor 安全性：保留 plugin 設定、SQLite 短暫 contention 容錯、大規模 Doctor 修復有界 (#160344, #160702, #160718, #161832, #162290, #162321, #162394)
- ⭐ Managed-proxy TLS health probe 修復 (#161946)
- ⭐ Anthropic 背景 Bash 完成後 turn 不再卡住 (#161260)
- ⭐ Sandbox read-only skill refresh 不再 EACCES (#160137)
- Codex Computer Use / session discovery heap 修復 (#162467, #162912)
- Telegram preview writer-authority 重檢 (#162304)
- Windows 相關（不影響 Linux Docker）：cron/session proxy、compile-cache 路徑、2026.9.4 schema 轉換保護

#### Known Issues / Caveats

- 無需手動 DB migration。
- 官方 Telegram 整合檢查本次被 waive（未跑）——若我們有使用 Telegram channel，部署後需自行冒煙測試。

### 1.3 我們的自訂 Patch 清單（需移植）

| Commit        | 內容                                                                                                                                                                                                                                     |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `383a4b33010` | purge 官方 workflows + 精簡 Matrix `docker-release.yml`（以 SOP 指令重做，不 cherry-pick）                                                                                                                                               |
| `97e272705a1` | Dockerfile 自訂層（locale/rsync/faster-whisper/edge-tts/ffmpeg/openssh/tini）、rate pacing（`extensions/google/embedding-provider.ts`、`extensions/memory-core/src/memory/manager-embedding-ops.ts`）、`TODO-docker-build-rsync-utf8.md` |
| `e412c398a1d` | 補回 `assets/whisper`、`docker/entrypoint-ssh.sh`                                                                                                                                                                                        |
| （不移植）    | v2026.9.7 worksheet 文件 commits（`c3183b4348e`、`e3277eef1f9`、`71c63583a87`）                                                                                                                                                          |

### 1.4 衝突風險評估

自訂檔案 vs. 官方 v2026.9.7→v2026.9.8 變更檔案的交集：**0 個檔案**（已用 `comm -12` 比對）。

| 風險                                  | 等級    | 說明 / 對策                                                          |
| ------------------------------------- | ------- | -------------------------------------------------------------------- |
| cherry-pick 衝突                      | 🟢 極低 | 無重疊檔案；Dockerfile 官方未動                                      |
| Rate pacing patch 語意衝突            | 🟢 低   | 兩支檔案官方未修改；僅 extension package.json 依賴小改               |
| Gateway lock 造成 rolling update 卡住 | 🟡 中   | 確認 K3s Deployment `strategy: Recreate`（或單副本 + 舊 Pod 先終止） |
| Schema migration                      | 🟢 無   | 無 schema 版本變更                                                   |
| Telegram 未經官方驗證                 | 🟡 低   | 部署後手動冒煙（若有使用）                                           |

---

## 🚀 Phase 2: 執行步驟（等待 Go）

### Step 1: 確認 tag

- [x] `git fetch upstream refs/tags/v2026.9.8:refs/tags/v2026.9.8`
- [x] `git rev-parse v2026.9.8^{commit}` = `fc23bc864e45…`（與官方 release SHA 一致）

### Step 2: 建立新分支 from 官方 tag

```bash
git checkout v2026.9.8
git checkout -b my-config-v2026.9.8
```

- [x] HEAD 指向 `fc23bc864e4`

### Step 3: 清除官方 CI Workflows，覆蓋精簡 docker-release.yml

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.9.7 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [x] `.github/workflows/` 只剩 `docker-release.yml`
- [x] 內容與 `my-config-v2026.9.7` 版本一致（`git diff my-config-v2026.9.7 -- .github/workflows` 為空）

### Step 4: 移植自訂 patch

```bash
git cherry-pick 97e272705a1 e412c398a1d
```

- [x] 無衝突
- [x] Dockerfile：locale (en_US / zh_TW)、rsync、faster-whisper、edge-tts、ffmpeg、PYTHONPATH、openssh-server、`entrypoint-ssh.sh` COPY、官方 ENTRYPOINT 保留
- [x] `assets/whisper`、`docker/entrypoint-ssh.sh` 存在
- [x] rate pacing patch 存在（google embedding provider / memory-core embedding ops）
- [x] commit message 版本字樣更新為 v2026.9.8

### Step 5: 本地輕量驗證（禁止 docker build / tsgo / vitest）

```bash
git status
git log --oneline -5
git diff --check v2026.9.8..HEAD
grep -nE "zh_TW|faster-whisper|openssh|tini|edge-tts" Dockerfile
git diff --stat v2026.9.8..HEAD -- . ':!.github'
```

- [x] 工作區乾淨
- [x] 自訂差異只包含預期檔案（6 files changed）

### Step 6: 加入本 worksheet 並 Push 分支

```bash
git add docs/worksheet-upgrade-openclaw-v2026.9.8-20261003.md
git commit -m "docs: add v2026.9.8 upgrade worksheet"
git push origin my-config-v2026.9.8
```

- [x] Push 成功

### Step 7: 觸發 Docker CI Build（需使用者確認）

```bash
git tag -f v2026.9.8
git push -f origin v2026.9.8
gh workflow run docker-release.yml --repo kuniakil/openclaw --ref my-config-v2026.9.8 -f tag=v2026.9.8 -f platforms=all
```

- [x] GitHub Actions CI 已觸發：[Run 37120581501](https://github.com/kuniakil/openclaw/actions/runs/37120581501)
- [x] CI 建置完成（綠燈，amd64 & arm64 multi-arch 合併成功）
- [x] `ghcr.io/kuniakil/openclaw:2026.9.8` 可 pull

---

## ✅ Phase 3: Post-Upgrade

- [x] K3s 更新 image tag / 手動 pull 最新 Docker image 測試成功
- [x] Gateway 正常啟動，各項工具鏈與核心功能 smoke test 正常
- [x] 關鍵 Toolchain Smoke Test 結果記錄：
  - `exec`：✅ 跑 `ls` / `date` 正常
  - `openclaw CLI`：✅ `openclaw nodes list` 印出連線 node 正常
  - `nodes (invoke API)`：✅ Mac + POCO 連線與 API 調用正常
  - `view_image`：✅ 正常（先前為 `/tmp` 容器暫存圖被清理造成的路徑假警報，早先已實證載入成功）
  - `write / read / catalog`：✅ 寫入 SKILL.md、讀取 Dify 文件正常
  - `web_fetch / web_search`：✅ Dify KB、Twitter 等網路搜尋與抓取正常
  - `tts`：✅ 語音合成輸出正常
- [x] 清理本地暫存 tag：`git tag -d upstream-v2026.9.7 release-publish/7a438dc93ec0-1790883042`
- [x] Worksheet 全部驗證項目標記完成
- [ ] Session wrap-up 發布至 WordPress KB

---

## 📌 參考連結

- 官方 Release: https://github.com/openclaw/openclaw/releases/tag/v2026.9.8
- 官方 Release notes: https://docs.openclaw.ai/releases/2026.9.8
- CHANGELOG: `git show v2026.9.8:CHANGELOG/2026.9.8.md`
- npm: https://www.npmjs.com/package/openclaw/v/2026.9.8
