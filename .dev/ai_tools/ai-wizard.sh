#!/bin/zsh

echo "🧙 AI Agent Wizard: [Provider: ${AI_ACTIVE_PROVIDER}] [Agent: ${AI_ACTIVE_AGENT}] [Model: ${AI_MODEL_NAME}]"

export PATH="$HOME/.npm-global/bin:$HOME/.local/bin:$PATH"
export BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR" "$HOME/.npm-global/bin"

PROVIDER_PREFIX="${(U)AI_ACTIVE_PROVIDER}"
KEY_VAR="${PROVIDER_PREFIX}_API_KEY"
BASE_VAR="${PROVIDER_PREFIX}_API_BASE"
BASE_URL_VAR="${PROVIDER_PREFIX}_BASE_URL"

export CURRENT_API_KEY="${(P)KEY_VAR}"
export CURRENT_API_BASE="${(P)BASE_VAR}"
if [ -z "$CURRENT_API_BASE" ]; then
  export CURRENT_API_BASE="${(P)BASE_URL_VAR}"
fi

# Устаревший алиас: часть внешних рецептов/инструментов ещё читает AI_ACTIVE_MODEL.
export AI_ACTIVE_MODEL="${AI_MODEL_NAME}"

case "$PROVIDER_PREFIX" in
  ANTHROPIC)
    # Не затираем ANTHROPIC_AUTH_TOKEN: Claude Code может работать через base_url + auth_token.
    if [ -n "$CURRENT_API_KEY" ]; then export ANTHROPIC_API_KEY="$CURRENT_API_KEY"; fi
    if [ -n "$CURRENT_API_BASE" ] && [ -z "${ANTHROPIC_BASE_URL:-}" ]; then
      export ANTHROPIC_BASE_URL="$CURRENT_API_BASE"
    fi
    ;;
  DEEPSEEK_HARNESS)
    if [ -n "$CURRENT_API_KEY" ]; then export DEEPSEEK_API_KEY="$CURRENT_API_KEY"; fi
    if [ -n "$CURRENT_API_BASE" ] && [ -z "${DEEPSEEK_BASE_URL:-}" ]; then
      export DEEPSEEK_BASE_URL="$CURRENT_API_BASE"
    fi
    ;;
  GEMINI)
    if [ -n "$CURRENT_API_KEY" ]; then export GEMINI_API_KEY="$CURRENT_API_KEY"; fi
    if [ -n "$CURRENT_API_KEY" ]; then export GOOGLE_API_KEY="$CURRENT_API_KEY"; fi
    if [ -n "$CURRENT_API_BASE" ]; then export GEMINI_API_BASE="$CURRENT_API_BASE"; fi
    ;;
  COPILOT)
    if [ -n "$CURRENT_API_KEY" ]; then export GITHUB_TOKEN="$CURRENT_API_KEY"; fi
    ;;
  *)
    # OpenAI-совместимые провайдеры: GROQ, OPENROUTER, ...
    if [ -n "$CURRENT_API_KEY" ]; then export OPENAI_API_KEY="$CURRENT_API_KEY"; fi
    if [ -n "$CURRENT_API_BASE" ]; then export OPENAI_API_BASE="$CURRENT_API_BASE"; fi
    ;;
esac

AGENT_RECIPE_FILE="/app_ai_tools/recipes/agents/${(L)AI_ACTIVE_AGENT}.sh"

if [ -f "$AGENT_RECIPE_FILE" ]; then
  source "$AGENT_RECIPE_FILE"
else
  echo "❌ Сценарий установки Агента не найден: $AGENT_RECIPE_FILE"
  return 1
fi

if [ -z "${CHECK_CMD:-}" ]; then
  echo "❌ Рецепт ${AI_ACTIVE_AGENT} не задал CHECK_CMD"
  return 1
fi

if command -v "$CHECK_CMD" >/dev/null 2>&1; then
  echo "✅ Агент ${AI_ACTIVE_AGENT} готов (найден: $(command -v "$CHECK_CMD"))"
  echo "✅ Модель: ${AI_MODEL_NAME:-${AI_MODEL_NAME_DETECTED}} | Провайдер: ${AI_ACTIVE_PROVIDER}"
  return 0
fi

if [ -f "$BIN_DIR/$CHECK_CMD" ]; then
  echo "✅ Агент ${AI_ACTIVE_AGENT} готов (найден: $BIN_DIR/$CHECK_CMD)"
  echo "✅ Модель: ${AI_MODEL_NAME:-${AI_MODEL_NAME_DETECTED}} | Провайдер: ${AI_ACTIVE_PROVIDER}"
  return 0
fi

echo "⚠️  Агент ${AI_ACTIVE_AGENT} ещё не установлен."

install_agent() {
  echo "📥 Запуск установки..."
  if eval "$INSTALL_CMD"; then
    echo "✅ Установка завершена успешно."
    return 0
  fi
  echo "❌ Ошибка при установке."
  return 1
}

case "${AI_AUTO_INSTALL:-no}" in
  yes)
    install_agent || return 1
    ;;
  no)
    echo "ℹ️  AI_AUTO_INSTALL=no — установка пропущена."
    echo "💡 Зайдите в контейнер и выполните: source /app_ai_tools/ai-wizard.sh"
    ;;
  ask)
    if [ ! -t 0 ]; then
      echo "ℹ️  Нет TTY для интерактивной установки. Используйте AI_AUTO_INSTALL=yes или docker compose exec."
    else
      echo -n "👉 Установить сейчас? (y/n): "
      read -k 1 install_confirm
      echo ""
      if [[ "$install_confirm" == "y" || "$install_confirm" == "Y" ]]; then
        install_agent || return 1
      else
        echo "🚫 Установка пропущена."
      fi
    fi
    ;;
  *)
    echo "⚠️  Неизвестный AI_AUTO_INSTALL=${AI_AUTO_INSTALL}; установка пропущена."
    ;;
esac
