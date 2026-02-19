################################################################################
# Stage 1: builder — compile everything, then prune to production deps only
################################################################################
FROM node:22-bookworm AS builder

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

# Build tools for native modules + Ruby compilation
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf bison build-essential libssl-dev libyaml-dev libreadline-dev \
    zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev libgdbm-compat-dev \
    rustc gawk && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Compile Ruby 3.3.8 into /opt/ruby (clean copy target for runtime stage)
ENV RUBY_VERSION=3.3.8
RUN git clone https://github.com/rbenv/ruby-build.git /tmp/ruby-build && \
    /tmp/ruby-build/bin/ruby-build $RUBY_VERSION /opt/ruby && \
    rm -rf /tmp/ruby-build
RUN /opt/ruby/bin/gem install bundler

WORKDIR /app

# Install Node dependencies (full, including devDependencies for build)
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

# Copy source and build
COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build

# Ensure memory-lancedb extension dependencies are installed.
# LanceDB has native bindings that may not be hoisted by pnpm in all configurations.
RUN pnpm install --filter @openclaw/memory-lancedb --prod --no-frozen-lockfile || true

ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

# Save build output before pruning — pnpm prune may remove workspace dirs.
RUN cp -r dist /tmp/dist-save

# Strip devDependencies — native modules in `dependencies` survive this step.
# Both stages use bookworm so compiled .node binaries remain compatible.
RUN CI=true pnpm prune --prod

# Restore build output after prune.
RUN cp -r /tmp/dist-save dist


################################################################################
# Stage 2: runtime — slim image with only what's needed to run
################################################################################
FROM node:22-bookworm-slim

RUN corepack enable

# Runtime shared libraries for Ruby
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl3 libyaml-0-2 libreadline8 libffi8 libgdbm6 zlib1g libncurses6 \
    ca-certificates curl gnupg gawk && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# PostgreSQL 16 + pgvector (binary packages, no -dev headers)
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-16 postgresql-16-pgvector postgresql-client-16 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PGDATA=/data/postgres
ENV PATH="/usr/lib/postgresql/16/bin:${PATH}"

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# OpenAI Codex CLI
RUN npm install -g @openai/codex

# Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Optional extra packages
ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Copy Ruby from builder
COPY --from=builder /opt/ruby /opt/ruby
ENV PATH="/opt/ruby/bin:${PATH}"

WORKDIR /app

# Copy built artifacts and production node_modules from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/scripts ./scripts
COPY --from=builder /app/skills ./skills
COPY --from=builder /app/extensions ./extensions
COPY --from=builder /app/docs ./docs
COPY --from=builder /app/openclaw.mjs ./openclaw.mjs
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/pnpm-lock.yaml ./pnpm-lock.yaml
COPY --from=builder /app/pnpm-workspace.yaml ./pnpm-workspace.yaml
COPY --from=builder /app/.npmrc ./.npmrc

# Optionally install Chromium and Xvfb for browser automation.
# Build with: docker build --build-arg OPENCLAW_INSTALL_BROWSER=1 ...
# Adds ~300MB but eliminates the 60-90s Playwright install on every container start.
# Must run after node_modules copy so playwright-core is available.
ARG OPENCLAW_INSTALL_BROWSER=""
RUN if [ -n "$OPENCLAW_INSTALL_BROWSER" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends xvfb && \
      node /app/node_modules/playwright-core/cli.js install --with-deps chromium && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

ENV NODE_ENV=production

# Make entrypoint executable
RUN chmod +x /app/scripts/fly-entrypoint.sh

ENTRYPOINT ["/app/scripts/fly-entrypoint.sh"]
CMD ["node", "dist/index.js"]
