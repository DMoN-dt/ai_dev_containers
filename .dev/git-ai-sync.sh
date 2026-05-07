#!/bin/bash
# Создает Git Worktree для AI контейнера с целью изоляции файлов и ветки на хосте.

git branch ai_workspace 2>/dev/null || true

if [ ! -d "ai_worktree" ]; then
  git worktree add ./ai_worktree ai_workspace
  echo "✅ Worktree создана в папке ./ai_worktree"
else
  echo "ℹ️ Worktree уже существует. Для обновления сделайте git reset внутри папки."
fi
