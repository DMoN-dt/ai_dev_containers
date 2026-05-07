CHECK_CMD="sgpt"
INSTALL_CMD="apk add --no-cache python3 py3-pip python3-dev build-base && pip install --user shell-gpt"

# Shell-GPT специфичные настройки
# По умолчанию он использует gpt-3.5-turbo, переопределяем на нашу модель
export SGPT_MODEL="$AI_ACTIVE_MODEL"
