#!/bin/sh
# Установка прав на запись для worktree всех контейнеров AI-агентов.
#
# Запускать в контейнере app (там есть админские креды Postgres):

find . -maxdepth 1 -type d -name "ai*_worktree" -print0 | xargs -0 chmod -R g+wX,o+wX

echo ""
echo "✅ Права на запись для ai*_worktree обновлены."
