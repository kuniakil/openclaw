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
5. **Gemini Embedding Rate-Pacing Restored (Option C):**
   * Upstream v2026.8.2 did not yet include PR #128945, so testing revealed Gemini Free Tier 429 quota exhaustion recurred during restart/memory sync spikes.
   * Re-applied Option C: `MIN_GEMINI_EMBEDDING_INTERVAL_MS = 1200ms` rate pacing + exponential backoff retry (2s ~ 15s) in `extensions/google/embedding-provider.ts`.

---

## Conflict analysis

| File | Custom changes | Upstream Changes | Resolution |
|---|---|---|---|
| `.github/workflows/*` | Only keep `docker-release.yml` | Updated/added workflows | Deleted all unused official workflows via policy command. |
| `Dockerfile` | Custom TTS/STT, SSH, locales | Added `COPY package-lifecycle-marker.mjs` (build stage) | Re-applied custom layers; inserted new COPY line. |
| `extensions/google/embedding-provider.ts` | rate-pacing + backoff patch | Removed rate-pacing | **Option C: Re-applied rate pacing (1200ms) + exponential backoff.** |
| `AGENTS.md` | Custom upgrade policy appended | Updated policy rules | Took official version, re-appended custom block. |
| `.gitignore` | Custom `.aider*` ignore | No change | Confirmed present. |

---

## Upstream Tracking Note: Embedding 429 & Rate Limit Issues

* **上游核心 PR（仍待合併）：**
  * **PR #128945** (`fix(memory): exhausted-quota embedding errors retry forever and starve the sync queue`)
    修復層級：HTTP boundary `Retry-After` 解析、致命錯誤 terminal 標記、Remote provider degradation lifecycle。
* **策略與實測結果：**
  * 實測證實若不加 rate-pacing，在重啟時 multiple memory sync 尖峰下 Gemini Free Tier（15 RPM）必然觸發 429 `RESOURCE_EXHAUSTED`。
  * 採用 Option C 維持 1200ms 請求間隔限制，確保生產環境穩定。
