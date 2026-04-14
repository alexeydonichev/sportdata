package main

import (
	"context"
	"log"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"sportdata/api-gateway/internal/router"
)

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		dbURL = "postgres://sportdata:sportdata@localhost:5432/sportdata?sslmode=disable"
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	redisURL := os.Getenv("REDIS_URL")
	if redisURL == "" {
		redisURL = "redis://localhost:6379/0"
	}

	ctx := context.Background()

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatalf("Unable to connect to database: %v", err)
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("Database ping failed: %v", err)
	}
	log.Println("Connected to database")

	opts, err := redis.ParseURL(redisURL)
	if err != nil {
		log.Printf("Redis URL parse error: %v — running without Redis", err)
	}
	var redisClient *redis.Client
	if opts != nil {
		redisClient = redis.NewClient(opts)
		if _, err := redisClient.Ping(ctx).Result(); err != nil {
			log.Printf("Redis ping failed: %v — running without Redis", err)
			redisClient = nil
		} else {
			log.Println("Connected to Redis")
		}
	}

	r := router.Setup(pool, redisClient)

	log.Printf("Starting API Gateway on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
