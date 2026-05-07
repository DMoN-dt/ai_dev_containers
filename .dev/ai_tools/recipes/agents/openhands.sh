# OpenHands (ранее известный как OpenDevin)

CHECK_CMD="openhands-cli"
INSTALL_CMD="apk add --no-cache python3 py3-pip python3-dev build-base && pip install --user openhands-cli"

export OPENAI_API_KEY="$CURRENT_API_KEY"
export ANTHROPIC_API_KEY="$CURRENT_API_KEY"

export LLM_MODEL="${AI_MODEL_NAME}"
