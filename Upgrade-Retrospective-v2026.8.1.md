# Upgrade Retrospective: v2026.7.1-2 -> v2026.8.1

**Date:** 2026-09-01
**Branch:** `my-config-v2026.8.1`
**Tag Target:** `v2026.8.1-1`
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

---

## Conflict analysis

| File | Custom changes | Upstream Changes | Resolution |
|---|---|---|---|
| `.github/workflows/*` | Only keep `docker-release.yml` | 90+ workflows added/updated | Deleted all unused official workflows via policy command. |
| `.github/workflows/docker-release.yml` | `workflow_dispatch` manual trigger | Restructured to `workflow_call` | Restored our proven `workflow_dispatch` workflow. |
| `Dockerfile` | Custom TTS/STT, SSH, locales | Stages restructured (`dependency-inputs`, `production-deps`, `runtime-assets`) | Inserted custom layers cleanly into the final `runtime` stage before `USER node`. |
| `.gitignore` | Custom `.aider*` ignore | Updated upstream rules | Appended `.aider*` cleanly to the bottom. |

---

## Next Steps

1. Tag commit as `v2026.8.1-1`:
   ```bash
   git tag v2026.8.1-1
   ```
2. Push branch and tag to origin:
   ```bash
   git push -u origin my-config-v2026.8.1
   git push origin v2026.8.1-1
   ```
3. Trigger `docker-release.yml` with `tag=v2026.8.1-1` in GitHub Actions.
