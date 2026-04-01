package main

import (
	"bufio"
	"context"
	"log"
	"os"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"sportdata-api/internal/router"
)

func main() {
	loadEnv(".env")

	log.Println("🚀 YourFit Analytics API запускается...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	// PostgreSQL
	db, err := pgxpool.New(ctx, getEnv("DATABASE_URL", ""))
	if err != nil {
		log.Fatalf("❌ PostgreSQL: %v", err)
	}
	if err := db.Ping(ctx); err != nil {
		log.Fatalf("❌ PostgreSQL не отвечает: %v", err)
	}
	log.Println("✅ PostgreSQL подключён")

	// Redis
	redisClient := redis.NewClient(&redis.Options{
		Addr:     getEnv("REDIS_URL", "localhost:6379"),
		Password: getEnv("REDIS_PASSWORD", ""),
		DB:       0,
	})
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Fatalf("❌ Redis: %v", err)
	}
	log.Println("✅ Redis подключён")

	// Router
	r := router.Setup(db, redisClient)

	port := getEnv("PORT", "8080")
	log.Printf("🔒 YourFit Analytics API (production mode) → :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("❌ Сервер: %v", err)
	}
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func loadEnv(path string) {
	f, err := os.Open(path)
	if err != nil {
		return
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		parts := strings.SplitN(line, "=", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			val := strings.TrimSpace(parts[1])
			if os.Getenv(key) == "" {
				os.Setenv(key, val)
			}
		}
	}
}
