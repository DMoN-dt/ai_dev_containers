#!/bin/zsh
set -e

echo "🤖 AI Agent Startup Sequence..."

# Проверка доступности Postgres
echo "🔎 Checking Postgres ($DB_HOST)..."
until pg_isready -h "$DB_HOST" -U "$DB_USER"; do
  echo "⏳ Waiting for Postgres..."
  sleep 2
done

# Проверка доступности отдельного Redis для AI
echo "🔎 Checking Redis (db_redis_ai)..."
until nc -z db_redis_ai 6379; do
  echo "⏳ Waiting for AI Redis..."
  sleep 2
done

# Проверка существования базы данных
# Пытаемся подключиться к БД, если нет — сигнализируем, что нужно запустить setup_ai_user
export PGPASSWORD="$DB_PASSWORD"
echo "🔎 Checking Postgres DB access: $POSTGRES_DB_DEVELOPMENT ..."
if ! psql -h "$DB_HOST" -U "$DB_USER" -d "$POSTGRES_DB_DEVELOPMENT" -c 'select 1' > /dev/null 2>&1; then
  echo "❌ ERROR: Database $POSTGRES_DB_DEVELOPMENT not found!"
  echo "💡 Please run this on your HOST: docker compose exec app ./bin/setup_ai_user <agent_name>"
  unset PGPASSWORD
  exit 1
fi

echo "🔎 Checking Postgres DB access: $POSTGRES_DB_TEST ..."
if ! psql -h "$DB_HOST" -U "$DB_USER" -d "$POSTGRES_DB_TEST" -c 'select 1' > /dev/null 2>&1; then
  echo "❌ ERROR: Database $POSTGRES_DB_TEST not found!"
  echo "💡 Please run this on your HOST: docker compose exec app ./bin/setup_ai_user <agent_name>"
  unset PGPASSWORD
  exit 1
fi

unset PGPASSWORD
echo "✅ Postgres is ready!"

# Проверка umask для rootless
if [ "$ROOTLESS_UMASK" = "true" ]; then
    umask 000
    echo "🔓 Umask set to 000 (Rootless mode)"
fi

APP_SOURCE_DIR="/app_${PROJECT_NAME}_ai_src"
APP_WORKING_DIR="/app_${PROJECT_NAME}_ai_out"

# Исправляем пути git worktree для работы внутри контейнера
if [ -f "$APP_WORKING_DIR/.git" ]; then
    echo "🔧 Fixing git worktree paths for container..."
    # Определяем, где на самом деле лежит .git основного репозитория внутри контейнера
    REAL_GIT_DIR="$APP_SOURCE_DIR/.git"
    
    # Перезаписываем файл .git в рабочей директории, чтобы он указывал на правильный путь внутри
    # Мы берем путь к воркдере из основного репозитория
    echo "gitdir: ${REAL_GIT_DIR}/worktrees/ai_worktree" > "$APP_WORKING_DIR/.git"
fi

# Настройка безопасных директорий для Git
# Это необходимо, так как файлы монтируются с хоста (разные UID)
echo "🛡️ Configuring Git safe directories..."
git config --global --add safe.directory "$APP_SOURCE_DIR"
git config --global --add safe.directory "$APP_WORKING_DIR"

# Создаем символическую ссылку /app, чтобы путь был привычным
# Направляем её на рабочую директорию (_ai_out)
if [ ! -e /app ]; then
    ln -s "$APP_WORKING_DIR" /app
    echo "🔗 Created symlink /app -> $APP_WORKING_DIR"
else
    echo "ℹ️  /app already exists, skipping symlink creation"
fi

# Проверка сетевой связности через прокси
# Если переменная https_proxy задана, проверяем доступность этого узла
echo "🛡️ Проверка выхода в Интернет..."
if [ -n "$https_proxy" ]; then
  PROXY_HOST=$(echo $https_proxy | sed -e 's|.*[/|//]\([^:/]*\).*|\1|')
  PROXY_PORT=$(echo $https_proxy | sed -e 's|.*:\([0-9]*\).*|\1|')

  echo "🛡️ Network Security: Routing via $PROXY_HOST:$PROXY_PORT"
  
  if ! nc -z "$PROXY_HOST" "$PROXY_PORT"; then
    echo "❌ ERROR: Proxy $PROXY_HOST:$PROXY_PORT is unreachable!"
    echo "Check if your host proxy is running and listening on the docker interface."
    exit 1
  fi

  # Проверка подключений к DNS и HTTPS
  if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 https://google.com/generate_204 | grep -q "204"; then
    echo "✅ Internet access confirmed (Google HTTP 204)"
  else
    echo "❌ ERROR: Proxy is UP, but no internet access!"
    echo "Check your host proxy settings."
    exit 1
  fi

  # Проверка Блокировки прямого доступа
  # Пытаемся пойти в обход прокси. В internal сети это должно упасть.
  echo "🛡️ Verifying network isolation..."
  if curl --noproxy "*" -s -m 2 https://google.com/generate_204 > /dev/null 2>&1; then
     echo "\n⚠️  WARNING: Direct Internet access is possible! Network Isolation failed.\n"
  else
     echo "🔒 Isolation confirmed: Internet access blocked."
  fi

  IP_CHECK_URL=http://ip-api.com/json/
  RES_NORMAL=$(curl -s "$IP_CHECK_URL")
  RES_NOPROXY=$(curl -s --noproxy "*" "$IP_CHECK_URL")

  if [ "$RES_NORMAL" = "$RES_NOPROXY" ]; then
    echo "⚠️  WARNING: No IP address spoofing via Proxy!"
  else
    echo "✅ PROXY detected: Different IP information"
  fi
  echo "\n💡 Current IP Address information:\n$RES_NORMAL\n"
else
  echo "\n⚠️  WARNING: PROXY Settings not found.\n"
fi

# Установка/проверка гемов
echo "📦 Checking bundle dependencies..."
bundle check || bundle install

# Синхронизация схемы (на случай, если в worktree пришли новые миграции)
echo "🏗️  Ensuring database schema is up to date..."
export PGHOST="$DB_HOST"
export PGPORT="$DB_PORT"
export PGUSER="$DB_USER"
export PGPASSWORD="$DB_PASSWORD"
#bundle exec rails db:prepare
unset PGPASSWORD

if ! command -v python3 &> /dev/null; then
    echo "🐍 Python-3 not found"
fi

# Запуск AI Wizard для проверки/установки агентов
if [ -f "/app_ai_tools/ai-wizard.sh" ]; then
    echo "======================"
    source "/app_ai_tools/ai-wizard.sh"
fi

echo "✅ AI Agent is ready to work!\n"

exec "$@"
