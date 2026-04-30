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

## 3. 個人自定義配置清單 (Customizations)
- **Docker Workflow**：修改 `.github/workflows/docker-release.yml`，將觸發條件限制為 `workflow_dispatch` 並修正標籤邏輯。
- **Gitignore**：添加 Docker 執行期產生的數據檔案過濾。
