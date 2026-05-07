#!/bin/zsh

# Скрипт для создания пользователя и баз данных в Postgres.
# Запускать внутри контейнера `app`

# Определение имени проекта:
# Сначала - из названия папки (app_name)
#
# Шаблон: ищем 'app_', берем всё после него, 
# а затем отсекаем '_ai_src' или '_ai_out', если они есть в конце
CURRENT_DIR_NAME=$(basename "$PWD")
if [[ "$CURRENT_DIR_NAME" =~ ^app_(.+)$ ]]; then
    PROJ="${match}"
    # Убираем суффиксы через zsh-модификаторы
    PROJ="${PROJ%_ai_src}"
    PROJ="${PROJ%_ai_out}"
fi

# Если папка app без имени проекта, ищем в .env
if [ -z "$PROJ" ] && [ -f ".env" ]; then
    PROJ=$(grep '^PROJECT_NAME=' .env | cut -d '=' -f2 | tr -d '"' | tr -d "'")
fi
# Если в файле .env пусто, берем из ENV
PROJ=$(echo "${PROJ:-$PROJECT_NAME}" | tr '[:upper:]' '[:lower:]')

if [ -z "$PROJ" ]; then
    echo "❌ Ошибка: Не найдено название текущего проекта (PROJECT_NAME)"
    exit 1
fi

# Проверка аргументов
AGENT_CODE=$(echo "$1" | tr '[:lower:]' '[:upper:]')
if [ -z "$AGENT_CODE" ]; then
  echo "❌ Укажите код агента (например: setup_ai_user gemini)"
  exit 1
fi

USER_VAR="POSTGRES_AI_USER_${AGENT_CODE}"
PASS_VAR="POSTGRES_AI_PASSWORD_${AGENT_CODE}"

# ${(P)VAR_NAME} - Это функция Zsh для работы с динамическими именами переменных. 
NEW_USER=${(P)USER_VAR}
NEW_PASS=${(P)PASS_VAR}

if [ -z "$NEW_USER" ]; then echo "❌ Ошибка: Переменная $USER_VAR не найдена в .env"; exit 1; fi
if [ -z "$NEW_PASS" ]; then echo "❌ Ошибка: Переменная $PASS_VAR не найдена в .env"; exit 1; fi

DB_NAME_1="ai_${(L)PROJ}_${(L)AGENT_CODE}_development"
DB_NAME_2="ai_${(L)PROJ}_${(L)AGENT_CODE}_test"

# Подтверждение
echo "----------------------------------------------------------"
echo "🚀 Настройка AI-агента для БД"
echo "Проект: $PROJ | Агент: $AGENT_CODE | Пользователь БД: $NEW_USER"
echo "Будут настроены базы:"
echo "  - $DB_NAME_1"
echo "  - $DB_NAME_2"
echo "----------------------------------------------------------"
echo -n "Продолжить? (y/n): "
read confirmation

if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
  echo "🚫 Отменено пользователем."
  exit 0
fi

# Проверка psql
if ! command -v psql &> /dev/null; then
    echo "❌ Ошибка: psql client не найден в контейнере."
    exit 1
fi

# Выполнение SQL
export PGPASSWORD=$PGPASSWORD 
DATABASES=("$DB_NAME_1" "$DB_NAME_2")

# Функция для выполнения SQL и обработки ошибок
run_sql() {
  local query=$1
  local db=${2:-"postgres"}
  # Выполняем psql, перехватывая stderr
  local err_msg
  err_msg=$(psql -h "$PGHOST" -U "$PGUSER" -d "$db" -c "$query" 2>&1)
  local cmd_result=$?

  if [ $cmd_result -ne 0 ]; then
    if echo "$err_msg" | grep -qE "already exists|уже существует"; then
      echo "ℹ️  Уже есть в БД, пропускаем..."
    else
      echo "❌ КРИТИЧЕСКАЯ ОШИБКА БД:"
      echo "$err_msg"
      exit 1
    fi
  fi
}

echo "👤 Создание пользователя $NEW_USER..."
run_sql "CREATE USER $NEW_USER WITH PASSWORD '$NEW_PASS';"

# Создаем базы и настраиваем доступы
for DB in $DATABASES; do
  echo "⚙️  Настройка базы: $DB"

  run_sql "CREATE DATABASE $DB OWNER $PGUSER;"

  # Настраиваем права
  psql -h "$PGHOST" -U "$PGUSER" -d "$DB" <<-EOSQL 2>/dev/null
    GRANT ALL PRIVILEGES ON DATABASE "$DB" TO "$NEW_USER";
    GRANT ALL PRIVILEGES ON SCHEMA public TO "$NEW_USER";W_USER";

    GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO "$NEW_USER";
    GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO "$NEW_USER";

    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO "$NEW_USER";
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO "$NE
EOSQL

  if [ $? -ne 0 ]; then
    echo "❌ Ошибка при выдаче прав на базу $DB для $NEW_USER"
    exit 1
  fi

  if [ -f "db/schema.rb" ]; then
    echo "🏗️  Загрузка схемы в $DB..."
    if ! DATABASE_URL="postgresql://$NEW_USER:$NEW_PASS@$PGHOST/$DB" RAILS_ENV=test bundle exec rails db:schema:load > /dev/null; then
      echo "❌ Ошибка при выполнении rails db:schema:load"
      exit 1
    fi
  fi
done

echo "✅ Успешно завершено для проекта $PROJ."
