# Upgrade Worksheet: openclaw → v2026.9.7

**Date:** 2026-09-30  
**Operator:** kuniakil  
**Current branch:** `my-config-v2026.9.6`  
**Current tag:** `v2026.9.6`  
**Target tag:** `v2026.9.7` (官方 Latest, 約 6 小時前發布)  
**New branch:** `my-config-v2026.9.7`

---

## 📋 Phase 1: Pre-Upgrade Analysis

### 1.1 版本差異概覽（已確認 diff）

| 項目                           | 現在 (v2026.9.6)                        | 目標 (v2026.9.7)                                                    |
| ------------------------------ | --------------------------------------- | ------------------------------------------------------------------- |
| 官方 tag                       | v2026.9.6                               | **v2026.9.7**                                                       |
| package.json version           | 2026.9.6                                | 2026.9.7                                                            |
| Node engine                    | >=24.16.0 <25 \|\| >=26.1.0             | 同左（未變）                                                        |
| `node:24-bookworm` digest      | `sha256:934240a1...`                    | **`sha256:64af3819...`** ✅ 更新                                    |
| `node:24-bookworm-slim` digest | `sha256:3638d9a6...`                    | **`sha256:0e0ff40c...`** ✅ 更新                                    |
| Bun image                      | `oven/bun:1.4.0`                        | **`oven/bun:1.4.2`** ✅ 更新                                        |
| 新增檔案 COPY                  | —                                       | `node-compile-cache.mjs`, `docker-entrypoint.mjs`                   |
| 刪除檔案 COPY                  | `scripts/lib/guard-inventory-utils.mjs` | → `scripts/lib/javascript-statements.mjs`                           |
| `ENTRYPOINT`                   | `["tini", "-s", "--"]`                  | **`["tini", "-s", "--", "node", "/app/docker-entrypoint.mjs"]`** ⚠️ |
| DB schema: state               | 18                                      | **19**                                                              |
| DB schema: agent               | 23                                      | **24**                                                              |
| `updateAdmissionProtocol`      | —                                       | 新增 `1`                                                            |

---

### 1.1.1 ENTRYPOINT 變更分析（已確認無實際衝突）

> [!NOTE]
> **`ENTRYPOINT` 在 v2026.9.7 中加入了 `node /app/docker-entrypoint.mjs`。**
>
> - **官方新版**：`ENTRYPOINT ["tini", "-s", "--", "node", "/app/docker-entrypoint.mjs"]`
> - **`docker-entrypoint.mjs` 作用**：容器啟動時執行 unattended retained-volume repair，然後 exec 後續 CMD
> - **我們的 `entrypoint-ssh.sh`**：純 SSH setup script（**無 `exec "$@"` 行**），不作為 ENTRYPOINT 使用；是 COPY 進去後由 Zeabur platform 手動呼叫的備用腳本
>
> **✅ 結論：無實際衝突。接受官方新 ENTRYPOINT，繼續 COPY `entrypoint-ssh.sh` 備用即可。**

---

### 1.2 官方 v2026.9.7 Highlights（Breaking Changes / 重要新功能）

> [!NOTE]
> 此版本重點在穩定性與性能修復，**無重大 breaking schema 變更**。

#### 🆕 重要新功能

- **OpenAI Agents API 插件**：支援 OpenAI-hosted 或 self-hosted 環境，串流回覆、工具整合
- **Sign in with ChatGPT (Beta)**：新增 SIWC 認證方式
- **更新安全性 (Update Safety)**：更新前自動備份所有 state/agent DB，rollback 時自動還原
- **Gateway 回應性大幅提升**：transcript writes、history 準備、artifact 讀取等移至 off-thread
- **Native Apple Chat 增強**：macOS/iOS 顯示訊息時間、模型資訊、接受附件
- **Claude Sonnet 5.5 支援**
- **Kie AI / Z.AI / Novita 影片生成提供者**
- **Config `${VAR:-default}` 語法支援**
- **Docker 更新速度優化**：OverlayFS 安裝更新更快

#### 🐛 與 Docker 相關的重要修復

- **`v2026.9.6` 升級後 Doctor plugin captures read-only 問題已修復** (#160446)
- **OverlayFS/Docker 更新不再花費數分鐘 retain 舊 runtime** (#160845)
- Bun-only 安裝：更新、repair、Chrome MCP 不再需要 Node
- 更新後不再在 npm global root 留下多餘 DB 副本
- Plugin listener settings 在 plugin 更新後存活

#### ⚠️ Known Issues（已知問題）

- **Windows 從 2026.9.6 更新**：可能以 exit code 13 無聲結束，重跑 `openclaw update` 即可（我們用 Linux Docker，**不影響**）
- **Docker update time**：更新仍可能需要數分鐘（Gateway 停止期間），已知行為

---

### 1.3 Upcoming Deprecations（即將移除，目標 2026-10-01）

> [!WARNING]
> 這些 deprecation 在 v2026.9.7 中仍可用，但已標記移除目標日期 **2026-10-01**。
> 我們的 Docker 映像不直接使用這些 SDK 路徑，但需確認無自訂 plugin 依賴。

| 已棄用路徑                                                                           | 替換方案                                                                             |
| ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| `openclaw/plugin-sdk/config-runtime`                                                 | `api.pluginConfig`, `config-mutation`, `runtime-config-snapshot`, `config-contracts` |
| `openclaw/plugin-sdk/channel-reply-pipeline`, `channel-lifecycle`, `channel-message` | `channel-outbound`, `channel-inbound`                                                |
| `openclaw/plugin-sdk/infra-runtime`                                                  | focused subpaths: `delivery-queue-runtime`, `diagnostic-runtime`, 等                 |
| Public media-understanding & memory-host-core SDK facades                            | `api.registerMediaUnderstandingProvider(...)`                                        |
| Legacy media projection                                                              | `MsgContext.media`, `InboundMediaFacts[]`                                            |
| Channel webhook listener inputs (`webhookPort`/`webhookHost`)                        | `legacyWebhook`；Doctor 自動遷移                                                     |

**評估：我們的 Docker 映像為純 runtime 容器，不使用 plugin SDK。⟹ 風險極低。**

---

### 1.4 我們的自訂 Patch 清單（需移植）

| 自訂項目                      | 說明                                |
| ----------------------------- | ----------------------------------- |
| UTF-8 locale (en_US / zh_TW)  | `locales` 安裝 + locale-gen         |
| `rsync` 安裝                  | 與 locale 同一 RUN 層               |
| `faster-whisper` + Python pip | `/usr/local/lib/faster-whisper`     |
| `edge-tts`                    | `/home/node/.openclaw/edge-tts-lib` |
| `ffmpeg`                      | apt-get install                     |
| `PYTHONPATH` ENV              | `/usr/local/lib/faster-whisper`     |
| `openssh-server`              | SSH 遠端接入                        |
| `entrypoint-ssh.sh` COPY      | COPY script                         |
| `tini` ENTRYPOINT             | `tini -s --`                        |

---

### 1.5 Dockerfile diff 確認（upstream fetch 完成後）

```bash
# 確認 v2026.9.7 tag 在本地
git tag --sort=-version:refname | grep v2026.9.7

# Dockerfile diff
git diff v2026.9.6..v2026.9.7 -- Dockerfile

# package.json diff（確認 engines / base image digest）
git diff v2026.9.6..v2026.9.7 -- package.json

# workflow diff
git diff v2026.9.6..v2026.9.7 -- .github/workflows/ --stat
```

---

## 🚀 Phase 2: 執行步驟（已完成並觸發 CI）

### Step 1: 確認 upstream fetch 完成並有 v2026.9.7 tag

- [x] `git fetch upstream --tags`
- [x] `git tag | grep v2026.9.7` → 確認 tag 存在

### Step 2: 建立新分支 from 官方 tag

```bash
git checkout v2026.9.7
git checkout -b my-config-v2026.9.7
```

- [x] 確認 HEAD 指向 v2026.9.7

### Step 3: 清除官方 CI Workflows，保留我們的 docker-release.yml

```bash
find .github/workflows -type f ! -name 'docker-release.yml' -delete
git checkout my-config-v2026.9.6 -- .github/workflows/docker-release.yml
git add .github/workflows
git commit -m "chore: purge official CI workflows; use optimized matrix docker-release.yml"
```

- [x] 確認 `.github/workflows/` 只剩 `docker-release.yml`
- [x] 確認 docker-release.yml 內容是我們的精簡 Matrix 版本

### Step 4: 移植自訂 Dockerfile patch

```bash
git cherry-pick 9c5c205aea9
```

- [x] 確認 locale (en_US / zh_TW) 存在
- [x] 確認 rsync 安裝
- [x] 確認 faster-whisper / edge-tts / ffmpeg 層
- [x] 確認 openssh-server + entrypoint-ssh.sh
- [x] 確認 tini ENTRYPOINT (對齊官方 docker-entrypoint.mjs)
- [x] 確認 PYTHONPATH ENV 設定
- [x] 確認 rate pacing patch (google embedding provider & memory-ops)

### Step 5: 更新版本引用（commit message 中 9.6 → 9.7）

- [x] commit message / docs 版本引用已更新

### Step 6: 本地輕量驗證（禁止跑 Docker build 或 tsgo）

```bash
git status
git log --oneline -5
grep -n "zh_TW\|faster-whisper\|openssh\|tini" Dockerfile
```

- [x] git status 乾淨
- [x] Dockerfile 自訂 patch 完整
- [x] `git diff --check` 無空白錯誤

### Step 7: Push 分支到 origin

```bash
git push origin my-config-v2026.9.7
```

- [x] Push 成功，GitHub 可見新分支

### Step 8: 觸發 Docker CI Build

```bash
git tag -f v2026.9.7
git push -f origin v2026.9.7
gh workflow run docker-release.yml --repo kuniakil/openclaw --ref my-config-v2026.9.7 -f tag=v2026.9.7 -f platforms=all
```

- [x] GitHub Actions `docker-release.yml` 成功觸發 ([Run 36710788257](https://github.com/kuniakil/openclaw/actions/runs/36710788257))
- [ ] 等待 CI build 完成：`ghcr.io/kuniakil/openclaw:2026.9.7`

---

- [x] GitHub Actions CI build 成功（綠燈）([Run 36711253135](https://github.com/kuniakil/openclaw/actions/runs/36711253135))
- [x] Docker image 在 GHCR 可 pull：`docker pull ghcr.io/kuniakil/openclaw:2026.9.7`
- [x] K3s 集群更新 deployment image tag
- [x] Gateway 正常啟動，`openclaw doctor` 遷移成功 (Schema 23 -> 24 / State 18 -> 19)
- [x] STT (faster-whisper) / TTS (edge-tts) 功能與 binary 完整存在
- [x] SSH 接入 (sshd / tini / rsync) 正常
- [x] 將此 worksheet 完成項目標記 [x]
- [ ] 發布 session wrap-up 至 WordPress KB

---

## ⚠️ 風險評估

| 風險                              | 等級      | 說明                                                   |
| --------------------------------- | --------- | ------------------------------------------------------ |
| Dockerfile base image digest 更新 | 🟡 低     | node:24-bookworm digest 可能改變，需重新固定           |
| 自訂 patch cherry-pick 衝突       | 🟡 低     | v2026.9.7 修復集中在 JS runtime，Dockerfile 底層變動少 |
| Deprecation SDK 路徑影響          | 🟢 極低   | 我們是純 runtime Docker，不依賴 plugin-sdk             |
| Windows exit-code 13 更新問題     | 🟢 不適用 | 我們使用 Linux Docker                                  |
| Gateway DB migration              | 🟢 低     | 官方未提及 schema 破壞性變更                           |

---

## 📌 參考連結

- 官方 Release: https://github.com/openclaw/openclaw/releases/tag/v2026.9.7
- 官方 CHANGELOG: https://github.com/openclaw/openclaw/blob/v2026.9.7/CHANGELOG/records/2026.9.7.md
- 本次 release CI SHA: `c074824a27c96d3983043f9eeb33823cd1772d8c`
- npm 包: https://www.npmjs.com/package/openclaw/v/2026.9.7
