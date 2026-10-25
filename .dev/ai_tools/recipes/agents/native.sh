# Официальные Агенты моделей

case "${(U)AI_ACTIVE_PROVIDER}" in
  ANTHROPIC)
    CHECK_CMD="claude"
    INSTALL_CMD="npm install -g @anthropic-ai/claude-code --prefix ${NPM_CONFIG_PREFIX:-/root/.npm-global}"

    # Claude Code ищет ANTHROPIC_MODEL для выбора версии (перекрывает settings.json).
    [ -n "${CURRENT_API_KEY:-}" ] && export ANTHROPIC_API_KEY="$CURRENT_API_KEY"
    [ -n "${AI_MODEL_NAME:-}" ] && export ANTHROPIC_MODEL="$AI_MODEL_NAME"
    [ -n "${CURRENT_API_BASE:-}" ] && [ -z "${ANTHROPIC_BASE_URL:-}" ] && export ANTHROPIC_BASE_URL="$CURRENT_API_BASE"
    # ANTHROPIC_AUTH_TOKEN не трогаем: он может быть основным способом авторизации.

    if [ -z "$AI_MODEL_NAME" ]; then
      combined_list=$(printf "%s\n" "$ANTHROPIC_DEFAULT_MODEL" "$ANTHROPIC_DEFAULT_SONNET_MODEL" "$ANTHROPIC_DEFAULT_OPUS_MODEL" "$ANTHROPIC_DEFAULT_HAIKU_MODEL" | grep -v '^$')
      result_string=$(echo "$combined_list" | sort -u | paste -sd, -)
      export AI_MODEL_NAME_DETECTED="$result_string"
    fi
    ;;

  COPILOT)
    CHECK_CMD="gh"
    INSTALL_CMD="apk add --no-cache github-cli && gh extension install github/gh-copilot"

    [ -n "${CURRENT_API_KEY:-}" ] && export GITHUB_TOKEN="$CURRENT_API_KEY"

    alias copilot='gh copilot'

    echo "🐙 GitHub Copilot CLI (via gh) готов"
    echo "💡 Используйте команду 'gh copilot suggest' или 'gh copilot explain'"
    ;;

  DEEPSEEK_HARNESS)
    CHECK_CMD="dsh"
    INSTALL_CMD="npm install -g @deepseek-ai/dsh --prefix ${NPM_CONFIG_PREFIX:-/root/.npm-global}"

    [ -n "${AI_MODEL_NAME:-}" ] && export DSH_MODEL="$AI_MODEL_NAME"

    # In-box bundles: @deepseek-ai/dsh-base, @deepseek-ai/dsh-web-app, @deepseek-ai/dsh-headless, @deepseek-ai/dsh-sdk-app, @deepseek-ai/dsh-sdk-minimal, @deepseek-ai/dsh-acp-app

    echo "🐋 DeepSeek Harness CLI (dsh) готов к работе"
    echo "💡 Используйте команду 'dsh web' для запуска веб-интерфейса"
    ;;

  GEMINI)
    CHECK_CMD="gemini"
    INSTALL_CMD="npm install -g @google/gemini-cli@latest --prefix ${NPM_CONFIG_PREFIX:-/root/.npm-global}"

    [ -n "${CURRENT_API_KEY:-}" ] && export GEMINI_API_KEY="$CURRENT_API_KEY"
    [ -n "${CURRENT_API_KEY:-}" ] && export GOOGLE_API_KEY="$CURRENT_API_KEY"
    [ -n "${AI_MODEL_NAME:-}" ] && export GEMINI_MODEL="$AI_MODEL_NAME"
    ;;

  *)
    echo "❌ Для провайдера $AI_ACTIVE_PROVIDER не настроен NATIVE режим."
    return 1
    ;;
esac
