# Build context is the monorepo root, not this directory -- this package depends on
# @aqua-portfolio-manager/decoding via a pnpm workspace link (see package.json's "workspace:*"
# dependency), which needs the full workspace present to install and build. Matches
# apps/indexer/Dockerfile's own layout for the same reason. See deployment/docker-stack.yml for
# the actual build invocation.
FROM node:24.3.0-slim

ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
# Matches this repo's own package.json#packageManager.
RUN npm install -g pnpm@10.13.1

WORKDIR /repo

COPY . .

RUN pnpm install --frozen-lockfile
RUN pnpm --filter @aqua-portfolio-manager/arbitrageur build

WORKDIR /repo/apps/arbitrageur

# Migrations run on every start, not as a separate swarm job -- drizzle-kit migrate only applies
# pending migrations, so this is safe to repeat on every restart/redeploy. No --env-file: Docker
# Compose/Swarm already injects config via docker-stack.yml's environment block, unlike local dev
# (package.json's own "start" script), which reads a real .env file that doesn't exist in the image.
CMD ["sh", "-c", "pnpm db:migrate && node dist/main.js"]
