# Upgrade Retrospective: v2026.8.1 -> v2026.8.2

**Date:** 2026-09-02
**Branch:** `my-config-v2026.8.2`
**Tag Target:** `v2026.8.2`
**Docker Image:** `ghcr.io/kuniakil/openclaw:2026.8.2`
**Upstream base:** `v2026.8.2` (`0965053fe6b`)

---

## What was done

1. **New branch:** Created `my-config-v2026.8.2` from official release tag `v2026.8.2` (`0965053fe6b`).
2. **Workflows cleaned up:** Deleted 90+ unneeded official workflows to eliminate automated GitHub Actions trigger noise, preserving and restoring only our custom `docker-release.yml`.
3. **Restored custom tools & docs:**
   * Restored `assets/whisper` (Audio STT wrapper script)
   * Restored `docker/entrypoint-ssh.sh` (Zeabur SSH deployment entrypoint)
   * Restored upgrade guides and retrospectives
   * Confirmed `.aider*` ignore rules in `.gitignore`
   * Preserved custom upgrade policy in `AGENTS.md`
4. **Dockerfile updated:**
   * Re-applied custom layers (UTF-8 locales, rsync, TTS/STT, SSH)
   * Integrated upstream fix: `COPY scripts/lib/package-lifecycle-marker.mjs` (fixes #134231)
5. **Embedding rate-pacing patch removed (Option A):**
   * Our custom `sleepMs`, `lastGeminiEmbeddingRequestTime`, `MIN_GEMINI_EMBEDDING_INTERVAL_MS` patch is intentionally removed, aligning with upstream v2026.8.2.
   * Upstream now uses `providerOperationRetryConfig("read")` standard retry.
   * **Monitor:** Watch for Gemini embedding 429 errors post-deploy. If free-tier burst issues recur before upstream PR #128945 lands, re-evaluate Option C (rate-pacing only, no custom retry).

---

## Conflict analysis

| File | Custom changes | Upstream Changes | Resolution |
|---|---|---|---|
| `.github/workflows/*` | Only keep `docker-release.yml` | Updated/added workflows | Deleted all unused official workflows via policy command. |
| `Dockerfile` | Custom TTS/STT, SSH, locales | Added `COPY package-lifecycle-marker.mjs` (build stage) | Re-applied custom layers; inserted new COPY line. |
| `extensions/google/embedding-provider.ts` | rate-pacing + backoff patch | Removed same code, use `providerOperationRetryConfig("read")` | **Option A: Follow upstream, patch removed.** |
| `AGENTS.md` | Custom upgrade policy appended | Updated policy rules | Took official version, re-appended custom block. |
| `.gitignore` | Custom `.aider*` ignore | No change | Confirmed present. |

---

## Upstream Tracking Note: Embedding 429 & Rate Limit Issues

我們的 rate-pacing patch 在本次升級中對齊官方移除。後續追蹤：

* **上游核心 PR（仍待合併）：**
  * **PR #128945** (`fix(memory): exhausted-quota embedding errors retry forever and starve the sync queue`)
    修復層級：HTTP boundary `Retry-After` 解析、致命錯誤 terminal 標記、Remote provider degradation lifecycle。
* **監控策略：**
  * 若 Gemini Free Tier 環境在 v2026.8.2 部署後出現 embedding 429 burst，可採 Option C：保留 1200ms pacing，使用官方 `providerOperationRetryConfig("read")`。
  * 待 PR #128945 合併並發布後，可完全依賴官方標準實作。
