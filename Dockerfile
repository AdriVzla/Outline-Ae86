# Stage 1: Build the application from your source code
FROM node:22.21.0-slim AS builder

ARG APP_PATH=/opt/outline
WORKDIR $APP_PATH

# Install build dependencies that might be needed for native modules
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*

# 1. Copiamos el código fuente (el .dockerignore evitará que se copien node_modules locales)
COPY . .

# 2. Configuración de Yarn para producción en Linux
# Forzamos 'node-modules' linker para evitar problemas de "state file"
RUN corepack enable
RUN echo "nodeLinker: node-modules" > .yarnrc.yml

# 3. Instalamos dependencias
# Usamos 'yarn install' simple para regenerar el lockfile si es necesario en Linux
RUN yarn install

# 4. Construimos la aplicación
# Aumentamos la memoria disponible para el proceso de build para evitar crashes
ENV NODE_OPTIONS="--max-old-space-size=4096"
RUN yarn build

# ---

# Stage 2: Create the final, lean production image
FROM node:22.21.0-slim AS runner

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

# Copy built artifacts and production node_modules from the builder stage
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/build ./build
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/server ./server
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/public ./public
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/.sequelizerc ./.sequelizerc
COPY --from=builder --chown=nodejs:nodejs $APP_PATH/package.json ./package.json
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

USER nodejs

HEALTHCHECK --interval=1m CMD wget -qO- "http://localhost:${PORT:-3000}/_health" | grep -q "OK" || exit 1

EXPOSE 3000
CMD ["node", "build/server/index.js"]