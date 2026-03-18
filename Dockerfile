# Stage 1: Build the application from your source code
FROM node:20.18.0-slim AS builder

ARG APP_PATH=/opt/outline
WORKDIR $APP_PATH

# Install build dependencies that might be needed for native modules
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*

# 1. Copy dependency manifests first to leverage Docker's layer cache.
COPY package.json yarn.lock .yarnrc.yml* ./
COPY patches ./patches/

# 2. Enable Corepack and install ALL dependencies.
# This layer will be cached and only re-run if package.json or yarn.lock change.
RUN corepack enable && yarn install --frozen-lockfile

# 3. Copy the rest of the source code.
# The .dockerignore file will prevent local node_modules, etc., from being copied.
COPY . .

# 4. Build the application.
# Set memory limit to 3GB to prevent hitting container limits (leaving room for OS)
ENV NODE_OPTIONS="--max-old-space-size=3072"
# Force production build behavior
ENV NODE_ENV=production

# Run build steps sequentially. Disable sourcemaps to save memory.
RUN yarn vite:build --sourcemap=false
RUN yarn build:i18n
RUN yarn build:server

# ---

# Stage 2: Create the final, lean production image
FROM node:20.18.0-slim AS runner

LABEL org.opencontainers.image.source="https://github.com/outline/outline"

ARG APP_PATH=/opt/outline
WORKDIR $APP_PATH
ENV NODE_ENV=production

# Disable Datadog tracing as it can interfere with module loading
ENV DD_TRACE_ENABLED=false

# Create a non-root user
RUN addgroup --gid 1001 nodejs && \
    adduser --uid 1001 --ingroup nodejs nodejs && \
    mkdir -p /var/lib/outline && \
    chown -R nodejs:nodejs /var/lib/outline && \
    chown -R nodejs:nodejs $APP_PATH

# Copy only the necessary built files and the full node_modules from the builder stage.
# This is faster and more reliable than reinstalling production dependencies.
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/build ./build
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/server ./server
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/public ./public
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/.sequelizerc ./.sequelizerc
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/package.json ./package.json
# Also copy the yarn lockfile for consistency
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/yarn.lock ./yarn.lock
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/.yarnrc.yml ./.yarnrc.yml
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/.yarn ./.yarn
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/node_modules ./node_modules

# Install wget to healthcheck the server
RUN  apt-get update \
    && apt-get install -y wget \
    && rm -rf /var/lib/apt/lists/*

# Setup local file storage directory
ENV FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data
RUN mkdir -p "$FILE_STORAGE_LOCAL_ROOT_DIR" && \
    chown -R nodejs:nodejs "$FILE_STORAGE_LOCAL_ROOT_DIR" && \
    chmod 1777 "$FILE_STORAGE_LOCAL_ROOT_DIR"

# Habilitar Corepack también en la imagen final para poder usar 'yarn' en el arranque
RUN corepack enable

USER nodejs

HEALTHCHECK --interval=1m CMD wget -qO- "http://localhost:${PORT:-3000}/_health" | grep -q "OK" || exit 1

EXPOSE 3000
# Ejecutar migraciones de base de datos antes de iniciar el servidor
CMD ["sh", "-c", "yarn db:migrate && node build/server/index.js"]