# 🚀 Инструкция по развёртыванию образов Docker для разработки

Добро пожаловать! Этот проект контейнеризирован с использованием Docker. Для работы вам не нужно устанавливать Ruby, Postgres или Redis прямо на вашу машину.


## Назначение контейнеров

Эти Docker-контейнеры предназначены для локального запуска проекта с целью разработки и тестирования как непосредственно разработчиком, так и множеством AI-агентов.

Контейнер `app` предназначен для разработчика, в контейнере имеется полный доступ к файлам проекта и к базам данных. Создавать БД и пользователей для агентов рекомендуется именно в этом контейнере (с помощью скрипта `.dev/setup_ai_user.sh`)

Контейнеры `ai_agent` и `ai_agent_NN` предназначены для запуска внутри них ИИ-агентов. Там есть общая настройка для их выхода в Интернет через прокси-сервер.

Все настройки для контейнеров задаются в файлах `.env` и `docker-compose.dev.yml`

Общие базовые настройки (шаблон) контейнеров агентов хранятся в `docker-compose.ai-base.yml`


## Структура

```
host
├── docker rootless daemon
│   ├── app                 (основной контейнер, профиль manual)
│   ├── db_postgres         (общая БД)
│   ├── db_redis            (Redis приложения)
│   ├── db_redis_ai         (общий Redis AI, logical DB 0/1/...)
│   ├── ai_agent            (слот 1, worktree: ai_worktree)
│   └── ai_agent_2          (слот 2, worktree: ai2_worktree)
│   └── ...
│   └── ai_agent_N          (слот N, worktree: aiN_worktree)
|
|
└── git-worktrees на диске в папке проекта
    ├── ai_worktree
    └── ai2_worktree
    └── ...
    └── aiN_worktree
```

Используются:

* Один Postgres на все контейнеры

* Два Redis: один - для разработчика, один - для всех агентов.

* Отдельные HOME / worktree / БД у агентов.

* Агенты видят worktree друг друга только для чтения через `/ai_peers/<ai_slot>`.


## Docker

Перед началом убедитесь, что у вас установлены:
* **Docker** и **Docker Compose**

Рекомендуемый режим работы - [Docker Rootless](https://docs.docker.com/engine/security/rootless/) с запуском под отдельным ограниченным пользователем (вместо обычного запуска под root).
Это необходимо для повышения безопасности и изолированности контейнеров от основной системы и данных вашего пользователя.

Папка проекта должна быть доступна для того пользователя на чтение и на запись.
Это не обязательно должна быть та же самая папка, в которой работаете вы.

Для контейнеров AI-агентов создаётся отдельная папка через `git worktree`, в которую также выдаётся доступ на запись и внутри самого контейнера.

Без прав на чтение папки проекта, Docker не сможет примонтировать папку в контейнер и корректно отобразить её содержимое.

Далее все команды будут приводиться именно для такого режима работы Docker Rootless и ОС Ubuntu 24.04.

Из-за особенности создания файлов внутри rootless контейнера, в `App` при запуске по умолчанию стоит umask 000. Все файлы, которые создаются внутри контейнера (например, логи или отчеты SimpleCov), будут с правами на чтение и запись для всех.


### Подготовка Docker

Docker Rootless запускает демон от имени другого пользователя, к которому Ваш пользователь по умолчанию не имеет доступа.

Поэтому все команды для Docker потребуется запускать от имени того пользователя (назовём его - `dockeruser`).

И тот пользователь должен иметь права доступа как минимум на чтение во все необходимые папки проекта.


Создайте в корневой папке вашего пользователя файл `.docker_aliases`:

```bash
touch ~/.docker_aliases
```

И добавьте в него следующие команды (замените `dockeruser` везде на имя пользователя, под которым у вас запущен Docker):

```bash
# Docker Rootless aliases (Docker запущен под пользователем dockeruser)
alias duser='sudo -u dockeruser DOCKER_HOST=unix:///run/user/$(id -u dockeruser)/docker.sock docker '
alias dcom='sudo -u dockeruser DOCKER_HOST=unix:///run/user/$(id -u dockeruser)/docker.sock docker compose '
alias dstatus='sudo -u dockeruser XDG_RUNTIME_DIR=/run/user/$(id -u dockeruser) systemctl --user status docker'
```

Добавьте в `~/.bashrc` (или `~/.zshrc`):

```bash
[ -f ~/.docker_aliases ] && source ~/.docker_aliases
```

Примените:

```bash
source ~/.bashrc     # или source ~/.zshrc
```

Для проверки выполните следующие команды по-очереди:

```bash
duser info
dcom version
dstatus
```

> В алиасах есть завершающий пробел после `docker ` и `docker compose `.
> Он нужен, чтобы можно было дописывать подкоманды в конец: `duser ps`,
> `dcom --profile ai up -d`, `dcom logs -f ai_agent`.

> Если ваша версия `sudo` не принимает `VAR=value` перед командой, замените
> алиасы на вариант с `env`:
>
> ```bash
> alias duser='sudo -u dockeruser env DOCKER_HOST=unix:///run/user/$(id -u dockeruser)/docker.sock docker '
> alias dcom='sudo -u dockeruser env DOCKER_HOST=unix:///run/user/$(id -u dockeruser)/docker.sock docker compose '
> alias dstatus='sudo -u dockeruser env XDG_RUNTIME_DIR=/run/user/$(id -u dockeruser) systemctl --user status docker --no-pager'
> ```

Подробнее о настройке Docker и этих алиасах см. раздел [Docker Rootless под другим пользователем](DOCKER_ROOTLESS_OTHER_USER.md)

По умолчанию `sudo -u dockeruser ...` спросит ваш пароль.
Если команды запускаются часто, можно разрешить конкретному пользователю/группе запускать Docker от `dockeruser` без пароля.
Подробнее см. раздел [Docker Rootless: sudo без ввода пароля](DOCKER_ROOTLESS_SUDO_NOPASSWD.md)


## Добавление контейнеров в папку проекта

Скопируйте в папку проекта следующие папки из проекта `ai-dev-containers`:

```
.dev
.dev_docker
```

Из папки `.dev_docker` скопируйте в корень проекта следующие файлы:

* Конфиг контейнеров `docker-compose.dev.yml`

* Шаблон настроек `.env.example` и переименуйте его в `.env`

```bash
cp .dev_docker/docker-compose.dev.yml docker-compose.dev.yml
cp .dev_docker/.env.example .env
```


## Особенности прав доступа к папкам хоста изнутри контейнера

Поскольку в режиме Docker Rootless по умолчанию работа внутри самого контейнера происходит под собственным пользователем `root` контейнера, ваша система на хосте даже не знает о таком пользователе. При обращении к файловой системе хоста изнутри контейнера, идентификатор такого пользователя на хосте будет определяться как унаследованный от ID пользователя dockeruser. При этом самого пользователя в системе хоста нет и ни в каких группах он не состоит.

Эта особенность Rootless обуславливает необходимость выдать доступ на запись Другим (Всем) пользователям в те папки хоста, куда потребуется выполнять запись внутри контейнера.


## Инициализация пути к папке проекта

Далее в инструкциях для указания путь к папке проекта будет использоваться переменная:

```bash
YOUR_PROJECT_PATH=../blazing_star_project
```


## Настройка прав на папку проекта

Проверка доступности проекта для Docker:

```bash
sudo -u dockeruser ls -la $YOUR_PROJECT_PATH
sudo -u dockeruser cat $YOUR_PROJECT_PATH/.env >/dev/null && echo "env readable"
```

Если эти команды выше не работают — выдайте доступ.
Предпочтительный способ — общая группа для обоих пользователей (а не "chmod 777"):

```bash
sudo groupadd dockerdev 2>/dev/null || true
sudo usermod -aG dockerdev "$USER"
sudo usermod -aG dockerdev dockeruser

sudo chgrp -R dockerdev $YOUR_PROJECT_PATH
sudo chmod -R g+rwX $YOUR_PROJECT_PATH
```

После `usermod` выйдите из сессии и зайдите снова (или перезагрузитесь), чтобы новая группа применилась, повторите создание переменной `YOUR_PROJECT_PATH`.

Для файлов с секретами:

```bash
# .env должен быть читаем dockeruser, но не всему миру
sudo chmod 640 $YOUR_PROJECT_PATH/.env
sudo chgrp dockerdev $YOUR_PROJECT_PATH/.env
```


### Разрешение записи в основную папку проекта

Права на запись нужны для контейнера `App`, в котором будут выполняться тесты и делаться дампы БД.

Необходим доступ к следующим директориям: **db**, **log**, **tmp**, **coverage**, **storage**.

```bash
mkdir -p $YOUR_PROJECT_PATH/coverage/assets

chmod -R g+wX,o+wX $YOUR_PROJECT_PATH/log $YOUR_PROJECT_PATH/tmp $YOUR_PROJECT_PATH/coverage $YOUR_PROJECT_PATH/public $YOUR_PROJECT_PATH/storage $YOUR_PROJECT_PATH/db
```

Для NodeJs проектов:

```bash
mkdir -p $YOUR_PROJECT_PATH/node_modules

chmod -R g+wX,o+wX $YOUR_PROJECT_PATH/node_modules
```


## Git worktree для безопасной параллельной работы нескольких AI-агентов

Агенты работают в своей изолированной папке, которая отображает указанную вами ветку репозитория.

Такие папки монтируются в контейнер с правами на запись и на хосте к ним выдаётся доступ на запись для Всех (Вы + dockeruser + Другие).

Коммит в ветку и переключение веток не доступны внутри контейнера, поскольку общий основной каталог `.git`, содержащий индексы веток, монтируется только для чтения, в целях безопасности. Вы можете это изменить в `docker-compose.dev.yml`, заменив напротив пути `_ai_src` свойство `:ro` на `:rw` (либо примонтировав .git отдельно) и предоставив на папку `.git` на хосте доступ на запись всем.

Коммит в ветку возможно сделать только на хосте (вне контейнера агентов):

1. Переключить внутри папки `*_worktree` путь к каталогу git с контейнера на реальный путь на хосте.

2. Перейти в папку нужного worktree.

3. Выполнить все необходимые манипуляции с git на этой ветке и выполнить коммит, чтобы изменения сохранились в ветке, после чего вы уже сможете работать с ними из своей основой части репозитория или из других `*_worktree`.

4. Выйти из папки назад.

5. Переключить внутри worktree путь к каталогу git на корректный для контейнера.

6. Переключить worktree контейнера на другую ветку, чтобы высвободить текущую для дальнейшей работы с ней на хосте или в других контейнерах, т.к. Git не позволяет держать ветку открытой в нескольких местах.

7. Переключиться на хосте в нужную ветку, выполнить необходимые действия в ней, сделать пуш в репозиторий.

Ниже приведены последовательно команды, которые потребуются в дальнейшем для всех перечисленных действий:

```bash
.dev/wtree host <ai_slot>  # переключаем путь с контейнера на хост
cd ./ai_worktree           # заходим в worktree

git status
git add .
git commit -m '...'

cd ..
.dev/wtree docker <ai_slot>  # переключаем путь с хоста на контейнер

.dev/wtree switch <ai_slot> <other_branch> # переключаем ветку в контейнере на другую

git checkout <branch_name>
git push
```


## Конфигурация контейнеров

Основным файлом конфигурации контейнеров является `docker-compose.dev.yml`.

В нём расположены конфигурации основных контейнеров: `app`, `db_redis`, `db_postgres`, `db_redis_ai` и контейнеров ИИ-агентов (`ai_agent`, `ai_agent_NN`).

Базовые настройки контейнеров Агентов находятся в `.dev_docker/docker-compose.ai-base.yml` и импортируются в основной файл как шаблон для каждого агента.


**Для увеличения количества контейнеров агентов потребуется:**

- сделать дубликат контейнера `ai_agent_NN` в `docker-compose.dev.yml`

- заменить номер на новый во всех скопированных значениях параметров

- указать индивидуальные настройки в `.env` или оставить использование общих

- в `volumes` остальных контроллеров добавить монтирование папки в `peer` при необходимости


### Настройка параметров контейнеров в `.env`

Параметры окружения (пароли к базам, api ключи агентов) для всех контейнеров расположены в файле `.env`.

Скопируйте шаблон:

```bash
cd $YOUR_PROJECT_PATH

cp .dev_docker/.env.example .env

# .env должен быть читаем dockeruser, но не всему миру
sudo chmod 640 $YOUR_PROJECT_PATH/.env
```

Откройте `.env` в удобном редакторе (`nano .env`, `vim .env`, VS Code) и добавьте блок AI-переменных.

По умолчанию в данном файле указаны только настройки для контейнера `app`.

Если требуются контейнеры агентов, добавьте блок AI-переменных по примеру из `.dev_docker/ai_agents.env.example`.

Описание параметров - [AI_AGENTS_ENV.md](.dev_docker/docs/AI_AGENTS_ENV.md)

**ВАЖНО:** Не используйте одинаковые имена пользователей и одинаковые пароли для admin и агентов.


#### Пример настройки контейнера разработчика (app):

Выполните эти шаги последовательно:

1. **Настройка окружения Docker:**

   *Если у вас уже запущен локальный Postgres или Redis, измените порты `POSTGRES_EXTERNAL_PORT` и `REDIS_EXTERNAL_PORT` в `.env`, чтобы избежать конфликтов.*

   *Эти настройки должны будут совпадать с настройками в `config/settings/development.local.yml`*


   ```env
   ##### Настройки БД для разработки #####

   POSTGRES_ADMIN_USER=postgres
   POSTGRES_ADMIN_PASSWORD=pgadmin_password

   POSTGRES_DB_DEVELOPMENT=blazing_star_project_development
   POSTGRES_DB_TEST=blazing_star_project_test

   POSTGRES_EXTERNAL_PORT=5432
   REDIS_EXTERNAL_PORT=6379
   ```

2. **Настройка параметров Приложения:**
   Скопируйте шаблон настроек в локальный файл:

   В вашем `development.local.yml` укажите актуальные `db -> user` и `db -> password`

   `db -> host` укажите `db_postgres`

   `redis -> url` укажите `'redis://db_redis:6379'`

   Скрипт для выполнения всех перечисленных действий:

   ```bash
   cp config/settings/development.yml config/settings/development.local.yml

   sed -i '/^[[:space:]]*db:/,/^[[:space:]]*[^[:space:]-]/ { s/^\([[:space:]]*host:\).*/\1 db_postgres/ }' $YOUR_PROJECT_PATH/config/settings/development.local.yml

   sed -i '/^[[:space:]]*redis:/,/^[[:space:]]*[^[:space:]-]/ { s|^\([[:space:]]*url:\).*|\1 redis://db_redis:6379| }' $YOUR_PROJECT_PATH/config/settings/development.local.yml

   TMP_DB_USER=$(sed -n "s/^[[:space:]]*POSTGRES_ADMIN_USER=\([\"'\']\?\)\([^\"\'[:space:]#]\+\)\1.*/\2/p" .env | head -n 1)
   TMP_DB_PSWD=$(sed -n "s/^[[:space:]]*POSTGRES_ADMIN_PASSWORD=\([\"'\']\?\)\([^\"\'[:space:]#]\+\)\1.*/\2/p" .env | head -n 1)

   sed -i "s|^\([[:space:]]\+user:\).*|\1 '$TMP_DB_USER'|" config/settings/development.local.yml
   sed -i "s|^\([[:space:]]\+password:\).*|\1 '$TMP_DB_PSWD'|" config/settings/development.local.yml

   unset TMP_DB_USER TMP_DB_PSWD
   ```


#### Типичный пример настройки контейнера агента (ai_agent):

**1) Блок общих настроек:**
```env
### --- Общие настройки контейнеров агентов --- ###
APP_IMAGE_NAME=blazing_star_project-app:latest

AI_AGENT_DOCKER_CONTEXT=.
AI_AGENT_DOCKER_FILE=Dockerfile.dev.ai
AI_INSTRUCTIONS_PATH=../.dev_ai_instructions
DEV_DOCKER_TOOLS_PATH=../.dev

AI_AUTO_INSTALL=no
AI_AUTO_DB_PREPARE=false
AI_BUNDLE_INSTALL=auto
AI_VERIFY_NETWORK=true

POSTGRES_CPUS_LIMIT=1.0
POSTGRES_MEMORY_LIMIT=1G
AI_REDIS_CPUS_LIMIT=0.30
AI_REDIS_MEMORY_LIMIT=256M
```

** Пути к файлам должны указываться относительно каталога `.dev_docker`, поскольку файл шаблона `ai-base.yml` уже лежит в нём. Это актуально для `AI_AGENT_DOCKER_FILE`, `AI_INSTRUCTIONS_PATH`, `DEV_DOCKER_TOOLS_PATH`

**2) Агент и модель по умолчанию, общие ключи:**
```env
### --- Агент и модель по умолчанию (можно оставить пустыми) --- ###
#
# Полный список AGENT: `.dev/ai_tools/recipes/`
# Полный список PROVIDER: `.dev/ai_tools/recipes/{AGENT}.sh`
#
AI_ACTIVE_AGENT=NATIVE
AI_ACTIVE_PROVIDER=GROQ
AI_MODEL_NAME=groq/qwen/qwen3-32b

### --- Общие ключи для всех контейнеров агентов --- ###
OPENROUTER_API_KEY=
OPENROUTER_API_BASE=

GROQ_API_KEY=
GROQ_API_BASE=

GEMINI_API_KEY=
COPILOT_API_KEY=

ANTHROPIC_API_KEY=
ANTHROPIC_BASE_URL=
ANTHROPIC_AUTH_TOKEN=
ANTHROPIC_DEFAULT_MODEL=
ANTHROPIC_DEFAULT_SONNET_MODEL=
ANTHROPIC_DEFAULT_OPUS_MODEL=
ANTHROPIC_DEFAULT_HAIKU_MODEL=
```

**3) Блок настроек первого агента:**

Обратите внимание: названия переменных для первого агента не содержат порядковый номер (`AI_AGENT`).
Нумерация начинается со второго контейнера: `AI_AGENT_2`, `AI_AGENT_3` ...

```env
### --- Слот ai_agent (пример: Aider + Groq + Qwen) --- ###

AI_AGENT_ACTIVE_AGENT=AIDER
AI_AGENT_ACTIVE_PROVIDER=GROQ

# Одна модель на все режимы агента:
AI_AGENT_MODEL_NAME=qwen-2.5-coder-32b

AI_AGENT_DB_USER=ai_blazing_star_project_groq
AI_AGENT_DB_PASSWORD=change_me_groq
AI_AGENT_DB_DEVELOPMENT=ai_blazing_star_project_groq_development
AI_AGENT_DB_TEST=ai_blazing_star_project_groq_test
# AI_AGENT_TEST_ENV_NUMBER=2
AI_AGENT_REDIS_DB=0

# Ключ и Url модели этого слота-агента (для раздельной статистики и тарификации).
AI_AGENT_GROQ_API_KEY=
AI_AGENT_GROQ_API_BASE=
```

**4) Блок настроек второго агента:**

```env
### --- Слот ai_agent (пример: Claude) --- ###
# Полный список AGENT: `.dev/ai_tools/recipes/`
# Полный список PROVIDER: `.dev/ai_tools/recipes/{AGENT}.sh`

AI_AGENT_2_ACTIVE_AGENT=NATIVE
AI_AGENT_2_ACTIVE_PROVIDER=ANTHROPIC

# Разные модели:
ANTHROPIC_DEFAULT_MODEL=...
ANTHROPIC_DEFAULT_SONNET_MODEL=...
ANTHROPIC_DEFAULT_OPUS_MODEL=...
ANTHROPIC_DEFAULT_HAIKU_MODEL=...

AI_AGENT_DB_USER=ai_blazing_star_project_claude
AI_AGENT_DB_PASSWORD=change_me_claude
AI_AGENT_DB_DEVELOPMENT=ai_blazing_star_project_claude_development
AI_AGENT_DB_TEST=ai_blazing_star_project_claude_test
# AI_AGENT_TEST_ENV_NUMBER=2
AI_AGENT_REDIS_DB=0

# Ключ модели этого слота-агента (для раздельной статистики и тарификации).
AI_AGENT_ANTHROPIC_API_KEY=
```

**5) Добавление рабочих папок агентов в контейнер `app`**

Раскомментируйте или добавьте строки в `docker-compose.dev.yml`, если папки агентов нужны в контейнере `app` только для чтения:

```yml
services:
  app:
    volumes:
      # Worktrees AI-агентов только для чтения:
      # - ./ai_worktree:/ai_peers/ai_agent:ro
      # - ./ai2_worktree:/ai_peers/ai_agent_2:ro
      # - ./ai3_worktree:/ai_peers/ai_agent_3:ro
```


## Сеть Docker

В контейнерах используется внешняя сеть `shared_dev_network` для выхода в Интернет без прокси-сервера (для контейнера `app`, для контейнеров агентов - только на этапе сборки контейнера.)

Также используется изолированная внутренняя сеть Docker для всех AI-контейнеров.

Сети должны создаться при запуске контейнеров, если этого не произошло или вы их удалили, создайте вручную.

```bash
duser network create shared_dev_network
```

```bash
duser network create ai_isolated_network
```

** Если сеть уже есть, команда вернёт ошибку `already exists` — это нормально.


## Сборка образов Docker

Сначала необходимо раскомментировать строку в `docker-compose.ai-base.yml`, открывающую доступ AI контейнерам во внешнюю сеть хоста и в Интернет для скачивания и установки Python из репозиториев:

```yml
  networks:
    ....
    # - shared_network # Сеть с выходом во внешние сети хоста
```

Раскомментируйте `shared_network`:

```bash
sed -i '/networks:/,/^[[:space:]]*[a-zA-Z]/ s/# - shared_network/- shared_network/' .dev_docker/docker-compose.ai-base.yml
```

**Запуск сборки образов:**

Первым собирается образ контейнера `app`, затем AI-образ (он наследуется от app):

```bash
dcom -f docker-compose.dev.yml build app
dcom -f docker-compose.dev.yml --profile ai build
```

Первый запуск может занять 10–30 минут: скачиваются базовые образы, gem'ы, node/python-пакеты.


Проверка образов:

```bash
duser images | grep -E 'blazing_star_project-app|blazing_star_project-ai'
```

После сборки AI-образов, стоит закомментировать обратно, если нужно ограничить выход AI-агентов в Интернет и изолировать от локальной сети хоста:

```bash
sed -i '/networks:/,/^[[:space:]]*[a-zA-Z]/ s/- shared_network/# - shared_network/' .dev_docker/docker-compose.ai-base.yml
```


## Запуск инфраструктуры

> Вспомогательные контейнеры поднимутся сами при запуске основных (`app`, `ai_agent`, `ai_agent_NN`).
>
> Поэтому можете пропустить данный раздел и перейти сразу к следующему: `Запуск app`.

Postgres и Redis приложения:

```bash
dcom -f docker-compose.dev.yml up -d db_postgres db_redis
```

Redis для AI (у него профиль `ai`):

```bash
dcom -f docker-compose.dev.yml --profile ai up -d db_redis_ai
```

Проверка:

```bash
dcom -f docker-compose.dev.yml ps
dcom -f docker-compose.dev.yml logs --tail=50 db_postgres
dcom -f docker-compose.dev.yml logs --tail=50 db_redis_ai
```


## Запуск app

* *Опция --rm позволит автоматически удалить временный экземпляр контейнера после того, как вы выйдете из него*

Запустите app:

```bash
dcom -f docker-compose.dev.yml run --rm app
```

Если потребуется запуск с пробрасыванием настроенных портов из контейнера на хост:

```bash
dcom -f docker-compose.dev.yml run --service-ports --rm app
```

Проверьте доступность БД из контейнера:

```bash
pg_isready -h db_postgres -p 5432 -U "$PGUSER"
```

### Настройка баз данных

> Что делает скрипт `setup_ai_user`:
>
> * создаёт роль/пользователя БД;
> * создаёт development/test БД, если их нет;
> * ставит расширения `pg_trgm`, `uuid-ossp`;
> * выдаёт права на `public`/`analytics` и default privileges;
> * **не загружает схему** — схема должна грузиться вручную (для агента - из его worktree).

#### Настройка БД для `app`:

Находясь в контейнере `app`, создайте базы и пользователей для дальнейшей работы:

```bash
.dev/setup_ai_user.sh app --user "$DB_USER" --password "$DB_PASSWORD" --dev-db "$POSTGRES_DB_DEVELOPMENT" --test-db "$POSTGRES_DB_TEST" --owner "$DB_USER"
```

** *Добавьте опцию `--dry-run` к вызовам `setup_ai_user`, чтобы посмотреть план запросов без фактического выполнения действий.*

** *Добавьте опцию `-y` для выполнения действий без подтверждения.*

#### Настройка БД для `ai_agent`:

Далее из контейнера `app` создайте пользователей БД для агентов:

```bash
.dev/setup_ai_user.sh ai_agent -y

.dev/setup_ai_user.sh ai_agent_2 -y
```


## Проверка БД (в контейнере app)

Получить список пользователей БД:

```bash
psql -h db_postgres -U "$PGUSER" -d postgres -c "\du"
```

Получить список баз данных:

```bash
psql -h db_postgres -U "$PGUSER" -d postgres -c "\l"
```


## Настройка RSpec для хранения истории тестов

Для успешного сохранения статуса пройденых тестов в контейнере, проверьте, что в `spec/spec_helper.rb` указан путь, к которому вы предоставили доступ на запись:

```ruby
RSpec.configure do |config|
  ...

  config.example_status_persistence_file_path = ENV['RAILS_SPEC_STATUS_FILE_PATH'] || "spec/examples.txt"
```

По умолчанию в файлах `docker-compose.dev.yml` и `docker-compose.ai-base.yml` указан доступный путь:
```yml
RAILS_SPEC_STATUS_FILE_PATH=log/spec_examples.txt
```


## Проверка работоспособности в контейнерах (app и ai_agent)

Чтобы убедиться в том, что все настройки произведены корректно, проверим реальную работу.

Запустите тесты:

```bash
bundle exec rspec spec/services/
```

В случае проблем с базой в тестах, проверьте активный конфиг:

```bash
RAILS_ENV=test bundle exec rails runner \
  'p ActiveRecord::Base.connection_db_config.configuration_hash.slice(:host,:port,:database,:username)'
```

Запустите настройку схемы и миграций для среды `development`:

```bash
# bundle exec rails db:setup - не требуется, т.к. базу уже создала команда .dev/setup_ai_user.sh

bundle exec rails db:schema:load
```

Запустите консоль:

```bash
bundle exec rails c
```

В консоли выполните:

#### Проверка Postgres:

```ruby
  puts ActiveRecord::Base.connection_db_config.configuration_hash.slice(:host,:port,:database,:username)

  ApplicationRecord.connection.execute("SELECT 1")

  table_name = ApplicationRecord.connection.tables.first || raise(NotImplementedError, 'No tables found ')
  quoted_table = ApplicationRecord.connection.quote_table_name(table_name)
  ApplicationRecord.connection.execute("SELECT * FROM #{quoted_table} LIMIT 1").as_json
```

#### Проверка Redis:

```ruby
Rails.cache.redis.set('qwe', 'rty')
Rails.cache.redis.del('qwe')
Rails.cache.write('asd', 1, expires_in: 5.seconds)
```

Если никаких ошибок доступа не возникло, значит всё настроено корректно.


### Проверить версию Postgres и Pg Dump

Версия сервера:

```bash
psql -U "$DB_USER" -d postgres -c "SHOW server_version;"
```

Версия Pg Dump:
```bash
pg_dump -V
```

> **ВАЖНО:** Для корректной работы `pg_dump` в контейнере, его версия должна совпадать с версией сервера.
>
> В случае разных версий, делать дамп потребуется из контейнера БД:
> ```bash
> dcom -f docker-compose.dev.yml exec -T db_postgres pg_dump --schema-only --no-privileges --no-owner -U "${POSTGRES_ADMIN_USER:-postgres}" blazing_star_project_test > db/structure_.sql
> ```
>

### Решение проблем с Postgres

Просмотр логов Postgres:

```bash
duser logs blazing_star_project-db_postgres-1
```

Список монтируемых в контейнеры томов:

```bash
duser volume ls
```

#### Очистка volume с базой данных, предварительно убрав контейнер:

```bash
dcom -f docker-compose.dev.yml down db_postgres

duser volume rm blazing_star_project_pg_data
```

#### Удалить пользователя БД:

```bash
duser exec -it blazing_star_project-db_postgres-1 dropuser -U "$PGUSER" имя_удаляемого_пользователя
```

или через SQL:

```bash
psql -h db_postgres -U "$PGUSER" -d postgres -c "DROP DATABASE <dbname>"
psql -h db_postgres -U "$PGUSER" -d postgres -c "DROP USER <username>"
```

#### Установка нового пароля администратора Postgres:

1. Запустите консоль `psql` в контейнере `db_postgres`:
```bash
duser exec -it blazing_star_project-db_postgres-1 psql -U postgres
```

2. Внутри консоли psql выполните SQL-запрос для смены пароля:
```sql
ALTER USER postgres WITH PASSWORD 'новый_пароль';
```

#### Фикс `db/structure.sql` от создания комментариев к объектам БД:

```bash
bundle exec rake db:clean_structure
```


## Рабочие папки AI-агентов

Для каждого контейнера ai_agent_NN создайте на отдельную git worktree папку в каталоге проекта:

```bash
.dev/wtree create ai_agent

.dev/wtree create ai_agent_2

.dev/wtree create ai_agent_3
```

Переключить `.git`-пути на внутри-контейнерные сразу для всех (без указания конкретного контейнера):

```bash
.dev/wtree docker
```

Проверка:

```bash
.dev/wtree list
ls -la ai_worktree ai2_worktree ai3_worktree
```

**Если скрипты не исполняются:**

Либо выполните `chmod +x` на хосте:

```bash
chmod +x .dev/setup_ai_user.sh \
  .dev/wtree \
  .dev/ai-entrypoint.sh \
  .dev/git-ai-sync.sh \
  .dev/rootless_folders.sh \
  .dev/ai_tools/ai-wizard.sh
```

Либо запускайте скрипты через `sh`:

```bash
sh .dev/wtree create ai_agent_2
sh .dev/wtree docker ai_agent_2
```


## Запуск AI-агентов

```bash
dcom -f docker-compose.dev.yml --profile ai run --rm ai_agent
```

```bash
dcom -f docker-compose.dev.yml --profile ai run --rm ai_agent_2
```

В каждом AI контейнере необходимо инициализировать базу данных, если они отличаются:

```bash
bundle exec rails db:schema:load
```

И также проверить корректность работы:

```bash
bundle exec rspec spec/services/
```

```bash
bundle exec rails c
```

```ruby
ApplicationRecord.connection.execute("SELECT 1")

table_name = ApplicationRecord.connection.tables.first || raise(NotImplementedError, 'No tables found ')
quoted_table = ApplicationRecord.connection.quote_table_name(table_name)
puts ApplicationRecord.connection.execute("SELECT * FROM #{quoted_table} LIMIT 1").as_json.size

Rails.cache.redis.set('qwe', 'rty')
Rails.cache.redis.del('qwe')
Rails.cache.write('asd', 1, expires_in: 5.seconds)
```

## Всё
Если никаких ошибок не возникло, значит всё готово.
