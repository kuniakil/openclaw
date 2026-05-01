# syntax=docker/dockerfile:1.7

# ── Stage 1: Builder ───────────────────────────────────────────
# Use standard Node Bookworm image for building (robust build tools included)
FROM node:24-bookworm AS builder

# Install additional build-time dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ curl ca-certificates unzip && \
    rm -rf /var/lib/apt/lists/*

# Install Bun for build scripts
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Ensure pnpm is available
RUN corepack enable

WORKDIR /app
# Copy project source
COPY . .

# Pre-package all dependencies including plugin native addons.
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    OPENCLAW_EAGER_BUNDLED_PLUGIN_DEPS=1 \
    pnpm install --frozen-lockfile

# Generate the materialized manifest so OpenClaw recognizes the cache
# Hash for /app is f53b52ad6d21
RUN node -e ' \
    const fs = require("node:fs"); \
    const pkg = JSON.parse(fs.readFileSync("package.json", "utf8")); \
    const manifest = { \
      name: "openclaw-runtime-deps-install", \
      private: true, \
      dependencies: pkg.dependencies \
    }; \
    fs.writeFileSync("staged-manifest.json", JSON.stringify(manifest, null, 2)); \
    '

# ── Stage 2: Final Image ───────────────────────────────────────
FROM ghcr.io/openclaw/openclaw:2026.4.29
USER root

# Install runtime system tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 golang-go wget curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager and tool runner)
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Inject pre-packaged dependencies into the official cache directory.
# Directory name logic: openclaw-${version}-${pathHash}
ARG RUNTIME_DEPS_CACHE_DIR="/var/lib/openclaw/plugin-runtime-deps/openclaw-2026.4.29-f53b52ad6d21"
RUN mkdir -p ${RUNTIME_DEPS_CACHE_DIR}

# Copy compiled dependencies and manifest into the cache
COPY --from=builder /app/node_modules ${RUNTIME_DEPS_CACHE_DIR}/node_modules
COPY --from=builder /app/staged-manifest.json ${RUNTIME_DEPS_CACHE_DIR}/package.json

# Ensure correct permissions for the node user
RUN chown -R node:node /var/lib/openclaw/plugin-runtime-deps

# Revert to standard node user
USER node
WORKDIR /app
