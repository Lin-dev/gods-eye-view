# syntax=docker/dockerfile:1
###############################################################################
# God's Eye View — hosted image for the quashicorp k3s cluster (linux/arm64).
#
# The app has no separate compiled server: the /api/* provider proxies are Vite
# plugins that register configurePreviewServer, so `vite build` + `vite preview`
# serves the production bundle AND the API routes. The key-entry panel
# (Provider Settings / POWER UP) is deliberately excluded from preview, so keys
# come from the container environment only.
#
# Build (native arm64 on Apple Silicon):
#   docker buildx build --platform linux/arm64 \
#     --build-arg CESIUM_ION_TOKEN="$CESIUM_ION_TOKEN" \
#     -t 192.168.86.24:32000/gods-eye-view:<YYYYMMDD>-<sha7> --push .
#
# The two browser keys (GOOGLE_MAPS_API_KEY, CESIUM_ION_TOKEN) are compiled into
# the bundle via Vite `define`, so changing them means a rebuild. Every other
# provider key is read from process.env at request time (runtime Secret).
###############################################################################
FROM node:24-bookworm-slim

WORKDIR /app

# Puppeteer and sharp are QA-only devDependencies; skip the ~300 MB Chromium.
ENV PUPPETEER_SKIP_DOWNLOAD=1

# Browser-side keys, baked at build. Empty = keyless (Esri imagery, OSM fallback).
ARG GOOGLE_MAPS_API_KEY=""
ARG CESIUM_ION_TOKEN=""

# vite, vite-plugin-cesium and ws are devDependencies but required at runtime.
# Never `--omit=dev` and never set NODE_ENV=production before this step.
COPY package.json package-lock.json ./
RUN npm ci --include=dev && npm cache clean --force

COPY . .

RUN GOOGLE_MAPS_API_KEY="$GOOGLE_MAPS_API_KEY" CESIUM_ION_TOKEN="$CESIUM_ION_TOKEN" npm run build \
 && mkdir -p .gev-cache .gev-logs \
 && chown -R node:node .gev-cache .gev-logs

# HOST=0.0.0.0 is what flips Vite's allowedHosts to `true` (build/vite.js);
# without it a request with Host: eye.quashicorp.com is refused with 403.
ENV HOST=0.0.0.0 \
    PORT=4173

USER node
EXPOSE 4173

# node as PID 1 (npm would swallow SIGTERM). PORT does not reach `vite preview`,
# so the port is passed explicitly. `--configLoader native` imports
# vite.config.js directly instead of bundling it into node_modules/.vite-temp,
# so the pod can run with readOnlyRootFilesystem.
CMD ["node", "node_modules/vite/bin/vite.js", "preview", "--configLoader", "native", "--host", "0.0.0.0", "--port", "4173", "--strictPort"]
