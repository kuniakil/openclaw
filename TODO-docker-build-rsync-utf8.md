# TODO: Openclaw Docker Image Build Checklist

目前源碼已是對齊官方最新版。本任務目標為修改 Dockerfile 並打包新 Image。

---

### 📦 需修改事項 (Dockerfile)

- [ ] **1. 新增 rsync 與 locales 套件**：
      在 `apt-get install` 列表中加入 `rsync` 與 `locales`（支援 `rsync -avP` 極速傳檔與 UTF-8 支持）。

  ```dockerfile
  RUN apt-get update && apt-get install -y \
      openssh-server \
      rsync \
      locales \
      && rm -rf /var/lib/apt/lists/*
  ```

- [ ] **2. 寫入 UTF-8 語系環境變數**：
      加入以下環境變數，徹底解決 SSH 登入顯示中文資料夾亂碼問題：

  ```dockerfile
  ENV LANG=C.UTF-8 \
      LC_ALL=C.UTF-8
  ```

- [ ] **3. 進程收屍保障 (PID 1)**：
      確認 Entrypoint 或 Command 帶有 `tini` 代理，防止 `<defunct>` 殭屍進程產生。

---

### 🚀 執行步驟

1. 編輯 `Dockerfile` 套用上述修改。
2. 進行 `docker build` 並標記新 Tag（如 `ghcr.io/kuniakil/openclaw:2026.8.1-rsync`）。
3. Push 至 GHCR 鏡像庫：`docker push ghcr.io/kuniakil/openclaw:<new-tag>`。
4. 提醒使用者回至 `~/kubernetes` 更新 N100 部署版號。
