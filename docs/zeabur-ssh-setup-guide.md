# Zeabur 部署 OpenClaw 啟用 SSH 設定指南

本指南詳細說明如何在 Zeabur 平台上為 OpenClaw 容器啟用 SSH 伺服器，以便 AI Agent 或您本人可以遠端 SSH 進入容器進行排查與維護。

---

## 📋 事前準備

1. **取得公鑰**：確保您有 SSH 金鑰對。如果沒有，請在本機終端機執行以下指令生成：
   ```bash
   ssh-keygen -t ed25519 -C "your_email@example.com"
   ```
   產生的公鑰內容通常在 `~/.ssh/id_ed25519.pub`。

---

## ⚙️ Zeabur 設定步驟

### 1. 新增環境變數

SSHd 需要您的公鑰來驗證連線。請在 Zeabur 的 OpenClaw 服務控制面板中，新增以下環境變數：

- **變數名稱**：`SSH_PUBLIC_KEY`
- **變數值**：填入您的公鑰內容（必須是單行，例如 `ssh-ed25519 AAAAC3NzaC1l...`）。
  > [!TIP]
  > 請確保複製完整的公鑰文字，且變數值前後不要包含多餘的空白或換行。

---

### 2. 新增連接埠對照 (Port Mapping)

Zeabur 需要將外部網路流量導向容器內部的 SSH 預設連接埠（22）。

1. 在 OpenClaw 服務的 **Network (網路)** 設定區塊，新增一個連接埠對照。
2. 設定如下：
   - **容器內連接埠 (Port)**：`22`
   - **協議 (Protocol)**：`TCP`
3. Zeabur 會為您生成一個外部隨機連接埠（例如 `31022`）或允許您綁定自訂域名。請記錄下這個**外部連接埠**與**連線網址 (Domain/IP)**。

---

### 3. 修改啟動指令 (Start Command)

我們需要讓容器啟動時，先跑我們的 SSH 設定腳本，再接續原先 Zeabur 的 OpenClaw 初始化及啟動流程。

1. 在 OpenClaw 服務的 **Settings (設定)** 區塊，找到 **Start Command (啟動指令)**。
2. 將其修改為：
   ```bash
   /bin/sh -c '/app/docker/entrypoint-ssh.sh && /opt/openclaw/startup.sh && /opt/openclaw/start_gateway.sh'
   ```
3. 點擊 **Save (儲存)**。Zeabur 將會自動重啟您的服務。

---

## 🔌 遠端連線測試

當 Zeabur 重新部署完成且顯示 `Running` 狀態後，您可以使用以下指令從本機連線進去：

### 以 `root` 身分連線 (推薦，擁有一切維護權限)

```bash
ssh root@<Zeabur-連線域名-或-IP> -p <Zeabur-外部Port>
```

### 以 `node` 身分連線

```bash
ssh node@<Zeabur-連線域名-或-IP> -p <Zeabur-外部Port>
```

---

## 🛠️ 常見故障排查與維護指令

當成功登入 SSH 後，您可以隨時執行以下常用排修操作：

### 1. 解鎖卡住的隊列 (HOL Blocking)

如果機器人突然無回應，但 `/status` 正常，可能是訊息佇列卡在 `claimed` 狀態：

```bash
# 檢查是否有被卡住的 claimed 事件
sqlite3 /home/node/.openclaw/state/openclaw.sqlite "SELECT event_id, status FROM channel_ingress_events WHERE status = 'claimed';"

# 手動將卡住的事件解鎖為 failed
sqlite3 /home/node/.openclaw/state/openclaw.sqlite "UPDATE channel_ingress_events SET status = 'failed' WHERE status = 'claimed';"
```

### 2. 檢查資料庫日誌模式

```bash
sqlite3 /home/node/.openclaw/state/openclaw.sqlite "PRAGMA journal_mode;"
```

### 3. 強制清理 task 隊列狀態

```bash
node /app/dist/index.js tasks maintenance --force
```
