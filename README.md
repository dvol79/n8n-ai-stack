Оптимизированный стек для локальной автоматизации с ИИ на базе **n8n**, **PostgreSQL**, **Qdrant** и **LiteLLM**.

Архитектура специально спроектирована для эффективной работы на оборудовании с ограниченными ресурсами (например, Intel Core i5-3470S, 16 ГБ RAM), перенося тяжелые вычисления ИИ на внешний API через универсальный прокси-шлюз, что исключает vendor lock-in и позволяет мгновенно менять провайдера LLM без перенастройки workflows.

---

## 📑 Содержание

- [Архитектура стека](#архитектура-стека)
- [Предварительные требования](#-предварительные-требования)
- [Структура файлов](#-структура-файлов)
- [Быстрый старт](#-быстрый-старт)
- [Настройка n8n с LiteLLM](#n8n-litellm)
- [Бэкап и восстановление](#-бэкап-и-восстановление)
- [Смена провайдера ИИ](#-смена-провайдера-ии-без-перенастройки-n8n)
- [Устранение неполадок](#-устранение-неполадок-troubleshooting)
- [Полезные команды](#-полезные-команды)

---

## Архитектура стека

| Сервис | Контейнер | Назначение | Потребление RAM (примерно) |
|--------|-----------|------------|----------------------------|
| **PostgreSQL** | `n8n_postgres` | Надежное хранение данных n8n (workflow, executions) | ~150 МБ |
| **Qdrant** | `n8n_qdrant` | Локальная векторная база данных для RAG-сценариев | ~200–500 МБ |
| **LiteLLM** | `n8n_litellm` | Универсальный OpenAI-совместимый API-шлюз | ~100–200 МБ |
| **n8n** | `n8n_main` | Движок автоматизации и оркестрации | ~1–1.5 ГБ |

> **Итоговая нагрузка:** ~2–3 ГБ RAM, минимальная нагрузка на CPU.

---

## 📋 Предварительные требования

1. Установленные **Docker** и **Docker Compose**.
2. Утилита `openssl` (для генерации криптографически стойких ключей в `init.sh`).
3. API-ключ от любого LLM-провайдера:
  - [OpenRouter](https://openrouter.ai/) — агрегатор с сотнями моделей (рекомендуется)
  - [DeepSeek](https://platform.deepseek.com/) — дешевый и мощный
  - [OpenAI](https://platform.openai.com/) — оригинал
  - Любой другой OpenAI-совместимый API

---

## 📁 Структура файлов

В директории проекта должны находиться следующие файлы:

```
n8n-ai-stack/
├── docker-compose.yml       # Оркестрация контейнеров
├── litellm_config.yaml      # Конфигурация маршрутизации LiteLLM
├── .env.example             # Шаблон переменных окружения
├── init.sh                  # Скрипт генерации секретов
├── backup.sh                # Скрипт ежедневного бэкапа БД
└── README.md                # Этот файл
```

---

## 🚀 Быстрый старт

### Шаг 1: Подготовка файлов

Сделайте bash-скрипты исполняемыми:
```bash
chmod +x init.sh backup.sh
```

### Шаг 2: Генерация секретов

Запустите скрипт инициализации. Он создаст файл `.env` со случайными надежными паролями и ключами:
```bash
./init.sh
```

Скрипт сгенерирует:
- `POSTGRES_PASSWORD` — пароль для базы данных
- `N8N_ENCRYPTION_KEY` — ключ шифрования n8n (критически важен!)
- `N8N_BASIC_AUTH_PASSWORD` — пароль для базовой аутентификации

> ⚠️ **ВАЖНО:** Сохраните выведенные в консоль ключи (особенно `N8N_ENCRYPTION_KEY`). После первого запуска n8n изменение этого ключа приведет к безвозвратной потере доступа ко всем сохраненным credentials.

### Шаг 3: Добавление недостающих ключей

Откройте созданный файл `.env` и вручную добавьте ключ и модель для LiteLLM (они не генерируются автоматически):

```env
# --- LiteLLM (Универсальный шлюз) ---
LITELLM_MASTER_KEY=sk-придумайте_любую_длинную_строку_для_шлюза

# --- Провайдер ИИ (ОБЯЗАТЕЛЬНО!) ---
PROVIDER_API_KEY=sk-or-v1-ваш_реальный_ключ_от_openrouter_или_другого_провайдера
DEFAULT_MODEL=openrouter/deepseek/deepseek-chat
```

### Шаг 4: Запуск стека

```bash
docker compose up -d
```

Проверьте статус контейнеров (все должны быть в состоянии `Up`):
```bash
docker compose ps
```

Проверьте логи на наличие ошибок:
```bash
# Логи n8n
docker compose logs -f n8n

# Логи LiteLLM
docker compose logs -f litellm

# Логи PostgreSQL
docker compose logs -f postgres

# Логи всех сервисов
docker compose logs -f
```

### Шаг 5: Первоначальная настройка n8n

1. Откройте в браузере: [http://localhost:5678](http://localhost:5678)
2. Создайте аккаунт администратора.
3. Перейдите к [настройке LiteLLM](#n8n-litellm).

---

<a id="n8n-litellm"></a>
## ⚙️ Настройка n8n с LiteLLM

LiteLLM предоставляет **OpenAI-совместимый API**, поэтому n8n "думает", что общается с OpenAI, но запросы маршрутизируются к вашему провайдеру.

### Создание Credentials

1. Перейдите по прямой ссылке: [http://localhost:5678/credentials](http://localhost:5678/credentials)
2. Нажмите **+ Add** (или Create new credential).
3. В поиске выберите **OpenAI API**.
4. Заполните поля:
   - **API Key**: `$env.LITELLM_MASTER_KEY`
     *(Если n8n выдает ошибку при использовании выражения, просто скопируйте значение `LITELLM_MASTER_KEY` из файла `.env` и вставьте его сюда как обычный текст).*
   - **Base URL**: `http://localhost:4000` *(внутренний адрес шлюза в Docker-сети)*
5. Нажмите **Save**.

### Использование в workflows

В любом AI-узле (например, **OpenAI**, **AI Agent** или **Chat Model**):
1. Выберите созданные credentials.
2. В поле **Model** укажите: `universal-ai` (это имя задано в `litellm_config.yaml`).
3. Готово! Запрос уйдет через LiteLLM к вашему провайдеру.

---

## 💾 Бэкап и восстановление

Скрипт `backup.sh` создает сжатый SQL-дамп базы данных n8n.

### ⚠️ Критически важное предупреждение

Текущая версия `backup.sh` сохраняет **только дамп базы данных**. Если вы потеряете файл `.env` с оригинальным значением `N8N_ENCRYPTION_KEY`, расшифровать сохраненные credentials из SQL-дампа будет **невозможно**. Обязательно храните копию `.env` в надежном месте.

### Ручной запуск бэкапа

```bash
./backup.sh
```

Архивы сохраняются в папку `./backups` с именем `n8n_backup_ГГГГММДД_ЧЧММСС.sql.gz`.

### Настройка автоматического бэкапа (Cron)

Откройте crontab:
```bash
crontab -e
```

Добавьте задачу для ежедневного бэкапа в 3:00 ночи:
```cron
0 3 * * * /абсолютный/путь/к/вашей/папке/backup.sh >> /абсолютный/путь/к/вашей/папке/backups/cron.log 2>&1
```

> **Важно:** используйте **абсолютные пути**, иначе cron не найдет файлы при запуске.

### Восстановление из бэкапа

1. Остановите текущий стек:
```bash
docker compose down
```

2. Распакуйте нужный архив бэкапа:
```bash
gunzip -c backups/n8n_backup_20231025_030000.sql.gz > dump.sql
```

3. Запустите только базу данных:
```bash
docker compose up -d postgres
```

4. Дождитесь готовности PostgreSQL и восстановите дамп:
```bash
docker exec -i n8n_postgres psql -U n8n_user -d n8n_db < dump.sql
```

5. Запустите весь стек:
```bash
docker compose up -d
```

6. **Обязательно** убедитесь, что в `.env` указан правильный `N8N_ENCRYPTION_KEY` (тот же, что был на момент создания бэкапа).

---

## 🔄 Смена провайдера ИИ без перенастройки n8n

Благодаря LiteLLM, n8n "думает", что всегда общается с OpenAI. Чтобы сменить провайдера:

1. Откройте `.env`.
2. Измените `PROVIDER_API_KEY` и `DEFAULT_MODEL`.

**Примеры конфигураций:**

**OpenRouter (агрегатор моделей):**
```env
PROVIDER_API_KEY=sk-or-v1-ваш_ключ
DEFAULT_MODEL=openrouter/deepseek/deepseek-chat
```

**DeepSeek напрямую:**
```env
PROVIDER_API_KEY=sk-ваш_ключ_от_deepseek
DEFAULT_MODEL=deepseek/deepseek-chat
```

**Локальный Ollama (если установлен на хосте):**
```env
PROVIDER_API_KEY=dummy-key
DEFAULT_MODEL=ollama/qwen2:0.5b
```

3. Перезапустите контейнер LiteLLM:
```bash
docker compose restart litellm
```

**Никакие workflow или credentials в n8n изменять не нужно!**

---

## 🛠️ Устранение неполадок (Troubleshooting)

### ❌ Ошибка: `Mismatching encryption keys` в логах n8n

**Симптом:** n8n не запускается, в логах повторяется ошибка:
```
Error: Mismatching encryption keys. The encryption key in the settings file 
/home/node/.n8n/config does not match the N8N_ENCRYPTION_KEY env var.
```

**Причина:** n8n был запущен *до* выполнения `init.sh`, или вы изменили/перегенерировали `.env` после первого запуска. n8n зашифровал данные старым ключом и отказывается работать с новым.

**Решение А (если данных еще нет — рекомендуется):**
```bash
docker compose down
docker volume ls | grep n8n_data
docker volume rm <имя_тома_n8n_data>
docker compose up -d
```

**Решение Б (если нужно сохранить данные):**
```bash
docker compose down
docker run --rm -v <имя_тома_n8n_data>:/data alpine cat /data/config
# Скопируйте значение "encryptionKey" из вывода
# Вставьте его в .env как N8N_ENCRYPTION_KEY
docker compose up -d
```

---

### ❌ Ошибка LiteLLM: `LLM Provider NOT provided. You passed model=${DEFAULT_MODEL}`

**Симптом:** в логах LiteLLM:
```
litellm.BadRequestError: LLM Provider NOT provided. 
Pass in the LLM provider you are trying to call. You passed model=\${DEFAULT_MODEL}
```

**Причина:** Docker Compose **не подставляет** переменные окружения внутрь файлов, смонтированных через `volumes`. LiteLLM видит буквальную строку `${DEFAULT_MODEL}`.

**Решение:** Убедитесь, что в файле `litellm_config.yaml` используется специальный синтаксис LiteLLM для чтения переменных:

```yaml
model_list:
  - model_name: "universal-ai"
    litellm_params:
      model: os.environ/DEFAULT_MODEL
      api_key: os.environ/PROVIDER_API_KEY

general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
```

После исправления:
```bash
docker compose up -d --force-recreate litellm
```

---

### ❌ Ошибка LiteLLM: `No connected db`

**Симптом:** в логах LiteLLM:
```
litellm.proxy.proxy_server.user_api_key_auth(): Exception occured - No connected db.
```

**Причина:** Каскадная ошибка из-за невалидной конфигурации (см. предыдущий пункт). Как только вы исправите `litellm_config.yaml`, эта ошибка исчезнет.

---

### ❌ Ошибка `backup.sh`: `файл .env не найден`

**Симптом:** при запуске `./backup.sh`:
```
Ошибка: файл .env не найден в 
```

**Причина:** В старых версиях скрипта переменная `SCRIPT_DIR` использовалась **до** своего объявления.

**Решение:** Убедитесь, что вы используете актуальную версию `backup.sh`, где объявление `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE}")" && pwd)"` находится **в самом начале скрипта**, до любой проверки файлов.

---

### ❌ Не могу найти раздел "Credentials" в интерфейсе n8n

**Решение:**
1. Используйте прямую ссылку: [http://localhost:5678/credentials](http://localhost:5678/credentials)
2. Или создайте credential прямо из узла: добавьте на канвас узел **OpenAI** → нажмите на поле Credential → **Create New**.

---

### ❌ n8n не видит переменные окружения из `.env`

**Симптом:** выражение `={{ $env.LITELLM_MASTER_KEY }}` возвращает пустое значение.

**Решение:**
1. Убедитесь, что переменная действительно есть в `.env` и контейнер был перезапущен после её добавления:
   ```bash
   docker compose down
   docker compose up -d
   ```
2. Если выражения в credentials не работают, вставьте значение напрямую из `.env` как обычный текст.

---

## 💡 Полезные команды

### Управление стеком

```bash
# Запуск всех сервисов в фоне
docker compose up -d

# Остановка всех сервисов
docker compose down

# Перезапуск конкретного сервиса
docker compose restart litellm
docker compose restart n8n

# Полная очистка стека ⚠️ ВНИМАНИЕ: удалит все данные!
docker compose down -v
```

### Просмотр логов

```bash
# Логи n8n
docker compose logs -f n8n

# Логи LiteLLM
docker compose logs -f litellm

# Логи PostgreSQL
docker compose logs -f postgres

# Логи всех сервисов
docker compose logs -f
```

### Диагностика

```bash
# Статус всех контейнеров
docker compose ps

# Проверка здоровья PostgreSQL
docker exec n8n_postgres pg_isready -U n8n_user -d n8n_db

# Проверка доступности LiteLLM
curl http://localhost:4000/health
```

### Доступ к Web UI

- **n8n**: [http://localhost:5678](http://localhost:5678)
- **Qdrant Dashboard**: [http://localhost:6333/dashboard](http://localhost:6333/dashboard)
  *(Введите `QDRANT_API_KEY` из вашего `.env` для входа)*
- **LiteLLM**: [http://localhost:4000](http://localhost:4000)

---

## 📚 Дополнительные ресурсы

- [Документация n8n](https://docs.n8n.io/)
- [Документация LiteLLM](https://docs.litellm.ai/)
- [Документация Qdrant](https://qdrant.tech/documentation/)
- [OpenRouter Models](https://openrouter.ai/models)

---

## 📄 Лицензия

Этот проект использует компоненты со следующими лицензиями:
- **n8n**: Sustainable Use License / n8n Enterprise License
- **PostgreSQL**: PostgreSQL License
- **Qdrant**: Apache 2.0
- **LiteLLM**: MIT