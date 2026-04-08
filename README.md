# SportData Platform

[![CI](https://github.com/alexeydonichev/sportdata/actions/workflows/ci.yml/badge.svg)](https://github.com/alexeydonichev/sportdata/actions/workflows/ci.yml)
[![Go](https://img.shields.io/badge/Go-1.24-00ADD8?logo=go)](https://go.dev)
[![Next.js](https://img.shields.io/badge/Next.js-15-black?logo=next.js)](https://nextjs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql)](https://postgresql.org)

Аналитическая платформа для мультимаркетплейс-продавцов спортивных товаров.
Единый дашборд для агрегации данных с Wildberries, Ozon и Яндекс Маркет.

## Возможности

- Единый дашборд - выручка, прибыль, заказы со всех маркетплейсов
- Автосинхронизация - ETL с Wildberries, Ozon, Яндекс Маркет
- Аналитика - ABC-анализ, юнит-экономика, P&L, география продаж
- Управление товарами - каталог, остатки, карточки с метриками
- Безопасность - PASETO токены, AES-256 шифрование ключей, RBAC
- Мультитенант - роли от менеджера до суперадмина

## Архитектура

| Сервис | Стек | Назначение |
|--------|------|------------|
| frontend | Next.js 15, React 19, TailwindCSS, shadcn/ui | UI + BFF |
| api-gateway | Go 1.24, PASETO, bcrypt | Auth, RBAC, Admin API |
| etl-service | Go 1.24 | Синхронизация с маркетплейсами |
| postgres | PostgreSQL 16 | Основная БД |
| redis | Redis 7 | Кеш, сессии, rate limiting |

## Структура проекта




[![CI](https://github.com/alexeydonichev/sportdata/actions/workflows/ci.yml/badge.svg)](https://github.com/alexeydonichev/sportdata/actions/workflows/ci.yml)

Аналитическая платформа для мультимаркетплейс-продавцов спортивных товаров.

## Возможности

- Единый дашборд - выручка, прибыль, заказы со всех маркетплейсов
- Автосинхронизация - ETL с Wildberries, Ozon, Яндекс Маркет
- Аналитика - ABC-анализ, юнит-экономика, P&L
- Безопасность - PASETO токены, AES-256 шифрование, RBAC

## Стек

- Frontend: Next.js 15, React 19, TailwindCSS
- Backend: Go 1.24, PASETO, bcrypt
- Database: PostgreSQL 16, Redis 7

## Быстрый старт

git clone https://github.com/alexeydonichev/sportdata.git
cd sportdata
cp .env.example .env
make up
make admin

Открыть http://localhost:3000

## Лицензия

Proprietary - YourFit 2025
Да, согласен. Давай расширим! Открой nano:

```bash
nano README.md
```

Удали всё (Ctrl+A, затем Ctrl+K) и вставь это:

```
# SportData Platform

[![CI](https://github.com/alexeydonichev/sportdata/actions/workflows/ci.yml/badge.svg)](https://github.com/alexeydonichev/sportdata/actions/workflows/ci.yml)
[![Go](https://img.shields.io/badge/Go-1.24-00ADD8?logo=go)](https://go.dev)
[![Next.js](https://img.shields.io/badge/Next.js-15-black?logo=next.js)](https://nextjs.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?logo=postgresql)](https://postgresql.org)

Аналитическая платформа для мультимаркетплейс-продавцов спортивных товаров.
Единый дашборд для агрегации данных с Wildberries, Ozon и Яндекс Маркет.

## Возможности

- Единый дашборд - выручка, прибыль, заказы со всех маркетплейсов
- Автосинхронизация - ETL с Wildberries, Ozon, Яндекс Маркет
- Аналитика - ABC-анализ, юнит-экономика, P&L, география продаж
- Управление товарами - каталог, остатки, карточки с метриками
- Безопасность - PASETO токены, AES-256 шифрование ключей, RBAC
- Мультитенант - роли от менеджера до суперадмина

## Архитектура

| Сервис | Стек | Назначение |
|--------|------|------------|
| frontend | Next.js 15, React 19, TailwindCSS, shadcn/ui | UI + BFF |
| api-gateway | Go 1.24, PASETO, bcrypt | Auth, RBAC, Admin API |
| etl-service | Go 1.24 | Синхронизация с маркетплейсами |
| postgres | PostgreSQL 16 | Основная БД |
| redis | Redis 7 | Кеш, сессии, rate limiting |

## Структура проекта

```
sportdata/
├── .github/workflows/       # CI/CD
├── migrations/              # SQL миграции
├── api-gateway/             # Go сервис авторизации
│   ├── cmd/api/
│   └── internal/
│       ├── auth/            # PASETO, bcrypt
│       ├── handlers/        # HTTP handlers
│       └── middleware/      # Auth, RBAC
├── etl-service/             # Go ETL worker
│   ├── cmd/worker/
│   └── internal/
│       ├── marketplace/     # Ozon, WB клиенты
│       └── crypto/          # AES шифрование
├── frontend/                # Next.js приложение
│   ├── app/                 # App Router
│   └── components/          # React компоненты
├── docker-compose.yml
└── Makefile
```

## Быстрый старт

```bash
git clone https://github.com/alexeydonichev/sportdata.git
cd sportdata
cp .env.example .env
make up
make admin
```

Открыть http://localhost:3000

## Makefile команды

| Команда | Описание |
|---------|----------|
| make up | Запуск всех сервисов |
| make down | Остановка |
| make logs | Логи всех сервисов |
| make migrate | Применить миграции |
| make admin | Создать суперадмина |
| make psql | Подключиться к БД |
| make test | Запустить тесты |

## Модули дашборда

| Модуль | Описание |
|--------|----------|
| Главная | KPI: выручка, прибыль, заказы, средний чек |
| Продажи | Таблица с фильтрами по МП, категории, периоду |
| Товары | Каталог, карточка товара с аналитикой |
| Склад | Остатки по маркетплейсам и складам |
| Аналитика | P&L, ABC-анализ, юнит-экономика, география |
| Синхронизация | Управление API-ключами, история ETL |
| Админ | RBAC, управление пользователями |

## Безопасность

| Компонент | Технология |
|-----------|------------|
| Аутентификация | PASETO v4 токены |
| Пароли | bcrypt (cost 12) |
| API-ключи МП | AES-256-GCM шифрование |
| Авторизация | RBAC (5 ролей) |
| Rate limiting | Redis sliding window |
| Audit log | Логирование всех действий |

## API Endpoints

### Auth
- POST /api/auth/login - вход
- POST /api/auth/logout - выход
- GET /api/auth/me - текущий пользователь

### Admin
- GET /api/admin/users - список пользователей
- POST /api/admin/users - создать пользователя
- DELETE /api/admin/users/:id - удалить
- GET /api/admin/credentials - API-ключи
- POST /api/admin/credentials - добавить ключ
- POST /api/admin/credentials/:id/sync - запустить синхронизацию

## Роли

| Роль | Уровень | Права |
|------|---------|-------|
| super_admin | 100 | Полный доступ |
| admin | 80 | Управление пользователями |
| analyst | 60 | Просмотр всей аналитики |
| operator | 40 | Работа с заказами |
| manager | 20 | Базовый просмотр |

## Тестирование

```bash
make test
cd api-gateway && go test ./... -v
cd etl-service && go test ./... -v
```

## Лицензия

Proprietary - YourFit 2025
```

Сохрани: Ctrl+O, Enter, Ctrl+X

Потом:
```bash
wc -l README.md
```
