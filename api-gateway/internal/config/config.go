package config

import (
	"log"
	"os"
)

type Config struct {
	Port        string
	DatabaseURL string
	RedisURL    string
	RedisPass   string
	JWTSecret   string
}

func Load() *Config {
	cfg := &Config{
		Port:        getEnv("API_PORT", "8080"),
		DatabaseURL: requireEnv("DATABASE_URL"),
		RedisURL:    getEnv("REDIS_URL", "localhost:6379"),
		RedisPass:   requireEnv("REDIS_PASSWORD"),
		JWTSecret:   requireEnv("JWT_SECRET"),
	}
	if len(cfg.JWTSecret) < 32 {
		log.Fatal("JWT_SECRET must be at least 32 characters")
	}
	return cfg
}

func getEnv(key, fallback string) string {
	if val := os.Getenv(key); val != "" {
		return val
	}
	return fallback
}

func requireEnv(key string) string {
	val := os.Getenv(key)
	if val == "" {
		log.Fatalf("Required environment variable %s is not set", key)
	}
	return val
}
