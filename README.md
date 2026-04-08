# SportData Platform

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
