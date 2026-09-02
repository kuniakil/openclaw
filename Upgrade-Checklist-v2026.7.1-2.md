# Upgrade Checklist: v2026.7.1 -> v2026.7.1-2

**Prepared:** 2026-08-06  
**Current branch:** `my-config-v2026.7.1`  
**Current HEAD:** `db1e4187268`  
**Official old base:** `v2026.7.1` (`2d2ddc43d0d`)  
**Official target:** `v2026.7.1-2` (`0790d9f593ad`)  
**Proposed branch:** `my-config-v2026.7.1-2`  
**Proposed custom tag:** `custom-v2026.7.1-2`

> This document is the execution checklist. Checking an item records completion; it does not authorize a push, tag publication, GitHub Actions run, image publication, Kubernetes change, remote tag deletion, or backup cleanup. Obtain explicit approval immediately before each outward-facing or destructive action.

---

## 1. Scope and decisions

The upgrade will retain all current custom deployment features:

- SSH server and Zeabur entrypoint support.
- fast-whisper wrapper.
- `ffmpeg`.
- `edge-tts`.
- Custom `.gitignore` entries, including `.aider*`.
- Manual-only Docker release workflow.
- GHCR-only image publication; no Docker Hub requirement.

The official correction release will be adopted in full for Codex, Memory Core, state migration, npm plugin installation, WSL permissions, macOS Chat UI, and DMG packaging.

### Official release delta

Official `v2026.7.1-2` is nine commits ahead of `v2026.7.1` and changes 24 files. The main runtime changes are:

- Codex turns continue after progress replies until the terminal response.
- Memory Core recovers derived sidecar conflicts.
- Managed npm plugin installs recover incomplete lock metadata.
- Newer npm singleton-array metadata is accepted; multi-version arrays still fail closed.
- Reviewed migration residue is reported as a notice rather than blocking startup.
- Guarded WSL `EROFS` chmod failures are tolerated only when permissions are already private.
- Swift concurrency and macOS DMG layout corrections.

---

## 2. Conflict assessment

The current custom delta and official `v2026.7.1..v2026.7.1-2` changed-file list have **no direct path overlap**. A bounded rebase should therefore have few or no textual conflicts. The following semantic conflicts still require deliberate resolution.

| Surface                                |                       Risk | Reason                                                                                                                                             | Resolution                                                                                                                                                                                                                                   |
| -------------------------------------- | -------------------------: | -------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.github/workflows/docker-release.yml` |                     Medium | Official correction history introduced tag-triggered publishing and mandatory Docker Hub credentials; the custom branch deliberately removed both. | Use the official target as the structural base, then retain `workflow_dispatch` only and GHCR-only publication. Do not restore Docker Hub login, secrets, manifests, or automatic tag triggers. Preserve applicable GHCR attestation checks. |
| `Dockerfile`                           |                     Medium | Official correction history removed SSH, whisper, `ffmpeg`, and `edge-tts`; custom commits intentionally restore them.                             | Preserve official `--config.offline=true` pruning and all unrelated target changes. Reapply sshd, host keys, `ffmpeg`, edge-tts target install, whisper wrapper, and SSH entrypoint in their current stages.                                 |
| `.gitignore`                           |                     Medium | Official target expands the `.agents/skills` allowlist, while custom commits restore `.aider*` and local rules.                                    | Keep the complete official allowlist and general rules, then add only confirmed custom ignores. Do not shrink the official skill list. Put purely local `.agents` exclusions in `.git/info/exclude`.                                         |
| `assets/whisper`                       | Low Git / High operational | Custom deployment artifact; no official target overlap.                                                                                            | Preserve file, executable mode, shebang, and fast-whisper invocation. Validate with a real smoke test.                                                                                                                                       |
| `docker/entrypoint-ssh.sh`             | Low Git / High operational | Custom deployment artifact; no official target overlap.                                                                                            | Preserve startup behavior and executable mode. Verify sshd host keys and non-root OpenClaw runtime behavior.                                                                                                                                 |
| `docs/zeabur-ssh-setup-guide.md`       |                        Low | Custom operator documentation; no official target overlap.                                                                                         | Preserve and verify against the final Docker image and environment variables. Do not publish secrets or real hostnames.                                                                                                                      |
| Official runtime files                 |                        Low | No current custom changes in the 24 official paths.                                                                                                | Accept the official versions without local rewrites. Run focused correction-release tests.                                                                                                                                                   |
| `CHANGELOG.md`                         |                        Low | Official tag already owns the release notes.                                                                                                       | Accept the official tagged content. Do not add a custom changelog entry.                                                                                                                                                                     |

### Expected custom delta after rebase

The diff from official `0790d9f593ad` should be limited mainly to:

- `.github/workflows/docker-release.yml`
- `.gitignore`
- `Dockerfile`
- `assets/whisper`
- `docker/entrypoint-ssh.sh`
- `docs/zeabur-ssh-setup-guide.md`
- `Upgrade-Retrospective-v2026.7.1.md`
- This checklist and the new retrospective

Any additional runtime path requires investigation before continuing.

---

## 3. Preflight checklist

- [ ] Confirm working tree is clean with `git status -sb`.
- [ ] Record current HEAD as `db1e4187268` or update this document if it changed.
- [ ] Confirm remotes:
  - [ ] `origin` is the customized fork.
  - [ ] `upstream` is `https://github.com/openclaw/openclaw.git`.
- [ ] Verify official signed tag refs without relying on the colliding local tag:
  - [ ] `v2026.7.1^{}` is `2d2ddc43d0d` upstream.
  - [ ] `v2026.7.1-2^{}` is `0790d9f593ad` upstream.
- [ ] Confirm the current custom `v2026.7.1` tag points to `22fb3438425` and therefore must not be treated as the official base.
- [ ] Classify this source as the trusted maintainer fork before remote validation.
- [ ] Pre-warm the approved Blacksmith Testbox before code/build/test work.
- [ ] Create and verify an OpenClaw state backup:

```bash
openclaw backup create --verify
```

- [ ] Record the backup archive path and verification result outside the repository.
- [ ] Record the currently deployed GHCR image tag and digest.
- [ ] Record the current external Kustomize image tag/digest and rollout state.

---

## 4. Git safety and branch preparation

- [ ] Create a local backup branch at the exact pre-upgrade HEAD:

```bash
git branch backup/my-config-v2026.7.1-before-7.1-2 db1e4187268
```

- [ ] Verify the backup branch resolves to the expected commit.
- [ ] Fetch the official target by upstream ref/SHA without deleting or overwriting the custom local tag.
- [ ] Verify the target commit and tag signature.
- [ ] Create `my-config-v2026.7.1-2` from official commit `0790d9f593ad`.
- [ ] Do **not** delete, rename, or force-update the remote `v2026.7.1` tag during the upgrade.
- [ ] Do **not** create an official-looking `v2026.7.1-2` tag for custom code.

### Recommended replay sequence

Replay the bounded custom range after official base `2d2ddc43d0d`, preserving this dependency order:

- [ ] Manual-only GHCR workflow policy.
- [ ] Docker SSH support and `docker/entrypoint-ssh.sh`.
- [ ] Zeabur SSH documentation.
- [ ] fast-whisper, `ffmpeg`, and `edge-tts`.
- [ ] `.aider*` and other confirmed `.gitignore` customizations.
- [ ] Preserve the prior retrospective as historical documentation.
- [ ] Add the new retrospective only after proof is available.

Use bounded rebase/cherry-pick rather than a merge commit. Resolve each semantic surface independently and inspect the resulting commit before continuing.

---

## 5. Resolution checklist

### Docker workflow

- [ ] Trigger remains `workflow_dispatch` with an explicit tag input.
- [ ] No `push.tags` automatic release trigger is present.
- [ ] No Docker Hub credentials are required.
- [ ] No Docker Hub image or manifest is published.
- [ ] GHCR amd64 and arm64 images are built as intended.
- [ ] Multi-architecture GHCR manifest creation is preserved.
- [ ] GHCR attestation verification still checks the actual manifest type produced by the workflow.
- [ ] Workflow syntax and shell branches are valid.

### Dockerfile and custom tools

- [ ] Preserve official target changes, including offline prune behavior.
- [ ] `openssh-server` and `openssh-client` remain installed.
- [ ] `ffmpeg` remains installed.
- [ ] `/var/run/sshd` and host keys are initialized as designed.
- [ ] `docker/entrypoint-ssh.sh` is copied with executable permissions.
- [ ] `assets/whisper` is copied to the expected executable path.
- [ ] edge-tts is installed into the expected target directory.
- [ ] Ownership remains correct for the non-root `node` user.
- [ ] OpenClaw's normal gateway entrypoint and runtime user are not bypassed.

### Ignore rules

- [ ] Keep all official target `.agents/skills` allowlist entries.
- [ ] Keep the official target's current iOS, macOS, Mantis, cache, and generated-file rules.
- [ ] Restore `.aider`, `.aider*`, and `.aider.tags.cache.v4` ignores as required.
- [ ] Restore only other documented custom ignores.
- [ ] Do not use repository `.gitignore` for new local-only `.agents` exclusions.

### Official correction surfaces

- [ ] Accept official Codex changes unchanged.
- [ ] Accept official Memory Core changes unchanged.
- [ ] Accept official npm plugin installation changes unchanged.
- [ ] Accept official state migration and private-mode changes unchanged.
- [ ] Accept official Swift and macOS DMG changes unchanged.
- [ ] Preserve official release notes in `CHANGELOG.md`; add no custom entry.

---

## 6. Static and repository validation

### Lightweight local checks

- [ ] `git status -sb`
- [ ] Verify `0790d9f593ad` is an ancestor of the new branch.
- [ ] Inspect `git diff --name-status 0790d9f593ad..HEAD` against the expected custom delta.
- [ ] Run `git diff --check`.
- [ ] Inspect `git diff --numstat 0790d9f593ad..HEAD` and explain all production LOC retained or added.
- [ ] Verify executable modes for `assets/whisper` and `docker/entrypoint-ssh.sh`.
- [ ] Inspect Dockerfile stage ordering and final runtime user.
- [ ] Validate workflow YAML and embedded shell syntax.

### Remote Testbox/Crabbox gates

- [ ] Synchronize the exact candidate SHA to the approved remote test backend.
- [ ] Run path-scoped changed checks for all touched files.
- [ ] Run focused npm metadata and plugin-install tests.
- [ ] Run focused state migration and private-permission tests.
- [ ] Run focused Codex dynamic-tool/run-attempt tests.
- [ ] Run focused Memory Core doctor-contract tests.
- [ ] Run the remote build because Docker/package/runtime boundaries changed.
- [ ] Run Docker build and attestation verification on the supported architecture path.
- [ ] Record all Testbox/Crabbox run IDs and exact commands.
- [ ] Run fresh `$autoreview`; resolve all accepted/actionable findings.
- [ ] Repeat `$autoreview` until clean.

---

## 7. Candidate image user-path proof

- [ ] Build the candidate image from the exact candidate SHA.
- [ ] Start the Gateway through the normal image entrypoint.
- [ ] Confirm CLI version and Gateway health.
- [ ] Confirm `sshd` is executable and host keys exist.
- [ ] Confirm SSH entrypoint behavior on the intended Zeabur-style environment.
- [ ] Confirm `ffmpeg -version` succeeds.
- [ ] Confirm the `whisper` wrapper resolves fast-whisper.
- [ ] Complete a minimal real audio transcription smoke test.
- [ ] Confirm Python can import and run `edge_tts`.
- [ ] Complete a minimal real TTS smoke test.
- [ ] Exercise official plugin install/update metadata resolution.
- [ ] If deployed in production, exercise one Codex turn with a progress reply and terminal response.
- [ ] If deployed in production, verify Memory Core starts cleanly against a copied/controlled state fixture.
- [ ] Record proof artifacts outside the product repository.

---

## 8. Documentation and handoff

- [ ] Create `Upgrade-Retrospective-v2026.7.1-2.md` after validation.
- [ ] Record official base/tag SHA and custom branch HEAD.
- [ ] Record actual textual conflicts; explicitly state zero if none occurred.
- [ ] Record each semantic resolution.
- [ ] Record preserved SSH/TTS/Whisper behavior and proof.
- [ ] Record exact checks, Testbox/Crabbox run IDs, Docker workflow URL, GHCR digest, and K8s rollout result.
- [ ] Record known proof gaps, if any.
- [ ] Record backup branch and rollback image digest.
- [ ] Keep `Upgrade-Retrospective-v2026.7.1.md` as historical evidence.

---

## 9. Publication and deployment approval gates

Each unchecked item below requires explicit approval immediately before execution.

- [ ] **Approval required:** push `my-config-v2026.7.1-2` to `origin`.
- [ ] **Approval required:** create and push `custom-v2026.7.1-2`.
- [ ] **Approval required:** manually trigger `.github/workflows/docker-release.yml`.
- [ ] **Approval required:** publish the GHCR image and multi-architecture manifest.
- [ ] **Approval required:** update the external `my-k8s` image tag/digest.
- [ ] **Approval required:** apply the Kubernetes rollout.
- [ ] Verify the rollout reaches Ready/Running.
- [ ] Verify Gateway health and review startup logs.
- [ ] Repeat SSH, TTS, Whisper, Codex, Memory Core, and plugin-update smoke checks against the deployed image as applicable.
- [ ] Observe production through the agreed stability window.
- [ ] **Separate approval required:** normalize or remove the old remote custom `v2026.7.1` tag.
- [ ] **Separate approval required:** delete the backup branch after the stability window.

---

## 10. Rollback checklist

### Git rollback

- [ ] Stop the upgrade before push if any required gate fails.
- [ ] Return to `backup/my-config-v2026.7.1-before-7.1-2` or exact commit `db1e4187268`.
- [ ] Do not use an unverified reset target.
- [ ] Preserve the failed candidate branch for diagnosis unless deletion is explicitly approved.

### Image and Kubernetes rollback

- [ ] Restore the previously recorded `2026.7.1` image digest in external Kustomize configuration.
- [ ] Apply rollback only with explicit deployment approval.
- [ ] Wait for rollout completion.
- [ ] Verify Pod readiness, Gateway health, and startup logs.
- [ ] Re-run the critical custom feature checks.

### State rollback

- [ ] Keep the verified pre-upgrade OpenClaw backup available.
- [ ] Record whether `openclaw doctor` performed any migration.
- [ ] Restore persistent state only when required and only from the verified archive.
- [ ] Never add a runtime fallback or dual-read path to compensate for a failed migration.

---

## Completion criteria

The upgrade is complete only when all applicable checks are marked, the candidate is based on official `0790d9f593ad`, the custom delta is bounded and reviewed, remote gates pass, GHCR and deployment evidence are recorded, all retained SSH/TTS/Whisper features work through real user paths, and a tested rollback remains available.
