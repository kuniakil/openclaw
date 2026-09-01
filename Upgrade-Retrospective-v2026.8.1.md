# Upgrade Retrospective: v2026.7.1-2 -> v2026.8.1

**Date:** 2026-09-01
**Branch:** `my-config-v2026.8.1`
**Tag Target:** `v2026.8.1`
**Docker Image:** `ghcr.io/kuniakil/openclaw:2026.8.1`
**Upstream base:** `v2026.8.1` (`4d37fc4b0f86`)

---

## What was done

1. **New branch:** Created `my-config-v2026.8.1` from official release tag `v2026.8.1` (`4d37fc4b0f86`).
2. **Workflows cleaned up:** Deleted 90 unneeded official workflows to eliminate automated GitHub Actions trigger noise, preserving and restoring only our custom `docker-release.yml`.
3. **Restored custom tools & docs:**
   * Restored `assets/whisper` (Audio STT wrapper script)
   * Restored `docker/entrypoint-ssh.sh` (Zeabur SSH deployment entrypoint)
   * Restored upgrade guides, retrospectives, and playbooks
   * Added `.aider*` ignore rules to `.gitignore`
   * Preserved custom upgrade policy in `AGENTS.md`
4. **Dockerfile modernized:**
   * Adapted custom UTF-8 locales (`en_US.UTF-8`), `rsync`, and environment variables to the new bookworm-slim runtime stage.
   * Adapted `faster-whisper`, `edge-tts`, and `ffmpeg` installations into the new python/runtime layout.
   * Installed `openssh-server` and wired up `entrypoint-ssh.sh`.
5. **Resolved upstream absorption:**
   * Upstream `v2026.8.1` already absorbed multiple bugfixes (e.g. npm lock metadata #107294, DMG artwork #107142, memory sidecar conflict #108652, codex progress turn continue #108487). Those duplicate commits were safely skipped.
6. **Gemini Embedding Rate-Pacing Fix:**
   * Added `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 1200ms` pacing in `extensions/google/embedding-provider.ts` to prevent 429 burst errors on Gemini Free Tier (15 RPM).
   * Upgraded transient retry strategy with exponential backoff (2s ~ 15s) instead of tight tight retries.

---

## Conflict analysis

| File | Custom changes | Upstream Changes | Resolution |
|---|---|---|---|
| `.github/workflows/*` | Only keep `docker-release.yml` | 90+ workflows added/updated | Deleted all unused official workflows via policy command. |
| `.github/workflows/docker-release.yml` | `workflow_dispatch` manual trigger | Restructured to `workflow_call` | Restored our proven `workflow_dispatch` workflow. |
| `Dockerfile` | Custom TTS/STT, SSH, locales | Stages restructured (`dependency-inputs`, `production-deps`, `runtime-assets`) | Inserted custom layers cleanly into the final `runtime` stage before `USER node`. |
| `.gitignore` | Custom `.aider*` ignore | Updated upstream rules | Appended `.aider*` cleanly to the bottom. |
| `extensions/google/embedding-provider.ts` | Rate pacing + backoff for embeddings | Standard batch invocation | Added request spacing (1200ms) to avoid free-tier 429 rate limit. |

---

## Upstream Tracking Note: Memory 429 & Rate Limit Issues

官方目前已在著手重構並修復此問題，未來大版升級時可評估直接對齊上游解決方案並移除我們的臨時 patch：

* **核心上游 PR**：
  * **PR #128945** (`fix(memory): exhausted-quota embedding errors retry forever and starve the sync queue` by `scoootscooob` - MEMBER / P1)
  * 修復層級：
    1. HTTP boundary 結構化 `Retry-After` header 解析（上限 30s）。
    2. `insufficient_quota` 等致命錯誤立即標記 terminal，不再盲目重試。
    3. Remote provider degradation lifecycle（10 分鐘 probe backoff，避免已建好的語意索引被破壞）。
* **同源 Community Issues**：
  * **#91354** (`Gemini embeddings still use inline batch requests... causing 429 on low quota`)：提出 1 request / 10s 可穩定運作，思路與我們的 rate-pacing 一致。
  * **#132708** (`openai-compatible embeddings need configurable throttle + honor Retry-After`)：涵蓋千帆/阿里百煉/火山方舟等免費與開源 embedding 案例。
  * **#128938** (`Memory sync retries terminal OpenAI embeddings 429 on every sync`)。
* **後續策略**：
  * 當前維持我們自訂分支的 rate-pacing patch 確保生產環境穩定運作。
  * 待上游 PR #128945 合併並發布下一版本後，下一次升級即可順勢切換至官方標準實作。
