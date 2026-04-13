package handlers

import (
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
)

// Handler содержит зависимости для всех HTTP-хендлеров.
type Handler struct {
	db    *pgxpool.Pool
	redis *redis.Client
}

// New создаёт Handler.
func New(db *pgxpool.Pool, redis *redis.Client) *Handler {
	return &Handler{db: db, redis: redis}
}
