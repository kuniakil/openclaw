# syntax=docker/dockerfile:1.7

# ── Stage 1: Build ──────────────────────────────────────────────
# We use the standard multi-stage build provided by official OpenClaw
# but with EAGER_BUNDLED_PLUGIN_DEPS enabled to pre-package everything.

ARG OPENCLAW_EXTENSIONS="diagnostics-otel"
ARG OPENCLAW_BUNDLED_PLUGIN_DIR=extensions
ARG OPENCLAW_NODE_BOOKWORM_IMAGE="node:24-bookworm@sha256:3a09aa6354567619221ef6c45a5051b671f953f0a1924d1f819ffb236e520e6b"
ARG OPENCLAW_NODE_BOOKWORM_SLIM_IMAGE="node:24-bookworm-slim@sha256:e8e2e91b1378f83c5b2dd15f0247f34110e2fe895f6ca7719dbb780f929368eb"
ARG OPENCLAW_NODE_BOOKWORM_SLIM_DIGEST="sha256:e8e2e91b1378f83c5b2dd15f0247f34110e2fe895f6ca7719dbb780f929368eb"

FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS ext-deps
ARG OPENCLAW_EXTENSIONS
ARG OPENCLAW_BUNDLED_PLUGIN_DIR
RUN --mount=type=bind,source=${OPENCLAW_BUNDLED_PLUGIN_DIR},target=/tmp/${OPENCLAW_BUNDLED_PLUGIN_DIR},readonly \
    mkdir -p /out && \
    for ext in $OPENCLAW_EXTENSIONS; do \
      if [ -f "/tmp/${OPENCLAW_BUNDLED_PLUGIN_DIR}/$ext/package.json" ]; then \
        mkdir -p "/out/$ext" && \
        cp "/tmp/${OPENCLAW_BUNDLED_PLUGIN_DIR}/$ext/package.json" "/out/$ext/package.json"; \
      fi; \
    done

FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS build
ARG OPENCLAW_BUNDLED_PLUGIN_DIR

RUN set -eux; \
    apt-get update && apt-get install -y --no-install-recommends unzip && \
    for attempt in 1 2 3 4 5; do \
      if curl --retry 5 --retry-all-errors --retry-delay 2 -fsSL https://bun.sh/install | bash; then \
        break; \
      fi; \
      sleep $((attempt * 2)); \
    done
ENV PATH="/root/.bun/bin:${PATH}"
RUN corepack enable
WORKDIR /app

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY openclaw.mjs ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts/postinstall-bundled-plugins.mjs scripts/preinstall-package-manager-warning.mjs scripts/npm-runner.mjs scripts/windows-cmd-helpers.mjs ./scripts/
COPY scripts/lib/bundled-runtime-deps-install.mjs ./scripts/lib/bundled-runtime-deps-install.mjs
COPY scripts/lib/package-dist-imports.mjs ./scripts/lib/package-dist-imports.mjs

COPY --from=ext-deps /out/ ./${OPENCLAW_BUNDLED_PLUGIN_DIR}/

# OFFICIAL ENHANCEMENT: Enable eager bundling during install
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    NODE_OPTIONS=--max-old-space-size=2048 \
    OPENCLAW_EAGER_BUNDLED_PLUGIN_DEPS=1 \
    pnpm install --frozen-lockfile

COPY . .
RUN pnpm build:docker
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# ── Stage 2: Runtime Assets ─────────────────────────────────────
FROM build AS runtime-assets
ARG OPENCLAW_EXTENSIONS
ARG OPENCLAW_BUNDLED_PLUGIN_DIR
RUN printf 'packages:\n  - .\n  - ui\n' > /tmp/pnpm-workspace.runtime.yaml && \
    for ext in $OPENCLAW_EXTENSIONS; do \
      printf '  - %s/%s\n' "$OPENCLAW_BUNDLED_PLUGIN_DIR" "$ext" >> /tmp/pnpm-workspace.runtime.yaml; \
    done && \
    cp /tmp/pnpm-workspace.runtime.yaml pnpm-workspace.yaml && \
    CI=true NPM_CONFIG_FROZEN_LOCKFILE=false pnpm prune --prod && \
    OPENCLAW_EAGER_BUNDLED_PLUGIN_DEPS=1 node scripts/postinstall-bundled-plugins.mjs && \
    find dist -type f \( -name '*.d.ts' -o -name '*.d.mts' -o -name '*.d.cts' -o -name '*.map' \) -delete && \
    node scripts/check-package-dist-imports.mjs /app

# ── Stage 3: Runtime ────────────────────────────────────────────
FROM ${OPENCLAW_NODE_BOOKWORM_SLIM_IMAGE}
ARG OPENCLAW_BUNDLED_PLUGIN_DIR
WORKDIR /app

# Install runtime system utilities
RUN --mount=type=cache,id=openclaw-bookworm-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=openclaw-bookworm-apt-lists,target=/var/lib/apt,sharing=locked \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates procps hostname curl git lsof openssl python3 golang-go wget && \
    update-ca-certificates

# Install uv globally
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

RUN chown node:node /app

COPY --from=runtime-assets --chown=node:node /app/dist ./dist
COPY --from=runtime-assets --chown=node:node /app/node_modules ./node_modules
COPY --from=runtime-assets --chown=node:node /app/package.json .
COPY --from=runtime-assets --chown=node:node /app/patches ./patches
COPY --from=runtime-assets --chown=node:node /app/openclaw.mjs .
COPY --from=runtime-assets --chown=node:node /app/${OPENCLAW_BUNDLED_PLUGIN_DIR} ./${OPENCLAW_BUNDLED_PLUGIN_DIR}
COPY --from=runtime-assets --chown=node:node /app/skills ./skills
COPY --from=runtime-assets --chown=node:node /app/docs ./docs

# Pre-create and fix permissions for runtime volumes
RUN install -d -m 0755 -o node -g node /home/node/.openclaw && \
    install -d -m 0755 -o node -g node /var/lib/openclaw/plugin-runtime-deps

ENV NODE_ENV=production
ENV CI=true
USER node

HEALTHCHECK --interval=3m --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "openclaw.mjs", "gateway", "--allow-unconfigured"]
