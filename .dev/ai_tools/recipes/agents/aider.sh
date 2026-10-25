CHECK_CMD="aider"
INSTALL_CMD="apk add --no-cache python3 py3-pip python3-dev build-base && pip install --user aider-chat"

export AIDER_MODEL="${AI_MODEL_NAME}"

# Aider не всегда читает модель из env — фиксируем её в конфиге.
if [ -n "${AI_MODEL_NAME:-}" ]; then
  printf 'model: %s\n' "$AI_MODEL_NAME" > "$HOME/.aider.conf.yml"
fi
