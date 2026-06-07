# OpenClaw 升級原則與標準作業程序 (SOP)

為了確保 OpenClaw 的個人 Fork 既能緊跟官方 (upstream) 更新，又能確保個人自定義配置的安全與整潔，請遵循以下原則：

## 1. 核心原則
- **退可守**：在大規模升級（Rebase）前，必須建立備份分支（Checkpoint）。
- **對齊官方 Release**：升級必須以官方的 Release Tag（如 `v2026.4.27`）作為基準，而非直接對齊主分支的提交點。
- **線性歷史 (Rebase/Cherry-pick)**：使用 `cherry-pick` 或 `rebase` 將個人修改重新應用在新的官方 Tag 之上，保持 Git 歷史乾淨，避免使用 `git merge`。
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
2. **建立並切換至新版本分支**（以目標官方 Release Tag 為起點，維持線性歷史且不修改舊分支）：
   ```bash
   git checkout -b my-config-v[新版本號] v[新版本號]
   ```
3. **櫻桃挑選（Cherry-pick）自定義 commits**（依時間序從舊到新套用）：
   ```bash
   git cherry-pick <commit-hash-1> <commit-hash-2> ...
   ```
   *註：絕不使用 `git merge`，確保 Commit 歷史為純粹的單一軸線。*

### 第三階段：測試、清理與推回
1. **測試確認**：確保本地執行單元測試通過（僅進行本地測試，**不**在 Mac 本地執行耗時的 Docker image 建置）。
2. **清理冗餘工作流**：官方分支包含大量 CI/CD 腳本，會消耗 GitHub Actions 分鐘數。
   ```bash
   find .github/workflows -type f ! -name 'docker-release.yml' -delete
   ```
3. **提交並推送分支至您的 GitHub**：
   ```bash
   git add .github/workflows
   git commit -m "chore: cleanup official workflows"
   git push origin my-config-v[新版本號]
   ```

### 第四階段：觸發 Docker 建置
1. **手動觸發 Workflow**：
   ```bash
   gh workflow run docker-release.yml --repo kuniakil/openclaw --ref my-config-v[新版本號] -f tag=v[新版本號]
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

## 6. GHCR Package 管理（重要）

操作 GitHub Container Registry (GHCR) 前，**必須先閱讀**：
```
OPERATOR-GHCR-GUIDE.md
```

重點原則：
- **絕對不刪「無 tag」的 version**（這些是實際 image data）
- **只刪「有 tag」的 version**（只是指標，刪了不影響其他 images）
- 刪除前先 `docker manifest inspect <tag>` 確認結構

詳見：`OPERATOR-GHCR-GUIDE.md`

## 7. 個人自定義配置清單 (Customizations)

- **Docker Workflow**：修改 `.github/workflows/docker-release.yml`，將觸發條件限制為 `workflow_dispatch` 並修正標籤邏輯。
- **Gitignore**：添加 Docker 執行期產生的數據檔案過濾。

## 8. 個人操作文檔

- `GEMINI.md` — 本文件，升級 SOP 與關鍵原則
- `GEMINI-MASTER-PLAYBOOK.md` — 進階操作與疑難排解
- `OPERATOR-GHCR-GUIDE.md` — GHCR 操作風險說明（**刪除 Package 前必看**）
- `Upgrade-Retrospective-v*.md` — 每次升級的歷史記錄（在 .gitignore 中）
- `universal-agent-workflow.md` — 萬用 Agent 工作流文檔

---

## 🤖 AI 行為鐵律 (AI Behavior Rules)

- **優先徵求使用者同意 (Prioritize User Permission)**：在修改任何程式碼、設定檔（特別是 `Dockerfile`、`.env`、`openclaw.json`）或連線資料庫之前，AI **必須**先在對話框中報告修改計畫，並獲得使用者明確同意後才可動手。
- **動手前必先讀檔 (Look Before You Leap)**：禁止憑空猜測設定檔結構。在進行任何編輯前，AI **必須**先調用 `view_file` 工具閱讀目標檔案內容，理解當前結構後再做修改。
- **功能重疊處理**：若自訂 Commit 的功能已在官方新版本中被原生支援，必須直接捨棄該自訂 Commit，改用官方的設定方式。
- **衝突安全中止 (Safe Rollback)**：
  - 當 `rebase` 或 `cherry-pick` 發生衝突，且無法在 1 輪內自動解決時，必須**立刻執行 `git rebase --abort` 或 `git cherry-pick --abort` 恢復原狀**。
  - 禁止在衝突狀態下憑空猜測並修改程式碼。
  - 中止後，向使用者詳細回報衝突檔案與原因，並提出建議方案，等待使用者指示。
