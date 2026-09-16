# ---- Build stage ----
FROM node:22-alpine AS build

WORKDIR /app

# Copy dependency manifests first so Docker can cache the npm install layer
# and skip it on later builds when only app code changes.
COPY web-app/package.json web-app/package-lock.json ./
RUN npm ci --omit=dev

# Copy application source
COPY web-app/app.js ./

# ---- Runtime stage ----
FROM node:22-alpine AS runtime

WORKDIR /app

# node:22-alpine lags Alpine security packages (e.g. OpenSSL CVE-2026-45447).
# Upgrade OS packages before dropping root so Trivy HIGH findings are patched.
RUN apk upgrade --no-cache \
  && addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/app.js ./app.js

USER appuser

# The app reads PORT from env (defaults to 8080 if unset)
ENV PORT=8080
EXPOSE 8080

# Matches the app's real health endpoint, not a guess
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/live', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "app.js"]
