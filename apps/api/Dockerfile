# syntax=docker/dockerfile:1
#
# Reference image for the WattByte API (audit E-08). Build from the REPOSITORY ROOT:
#
#   docker build -f apps/api/Dockerfile -t wattbyte-api .
#
# Multi-stage: the build stage has pnpm and the dev dependencies and compiles; the runtime stage holds only the compiled
# output and production dependencies, runs as the unprivileged `node` user and answers a HEALTHCHECK on /health.
# Nothing secret is baked in: DATABASE_URL, JWT_SECRET and the rest arrive as environment variables at run time
# (docs/CONFIGURATION.md, docs/OPERATIONS.md).
#
# The base image is pinned by the digest of the multi-architecture index (node:22-bookworm-slim, Node 22.23.4 when pinned
# on 2026-10-30). Dependabot's `docker` ecosystem (or a manual bump) moves it; do not use a tag alone.
ARG NODE_IMAGE=node:22-bookworm-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da

FROM ${NODE_IMAGE} AS build
ENV CI=1
WORKDIR /repo
# The pnpm version comes from the root package.json "packageManager" field.
RUN corepack enable
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
COPY apps/api/package.json apps/api/
COPY apps/ai/package.json apps/ai/
COPY packages/contracts/package.json packages/contracts/
COPY packages/device-specs/package.json packages/device-specs/
RUN pnpm install --frozen-lockfile --filter "@wattbyte/api..."
COPY tsconfig.base.json ./
COPY scripts/copy-migrations.mjs scripts/
COPY apps/api apps/api
COPY apps/ai apps/ai
COPY packages packages
# Compiles the workspace dependencies first, then the API (and copies the .sql migrations next to the compiled migrator).
RUN pnpm --filter "@wattbyte/api..." build
# A self-contained production tree: compiled code plus production dependencies only.
RUN pnpm --filter @wattbyte/api --prod deploy --legacy /out \
 && rm -rf /out/src /out/tests /out/eslint.config.js /out/tsconfig.json /out/tsconfig.build.json

FROM ${NODE_IMAGE} AS runtime
ENV NODE_ENV=production \
    PORT=8080 \
    HOST=0.0.0.0
WORKDIR /app
COPY --from=build --chown=node:node /out/ ./
USER node
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["node", "-e", "fetch('http://127.0.0.1:'+(process.env.PORT||8080)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
# Migrations are a separate, deliberate step:  docker run --rm --env-file prod.env wattbyte-api node dist/database/migrate.js
# The retention job is scheduled the same way: node dist/scripts/retention.js   (docs/OPERATIONS.md)
CMD ["node", "dist/main.js"]
