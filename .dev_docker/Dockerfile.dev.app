ARG BASE_IMAGE=ruby:3.0.5-alpine

# Папка проекта внутри контейнера (значение заменяется из docker-compose.dev.yml)
ARG APP_DIR=/app

ARG TZONE=UTC
ARG ROOTLESS_UMASK=false

FROM ${BASE_IMAGE}

RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    postgresql-client \
    redis \
    git \
    openssh-client \
    libxml2-dev \
    libxslt-dev \
    tzdata \
    less \
    busybox-extras \
    poppler-utils \
    gcompat \
    libc6-compat \
    ncurses \
    curl \
    openssl \
    tcpdump \
    zsh \
    htop \
    mc

# Проброс переменных внутрь контейнера
ARG APP_DIR
ARG TZONE
ARG ROOTLESS_UMASK

# Установка Oh My Zsh для промпта с веткой git
RUN curl -fsSL -o /tmp/install.sh https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh && \
    sh /tmp/install.sh --unattended && \
    rm /tmp/install.sh && \
    git config --global --add safe.directory ${APP_DIR}

# Образ HOME для per-agent volumes /root: пустой named volume скрывает .zshrc/.oh-my-zsh.
RUN mkdir -p /opt/app-home-skeleton && \
    cp -a /root/.zshrc /root/.oh-my-zsh /root/.profile /root/.gitconfig /opt/app-home-skeleton/ 2>/dev/null || true

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_BIN=/usr/local/bundle/bin \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    LANG=C.UTF-8 \
    ROOTLESS_UMASK=$ROOTLESS_UMASK

WORKDIR ${APP_DIR}

COPY Gemfile Gemfile.lock ./
RUN export BUNDLER_VERSION=$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1 | tr -d '[:space:]') && \
    gem install bundler -v $BUNDLER_VERSION --no-document && \
    bundle install

# Если /app не существует, то создать symbolic link
RUN if [ "${APP_DIR}" != "/app" ] && [ ! -e /app ]; then \
        ln -s "${APP_DIR}" /app; \
    fi

# Для rootless mode создаем entrypoint с запуском umask 000,
# чтобы новые файлы в контейнере создавались с правами rw-rw-rw-
# Заодно восстанавливаем образ HOME при первом запуске с пустым volume.
RUN printf '#!/bin/sh\n\
if [ "$ROOTLESS_UMASK" = "true" ]; then\n\
    umask 000\n\
fi\n\
if [ -d /opt/app-home-skeleton ] && [ ! -e "$HOME/.zshrc" ]; then\n\
    cp -a /opt/app-home-skeleton/. "$HOME/"\n\
fi\n\
exec "$@"\n' > /entrypoint.sh \
    && chmod +x /entrypoint.sh

# RUN echo 'if [ "$ROOTLESS_UMASK" = "true" ]; then \
#    umask 000; \
#    echo "🔓 Umask set to 000 (Rootless mode)"; \
# fi' > /etc/profile.d/rootless_umask.sh \
# && chmod +x /etc/profile.d/rootless_umask.sh

# Устанавливаем часовой пояс
RUN if [ ! -f "/usr/share/zoneinfo/$TZONE" ]; then \
        echo "FATAL: Invalid Timezone '$TZONE'. Check your .env file."; \
        exit 1; \
    fi && \
    ln -snf "/usr/share/zoneinfo/$TZONE" /etc/localtime && \
    echo "$TZONE" > /etc/timezone

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/bin/zsh"]
