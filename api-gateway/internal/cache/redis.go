package cache

import (
	"context"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
)

var Ctx = context.Background()

func NewRedis() *redis.Client {

	addr := os.Getenv("REDIS_ADDR")
	if addr == "" {
		addr = "sportdata-redis:6379"
	}

	pass := os.Getenv("REDIS_PASSWORD")

	rdb := redis.NewClient(&redis.Options{
		Addr:     addr,
		Password: pass,
		DB:       0,
		PoolSize: 20,
	})

	return rdb
}

func Get(rdb *redis.Client, key string) ([]byte, error) {
	return rdb.Get(Ctx, key).Bytes()
}

func Set(rdb *redis.Client, key string, value []byte, ttl time.Duration) error {
	return rdb.Set(Ctx, key, value, ttl).Err()
}
