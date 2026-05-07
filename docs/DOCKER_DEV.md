# 🚀 Инструкция по развёртыванию образов Docker для разработки

Добро пожаловать! Этот проект контейнеризирован с использованием Docker. Для работы вам не нужно устанавливать Ruby, Postgres или Redis прямо на вашу машину.

## 1. Системные требования
Перед началом убедитесь, что у вас установлены:
* **Docker** и **Docker Compose**

Окружение настроено под [режим Docker Rootless](https://docs.docker.com/engine/security/rootless/), что накладывает определенные особенности на работу с правами доступа.

Так как Docker будет запущен в Rootless-режиме, ваш пользователь внутри контейнера и снаружи — это разные сущности.
Внутри - root, снаружи - указанный вами пользователь, под которым запущен демон Docker (вместо системного процесса).

Из-за особенности создания файлов внутри rootless контейнера, в App при запуске по умолчанию стоит umask 000. Все файлы, которые создаются внутри контейнера (например, логи или отчеты SimpleCov), будут с правами на чтение и запись для всех.

## 2. Первый запуск

Выполните эти шаги последовательно:

1. **Настройка переменных окружения Docker:**
   Скопируйте шаблон настроек в локальный файл:
   ```bash
   cp .env.example .env
   ```
   *Если у вас уже запущен локальный Postgres или Redis, измените порты `POSTGRES_EXTERNAL_PORT` и `REDIS_EXTERNAL_PORT` в `.env`, чтобы избежать конфликтов.*

   *Эти настройки должны будут совпадать с настройками в `config/settings/development.local.yml`*

2. **Настройка параметров Приложения:**
   Скопируйте шаблон настроек в локальный файл:
   ```bash
   cp config/settings/development.yml config/settings/development.local.yml
   ```

   В вашем `development.local.yml` укажите актуальные `db -> user` и `db -> password`

   `db -> host` укажите `db_postgres`

   `redis -> url` укажите `'redis://db_redis:6379'`

3. **Создайте общую сеть:**
   Это нужно, чтобы другие проекты видели базы внутри Docker (по именам сервисов db_postgres, db_redis).
   ```bash
   docker network create shared_dev_network
   ```

4. **Сборка и запуск контейнеров:**
   ```bash
   docker compose -f docker-compose.dev.yml up --build
   ```

5. **Подготовка приложения:**
   Установка гемов и запуск миграций БД внутри контейнера:
   ```bash
   docker compose -f docker-compose.dev.yml run --rm app sh -c "bundle install && rails db:setup"
   ```
   *Гемы сохраняются в хранилище docker volume, указанное в docker-compose.yml: bundle_data*

## 3. Ежедневная работа

### Запуск временного контейнера:
* *Опция --rm позволит автоматически удалить временный экземпляр контейнера после того, как вы выйдете из него*
   ```bash
   docker compose -f docker-compose.dev.yml run --rm app
   ```

### Основные команды (внутри контейнера):
* `rails s -b 0.0.0.0` — запуск веб-сервера.
* `rails c` — запуск интерактивной консоли.
* `rspec` — запуск тестов.

### Управление контейнерами (снаружи):
* **Остановка всех:** `docker compose -f docker-compose.dev.yml --profile manual stop`
* **Запуск Postgres и Redis:** `docker compose -f docker-compose.dev.yml start`
* **Просмотр логов:** `docker compose -f docker-compose.dev.yml logs -f --tail 30`
* **Объём занятого места:** `docker images`

## 4. Решение проблем (Troubleshooting)

* **Не создаётся контейнер:**:
   Для получения детального лога сборки используйте флаг `--progress=plain`. Это выведет весь текст установки пакетов apk прямо в терминал, и вы увидите конкретную строку с ошибкой.

   ```bash
   docker compose -f docker-compose.dev.yml build --progress=plain app
   ```

* **Сброс базы данных:** Удалить и пересоздать БД "с нуля":
  ```bash
  docker compose -f docker-compose.dev.yml exec db_postgres dropdb blazing_star_project_test
  docker compose -f docker-compose.dev.yml exec db_postgres dropdb blazing_star_project_development
  docker compose -f docker-compose.dev.yml run --rm app sh -c "rails db:setup"
  ```

* **Сброс контейнеров:** Полностью удалить контейнеры и пересоздать их "с нуля":
  ```bash
  docker compose -f docker-compose.dev.yml --profile manual down -v
  docker compose -f docker-compose.dev.yml up --build -d
  ```

* **Пропустить кэш контейнеров:** Установить контейнеры без кэша предыдущей установки:
  ```bash
  docker compose -f docker-compose.dev.yml up --build --no-cache -d
  ```

* **Пересобрать контейнер:** После изменений в Dockerfile.dev.app:
  ```bash
  docker compose -f docker-compose.dev.yml build app
  ```

* **Удалить том в контейнере:** После изменений в Dockerfile.dev.app:
  ```bash
  docker volume rm blazing_star_project_root_home
  ```

* **Ошибка сборки базы:** Если при сборке вы видите ошибку `Database names are not set!`, значит вы забыли создать файл `.env` или заполнить в нем названия баз.


## 5. Настройка контейнеров для AI агентов

[DOCKER_AI.md](./DOCKER_AI.md)
