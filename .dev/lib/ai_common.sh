#!/bin/sh
# Общие функции для AI-скриптов.
# Не читает .env и не печатает секреты.

ai_die() {
  printf '❌ %s\n' "$*" >&2
  exit 1
}

ai_project_root() {
  if [ -n "${AI_PROJECT_ROOT:-}" ]; then
    printf '%s\n' "$AI_PROJECT_ROOT"
    return 0
  fi

  if [ -n "${AI_DEV_DIR:-}" ]; then
    (CDPATH= cd -- "$AI_DEV_DIR/.." && pwd)
    return 0
  fi

  ai_die "AI_PROJECT_ROOT/AI_DEV_DIR не задан"
}

# Универсальная функция для чтения переменной из .env файла без его выполнения (source)
ai_read_env_var() {
  local var_name="$1"
  local file_path="${2:-.env}"

  if [ -f "$file_path" ]; then
    # Ищем строку вида VAR_NAME=значение, очищаем от пробелов, кавычек и комментариев
    sed -n "s/^[[:space:]]*${var_name}=\([\"'\']\?\)\([^\"\'[:space:]#]\+\)\1.*/\2/p" "$file_path" | head -n 1
  fi
}

ai_project_name() {
  # Если переменная уже есть в памяти (как в Docker) — используем её
  if [ -n "${PROJECT_NAME:-}" ]; then
    printf '%s\n' "$PROJECT_NAME"
    return 0
  fi

  # Если мы на хосте, пробуем прочитать из файла .env
  local dotenv_name
  dotenv_name=$(ai_read_env_var "PROJECT_NAME" ".env")
  
  if [ -n "$dotenv_name" ]; then
    printf '%s\n' "$dotenv_name" | tr '[:upper:]' '[:lower:]'
    return 0
  fi

  # Берём по имени папки
  root=$(ai_project_root)
  base=$(basename -- "$root")
  case "$base" in
    app_*) base=${base#app_} ;;
  esac
  printf '%s\n' "$base" | tr '[:upper:]' '[:lower:]'
}

ai_normalize_slot() {
  printf '%s\n' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_]/_/g'
}

ai_worktree_dir_name() {
  slot=$(ai_normalize_slot "$1")
  case "$slot" in
    ai_agent)
      printf 'ai_worktree\n'
      ;;
    ai_agent_[0-9]*)
      printf 'ai%s_worktree\n' "${slot#ai_agent_}"
      ;;
    *)
      printf '%s_worktree\n' "$slot"
      ;;
  esac
}

ai_worktree_path() {
  root=$(ai_project_root)
  name=$(ai_worktree_dir_name "$1")
  printf '%s/%s\n' "$root" "$name"
}

ai_branch_name() {
  slot=$(ai_normalize_slot "$1")
  case "$slot" in
    ai_agent)
      printf 'ai_workspace\n'
      ;;
    ai_agent_[0-9]*)
      printf 'ai_workspace_%s\n' "${slot#ai_agent_}"
      ;;
    *)
      printf 'ai_workspace_%s\n' "$slot"
      ;;
  esac
}

ai_container_source_dir() {
  project=$(ai_project_name)
  printf '/app_%s_ai_src\n' "$project"
}

ai_container_gitdir() {
  worktree=$(ai_worktree_path "$1")
  name=$(basename -- "$worktree")
  printf '%s/.git/worktrees/%s\n' "$(ai_container_source_dir)" "$name"
}

ai_gitdir_name_from_worktree() {
  gitfile="$1/.git"
  [ -f "$gitfile" ] || return 1
  line=$(sed -n 's/^gitdir: //p' "$gitfile" | head -n 1)
  [ -n "$line" ] || return 1
  basename -- "$line"
}

ai_write_container_gitdir() {
  worktree=$1
  name=${2:-}

  if [ -z "$name" ]; then
    name=$(ai_gitdir_name_from_worktree "$worktree" 2>/dev/null || true)
  fi
  if [ -z "$name" ]; then
    name=$(basename -- "$worktree")
  fi

  target="$(ai_container_source_dir)/.git/worktrees/$name"
  printf 'gitdir: %s\n' "$target" > "$worktree/.git"
}

# Вернуть worktree/.git на host-путь конкретного worktree.
# git worktree repair <path> не подходит: он всё равно чинит все worktree разом.
ai_write_host_gitdir() {
  worktree=$1
  name=${2:-}

  if [ -z "$name" ]; then
    name=$(ai_gitdir_name_from_worktree "$worktree" 2>/dev/null || true)
  fi
  if [ -z "$name" ]; then
    name=$(basename -- "$worktree")
  fi

  target="$(ai_project_root)/.git/worktrees/$name"
  if [ ! -d "$target" ]; then
    printf '⚠️   Нет admin-каталога %s\n' "$target" >&2
    return 1
  fi
  printf 'gitdir: %s\n' "$target" > "$worktree/.git"
}

ai_list_worktree_dirs() {
  root=$(ai_project_root)
  for dir in "$root"/*_worktree; do
    [ -d "$dir" ] || continue
    [ -f "$dir/.git" ] || continue
    printf '%s\n' "$dir"
  done
}

ai_require_command() {
  command -v "$1" >/dev/null 2>&1 || ai_die "Команда '$1' не найдена"
}
