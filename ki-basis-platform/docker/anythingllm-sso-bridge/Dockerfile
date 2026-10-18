# Authentik → AnythingLLM Simple-SSO bridge (Approach C1).
FROM node:22-alpine

RUN apk add --no-cache tzdata musl-locales musl-locales-lang wget \
 && ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime

ENV TZ=Europe/Berlin \
    LANG=de_DE.UTF-8 \
    LC_ALL=de_DE.UTF-8 \
    LC_TIME=de_DE.UTF-8 \
    LC_MONETARY=de_DE.UTF-8 \
    LC_NUMERIC=de_DE.UTF-8 \
    NODE_ENV=production \
    ALLM_SSO_BRIDGE_PORT=8080 \
    ALLM_SSO_BRIDGE_HOST=0.0.0.0 \
    ALLM_SSO_BRIDGE_MAP_PATH=/app/identity-map.json

WORKDIR /app

COPY package.json ./
COPY lib/ ./lib/
COPY server.js ./
COPY identity-map.json ./

USER node
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/health >/dev/null || exit 1

CMD ["node", "server.js"]
