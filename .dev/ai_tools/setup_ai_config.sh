#!/bin/sh
# Создание/обновление config/settings/development.local.yml и test.local.yml.
#
# Запускать из корня worktree:
#   ./.dev/setup_ai_config.sh              # создать файлы, если их ещё нет
#   ./.dev/setup_ai_config.sh soft_update  # добавить новые поля, сохранив старые значения
#   ./.dev/setup_ai_config.sh force_update # полностью заменить файлы новыми
#
# При создании development.local.yml и при force_update подставляются
# контейнерные значения db.host, db.user, db.password и db.dbname
# (только внутри секции db:), а также redis.url (только внутри секции redis:).
# test.local.yml копируется из test.yml без подстановок — там уже есть ENV.

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# ai_common.sh лежит рядом в .dev; fallback — чтобы скрипт работал автономно.
if [ -f "$SCRIPT_DIR/lib/ai_common.sh" ]; then
  . "$SCRIPT_DIR/lib/ai_common.sh"
fi
if ! command -v ai_die >/dev/null 2>&1; then
  ai_die() {
    printf '❌ %s\n' "$*" >&2
    exit 1
  }
fi

usage() {
  cat <<'EOF'
Использование:
  setup_ai_config.sh [soft_update|force_update]

Режимы:
  (без флага)    создать development.local.yml и test.local.yml, если их нет
  soft_update    дополнить существующие файлы новыми полями из development.yml
                 и test.yml, сохранив значения уже существующих полей
  force_update   полностью заменить файлы: development.local.yml — с подстановками,
                 test.local.yml — точной копией test.yml

Скрипт запускается из корня worktree и работает с файлами:
  config/settings/development.yml -> config/settings/development.local.yml
  config/settings/test.yml        -> config/settings/test.local.yml

При создании development.local.yml и force_update подставляются:
  db.host      -> db_postgres
  db.user      -> $DB_USER
  db.password  -> $DB_PASSWORD
  db.dbname    -> $POSTGRES_DB_DEVELOPMENT
  redis.url    -> redis://db_redis:6379

test.local.yml создаётся как копия test.yml без подстановок:
в test.yml значения уже берутся из ENV.
EOF
}

MODE=create
case "${1:-}" in
  "")
    ;;
  soft_update|soft-update|--soft-update|--soft_update)
    MODE=soft
    shift
    ;;
  force_update|force-update|--force-update|--force_update)
    MODE=force
    shift
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    ai_die "Неизвестный аргумент: $1"
    ;;
esac

[ "$#" -eq 0 ] || { usage >&2; ai_die "Лишние аргументы: $*"; }

ROOT=$(pwd)
SETTINGS_DIR="$ROOT/config/settings"

# Экранирование значения для replacement в sed: \, & и разделитель |.
sed_replacement() {
  printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

# Экранирование одиночных кавычек для YAML-скаляра в одинарных кавычках.
yaml_single_quoted() {
  printf '%s' "$1" | sed "s/'/''/g"
}

require_env() {
  db_env_name=$1
  eval "DB_NAME=\${$db_env_name:-}"

  [ -n "${DB_USER:-}" ] || ai_die "DB_USER не задан"
  [ -n "${DB_PASSWORD:-}" ] || ai_die "DB_PASSWORD не задан"
  [ -n "$DB_NAME" ] || ai_die "$db_env_name не задан"

  for value in "$DB_USER" "$DB_PASSWORD" "$DB_NAME"; do
    [ "$(printf '%s' "$value" | wc -l | tr -d ' ')" = "0" ] || \
      ai_die "Значения DB_USER, DB_PASSWORD и $db_env_name не должны содержать перевод строки"
  done
}

# Один проход sed: несколько -i подряд на gocryptfs оставляют файл с mode 600,
# после чего следующие sed не могут его открыть.
apply_env_overrides() {
  src=$1
  dst=$2
  db_name=$3

  user_sed=$(sed_replacement "$(yaml_single_quoted "$DB_USER")")
  password_sed=$(sed_replacement "$(yaml_single_quoted "$DB_PASSWORD")")
  dbname_sed=$(sed_replacement "$(yaml_single_quoted "$db_name")")

  # Все подстановки db.* ограничены секцией db:.
  # Конец блока — только строка верхнего уровня (без ведущих пробелов).
  sed \
    -e "/^[[:space:]]*db:/,/^[^[:space:]-]/ {
          s/^\([[:space:]]*host:\).*/\1 db_postgres/
          s|^\([[:space:]][[:space:]]*user:\).*|\1 '${user_sed}'|
          s|^\([[:space:]][[:space:]]*password:\).*|\1 '${password_sed}'|
          s|^\([[:space:]][[:space:]]*dbname:\).*|\1 '${dbname_sed}'|
        }" \
    -e '/^[[:space:]]*redis:/,/^[^[:space:]-]/ { s|^\([[:space:]]*url:\).*|\1 redis://db_redis:6379| }' \
    "$src" > "$dst"
}

write_from_template() {
  template=$1
  local_file=$2
  with_overrides=$3
  db_env_name=$4
  action=$5

  tmp="$local_file.tmp.$$"
  trap 'rm -f "$tmp"' EXIT HUP INT TERM

  if [ "$with_overrides" = "1" ]; then
    require_env "$db_env_name"
    apply_env_overrides "$template" "$tmp" "$DB_NAME"
  else
    cp "$template" "$tmp"
  fi

  mv "$tmp" "$local_file"

  trap - EXIT HUP INT TERM
  echo "✅ ${action}: $local_file"
}

soft_update() {
  template=$1
  local_file=$2

  command -v ruby >/dev/null 2>&1 || ai_die "Для soft_update нужен ruby"

  ruby -ryaml - "$template" "$local_file" <<'RUBY'
template_path, local_path = ARGV

def deep_merge(base, override)
  return override unless base.is_a?(Hash) && override.is_a?(Hash)

  base.merge(override) do |_key, base_value, override_value|
    if base_value.is_a?(Hash) && override_value.is_a?(Hash)
      deep_merge(base_value, override_value)
    else
      override_value
    end
  end
end

template = YAML.unsafe_load_file(template_path)
local = YAML.unsafe_load_file(local_path)

unless template.is_a?(Hash) && local.is_a?(Hash)
  warn "❌ Ожидались YAML-словари в #{template_path} и #{local_path}"
  exit 1
end

merged = deep_merge(template, local)
if merged == local
  puts "ℹ️  #{local_path} уже содержит все поля из #{template_path}"
  exit 0
end

tmp_path = "#{local_path}.tmp.#{Process.pid}"
begin
  File.write(tmp_path, YAML.dump(merged, line_width: -1))
  begin
    File.chmod(File.stat(local_path).mode, tmp_path)
  rescue SystemCallError
    # На gocryptfs chmod может быть запрещён — режим не критичен.
  end
  File.rename(tmp_path, local_path)
ensure
  File.unlink(tmp_path) if File.exist?(tmp_path)
end

puts "✅ Обновлён: #{local_path} (добавлены новые поля)"
RUBY
}

process_config() {
  template=$1
  local_file=$2
  with_overrides=$3
  db_env_name=$4

  [ -f "$template" ] || ai_die "Не найден $template (запускайте из корня worktree)"

  if [ ! -f "$local_file" ]; then
    write_from_template "$template" "$local_file" "$with_overrides" "$db_env_name" "Создан"
    return 0
  fi

  case "$MODE" in
    create)
      echo "ℹ️  $local_file уже существует; используйте soft_update или force_update"
      ;;
    soft)
      soft_update "$template" "$local_file"
      ;;
    force)
      write_from_template "$template" "$local_file" "$with_overrides" "$db_env_name" "Заменён"
      ;;
  esac
}

process_config \
  "$SETTINGS_DIR/development.yml" \
  "$SETTINGS_DIR/development.local.yml" \
  1 \
  POSTGRES_DB_DEVELOPMENT

process_config \
  "$SETTINGS_DIR/test.yml" \
  "$SETTINGS_DIR/test.local.yml" \
  0 \
  ""
