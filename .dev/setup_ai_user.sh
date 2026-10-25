#!/bin/sh
# Создание/обновление пользователя и БД AI-агента.
#
# Запускать в контейнере app (там есть админские креды Postgres):
#   docker compose exec app ./.dev/setup_ai_user.sh ai_agent_2 -y
#
# Схему скрипт НЕ загружает: она должна грузиться из worktree конкретного агента.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
AI_DEV_DIR="$SCRIPT_DIR"
AI_PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/lib/ai_common.sh"

usage() {
  cat <<'EOF'
Использование:
  setup_ai_user.sh <slot> [options]

Слот: ai_agent, ai_agent_2, ai_agent_3, ...

Опции:
  --user NAME          пользователь БД (иначе AI_AGENT*_DB_USER)
  --password PASS      пароль (иначе AI_AGENT*_DB_PASSWORD)
  --dev-db NAME        development-БД (иначе AI_AGENT*_DB_DEVELOPMENT)
  --test-db NAME       test-БД (точное имя; иначе AI_AGENT*_DB_TEST + TEST_ENV_NUMBER)
  --owner NAME         владелец новых БД (существующий пользователь; по умолчанию — $PGUSER, иначе — пользователь слота)
  --grant-to NAME      выдать права ещё одному пользователю (можно повторять)
  --read-only          все выданные права — только SELECT (не для миграций/RSpec)
  --co-owner           выдать membership в роли владельца БД (для миграций/db:test:prepare)
  --grant-only         не создавать пользователя/БД, только выдать права
  --dry-run            показать план/SQL, ничего не менять
  -y, --yes            без подтверждения
  -h, --help           эта справка
EOF
}

SLOT=""
USER_OVERRIDE=""
PASS_OVERRIDE=""
DEV_DB_OVERRIDE=""
TEST_DB_OVERRIDE=""
OWNER_OVERRIDE=""
GRANT_TO=""
READ_ONLY=0
CO_OWNER=0
GRANT_ONLY=0
DRY_RUN=0
ASSUME_YES=0

if [ "$#" -gt 0 ]; then
  case "$1" in
    -*) ;;
    *) SLOT=$1; shift ;;
  esac
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --user) USER_OVERRIDE=${2:?--user requires a value}; shift 2 ;;
    --password) PASS_OVERRIDE=${2:?--password requires a value}; shift 2 ;;
    --dev-db) DEV_DB_OVERRIDE=${2:?--dev-db requires a value}; shift 2 ;;
    --test-db) TEST_DB_OVERRIDE=${2:?--test-db requires a value}; shift 2 ;;
    --owner) OWNER_OVERRIDE=${2:?--owner requires a value}; shift 2 ;;
    --grant-to) GRANT_TO="$GRANT_TO ${2:?--grant-to requires a value}"; shift 2 ;;
    --read-only) READ_ONLY=1; shift ;;
    --co-owner) CO_OWNER=1; shift ;;
    --grant-only) GRANT_ONLY=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "❌ Неизвестная опция: $1" >&2; usage; exit 1 ;;
  esac
done

[ -n "$SLOT" ] || { usage; exit 1; }

if [ "$READ_ONLY" = "1" ] && [ "$CO_OWNER" = "1" ]; then
  ai_die "--read-only и --co-owner взаимоисключающие"
fi

SLOT=$(ai_normalize_slot "$SLOT")
PREFIX=$(printf '%s' "$SLOT" | tr '[:lower:]' '[:upper:]')
case "$PREFIX" in
  *[!A-Z0-9_]*) ai_die "Некорректный слот: $SLOT" ;;
esac

PROJECT=$(ai_project_name)
PROJECT=$(printf '%s' "$PROJECT" | tr '[:upper:]' '[:lower:]')

env_val() {
  printenv "$1" 2>/dev/null || true
}

ENV_USER=$(env_val "${PREFIX}_DB_USER")
ENV_PASS=$(env_val "${PREFIX}_DB_PASSWORD")
ENV_DEV=$(env_val "${PREFIX}_DB_DEVELOPMENT")
ENV_TEST=$(env_val "${PREFIX}_DB_TEST")
ENV_TEST_SUFFIX=$(env_val "${PREFIX}_TEST_ENV_NUMBER")

DB_USER=${USER_OVERRIDE:-$ENV_USER}
DB_PASS=${PASS_OVERRIDE:-$ENV_PASS}

if [ -n "$DEV_DB_OVERRIDE" ]; then
  DB_DEV=$DEV_DB_OVERRIDE
else
  DB_DEV=${ENV_DEV:-ai_${PROJECT}_${SLOT}_development}
fi

if [ -n "$TEST_DB_OVERRIDE" ]; then
  DB_TEST=$TEST_DB_OVERRIDE
else
  DB_TEST=${ENV_TEST:-ai_${PROJECT}_${SLOT}_test}
  DB_TEST="${DB_TEST}${ENV_TEST_SUFFIX:-}"
fi

[ -n "$DB_USER" ] || ai_die "Не задан пользователь БД. Укажите --user или ${PREFIX}_DB_USER в .env"
[ -n "$DB_PASS" ] || ai_die "Не задан пароль БД. Укажите --password или ${PREFIX}_DB_PASSWORD в .env"

for value in "$DB_USER" "$DB_DEV" "$DB_TEST" ${OWNER_OVERRIDE:-}; do
  printf '%s' "$value" | grep -Eq '^[a-z][a-z0-9_]*$' || \
    ai_die "Некорректное имя (нужно [a-z][a-z0-9_]*): $value"
done

for grantee in $GRANT_TO; do
  printf '%s' "$grantee" | grep -Eq '^[a-z][a-z0-9_]*$' || \
    ai_die "Некорректный --grant-to: $grantee"
done

NEWLINE_CHECK=$(printf '%s' "$DB_PASS" | wc -l | tr -d ' ')
[ "$NEWLINE_CHECK" = "0" ] || ai_die "Пароль не должен содержать перевод строки"

OWNER_FOR_NEW_DB=${OWNER_OVERRIDE:-${PGUSER:-$DB_USER}}

# Список грантополучателей: user:rw|ro. Пользователь слота — первым.
GRANTEES=""
add_grantee() {
  local user mode
  user=$1
  mode=$2
  case " $GRANTEES " in
    *" $user:"*) return 0 ;;
  esac
  GRANTEES="$GRANTEES $user:$mode"
}

SLOT_MODE=rw
if [ "$READ_ONLY" = "1" ]; then
  SLOT_MODE=ro
fi
add_grantee "$DB_USER" "$SLOT_MODE"

for grantee in $GRANT_TO; do
  add_grantee "$grantee" "$SLOT_MODE"
done

TITLE_KIND="AI-агента"
if [ "$SLOT" = "app" ]; then
  TITLE_KIND="таблиц для App"
fi

echo "----------------------------------------------------------"
echo "🚀 Настройка $TITLE_KIND (Postgres)"
echo "Проект:          $PROJECT"
echo "Слот:            $SLOT"
echo "Пользователь:    $DB_USER"
echo "Development DB:  $DB_DEV"
echo "Test DB:         $DB_TEST"
echo "Режим прав:      $SLOT_MODE"
if [ "$GRANT_ONLY" = "1" ]; then echo "Режим:           grant-only (без создания)"; fi
if [ "$CO_OWNER" = "1" ]; then echo "Co-owner:        membership в роли владельца"; fi
if [ -n "$GRANT_TO" ]; then echo "Доп. гранты:     $GRANT_TO"; fi
echo "----------------------------------------------------------"

if [ "$DRY_RUN" = "1" ]; then
  echo "🧪 DRY RUN: psql не вызывается"
  echo ""
  echo "-- role:"
  echo "SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', '$DB_USER', '<password>') WHERE NOT EXISTS (...);"
  echo "ALTER ROLE \"$DB_USER\" WITH LOGIN PASSWORD '<password>';"
  echo ""
  for db in "$DB_DEV" "$DB_TEST"; do
    echo "-- database: $db"
    if [ "$GRANT_ONLY" != "1" ]; then
      echo "CREATE DATABASE \"$db\" OWNER \"$OWNER_FOR_NEW_DB\"; -- если ещё нет"
      echo "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
      echo "CREATE EXTENSION IF NOT EXISTS \"uuid-ossp\";"
    fi
    for item in $GRANTEES; do
      grantee=${item%%:*}
      mode=${item##*:}
      if [ "$mode" = "ro" ]; then
        echo "GRANT CONNECT ON DATABASE \"$db\" TO \"$grantee\";"
        echo "GRANT USAGE ON SCHEMA public TO \"$grantee\";"
        echo "GRANT SELECT ON ALL TABLES/SEQUENCES IN SCHEMA public TO \"$grantee\";"
        echo "ALTER DEFAULT PRIVILEGES ... GRANT SELECT ... TO \"$grantee\";"
      else
        echo "GRANT CONNECT, TEMPORARY, CREATE ON DATABASE \"$db\" TO \"$grantee\";"
        echo "GRANT USAGE, CREATE ON SCHEMA public TO \"$grantee\";"
        echo "GRANT ALL ON ALL TABLES/SEQUENCES/FUNCTIONS IN SCHEMA public TO \"$grantee\";"
        echo "ALTER DEFAULT PRIVILEGES ... GRANT ALL ... TO \"$grantee\";"
      fi
      if [ "$CO_OWNER" = "1" ]; then
        echo "GRANT \"<owner>\" TO \"$grantee\"; -- если owner не admin"
      fi
    done
    echo ""
  done
  exit 0
fi

[ "$ASSUME_YES" = "1" ] || {
  if [ ! -t 0 ]; then
    ai_die "Нет TTY для подтверждения. Используйте --yes"
  fi
  printf 'Продолжить? (y/n): '
  read -r answer
  case "$answer" in
    y|Y) ;;
    *) echo "🚫 Отменено"; exit 0 ;;
  esac
}

ai_require_command psql
: "${PGHOST:?PGHOST не задан (запускайте в app-контейнере)}"
: "${PGUSER:?PGUSER не задан (нужны админские креды)}"
: "${PGPASSWORD:?PGPASSWORD не задан (нужны админские креды)}"
PGPORT=${PGPORT:-5432}

psql_admin() {
  local db
  db=$1
  shift
  psql -X -q -v ON_ERROR_STOP=1 -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$db" "$@"
}

role_exists() {
  psql_admin postgres -tA -c "SELECT 1 FROM pg_roles WHERE rolname = quote_ident('$1')" 2>/dev/null | grep -q 1
}

db_exists() {
  psql_admin postgres -tA -c "SELECT 1 FROM pg_database WHERE datname = quote_ident('$1')" 2>/dev/null | grep -q 1
}

db_owner() {
  psql_admin postgres -tA -c "SELECT pg_get_userbyid(datdba) FROM pg_database WHERE datname = quote_ident('$1')" 2>/dev/null | head -n 1
}

if [ "$GRANT_ONLY" = "1" ]; then
  role_exists "$DB_USER" || ai_die "Пользователь $DB_USER не существует; сначала выполните setup без --grant-only"
else
  echo "👤 Создаю/обновляю пользователя $DB_USER"
  psql_admin postgres -v db_user="$DB_USER" -v db_pass="$DB_PASS" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'db_user', :'db_pass')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'db_user')
\gexec
SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'db_user', :'db_pass')
\gexec
SQL
fi

for grantee in $GRANT_TO; do
  role_exists "$grantee" || ai_die "Пользователь $grantee не существует; сначала выполните setup для его слота"
done

for db in "$DB_DEV" "$DB_TEST"; do
  echo "⚙️  База: $db"

  if [ "$GRANT_ONLY" = "1" ]; then
    db_exists "$db" || ai_die "База $db не существует; сначала выполните setup без --grant-only"
  else
    if ! db_exists "$db"; then
      echo "   создаю БД (owner: $OWNER_FOR_NEW_DB)"
      psql_admin postgres -v db_name="$db" -v db_owner="$OWNER_FOR_NEW_DB" <<'SQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'db_owner')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name')
\gexec
SQL
    else
      echo "   БД уже существует, ownership не меняю"
    fi
  fi

  owner=$(db_owner "$db")
  [ -n "$owner" ] || ai_die "Не удалось определить owner для $db"

  echo "   extensions: pg_trgm, uuid-ossp"
  psql_admin "$db" -c 'CREATE EXTENSION IF NOT EXISTS pg_trgm; CREATE EXTENSION IF NOT EXISTS "uuid-ossp";'

  for item in $GRANTEES; do
    grantee=${item%%:*}
    mode=${item##*:}
    echo "   grants: $grantee ($mode)"

    if [ "$mode" = "ro" ]; then
      psql_admin "$db" -v db="$db" -v grantee="$grantee" -v owner="$owner" <<'SQL'
GRANT CONNECT ON DATABASE :"db" TO :"grantee";
GRANT USAGE ON SCHEMA public TO :"grantee";
GRANT SELECT ON ALL TABLES IN SCHEMA public TO :"grantee";
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public GRANT SELECT ON TABLES TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public GRANT SELECT ON SEQUENCES TO :"grantee";
SQL
    else
      psql_admin "$db" -v db="$db" -v grantee="$grantee" -v owner="$owner" <<'SQL'
GRANT CONNECT, TEMPORARY, CREATE ON DATABASE :"db" TO :"grantee";
GRANT USAGE, CREATE ON SCHEMA public TO :"grantee";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO :"grantee";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO :"grantee";
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public GRANT ALL ON TABLES TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public GRANT ALL ON SEQUENCES TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA public GRANT ALL ON FUNCTIONS TO :"grantee";
SQL
    fi

    if psql_admin "$db" -tA -c "SELECT 1 FROM pg_namespace WHERE nspname = 'analytics'" 2>/dev/null | grep -q 1; then
      if [ "$mode" = "ro" ]; then
        psql_admin "$db" -v grantee="$grantee" -v owner="$owner" <<'SQL'
GRANT USAGE ON SCHEMA analytics TO :"grantee";
GRANT SELECT ON ALL TABLES IN SCHEMA analytics TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA analytics GRANT SELECT ON TABLES TO :"grantee";
SQL
      else
        psql_admin "$db" -v grantee="$grantee" -v owner="$owner" <<'SQL'
GRANT USAGE, CREATE ON SCHEMA analytics TO :"grantee";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA analytics TO :"grantee";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA analytics TO :"grantee";
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA analytics TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA analytics GRANT ALL ON TABLES TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA analytics GRANT ALL ON SEQUENCES TO :"grantee";
ALTER DEFAULT PRIVILEGES FOR ROLE :"owner" IN SCHEMA analytics GRANT ALL ON FUNCTIONS TO :"grantee";
SQL
      fi
    fi

    if [ "$CO_OWNER" = "1" ] && [ "$owner" != "$grantee" ]; then
      if [ "$owner" = "$PGUSER" ]; then
        echo "   ⚠️  owner=$owner — это админ; membership не выдаю. Передайте ownership вручную."
      else
        psql_admin postgres -v owner="$owner" -v grantee="$grantee" <<'SQL'
GRANT :"owner" TO :"grantee";
SQL
      fi
    fi
  done
done

echo ""
echo "✅ Готово для слота $SLOT."
echo "Схему загрузите из worktree агента:"
echo "  docker compose exec $SLOT ./bin/rails db:schema:load"
echo "Для тестовой БД достаточно запустить RSpec (maintain_test_schema!), либо:"
echo "  docker compose exec -e RAILS_ENV=test $SLOT ./bin/rails db:schema:load"
echo "Если schema analytics была создана после этого запуска, повторите с --grant-only."
