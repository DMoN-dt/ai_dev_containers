#!/bin/zsh

echo "🧙 AI Agent Wizard: [Provider: ${AI_ACTIVE_PROVIDER}] [Agent: ${AI_ACTIVE_AGENT}]"

# Подготовка папки для исполняемых CLI агентов
BIN_DIR="/app_ai_tools/bin"
mkdir -p "$BIN_DIR"

# Определение имени провайдера и параметров его настроек
PROVIDER_PREFIX="${(U)AI_ACTIVE_PROVIDER}"
KEY_VAR="${PROVIDER_PREFIX}_API_KEY"
BASE_VAR="${PROVIDER_PREFIX}_API_BASE"

# Извлекаем значения настроек
export CURRENT_API_KEY="${(P)KEY_VAR}"
export CURRENT_API_BASE="${(P)BASE_VAR}"

# Экспортируем для CLI инструментов (стандарт для большинства)
export OPENAI_API_KEY="$CURRENT_API_KEY"
[ -n "$CURRENT_API_BASE" ] && export OPENAI_API_BASE="$CURRENT_API_BASE"

# Для специфичных CLI (Claude, Gemini)
export ANTHROPIC_API_KEY="$CURRENT_API_KEY"
export GOOGLE_API_KEY="$CURRENT_API_KEY"

# Загрузка сценария установки АГЕНТА
AGENT_RECIPE_FILE="/app_ai_tools/recipes/agents/${(L)AI_ACTIVE_AGENT}.sh"

if [ -f "$AGENT_RECIPE_FILE" ]; then
    source "$AGENT_RECIPE_FILE"
else
    echo "❌ Сценарий установки Агента не найден: $AGENT_RECIPE_FILE"
    return 1 # Используем return, так как этот скрипт будет запущен через source
fi

# Проверка: установлен ли агент?
# Проверяем либо системную команду, либо наличие файла в нашем bin
if ! command -v "$CHECK_CMD" &> /dev/null && [ ! -f "$BIN_DIR/$CHECK_CMD" ]; then
    echo "⚠️  Агент ${AI_ACTIVE_AGENT} ещё не установлен."
    echo -n "👉 Установить сейчас? (y/n): "
    read -k 1 install_confirm
    echo "" # Новая строка после read -k

    if [[ "$install_confirm" == "y" || "$install_confirm" == "Y" ]]; then
        echo "📥 Запуск установки..."
        # Выполняем команду установки из рецепта
        eval "$INSTALL_CMD"
        
        if [ $? -eq 0 ]; then
            echo "✅ Установка завершена успешно."
        else
            echo "❌ Ошибка при установке."
            return 1
        fi
    else
        echo "🚫 Установка пропущена. Агент может быть недоступен."
    fi
else
    echo "✅ Агент ${AI_ACTIVE_AGENT} готов (найден: $(command -v $CHECK_CMD || echo $BIN_DIR/$CHECK_CMD))"
    echo "✅ Модель: $AI_MODEL_NAME | Провайдер: $AI_ACTIVE_PROVIDER"
fi
