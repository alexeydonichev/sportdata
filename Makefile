.PHONY: help up down restart logs db-up db-down api web etl migrate seed

# Цвета
GREEN  := \033[0;32m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m

help: ## Показать справку
	@echo ""
	@echo "$(GREEN)SportData Platform$(NC) — Команды управления"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}'
	@echo ""

# ============================================
# Docker
# ============================================

up: ## Запустить всё (PostgreSQL + Redis)
	docker compose up -d
	@echo "$(GREEN)✅ Сервисы запущены$(NC)"
	@echo "PostgreSQL: localhost:5432"
	@echo "Redis:      localhost:6379"

down: ## Остановить всё
	docker compose down
	@echo "$(RED)⏹  Сервисы остановлены$(NC)"

restart: down up ## Перезапустить всё

logs: ## Логи всех сервисов
	docker compose logs -f

db-logs: ## Логи PostgreSQL
	docker compose logs -f postgres

db-shell: ## Подключиться к PostgreSQL
	docker compose exec postgres psql -U sportdata_admin -d sportdata

redis-shell: ## Подключиться к Redis
	docker compose exec redis redis-cli -a SportData_Redis_2025!

# ============================================
# API (Go)
# ============================================

api-init: ## Инициализировать Go модуль
	cd api-gateway && go mod init sportdata-api && go mod tidy

api-dev: ## Запустить API в dev режиме
	cd api-gateway && go run cmd/server/main.go

api-build: ## Собрать API бинарник
	cd api-gateway && CGO_ENABLED=0 go build -o bin/server cmd/server/main.go

api-test: ## Тесты API
	cd api-gateway && go test ./... -v

# ============================================
# Web (React)
# ============================================

web-init: ## Инициализировать React проект
	cd web && npm init vite@latest . -- --template react-ts

web-dev: ## Запустить React в dev режиме
	cd web && npm run dev

web-build: ## Собрать фронтенд
	cd web && npm run build

# ============================================
# ETL (Python)
# ============================================

etl-init: ## Инициализировать Python виртуальное окружение
	cd etl-service && python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt

etl-dev: ## Запустить ETL workers
	cd etl-service && source .venv/bin/activate && python -m src.scheduler.tasks

# ============================================
# Database
# ============================================

migrate: ## Применить миграции
	@echo "$(YELLOW)Применяю миграции...$(NC)"
	@for f in migrations/*.sql; do \
		echo "  → $$f"; \
		docker compose exec -T postgres psql -U sportdata_admin -d sportdata -f /docker-entrypoint-initdb.d/$$(basename $$f); \
	done
	@echo "$(GREEN)✅ Миграции применены$(NC)"

seed: ## Загрузить тестовые данные
	@echo "$(YELLOW)Загружаю тестовые данные...$(NC)"
	cd api-gateway && go run cmd/seed/main.go

# ============================================
# Утилиты
# ============================================

status: ## Статус сервисов
	docker compose ps

clean: ## Очистить всё (ОПАСНО — удалит данные!)
	docker compose down -v
	@echo "$(RED)🗑  Всё очищено включая данные$(NC)"
