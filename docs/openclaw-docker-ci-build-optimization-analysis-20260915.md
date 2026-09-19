# OpenClaw Docker CI/CD 建置時間優化規劃分析

- **建立時間**：2026-09-15
- **關聯議題**：OpenClaw GitHub Actions Docker 建置時間過長（~28-30 分鐘）vs Hermes Agent 建置時間極短（5-7 分鐘）。
- **目標**：透過工作流重構與快取/認證修剪，將 OpenClaw 原生雙架構（amd64 + arm64）建置時間從 **~~28 分鐘縮減至 10~~13 分鐘**，並建立未來升級時免衝突的直接覆蓋機制。

---

## 1. 耗時根本原因對比分析

透過調閱 OpenClaw（Run ID `34676697421`）與 Hermes Agent（Run ID `34913550568`）的建置日誌，發現兩者雖同為原生 `ubuntu-24.04-arm` + `ubuntu-latest`，但存在以下巨大差異：

| 瓶頸維度              | Hermes Agent (~6 分鐘)                             | OpenClaw 現行版本 (~28 分鐘)                                                                                                               | 節省潛力        |
| --------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ | --------------- |
| **BuildKit 快取導出** | 輕量 Python/Vite，導出耗時 **79 秒**。             | `cache-to: type=gha,mode=max`<br>因 54 個 workspace 中介層巨大，單是 `#93 exporting to GitHub Actions Cache` 就花了 **526 秒 (8分46秒)**！ | **~7-8 分鐘**   |
| **前置檢查階段**      | 單一 `prepare` job，耗時 **3 秒**。                | `validate_manual_backfill` 做 `fetch-depth: 0` 完整下載歷史（2m39s）+ `approve_manual_backfill` 環境簽核。                                 | **~2.5-3 分鐘** |
| **收尾合併階段**      | `imagetools create` 建立 manifest 僅花 **15 秒**。 | `create-manifest` 耗時 **3 分 11 秒**，加上 `verify-attestations`（38 秒）。                                                               | **~3 分鐘**     |
| **安全掃描產物**      | 未啟用 SBOM/Provenance。                           | 開啟 `sbom: true` 與 `provenance: mode=max`，觸發 `syft-scanner` 掃描數萬檔案。                                                            | **~1-2 分鐘**   |
| **腳本架構**          | 簡潔的 Matrix Strategy（~140 行）。                | 740 行巨大腳本，amd64 與 arm64 完全複製貼上，各有一百多行重複邏輯。                                                                        | 維護性巨幅提升  |

> **最終 Image 大小比較**：
>
> - `ghcr.io/kuniakil/openclaw:2026.9.4`：**1,531 MB**
> - `ghcr.io/kuniakil/hermes-agent:v2026.9.14`：**1,284 MB**
>   兩者僅差 250 MB，證實時間差距純粹是**建置流程中的中介層快取壓縮與冗餘前置/收尾工作流**所致。

---

## 2. 改造方案與副作用評估

1. **關閉 `mode=max`**：
   - 改為預設（僅快取最終 layer）或視情況移除。
   - **副作用**：**零**。快取純屬中介暫存，不影響最終產物；且版本升級時程式碼大改，`mode=max` 原本命中率就極低。
2. **關閉 `sbom` 與 `provenance`**：
   - 移除 `verify-attestations`。
   - **副作用**：**零**。K3s / containerd 部署完全不依賴 SBOM/Attestation，僅 GitHub GHCR 頁面不顯示盾牌標記。
3. **前置與收尾極簡化**：
   - 採用 Hermes 式的快速 `prepare` 與 `imagetools` 合併。
4. **未來升級策略（SOP 銜接）**：
   - 升級原則維持 **Cherry-pick**。
   - 遇到官方更新 `docker-release.yml` 時，**直接用我們的精簡版取代官方版**：
     ```bash
     git checkout my-config-v舊 -- .github/workflows/docker-release.yml
     git add .github/workflows/docker-release.yml
     ```
     完全免去排解 700 多行官方 CI 衝突的痛點。

---

## 3. 下一步實施清單 (Next Steps)

- [x] 在 `~/openclaw` 建立備份分支 (`backup/my-config-v2026.9.4-before-ci-refactor`)
- [x] 重構 `.github/workflows/docker-release.yml`：
  - 改用 Matrix Strategy (`linux/amd64` on `ubuntu-latest`, `linux/arm64` on `ubuntu-24.04-arm`)
  - 移除 `mode=max`，調整 cache 參數為預設單層 GHA cache
  - 移除 `sbom` 與 `provenance`，簡化 manifest 合併為 `imagetools create`
- [x] 驗證 YAML 語法並更新 SOP 規範
- [ ] Git commit & push，觸發測試建置並觀察耗時
