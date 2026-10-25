#!/bin/zsh
set -e

: "${PROJECT_NAME:?PROJECT_NAME is required}"
: "${AI_AGENT_INSTANCE:=ai_agent}"

APP_SOURCE_DIR="/app_${PROJECT_NAME}_ai_src"
APP_WORKING_DIR="/app_${PROJECT_NAME}_ai_out"

INSTANCE_TAG="[${AI_AGENT_INSTANCE}]"
log() { echo "${INSTANCE_TAG} $*"; }

if [ -f /app_ai_lib/ai_common.sh ]; then
  AI_PROJECT_ROOT="$APP_SOURCE_DIR"
  . /app_ai_lib/ai_common.sh
fi

fallback_worktree_name() {
  case "$AI_AGENT_INSTANCE" in
    ai_agent)
      echo "ai_worktree"
      ;;
    ai_agent_[0-9]*)
      echo "ai${AI_AGENT_INSTANCE#ai_agent_}_worktree"
      ;;
    *)
      echo "${AI_AGENT_INSTANCE}_worktree"
      ;;
  esac
}

log "🤖 AI Agent Startup Sequence..."

if [ "${ROOTLESS_UMASK:-false}" = "true" ]; then
  umask 000
  log "🔓 Umask set to 000 (Rootless mode)"
fi

# Пустой HOME volume скрывает .zshrc/.oh-my-zsh из образа.
if [ -d /opt/app-home-skeleton ] && [ ! -e "$HOME/.zshrc" ]; then
  cp -a /opt/app-home-skeleton/. "$HOME/" 2>/dev/null || true
fi
export GIT_OPTIONAL_LOCKS=0

# Compose обязан передать эти переменные в environment контейнера:
# docker compose exec не видит export'ы, сделанные PID 1.
: "${DB_HOST:=db_postgres}"
: "${DB_PORT:=5432}"
: "${DB_USER:?DB_USER is required}"
: "${DB_PASSWORD:?DB_PASSWORD is required}"
: "${POSTGRES_DB_DEVELOPMENT:?POSTGRES_DB_DEVELOPMENT is required}"
: "${POSTGRES_DB_TEST:?POSTGRES_DB_TEST is required}"
: "${REDIS_URL:?REDIS_URL is required}"

export DB_HOST DB_PORT DB_USER DB_PASSWORD POSTGRES_DB_DEVELOPMENT POSTGRES_DB_TEST
export PGHOST="${PGHOST:-$DB_HOST}"
export PGPORT="${PGPORT:-$DB_PORT}"
export PGUSER="${PGUSER:-$DB_USER}"
export PGPASSWORD="${PGPASSWORD:-$DB_PASSWORD}"

REDIS_HOST="${REDIS_HOST:-db_redis_ai}"
REDIS_PORT="${REDIS_PORT:-6379}"
TEST_DB_WITH_SUFFIX="${POSTGRES_DB_TEST}${TEST_ENV_NUMBER:-}"

# Postgres
if [ "${AI_CHECK_POSTGRES:-true}" = "true" ]; then
  log "🔎 Checking Postgres ($DB_HOST:$DB_PORT)..."
  until pg_isready -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" >/dev/null 2>&1; do
    log "⏳ Waiting for Postgres..."
    sleep 2
  done
fi

# Redis
if [ "${AI_CHECK_REDIS:-true}" = "true" ]; then
  log "🔎 Checking Redis ($REDIS_HOST:$REDIS_PORT)..."
  if command -v redis-cli >/dev/null 2>&1; then
    until redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping 2>/dev/null | grep -q PONG; do
      log "⏳ Waiting for Redis..."
      sleep 2
    done
  else
    until nc -z "$REDIS_HOST" "$REDIS_PORT"; do
      log "⏳ Waiting for Redis..."
      sleep 2
    done
  fi
  log "✅ Redis is ready"
fi

# Проверка доступа к своим БД
if [ "${AI_CHECK_POSTGRES:-true}" = "true" ]; then
  log "🔎 Checking database access: $POSTGRES_DB_DEVELOPMENT, $TEST_DB_WITH_SUFFIX"
  for db in "$POSTGRES_DB_DEVELOPMENT" "$TEST_DB_WITH_SUFFIX"; do
    if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$db" -c 'select 1' >/dev/null 2>&1; then
      log "❌ ERROR: Database $db is not available for user $DB_USER"
      log "💡 Run on host: docker compose exec app sh ./.dev/setup_ai_user.sh $AI_AGENT_INSTANCE -y"
      exit 1
    fi
  done
  log "✅ Postgres is ready"
fi


# Git worktree: имя берём из текущего .git, fallback — отображение слота.
GIT_FILE="$APP_WORKING_DIR/.git"
if [ ! -f "$GIT_FILE" ]; then
  log "❌ ERROR: $APP_WORKING_DIR is not an initialized git worktree"
  log "💡 Run on host: ./.dev/wtree create $AI_AGENT_INSTANCE"
  exit 1
fi

GITDIR_LINE=$(sed -n 's/^gitdir: //p' "$GIT_FILE" | head -n 1)
if [ -n "$GITDIR_LINE" ]; then
  WT_NAME=$(basename -- "$GITDIR_LINE")
else
  WT_NAME=$(fallback_worktree_name)
fi

TARGET_GITDIR="$APP_SOURCE_DIR/.git/worktrees/$WT_NAME"
if [ ! -d "$TARGET_GITDIR" ]; then
  FALLBACK_NAME=$(fallback_worktree_name)
  TARGET_GITDIR="$APP_SOURCE_DIR/.git/worktrees/$FALLBACK_NAME"
fi
if [ ! -d "$TARGET_GITDIR" ]; then
  log "❌ ERROR: git metadata not found for worktree '$WT_NAME' in $APP_SOURCE_DIR/.git/worktrees"
  log "💡 Run on host: ./.dev/wtree create $AI_AGENT_INSTANCE && ./.dev/wtree docker"
  exit 1
fi

if [ "$GITDIR_LINE" = "$TARGET_GITDIR" ]; then
  log "✅ Git worktree path is correct"
else
  log "🔧 Fixing git worktree path: $APP_WORKING_DIR -> $TARGET_GITDIR"

  # Пытаемся перезаписать файл только в случае реального несовпадения путей
  if ! error_msg=$(printf 'gitdir: %s\n' "$TARGET_GITDIR" 2>&1 >"$GIT_FILE"); then
    echo ""
    log "❌ ERROR: Failed to write to $GIT_FILE"
    log "📝 System error details: $error_msg"
    log "💡 Check your docker volumes configuration and file permissions."
  else
    log "✅ Git worktree path successfully updated"
  fi
fi


for dir in "$APP_SOURCE_DIR" "$APP_WORKING_DIR"; do
  if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx "$dir"; then
    git config --global --add safe.directory "$dir"
  fi
done

# /app должен указывать на рабочий worktree.
if [ -L /app ]; then
  ln -sfn "$APP_WORKING_DIR" /app
elif [ ! -e /app ]; then
  ln -s "$APP_WORKING_DIR" /app
else
  log "ℹ️  /app exists and is not a symlink; skip"
fi

# Проверка сети/прокси (опционально).
if [ "${AI_VERIFY_NETWORK:-true}" = "true" ]; then
  if [ -n "${https_proxy:-}" ]; then
    PROXY_NO_SCHEME=${https_proxy#*://}
    PROXY_HOST=${PROXY_NO_SCHEME%%:*}
    PROXY_PORT=${PROXY_NO_SCHEME#*:}
    PROXY_PORT=${PROXY_PORT%%/*}
    [ "$PROXY_PORT" != "$PROXY_NO_SCHEME" ] || PROXY_PORT=80

    log "🛡️ Network Security: Routing via $PROXY_HOST:$PROXY_PORT"
    if ! nc -z "$PROXY_HOST" "$PROXY_PORT"; then
      log "❌ ERROR: Proxy $PROXY_HOST:$PROXY_PORT is unreachable!"
      exit 1
    fi

    if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://google.com/generate_204 | grep -q "204"; then
      log "✅ Internet access confirmed"
    else
      log "❌ ERROR: Proxy is UP, but no internet access!"
      exit 1
    fi

    if curl --noproxy "*" -s -m 2 https://google.com/generate_204 >/dev/null 2>&1; then
      log "⚠️  WARNING: Direct Internet access is possible! Network isolation failed."
    else
      log "🔒 Isolation confirmed: direct Internet access blocked"
    fi
  else
    log "⚠️  WARNING: Proxy settings not found"
  fi
fi

# Bundle: используем гемы из образа; install только при необходимости.
if bundle check >/dev/null 2>&1; then
  log "📦 Bundle dependencies are satisfied"
elif [ "${AI_BUNDLE_INSTALL:-auto}" = "no" ]; then
  log "⚠️  Bundle dependencies are missing, AI_BUNDLE_INSTALL=no — skipping"
else
  log "📦 Installing bundle dependencies..."
  bundle install
fi

# Локальный конфиг: создаём development.local.yml, test.local.yml при необходимости и
# дополняем существующий файл новыми полями из development/test.yml.
AI_CONFIG_SCRIPT="/app_ai_tools/setup_ai_config.sh"
if [ -f "$AI_CONFIG_SCRIPT" ]; then
  log "⚙️  Preparing local settings config..."
  if ! ( cd "$APP_WORKING_DIR" && sh "$AI_CONFIG_SCRIPT" soft_update ); then
    log "⚠️  setup_ai_config.sh failed; continuing"
  fi
else
  log "⚠️  setup_ai_config.sh not found; skipping"
fi

# Опциональная загрузка development-схемы в пустую БД.
if [ "${AI_AUTO_DB_PREPARE:-false}" = "true" ]; then
  if ! psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$POSTGRES_DB_DEVELOPMENT" \
       -tAc "SELECT to_regclass('public.schema_migrations')" 2>/dev/null | grep -q .; then
    log "🏗️  Empty database detected, loading development schema..."
    bundle exec rails db:schema:load
  else
    log "ℹ️  Development database already has a schema; skipping db:schema:load"
  fi
fi

# Сброс избыточных прав на запись для групп и других пользователей в папке автодополнений zsh
chmod -R g-w,o-w /root/.oh-my-zsh/cache/completions 2>/dev/null || true

# Wizard: установка/проверка CLI.
if [ -f /app_ai_tools/ai-wizard.sh ]; then
  log "======================"
  if ! source /app_ai_tools/ai-wizard.sh; then
    log "⚠️  AI wizard failed; shell is still available"
  fi
fi

log "✅ AI Agent is ready to work!"
echo ""
exec "$@"
