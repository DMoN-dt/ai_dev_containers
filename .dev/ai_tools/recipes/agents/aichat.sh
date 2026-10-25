CHECK_CMD="aichat"

if [ -n "${TOOL_AICHAT_URL:-}" ]; then
  AICHAT_URL="$(printf '%s' "$TOOL_AICHAT_URL" | tr -d ' ')"
  INSTALL_CMD="curl -L $AICHAT_URL | tar xz -C $BIN_DIR"
else
  INSTALL_CMD="echo 'TOOL_AICHAT_URL не задан в .env' && false"
fi

# Генерация конфига aichat на лету под провайдера
CONFIG_DIR="$HOME/.config/aichat"
mkdir -p "$CONFIG_DIR"

# Определяем тип для aichat
AICHAT_CONFIG_TYPE="openai"

case "${(U)AI_ACTIVE_PROVIDER}" in
  GEMINI)    AICHAT_CONFIG_TYPE="gemini" ;;
  ANTHROPIC) AICHAT_CONFIG_TYPE="claude" ;;
esac

cat <<EOF > "$CONFIG_DIR/config.yaml"
clients:
  - type: $AICHAT_CONFIG_TYPE
    api_key: "$CURRENT_API_KEY"
    api_base: "$CURRENT_API_BASE"
model: "$AI_MODEL_NAME"
EOF
