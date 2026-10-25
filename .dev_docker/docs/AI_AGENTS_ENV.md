# Переменные AI-агентов

Файл `.env` (и `.env.example`) намеренно скрыт внутри AI-контейнера, поэтому
этот блок нужно перенести в `.env` на хосте. Существующие переменные
(`PROJECT_NAME`, `APP_DOCKER_*`, `POSTGRES_*`, `REDIS_EXTERNAL_PORT`,
`TIMEZONE`, `RAILS_LOG_MAX_SIZE`, `AI_PROXY_URL`, `AI_NO_PROXY`) остаются как есть.

## Слоты

Слот — это контейнер `ai_agent`, `ai_agent_2` или `ai_agent_3`.
Пути worktree зафиксированы в compose и `.dev/lib/ai_common.sh`:

| Слот | Worktree | Ветка по умолчанию |
|---|---|---|
| `ai_agent` | `./ai_worktree` | текущая (для нового — `ai_workspace`) |
| `ai_agent_2` | `./ai2_worktree` | `ai_workspace_2` |
| `ai_agent_3` | `./ai3_worktree` | `ai_workspace_3` |

## Общие AI-настройки

```env
APP_IMAGE_NAME=coruscant-app:latest

AI_AGENT_DOCKER_CONTEXT=.
AI_AGENT_DOCKER_FILE=.dev_docker/Dockerfile.dev.ai
AI_INSTRUCTIONS_PATH=.dev_ai_instructions
DEV_DOCKER_TOOLS_PATH=./.dev

AI_AUTO_INSTALL=no
AI_AUTO_DB_PREPARE=false
AI_BUNDLE_INSTALL=auto
AI_VERIFY_NETWORK=true

POSTGRES_CPUS_LIMIT=1.0
POSTGRES_MEMORY_LIMIT=1G
AI_REDIS_CPUS_LIMIT=0.30
AI_REDIS_MEMORY_LIMIT=256M
```

`AI_AUTO_INSTALL=no` безопасен для `docker compose --profile ai up -d`:
CLI устанавливается вручную из интерактивной сессии. Поставьте `yes`, если
хотите автоустановку при старте, или `ask` — только для ручного запуска
wizard'а из `docker compose exec ... zsh`.

Если ваш прокси не пропускает `https://google.com/generate_204`, entrypoint
завершится с ошибкой сети. В этом случае поставьте `AI_VERIFY_NETWORK=false`
(проверка изоляции/прокси будет пропущена).

## Слот ai_agent (пример: Claude)

```env
AI_AGENT_ACTIVE_AGENT=NATIVE
AI_AGENT_ACTIVE_PROVIDER=ANTHROPIC
AI_AGENT_MODEL_NAME=claude-sonnet-5-5

AI_AGENT_DB_USER=ai_coruscant_claude
AI_AGENT_DB_PASSWORD=change_me_claude
AI_AGENT_DB_DEVELOPMENT=ai_coruscant_claude_development
AI_AGENT_DB_TEST=ai_coruscant_claude_test
# AI_AGENT_TEST_ENV_NUMBER=2
AI_AGENT_REDIS_DB=0

# Ключ модели этого слота. Должен отличаться от ключей других слотов,
# если нужна раздельная тарификация.
AI_AGENT_ANTHROPIC_API_KEY=change_me_claude_key
```

## Слот ai_agent_2 (пример: Qwen/Aider через GROQ)

```env
AI_AGENT_2_ACTIVE_AGENT=AIDER
AI_AGENT_2_ACTIVE_PROVIDER=GROQ
AI_AGENT_2_MODEL_NAME=qwen-2.5-coder-32b

AI_AGENT_2_DB_USER=ai_coruscant_qwen
AI_AGENT_2_DB_PASSWORD=change_me_qwen
AI_AGENT_2_DB_DEVELOPMENT=ai_coruscant_qwen_development
AI_AGENT_2_DB_TEST=ai_coruscant_qwen_test
# AI_AGENT_2_TEST_ENV_NUMBER=2
AI_AGENT_2_REDIS_DB=1

AI_AGENT_2_GROQ_API_KEY=change_me_qwen_key
```

## Слот ai_agent_3 (пример: Gemini)

```env
AI_AGENT_3_ACTIVE_AGENT=NATIVE
AI_AGENT_3_ACTIVE_PROVIDER=GEMINI
AI_AGENT_3_MODEL_NAME=gemini-2.0-flash

AI_AGENT_3_DB_USER=ai_coruscant_gemini
AI_AGENT_3_DB_PASSWORD=change_me_gemini
AI_AGENT_3_DB_DEVELOPMENT=ai_coruscant_gemini_development
AI_AGENT_3_DB_TEST=ai_coruscant_gemini_test
# AI_AGENT_3_TEST_ENV_NUMBER=2
AI_AGENT_3_REDIS_DB=2

AI_AGENT_3_GEMINI_API_KEY=change_me_gemini_key
```

## API-ключи и раздельная тарификация

У каждого слота свои ключи доступа к API моделей. Имя переменной:
`AI_AGENT_<PROVIDER>_API_KEY`, `AI_AGENT_2_<PROVIDER>_API_KEY`,
`AI_AGENT_3_<PROVIDER>_API_KEY`. Префикс слота совпадает с префиксом
DB-переменных.

Приоритет для fallback-провайдера слота:

| Приоритет | Переменная | Назначение |
|---|---|---|
| 1 | `AI_AGENT[_N]_<PROVIDER>_API_KEY` | ключ конкретного агента |
| 2 | `AI_AGENT[_N]_API_KEY` | alias для fallback-провайдера слота |
| 3 | `<PROVIDER>_API_KEY` | глобальный legacy-ключ, общий для слотов |

Fallback-провайдеры (default в compose): `ai_agent` — ANTHROPIC,
`ai_agent_2` — GROQ, `ai_agent_3` — GEMINI. Если
`AI_AGENT*_ACTIVE_PROVIDER` указывает на другого провайдера, используйте
provider-specific переменные этого провайдера.

Для провайдера, который не является fallback для слота, глобальный ключ
не подставляется. Задайте явный `AI_AGENT[_N]_<PROVIDER>_API_KEY`: так
ключи других агентов не попадут в контейнер.

Поддерживаемые провайдеры и переменные:

| Провайдер | Ключ | Base URL / токен |
|---|---|---|
| ANTHROPIC | `AI_AGENT[_N]_ANTHROPIC_API_KEY` | `..._ANTHROPIC_BASE_URL`, `..._ANTHROPIC_AUTH_TOKEN` |
| GROQ | `AI_AGENT[_N]_GROQ_API_KEY` | `..._GROQ_API_BASE` |
| GEMINI | `AI_AGENT[_N]_GEMINI_API_KEY` | `..._GEMINI_API_BASE`; дублируется в `GOOGLE_API_KEY` |
| OPENROUTER | `AI_AGENT[_N]_OPENROUTER_API_KEY` | `..._OPENROUTER_API_BASE` |
| COPILOT | `AI_AGENT[_N]_COPILOT_API_KEY` | wizard передаёт ключ в `GITHUB_TOKEN` |

Аналогично работают base URL: `AI_AGENT[_N]_API_BASE` — alias для
fallback-провайдера. Для ANTHROPIC доступен и auth token:
`AI_AGENT[_N]_ANTHROPIC_AUTH_TOKEN` (alias `AI_AGENT[_N]_AUTH_TOKEN`).

Например, если `ai_agent_2` переключён на ANTHROPIC, используйте
`AI_AGENT_2_ANTHROPIC_API_KEY` и при необходимости
`AI_AGENT_2_ANTHROPIC_BASE_URL`/`AI_AGENT_2_ANTHROPIC_AUTH_TOKEN`.

Если провайдера нет в таблице, добавьте его переменные в `environment`
нужного сервиса в `docker-compose.dev.yml` по тому же шаблону: имя
`AI_AGENT[_N]_<PROVIDER>_API_KEY` (и `..._API_BASE`, если нужно).

### Несколько агентов на одной модели

Чтобы трафик тарифицировался раздельно, задайте каждому слоту свой ключ.
Пример: все три агента используют Anthropic.

```env
AI_AGENT_ACTIVE_PROVIDER=ANTHROPIC
AI_AGENT_2_ACTIVE_PROVIDER=ANTHROPIC
AI_AGENT_3_ACTIVE_PROVIDER=ANTHROPIC

AI_AGENT_ANTHROPIC_API_KEY=sk-ant-agent1
AI_AGENT_2_ANTHROPIC_API_KEY=sk-ant-agent2
AI_AGENT_3_ANTHROPIC_API_KEY=sk-ant-agent3
```

`AI_AGENT*_ACTIVE_AGENT` и `AI_AGENT*_MODEL_NAME` тоже должны соответствовать
выбранному провайдеру и модели.

Одинаковые ключи у нескольких слотов означают общую тарификацию. Если
per-agent ключ не задан, слот получит пустое значение либо глобальный
fallback, если этот провайдер — fallback-провайдер слота.

Раздельные ключи дают раздельный учёт трафика у провайдера. Итоговая
тарификация зависит от настроек аккаунта провайдера: для полностью
независимых счетов может понадобиться отдельный проект или организация.

### Глобальные ключи (legacy)

Глобальные переменные оставлены для обратной совместимости и подставляются
только в слот, для которого провайдер является fallback. Если нужна раздельная
тарификация, используйте per-agent ключи, а не глобальные:

```env
# ai_agent (fallback ANTHROPIC)
ANTHROPIC_API_KEY=
ANTHROPIC_AUTH_TOKEN=
ANTHROPIC_BASE_URL=

# ai_agent_2 (fallback GROQ)
GROQ_API_KEY=
GROQ_API_BASE=

# ai_agent_3 (fallback GEMINI)
GEMINI_API_KEY=
GEMINI_API_BASE=
# GOOGLE_API_KEY обычно равен GEMINI_API_KEY
```

### Настройки моделей Claude/Anthropic

Все несекретные настройки Claude/Anthropic можно задать per-agent.
Generic alias (`AI_AGENT[_N]_MODEL`) есть только у `ANTHROPIC_MODEL`.
Для остальных параметров используется только полное имя с префиксом слота:
`AI_AGENT[_N]_<NAME>` -> глобальный `<NAME>`.

| Глобальная переменная | Per-agent (полное имя) | Per-agent (короткое имя) |
|---|---|---|
| `ANTHROPIC_MODEL` | `AI_AGENT[_N]_ANTHROPIC_MODEL` | `AI_AGENT[_N]_MODEL` |
| `ANTHROPIC_DEFAULT_MODEL` | `AI_AGENT[_N]_ANTHROPIC_DEFAULT_MODEL` | — |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | `AI_AGENT[_N]_ANTHROPIC_DEFAULT_SONNET_MODEL` | — |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | `AI_AGENT[_N]_ANTHROPIC_DEFAULT_OPUS_MODEL` | — |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | `AI_AGENT[_N]_ANTHROPIC_DEFAULT_HAIKU_MODEL` | — |
| `CLAUDE_CODE_SUBAGENT_MODEL` | `AI_AGENT[_N]_CLAUDE_CODE_SUBAGENT_MODEL` | — |
| `CLAUDE_CODE_EFFORT_LEVEL` | `AI_AGENT[_N]_CLAUDE_CODE_EFFORT_LEVEL` | — |
| `ENABLE_TOOL_SEARCH` | `AI_AGENT[_N]_ENABLE_TOOL_SEARCH` | — |

Для `ANTHROPIC_MODEL` между коротким именем и глобальным значением
учитывается существующая per-slot переменная `AI_AGENT[_N]_MODEL_NAME`.
`AI_AGENT[_N]_MODEL_NAME` — общая модель слота, её используют wizard и
рецепты; `AI_AGENT[_N]_ANTHROPIC_MODEL`/`AI_AGENT[_N]_MODEL` — точечный
override именно для `ANTHROPIC_MODEL` в Claude Code.

Пустое значение означает fallback на следующий уровень цепочки. Если нужен
другой параметр `ANTHROPIC_*` или `CLAUDE_CODE_*`, добавьте его в
`environment` нужного сервиса в `docker-compose.dev.yml` по той же цепочке.

Пример:

```env
# ai_agent
AI_AGENT_ANTHROPIC_MODEL=claude-sonnet-5-5
AI_AGENT_ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-5-5
AI_AGENT_CLAUDE_CODE_SUBAGENT_MODEL=claude-haiku-5-5
AI_AGENT_ENABLE_TOOL_SEARCH=true

# ai_agent_2
AI_AGENT_2_ANTHROPIC_MODEL=claude-opus-5-5
AI_AGENT_2_ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-5-5
AI_AGENT_2_CLAUDE_CODE_EFFORT_LEVEL=high
AI_AGENT_2_ENABLE_TOOL_SEARCH=false
```

Глобальные переменные — общий fallback для всех слотов:

```env
ANTHROPIC_MODEL=
ANTHROPIC_DEFAULT_MODEL=
ANTHROPIC_DEFAULT_SONNET_MODEL=
ANTHROPIC_DEFAULT_OPUS_MODEL=
ANTHROPIC_DEFAULT_HAIKU_MODEL=
CLAUDE_CODE_SUBAGENT_MODEL=
CLAUDE_CODE_EFFORT_LEVEL=
ENABLE_TOOL_SEARCH=
```

## Общие БД: как настраивать

По умолчанию у каждого слота свои пользователь и БД. Чтобы использовать одну БД:

1. **Одна БД, один пользователь** — задайте одинаковые `AI_AGENT*_DB_USER`,
   `AI_AGENT*_DB_PASSWORD`, `AI_AGENT*_DB_DEVELOPMENT`, `AI_AGENT*_DB_TEST`
   у нужных слотов. Пароли должны совпадать: `setup_ai_user.sh` выполняет
   `ALTER ROLE ... PASSWORD`.
2. **Одна БД, разные пользователи** — задайте одинаковые DB-имена, но разные
   user/password. Выполните `setup_ai_user.sh` для каждого слота; второй получит
   grants и default privileges. Для миграций/`db:test:prepare` нужен
   `--co-owner` (membership во владельца) или один выделенный writer.
3. **Read-only проверяющий** — `setup_ai_user.sh <slot> --grant-to <user> --read-only`.
   Такой пользователь не сможет запускать миграции и RSpec.
4. **Общая тестовая БД** — задайте разные `AI_AGENT*_TEST_ENV_NUMBER` и
   провижиньте БД с суффиксами (`_test2`, `_test3`), иначе параллельные тесты
   будут мешать друг другу.

Подробные команды — в `docs/DOCKER_DEV.md`.
