package config

import (
	"bufio"
	"os"
	"strings"
)

type Config struct {
	DatabaseURL    string
	RedisURL       string
	EncryptionKey  string
	ETLSecret      string
	ListenAddr     string
	WorkerInterval string
}

func Load() *Config {
	loadEnv("../.env")
	loadEnv(".env")

	return &Config{
		DatabaseURL:    getEnv("DATABASE_URL", "postgres://sportdata_admin:SportData_S3cure_2025!@postgres:5432/sportdata?sslmode=disable"),
		RedisURL:       getEnv("REDIS_URL", "redis:6379"),
		EncryptionKey:  getEnv("ENCRYPTION_KEY", ""),
		ETLSecret:      getEnv("ETL_SECRET", ""),
		ListenAddr:     getEnv("ETL_LISTEN", ":8081"),
		WorkerInterval: getEnv("SYNC_INTERVAL", "30m"),
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
