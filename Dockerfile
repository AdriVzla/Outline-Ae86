# Stage 1: Build the application from your source code
FROM node:22.21.0-slim AS builder

ARG APP_PATH=/opt/outline
WORKDIR $APP_PATH

# Install build dependencies that might be needed for native modules
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*

# Copy dependency manifests first to leverage Docker cache
COPY package.json yarn.lock ./
COPY packages ./packages
COPY plugins ./plugins

# Install all dependencies and build the application
# This is the crucial step that compiles your modified code
RUN yarn install --frozen-lockfile

# Copy the rest of your source code
COPY . .

RUN yarn build

# ---

# Stage 2: Create the final, lean production image
FROM node:22.21.0-slim AS runner

LABEL org.opencontainers.image.source="https://github.com/outline/outline"

ARG APP_PATH=/opt/outline
WORKDIR $APP_PATH
ENV NODE_ENV=production

# Create a non-root user (same as your original Dockerfile)
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

# Setup local file storage directory (same as your original Dockerfile)
ENV FILE_STORAGE_LOCAL_ROOT_DIR=/var/lib/outline/data
RUN mkdir -p "$FILE_STORAGE_LOCAL_ROOT_DIR" && \
    chown -R nodejs:nodejs "$FILE_STORAGE_LOCAL_ROOT_DIR" && \
    chmod 1777 "$FILE_STORAGE_LOCAL_ROOT_DIR"

USER nodejs

HEALTHCHECK --interval=1m CMD wget -qO- "http://localhost:${PORT:-3000}/_health" | grep -q "OK" || exit 1

EXPOSE 3000
CMD ["node", "build/server/index.js"]
