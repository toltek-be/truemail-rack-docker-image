# --- Étape de build ---
FROM ruby:3.3-alpine AS builder

RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache \
        git \
        build-base \
        shared-mime-info

WORKDIR /usr/src/app

# Clonage léger sans l'historique complet pour accélérer le build
RUN git clone --depth=1 https://github.com/truemail-rb/truemail-rack.git . && \
    rm -rf .git && \
    sed -i '/^ruby(/d' Gemfile

RUN bundle config set --local without 'development test' && \
    bundle update truemail && \
    bundle install && \
    bundle clean --force && \
    rm -rf /usr/local/bundle/cache/*.gem /root/.bundle /root/.gem

# --- Étape finale (Production) ---
FROM ruby:3.3-alpine

# Mise à jour des paquets de base pour corriger les CVEs et installation minimale
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache tzdata libstdc++ && \
    addgroup -g 10001 -S truemail && \
    adduser -u 10001 -S -G truemail -s /sbin/nologin truemail

WORKDIR /usr/src/app

ENV RACK_ENV=production \
    PORT=9292

# Copie des dépendances et de l'application
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY --from=builder --chown=truemail:truemail /usr/src/app /usr/src/app

USER truemail

EXPOSE 9292

# Healthcheck utilisant wget (intégré à BusyBox) pour éliminer curl et réduire les vulnérabilités
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:9292/healthcheck || exit 1

CMD ["bundle", "exec", "rackup", "-o", "0.0.0.0", "-p", "9292"]
