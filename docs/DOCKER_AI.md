# 🤖 Инструкция по развёртыванию AI-агентов в Docker

Эта инструкция описывает процесс подготовки и запуска изолированного контейнера с AI-инструментами (Aider, Claude Code, Gemini CLI, AIChat и др.) для работы над проектом.

> **Важно:** Данная инструкция подразумевает, что основная настройка контейнеров для разработки уже выполнена. Если вы ещё не настроили базовое окружение, сначала изучите [DOCKER_DEV.md](./DOCKER_DEV.md).

## 1. Подготовка рабочей области (Worktree)

Для безопасности основного кода и изоляции экспериментов AI-агентов используется механизм `git worktree`. Это позволяет агенту видеть файлы, но не «мусорить» в текущем основном разделе.

```bash
# Создание отдельного ответвления и папки для AI
./.dev/git-ai-sync.sh

# Установка прав на запись для рабочей папки
chmod -R o+w ./ai_worktree
```

## 2. Настройка конфигурации проекта

Скопируйте шаблоны настроек приложения внутри рабочей области агента:

```bash
cp ./ai_worktree/config/settings/development.yml ./ai_worktree/config/settings/development.local.yml
cp ./ai_worktree/config/settings/test.yml ./ai_worktree/config/settings/test.local.yml
```

## 3. Права доступа на скрипты

Убедитесь, что все скрипты и имеют права на выполнение:

```bash
chmod +x .dev/*.sh
chmod +x .dev/ai-entrypoint.sh
chmod +x .dev/ai_tools/ai-wizard.sh
chmod +x .dev/ai_tools/recipes/agents/*.sh
```

## 4. Настройка переменных окружения (.env)

1.  Создайте локальный `.env` (если отсутствует):
    ```bash
    cp .env.example .env
    ```

2.  Откройте `.env` и настройте следующие блоки:

### Настройки доступа (Провайдеры)

Укажите Ключи и URL тех площадок, которыми планируете пользоваться:

```bash
ANTHROPIC_API_KEY=sk-ant-...
GROQ_API_KEY=gsk_...
GROQ_API_URL=https://api.groq.com/openai/v1
OPENROUTER_API_KEY=sk-or-...
OPENROUTER_API_URL=
```

### Настройки активной сессии

```bash
AI_ACTIVE_PROVIDER=ANTHROPIC           # Имя площадки, API-ключ которой использовать
AI_ACTIVE_AGENT=NATIVE                 # Тип (NATIVE, AIDER, AICHAT, KILOCODE и т.д.)
AI_ACTIVE_MODEL=groq/qwen/qwen3-32b    # Код модели полностью
AI_PROXY_URL=http://host-network-ip.addr:3067 # Если требуется прокси, либо ""
```

### Настройки БД для агентов

Для каждого агента (модели) рекомендуется отдельный пользователь:

```bash
POSTGRES_AI_USER_QWEN=qwen_user
POSTGRES_AI_PASSWORD_QWEN=secure_pass
```

## 5. Инициализация базы данных

Перед запуском агента необходимо создать его базу данных и пользователя.

Выполните внутри основного контейнера `app`:

```bash
# Формат: .dev/setup_ai_user <название_провайдера_или_агента>

docker compose run --rm app .dev/setup_ai_user qwen
```

## 6. Запуск и работа

Подразумевается, что при использовании режима Docker Rootless, при входе текущего пользователя иницализируются следующие переменные:
```bash
export DOCKER_HOST=unix:///run/user/$(id -u dockeruser)/docker.sock
export DOCKER_USER_ID=$(id -u dockeruser)
```

### Запуск контейнера (обычный)

Запуск производится через профиль `ai`. Контейнер автоматически проверит зависимости и предложит установить выбранного агента при запуске.

```bash
docker compose -f docker-compose.dev.yml --profile ai run --rm ai_agent
```


### Запуск контейнера (VSCode Dev Containers)

Для запуска в VSCode текущий пользователь должен иметь разрешения на доступ к Docker.

Если Docker запускается в режиме Rootless под другим пользователем, тогда необходимо получить права на чтение и запись в сокет демона Docker.

```bash
.dev/rootless_socket.sh
```

Поскольку файлы внутри контейнера будут изменяться пользователем, которого нет на хосте, нужно выдать права на запись "всем" для необходимых папок проекта непосредственно на хосте.

```bash
.dev/rootless_folders.sh
```

Скопируйте папку .devcontainer.example
```bash
cp .devcontainer.example .devcontainer
```

В файле .devcontainer/devcontainer.json укажите пути, соответствующие имени проекта PROJECT_NAME, указанному в файле .env

Установить в VS Code расширение Dev Containers (ms-vscode-remote.remote-containers)

Нажать F1 -> Dev Containers: Reopen  on Container


### Команды внутри контейнера

После входа в консоль контейнера можно запускать установленные инструменты.

**Пример для Aider:**

```bash
aider --no-git
```

*(Флаг `--no-git` рекомендуется, так как вы уже находитесь внутри подготовленного worktree).*


## Советы

*   Исходники проекта примонтированы в `/app_..._ai_src` в режиме **ReadOnly**.
*   Все изменения, которые делает AI, сохраняются в `/app_..._ai_out` (ваша папка `ai_worktree` на хосте).
*   Если нужно сменить модель, просто поправьте `.env` и перезапустите контейнер.
*   Если нужно сменить агента, поправьте `.env`, убедитесь в актуальности пользователя БД для нового агента и перезапустите контейнер.
