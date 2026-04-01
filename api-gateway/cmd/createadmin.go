package main

import (
	"context"
	"fmt"
	"log"
	"os"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
)

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://sportdata_admin:SportData_S3cure_2025!@localhost:5432/sportdata?sslmode=disable"
	}

	password := os.Getenv("ADMIN_PASSWORD")
	if password == "" {
		password = "YF_Sup3r_Adm1n_2026!"
	}

	email := os.Getenv("ADMIN_EMAIL")
	if email == "" {
		email = "admin@yourfit.ru"
	}

	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		log.Fatal("bcrypt error:", err)
	}

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		log.Fatal("db connect error:", err)
	}
	defer conn.Close(ctx)

	var dbName string
	if err := conn.QueryRow(ctx, "SELECT current_database()").Scan(&dbName); err != nil {
		log.Fatal("db ping error:", err)
	}
	fmt.Printf("📡 Подключено к БД: %s\n", dbName)

	tag, err := conn.Exec(ctx, `
		INSERT INTO users (email, password_hash, first_name, last_name, role_id, is_hidden)
		VALUES ($1, $2, 'Super', 'Admin', 1, true)
		ON CONFLICT (email) DO UPDATE SET password_hash = $2
	`, email, string(hash))
	if err != nil {
		log.Fatal("insert error:", err)
	}

	fmt.Printf("✅ Супер-админ создан: %s / %s (rows affected: %d)\n", email, password, tag.RowsAffected())
}
