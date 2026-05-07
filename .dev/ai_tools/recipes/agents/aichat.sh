CHECK_CMD="aichat"
AICHAT_URL="$(echo "$TOOL_AICHAT_URL" | tr -d ' ')"
INSTALL_CMD="curl -L $AICHAT_URL | tar xz -C /app_ai_tools/bin"

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
