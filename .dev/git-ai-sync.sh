#!/bin/sh
# Обратная совместимость: создание worktree переехало в wtree create.
set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec sh "$SCRIPT_DIR/wtree" create "$@"
