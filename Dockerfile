# syntax=docker/dockerfile:1.7

# Use the official production image as the foundation
FROM ghcr.io/openclaw/openclaw:2026.4.29
USER root

# Install system tools required for your skills/extensions
# We include build-essential (make, g++) because some plugins may need to re-compile 
# native addons during the in-place pnpm install.
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 golang-go wget curl ca-certificates unzip make g++ && \
    rm -rf /var/lib/apt/lists/*

# Install uv (Python package manager) globally
RUN curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR=/usr/local/bin sh

# Set environment variables to ensure non-interactive pnpm behavior
ENV CI=true
ENV NPM_CONFIG_CONFIRM_MODULES_PURGE=false
ENV OPENCLAW_EAGER_BUNDLED_PLUGIN_DEPS=1

WORKDIR /app

# Copy the project source to allow pnpm to resolve and compile plugin dependencies
# We copy it into /app which already exists in the base image, effectively 
# "warming up" the existing installation.
COPY . .

# Perform an in-place install to pre-package all plugin native dependencies.
# This ensures symlinks and binary compatibility are preserved within the official image.
RUN --mount=type=cache,id=openclaw-pnpm-store,target=/root/.local/share/pnpm/store,sharing=locked \
    pnpm install --frozen-lockfile

# Final cleanup: ensure correct ownership and revert to official user
RUN chown -R node:node /app
USER node

# Inherit the official ENTRYPOINT and CMD from the base image.
# The gateway will now start instantly as all dependencies are already "materialized".
