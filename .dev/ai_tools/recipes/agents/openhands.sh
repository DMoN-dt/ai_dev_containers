# OpenHands (ранее известный как OpenDevin)

CHECK_CMD="openhands-cli"
INSTALL_CMD="apk add --no-cache python3 py3-pip python3-dev build-base && pip install --user openhands-cli"

case "${(U)AI_ACTIVE_PROVIDER}" in
  ANTHROPIC)
    [ -n "${CURRENT_API_KEY:-}" ] && export ANTHROPIC_API_KEY="$CURRENT_API_KEY"
    ;;
  GEMINI)
    [ -n "${CURRENT_API_KEY:-}" ] && export GEMINI_API_KEY="$CURRENT_API_KEY"
    [ -n "${CURRENT_API_KEY:-}" ] && export GOOGLE_API_KEY="$CURRENT_API_KEY"
    ;;
  *)
    [ -n "${CURRENT_API_KEY:-}" ] && export OPENAI_API_KEY="$CURRENT_API_KEY"
    [ -n "${CURRENT_API_BASE:-}" ] && export OPENAI_API_BASE="$CURRENT_API_BASE"
    ;;
esac

export LLM_MODEL="${AI_MODEL_NAME}"
