# Build context is the monorepo root, not this directory -- this package depends on
# @aqua-portfolio-manager/addresses via a pnpm workspace link (see package.json's
# "workspace:*" dependency), which needs the full workspace present to install and build.
# See deployment/docker-stack.yml for the actual build invocation.
FROM node:24.3.0-slim

# psql is needed for dumping/restoring the initial effects cache, matching this repo's other
# Envio-based indexer deployments on the same host.
RUN apt-get update && \
    apt-get install -y --no-install-recommends postgresql-client && \
    rm -rf /var/lib/apt/lists/*

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
# Matches this repo's own package.json#packageManager.
RUN npm install -g pnpm@10.13.1

WORKDIR /repo

COPY . .

RUN pnpm install --frozen-lockfile
RUN pnpm --filter @aqua-portfolio-manager/indexer codegen

WORKDIR /repo/apps/indexer

CMD ["pnpm", "envio", "start"]
