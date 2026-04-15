.PHONY: test test-unit test-integration test-cover test-all

DOCKER_NET = $(shell docker inspect $$(docker ps -qf "name=postgres") -f '{{range $$k,$$v := .NetworkSettings.Networks}}{{$$k}}{{end}}' 2>/dev/null | head -1)
DB_URL = postgres://sportdata_admin:Sp0rtD@ta2024SecurePass!@postgres:5432/sportdata?sslmode=disable
DOCKER_RUN = docker run --rm --network="$(DOCKER_NET)" \
	-v $$(pwd):/app -v go-mod-cache:/go/pkg/mod -v go-build-cache:/root/.cache/go-build \
	-w /app -e DATABASE_URL='$(DB_URL)' -e JWT_SECRET='integration-test-secret' -e CGO_ENABLED=0 \
	golang:1.24-alpine

test-unit:
	@echo "Unit tests..."
	@$(DOCKER_RUN) go test ./internal/handlers/ ./internal/middleware/ -count=1 -v -run '^Test[^I]'

test: test-unit
	@echo "Unit tests passed"

test-integration:
	@echo "Integration tests (network: $(DOCKER_NET))..."
	@$(DOCKER_RUN) go test ./internal/handlers/ -tags=integration -v -count=1 -timeout=60s

test-cover:
	@echo "Running tests with coverage..."
	@$(DOCKER_RUN) go test ./internal/handlers/ ./internal/middleware/ -tags=integration \
	  -coverprofile=coverage.out -covermode=atomic -count=1 -timeout=60s -v
	@echo ""
	@echo "Coverage summary:"
	@$(DOCKER_RUN) go tool cover -func=coverage.out | grep -E '(total|handlers|middleware)'

test-all: test-unit test-integration
	@echo "All tests passed"
