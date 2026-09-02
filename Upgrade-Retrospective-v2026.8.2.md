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
5. **Gemini Embedding Rate-Pacing Optimized for Free Tier (15 RPM):**
   * Upstream v2026.8.2 did not yet include PR #128945, so testing revealed Gemini Free Tier 429 quota exhaustion recurred during restart/memory sync spikes.
   * `MIN_GEMINI_EMBEDDING_INTERVAL_MS` adjusted to `4200ms` (~14 RPM, strictly under the 15 RPM quota limit).
   * `extensions/google/embedding-provider.ts` retry backoff set to 10s ~ 30s with 5 attempts.
   * `extensions/memory-core` retry delay base adjusted to 4000ms and max to 30000ms to eliminate sub-second tight retry loops.

---

## Conflict analysis

| File | Custom changes | Upstream Changes | Resolution |
|---|---|---|---|
| `.github/workflows/*` | Only keep `docker-release.yml` | Updated/added workflows | Deleted all unused official workflows via policy command. |
| `Dockerfile` | Custom TTS/STT, SSH, locales | Added `COPY package-lifecycle-marker.mjs` (build stage) | Re-applied custom layers; inserted new COPY line. |
| `extensions/google/embedding-provider.ts` | rate-pacing + backoff patch | Removed rate-pacing | **Tuned rate pacing (4200ms) + 10s-30s backoff for 15 RPM.** |
| `extensions/memory-core/src/memory/manager-embedding-ops.ts` | retry backoff constants | Default 500ms | **Increased base retry delay to 4000ms, max 30000ms.** |
| `AGENTS.md` | Custom upgrade policy appended | Updated policy rules | Took official version, re-appended custom block. |
| `.gitignore` | Custom `.aider*` ignore | No change | Confirmed present. |

---

## Upstream Tracking Note: Embedding 429 & Rate Limit Issues

* **上游核心 PR（仍待合併）：**
  * **PR #128945** (`fix(memory): exhausted-quota embedding errors retry forever and starve the sync queue`)
    修復層級：HTTP boundary `Retry-After` 解析、致命錯誤 terminal 標記、Remote provider degradation lifecycle。
* **策略與實測結果：**
  * 實測證實若不加 rate-pacing 或間隔過小（1200ms），在重啟時 multiple memory sync 尖峰下 Gemini Free Tier（15 RPM）必然觸發 429 `RESOURCE_EXHAUSTED`。
  * 採用 4200ms 請求間隔限制與 4000ms~30000ms 退避，確保在 15 RPM 限制下永不觸發 quota 超額。
