#!/bin/sh
# Выставляет права на coverage/log/tmp во всех worktree AI-агентов.
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
AI_DEV_DIR="$SCRIPT_DIR"
AI_PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
. "$SCRIPT_DIR/lib/ai_common.sh"

if [ "$#" -gt 0 ]; then
  dirs=""
  for slot in "$@"; do
    dirs="$dirs $(ai_worktree_path "$slot")"
  done
else
  dirs=$(ai_list_worktree_dirs)
fi

if [ -z "$dirs" ]; then
  echo "ℹ️  Worktree не найдены"
  exit 0
fi

for worktree in $dirs; do
  [ -d "$worktree" ] || continue
  for rel in coverage log tmp; do
    [ -d "$worktree/$rel" ] || continue
    chmod -R u+wX,g+wX,o+wX "$worktree/$rel"
  done
  echo "✅ Права обновлены: $worktree"
done
