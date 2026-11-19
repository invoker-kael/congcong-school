FROM node:22-bookworm-slim AS build
WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY package.json package-lock.json ./
COPY apps/web/package.json apps/web/package.json
COPY packages/core/package.json packages/core/package.json
RUN npm ci --no-audit --no-fund

# Bundle course data and images; mount the large web audio archive at runtime.
COPY scripts/install-release.py scripts/install-release.py
ARG ASSETS_RELEASE=v1.8.3
RUN python3 scripts/install-release.py --tag "$ASSETS_RELEASE" \
    --asset-kind story-images \
    --asset-kind textbook-pages \
    --asset-kind source-data \
    --asset-kind data

COPY packages/core packages/core
COPY apps/web apps/web
COPY output output
COPY content content
COPY scripts/tts/apply_audio_versions.py scripts/tts/apply_audio_versions.py
COPY release/audio-version-map.json release/audio-version-map.json
COPY release/content-baseline-v1.4.0.json release/content-baseline-v1.4.0.json
COPY scripts/checks/content-retention.py scripts/checks/content-retention.py
COPY scripts/run-python.mjs scripts/run-python.mjs
RUN WEB_AUDIO_EXTERNAL=1 npm run build:container --workspace=china-study-free

FROM nginx:stable-alpine AS runtime
COPY docker/nginx.conf /etc/nginx/nginx.conf
COPY LICENSE /usr/share/nginx/html/LICENSE.txt
USER nginx
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
CMD ["nginx", "-g", "daemon off;"]

# Optional fast packaging of an already built site; provide the named context.
FROM runtime AS prebuilt
COPY --chown=nginx:nginx --from=site / /usr/share/nginx/html

# Default: build the static web app; verified MP3 audio is mounted at runtime.
FROM runtime AS production
COPY --chown=nginx:nginx --from=build /app/apps/web/out /usr/share/nginx/html
