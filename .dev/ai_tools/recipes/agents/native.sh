# Официальные Агенты моделей

case "${(U)AI_ACTIVE_PROVIDER}" in
  ANTHROPIC)
    CHECK_CMD="claude"
    INSTALL_CMD="npm install -g @anthropic-ai/claude-code --prefix /node_packages"

    export ANTHROPIC_API_KEY="$CURRENT_API_KEY"

    # Claude Code ищет именно CLAUDE_CODE_MODEL для выбора версии
    export CLAUDE_CODE_MODEL="$AI_ACTIVE_MODEL"
    ;;

  COPILOT)
    CHECK_CMD="gh"
    # Установка GitHub CLI и расширения copilot
    INSTALL_CMD="apk add --no-cache github-cli && gh extension install github/gh-copilot"
    
    # Официальный CLI GitHub ожидает GITHUB_TOKEN или GITHUB_ENTERPRISE_TOKEN
    export GITHUB_TOKEN="$CURRENT_API_KEY"
    
    # Для Copilot CLI модель обычно выбирается через флаги или внутренний конфиг,
    # алиас для удобства:
    alias copilot='gh copilot'

    echo "🐙 GitHub Copilot CLI (via gh) готов"
    echo "💡 Используйте команду 'gh copilot suggest' или 'gh copilot explain'"
    ;;

  GEMINI)
    # Согласно https://geminicli.com/docs/get-started/installation/
    CHECK_CMD="gemini"
    INSTALL_CMD="npm install -g @google/gemini-cli@latest --prefix /node_packages"

    # Официальный CLI использует переменную GEMINI_API_KEY
    export GEMINI_API_KEY="$CURRENT_API_KEY"

    # Если используется модель, отличная от дефолтной
    export GEMINI_MODEL="${AI_ACTIVE_MODEL:-gemini-2.0-flash}"

    # Официальная переменная для Google AI SDK
    export GOOGLE_API_KEY="$CURRENT_API_KEY"
    ;;

  *)
    echo "❌ Для провайдера $AI_ACTIVE_PROVIDER не настроен NATIVE режим."
    return 1
    ;;
esac
