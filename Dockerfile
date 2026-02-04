FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

# Install Ruby 3.3.8 via ruby-build
RUN apt-get update && apt-get install -y --no-install-recommends \
    autoconf bison build-essential libssl-dev libyaml-dev libreadline-dev \
    zlib1g-dev libncurses5-dev libffi-dev libgdbm-dev libgdbm-compat-dev \
    rustc gawk && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PostgreSQL 16 with pgvector from official PostgreSQL repo
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates gnupg && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-16 postgresql-16-pgvector postgresql-client-16 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure PostgreSQL to use /data/postgres for persistence
ENV PGDATA=/data/postgres
ENV PATH="/usr/lib/postgresql/16/bin:${PATH}"

# Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends gh && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install OpenAI Codex CLI globally
RUN npm install -g @openai/codex

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

ENV RUBY_VERSION=3.3.8
RUN git clone https://github.com/rbenv/ruby-build.git /tmp/ruby-build && \
    /tmp/ruby-build/bin/ruby-build $RUBY_VERSION /usr/local && \
    rm -rf /tmp/ruby-build

RUN gem install bundler

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Make entrypoint executable
RUN chmod +x /app/scripts/fly-entrypoint.sh

ENTRYPOINT ["/app/scripts/fly-entrypoint.sh"]
CMD ["node", "dist/index.js"]
