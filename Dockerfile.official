# syntax=docker/dockerfile:1.7

# ── Stage 1: Builder ───────────────────────────────────────────
FROM node:24-bookworm AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ curl ca-certificates unzip && \
    rm -rf /var/lib/apt/lists/*

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

# Ensure pnpm is available
RUN corepack enable

WORKDIR /app
COPY . .

# Build dependencies
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    OPENCLAW_EAGER_BUNDLED_PLUGIN_DEPS=1 \
    pnpm install --frozen-lockfile

# ── Stage 2: Final Image ───────────────────────────────────────
FROM ghcr.io/openclaw/openclaw:2026.4.29
USER root

# Prevent pnpm from asking questions or failing without TTY
ENV CI=true
ENV NPM_CONFIG_CONFIRM_MODULES_PURGE=false

# Install runtime system tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 golang-go wget curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# TRICK: Make OpenClaw believe it is in a "Source Checkout" environment.
# This forces it to look for dependencies in /app/node_modules instead of 
# staging them to /var/lib/openclaw/plugin-runtime-deps/.
# This was verified on Mac to reduce staging time from 80s to 12ms.
RUN touch /app/pnpm-workspace.yaml && \
    mkdir -p /app/src && \
    mkdir -p /app/extensions

# Copy compiled dependencies directly into /app
# This ensures everything needed is present in the "dev-mode" root.
COPY --from=builder /app/node_modules /app/node_modules

# Ensure correct permissions
RUN chown -R node:node /app

# Use standard node user
USER node
WORKDIR /app
