# Upgrade Retrospective: v2026.6.11 -> v2026.7.1

**Date:** 2026-07-16
**Branch:** `my-config-v2026.7.1`
**Tag:** `v2026.7.1` (force-updated to `22fb3438425` on origin)
**Upstream base:** `v2026.7.1` (`2d2ddc43d0d` / annotated: `2d2ddc43d0d`)
**Workflow Run:** https://github.com/kuniakil/openclaw/actions/runs/29463345283

---

## What was done

1. **Backup branch:** `backup/rebase-v2026.7.1` at `feeb3cac1f0` (preserves the prior configurations before upgrade).
2. **New branch:** `my-config-v2026.7.1` rebased directly from official `v2026.7.1` (`2d2ddc43d0d`).
3. **Rebased custom commits:**
   * Recovered custom GEMINI playbooks, guides, and documentation.
   * Workflows cleaned up to keep only `docker-release.yml`.
   * Custom edge-tts installation, sshd support, and whisper wrapper applied cleanly to `Dockerfile`.
   * Custom `.gitignore` configurations preserved (such as `.aider*` and exclude rules).
4. **Conflicts resolved:**
   * **Workflow cleanup (`d8c7db2b951`)**: Skip custom deletions to cleanly inherit new v2026.7.1 workflows. Staged manual cleanup for release.
   * **GEMINI Upgrade SOP (`8357076867c`, `fbe4fbe454e`)**: Skip custom edits on GEMINI.md as the file is no longer present in upstream v2026.7.1.
   * **Gitignore (`22fb3438425`)**: Re-applied custom ignore rules for `.aider` and local development artifacts manually after rebase.
5. **Pushed to origin:**
   * Branch: `origin/my-config-v2026.7.1` -> `22fb3438425`
   * Tag: `origin/v2026.7.1` -> `22fb3438425` (force-updated tag on origin)
6. **Docker release triggered:**
   * Triggered manually via `gh workflow run docker-release.yml` with `tag=v2026.7.1`.
   * Run URL: https://github.com/kuniakil/openclaw/actions/runs/29463345283
7. **N100 Deployment**:
   * Updated image tag to `"2026.7.1"` in kustomization config.
   * Applied changes to N100 K8s cluster and successfully verified rollout status.

---

## Conflict analysis

| File | Custom commits touching | Upstream Changes | Actual Conflict | Resolution |
|---|---|---|---|---|
| `.github/workflows/*` (other workflows) | `d8c7db2b951` | Updated workflow structures. | modify/delete conflicts | Skip deletion commits; kept clean upstream files for the tag base. |
| `GEMINI.md` | `8357076867c`, `fbe4fbe454e` | Removed upstream. | delete/modify conflicts | Skip commits modifying this file. |
| `.gitignore` | `feeb3cac1f0` | Added log/tmp ignore rules. | overlap merge conflicts | Resolved manually; merged official rules with custom `.aider*` ignore entries. |

---

## Rollback Procedure
If the upgraded branch has issues and you need to rollback:
```bash
# Option 1: Switch back to the previous stable branch
git checkout my-config-v2026.6.11

# Option 2: Force-push backup branch to restore remote state
git checkout backup/rebase-v2026.7.1
git push --force origin backup/rebase-v2026.7.1:my-config-v2026.7.1
git tag --force v2026.7.1 backup/rebase-v2026.7.1
git push --force origin v2026.7.1
```

---

## Post-upgrade Checklist

* [x] Create backup branch `backup/rebase-v2026.7.1`
* [x] Align branch head to customized `v2026.7.1` (`22fb3438425`)
* [x] Force tag `v2026.7.1` to customized commit
* [x] Push tag and branch to `origin`
* [x] Trigger manual workflow run on GitHub
* [x] Verify Docker build finishes successfully on GitHub Actions (GHCR package generated)
* [x] Update Kustomize config in `my-k8s` repository
* [x] Deploy new Docker image to N100 cluster
* [x] Validate that gateway rollout status finishes successfully and Pod is Running
