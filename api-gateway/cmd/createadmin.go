package main

import (
	"context"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
)

func main() {
	hash, err := bcrypt.GenerateFromPassword([]byte("YF_Sup3r_Adm1n_2026!"), bcrypt.DefaultCost)
	if err != nil {
		log.Fatal(err)
	}

	ctx := context.Background()
	conn, err := pgx.Connect(ctx, "postgres://sportdata_admin:SportData_S3cure_2025!@localhost:5432/sportdata?sslmode=disable")
	if err != nil {
		log.Fatal(err)
	}
	defer conn.Close(ctx)

	_, err = conn.Exec(ctx, `
		INSERT INTO users (email, password_hash, first_name, last_name, role_id, is_hidden)
		VALUES ('admin@yourfit.ru', $1, 'Super', 'Admin', 1, true)
		ON CONFLICT (email) DO UPDATE SET password_hash = $1
	`, string(hash))
	if err != nil {
		log.Fatal(err)
	}

	fmt.Println("✅ Супер-админ создан: admin@yourfit.ru / YF_Sup3r_Adm1n_2026!")
}
