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
	"golang.org/x/crypto/bcrypt"

	"sportdata-api/internal/router"
)

func main() {
	loadEnv(".env")

	log.Println("YourFit Analytics API starting...")

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	db, err := pgxpool.New(ctx, getEnv("DATABASE_URL", ""))
	if err != nil {
		log.Fatalf("PostgreSQL connection failed: %v", err)
	}
	if err := db.Ping(ctx); err != nil {
		log.Fatalf("PostgreSQL ping failed: %v", err)
	}
	log.Println("PostgreSQL connected")

	redisClient := redis.NewClient(&redis.Options{
		Addr:     getEnv("REDIS_URL", "localhost:6379"),
		Password: getEnv("REDIS_PASSWORD", ""),
		DB:       0,
	})
	if err := redisClient.Ping(ctx).Err(); err != nil {
		log.Fatalf("Redis connection failed: %v", err)
	}
	log.Println("Redis connected")

	seedSuperAdmin(db)

	r := router.Setup(db, redisClient)

	port := getEnv("PORT", "8080")
	log.Printf("API listening on :%s", port)
	if err := r.Run(":" + port); err != nil {
		log.Fatalf("Server failed: %v", err)
	}
}

func seedSuperAdmin(db *pgxpool.Pool) {
	email := getEnv("SUPERADMIN_EMAIL", "")
	password := getEnv("SUPERADMIN_PASSWORD", "")

	if email == "" || password == "" {
		log.Println("SUPERADMIN_EMAIL/PASSWORD not set, skipping seed")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	var exists bool
	err := db.QueryRow(ctx, "SELECT EXISTS(SELECT 1 FROM users WHERE email = $1)", email).Scan(&exists)
	if err != nil {
		log.Printf("Superadmin check failed: %v", err)
		return
	}

	if exists {
		log.Println("Superadmin already exists")
		return
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		log.Printf("Password hash failed: %v", err)
		return
	}

	var roleID int
	err = db.QueryRow(ctx, "SELECT id FROM roles WHERE slug = 'super_admin' OR level = 0 ORDER BY level ASC LIMIT 1").Scan(&roleID)
	if err != nil {
		log.Printf("Role super_admin not found: %v", err)
		return
	}

	_, err = db.Exec(ctx, `
		INSERT INTO users (email, password_hash, first_name, last_name, role_id, is_active, is_hidden)
		VALUES ($1, $2, 'Super', 'Admin', $3, true, true)
	`, email, string(hash), roleID)

	if err != nil {
		log.Printf("Superadmin creation failed: %v", err)
		return
	}

	log.Printf("Superadmin created: %s", email)
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
