# Upgrade Retrospective: v2026.5.19 → v2026.5.26

**Date:** 2026-05-28
**Branch:** `my-config-v2026.5.26` (pushed to origin)
**Tag:** `v2026.5.26` (pushed to origin)
**Upstream base:** `v2026.5.26` (`be07dfce9a`)

---

## What was done

1. **Backup created:** `backup/my-config-v2026.5.19` at `a15b7d7783`
2. **New branch:** `my-config-v2026.5.26` from official `v2026.5.26`
3. **Cherry-picked custom commits** (from `my-config-v2026.5.19`):
   - `9541eee2ac` chore: restore Upgrade-Retrospective-v2026.5.6.md
   - `c065e7ac70` chore: ignore Upgrade-Retrospective files
   - `8338ffc4f0` chore: remove offline=true from pnpm prune for arm64 build
4. **New commits on branch:**
   - `ae2de1b797` chore: cleanup official workflows (deleted 55 workflows, kept only docker-release.yml)
   - `da4419cb40` chore: restore GEMINI docs and add to gitignore
   - `fe4fcfb658` chore: add universal-agent-workflow.md to gitignore
5. **Workflows cleaned:** Only `docker-release.yml` remains
6. **Docker build triggered:** https://github.com/kuniakil/openclaw/actions/runs/26557207557 (push trigger via v2026.5.26 tag)

---

## How to rollback

If `my-config-v2026.5.26` has issues and needs to revert:

```bash
# Option 1: Switch back to old branch
git checkout my-config-v2026.5.19

# Option 2: Force-push old branch to my-config-v2026.5.26
git checkout my-config-v2026.5.19
git push --force origin my-config-v2026.5.26
```

Backup branch at `a15b7d7783` preserves all custom history.

---

## Post-upgrade checklist

- [ ] Docker build completes successfully (amd64 + arm64)
- [ ] Verify image tag `v2026.5.26` contains our branch commits
- [ ] Deploy to Zeabur if image is good
- [ ] Check VPS environment variables still valid after upgrade

---

## Personal docs persistence (GEMINI.md / gitignore)

After this upgrade, personal operational docs are tracked in `.gitignore`:

```
GEMINI*.md
GEMINI-MASTER-PLAYBOOK.md
Upgrade-Retrospective*.md
Upgrade-Retrospective*.html
universal-agent-workflow.md
```

**For future upgrades**, restore personal docs with:

```bash
git checkout backup/my-config-v[old-version] -- GEMINI*.md .gitignore
git add GEMINI*.md .gitignore
git commit -m "chore: restore personal docs from backup"
```

---

## Commit history on new branch

```
fe4fcfb658 chore: add universal-agent-workflow.md to gitignore
da4419cb40 chore: restore GEMINI docs and add to gitignore
ae2de1b797 chore: cleanup official workflows
8338ffc4f0 chore: remove offline=true from pnpm prune for arm64 build
c065e7ac70 chore: ignore Upgrade-Retrospective files
9541eee2ac chore: restore Upgrade-Retrospective-v2026.5.6.md
10ad3aa160 chore(release): prepare 2026.5.26 stable  ← official v2026.5.26
...
```