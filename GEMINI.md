# OpenClaw 升級原則與標準作業程序 (SOP)

為了確保 OpenClaw 的個人 Fork 既能緊跟官方 (upstream) 更新，又能確保個人自定義配置的安全與整潔，請遵循以下原則：

## 1. 核心原則
- **退可守**：在大規模升級（Rebase）前，必須建立備份分支（Checkpoint）。
- **對齊官方 Release**：升級必須以官方的 Release Tag（如 `v2026.4.27`）作為基準，而非直接對齊主分支的提交點。
- **線性歷史 (Rebase)**：使用 `rebase` 將個人修改（如 Docker Workflow 調整）重新應用在新的官方 Tag 之上，保持 Git 歷史乾淨。
- **手動觸發建置**：為了節省資源並保持 Image Registry 整潔，嚴禁透過推送 Tag 自動觸發建置。必須使用 `workflow_dispatch` 手動指定 Tag。

## 2. 升級標準流程 (Standard Upgrade Workflow)

### 第一階段：準備與備份
1. **清理環境**：刪除本地臨時備份檔（`*.backup*`）。
2. **建立檢查點**：建立備份分支，格式為 `backup/my-config-v[舊版本號]`。
   ```bash
   git branch backup/my-config-v2026.4.22
   ```

### 第二階段：同步與對齊
1. **抓取官方進度**：
   ```bash
   git fetch upstream --tags
   ```
2. **執行 Rebase**：將目前的 `main` 分支 rebase 到目標官方 Tag。
   ```bash
   git rebase v2026.4.27
   ```
   *若有衝突，由 Gemini 協助分析並解決，優先保留個人自定義邏輯。*

### 第三階段：同步遠端與存檔
1. **強制推送主分支**：
   ```bash
   git push origin main --force
   ```
   *注意：嚴禁執行 `git push origin [Tag名稱]` 以避免觸發重複的自動工作流。*
2. **建立新版里程碑分支**：
   ```bash
   git branch my-config-v2026.4.27
   git push origin my-config-v2026.4.27
   ```

### 第四階段：觸發 Docker 建置
1. **手動觸發 Workflow**：
   ```bash
   gh workflow run docker-release.yml --repo kuniakil/openclaw -f tag=v2026.4.27
   ```
2. **監控進度**：使用 `gh run watch` 或網頁監控。

---

## 4. 關鍵部署檢查點 (Infrastructure Monitoring)
在每次進版（特別是 Rebase 之後），Gemini 應主動檢查以下內容，並提醒使用者同步更新 VPS (Zeabur) 配置：

- **Runtime 依賴處理 (Self-containment Check)**：
  - **觀察**：自 v2026.4.27 起，官方改用啟動時動態下載 Runtime (約 1GB)，導致 VPS 部署容易因網路/性能問題超時。
  - **原則**：理想的 Docker 鏡像應為「自包含」，即所有運作依賴應在編譯時包入，而非啟動後安裝。
  - **狀態**：已於 v2026.5.2 版本中回歸「官方純正鏡像」策略。
    - **效能突破**：官方於 v2026.4.30+ 修正了 Telegram typing 延遲，並將啟動修復改為 `verify-only`，解決了同步阻塞問題。
    - **配置策略**：不再自定義編譯 Image，直接使用官方 `ghcr.io/openclaw/openclaw` 鏡像。
    - **動態擴充**：透過 `.env` 的 `OPENCLAW_DOCKER_APT_PACKAGES` 安裝系統工具（Python 已被官方包回）。
    - **最終結論**：Mac 啟動時間降至 2.6s，且回話絲滑，證明「對齊官方主分支」是目前最優解。
  - **長期監控任務**：每次進版時，必須優先檢查官方 Release Notes 是否已解決已知的效能瓶頸。若官方已修復，則應移除所有自定義 Patch，保持 Fork 的純淨性。
- **環境變數與掛載點變動**：
  - 檢查 `.yml` 中是否有新增的 `environment` 變數。
  - 檢查是否有新增的 `volumes` 需求。若有，必須主動提醒使用者在 Zeabur Dashboard 手動同步新增 Volume 掛載點。

## 5. 個人自定義配置清單 (Customizations)
- **Docker Workflow**：修改 `.github/workflows/docker-release.yml`，將觸發條件限制為 `workflow_dispatch` 並修正標籤邏輯。
- **Gitignore**：添加 Docker 執行期產生的數據檔案過濾。
