package main

import (
	"context"
	"fmt"
	"os"
	"sportdata-etl/internal/crypto"

	"github.com/jackc/pgx/v5"
)

func main() {
	apiKey := os.Args[1]
	encKey := os.Args[2]
	dbURL := os.Args[3]

	encrypted, err := crypto.Encrypt(apiKey, encKey)
	if err != nil {
		fmt.Printf("Encrypt error: %v\n", err)
		os.Exit(1)
	}

	decrypted, err := crypto.Decrypt(encrypted, encKey)
	if err != nil {
		fmt.Printf("Decrypt verify error: %v\n", err)
		os.Exit(1)
	}
	if decrypted != apiKey {
		fmt.Printf("MISMATCH!\n")
		os.Exit(1)
	}
	fmt.Println("Encrypt/Decrypt verification: OK")

	hint := crypto.Hint(apiKey)

	conn, err := pgx.Connect(context.Background(), dbURL)
	if err != nil {
		fmt.Printf("DB error: %v\n", err)
		os.Exit(1)
	}
	defer conn.Close(context.Background())

	tag, err := conn.Exec(context.Background(),
		"UPDATE marketplace_credentials SET api_key_encrypted=$1, api_key_hint=$2, updated_at=NOW() WHERE id=2",
		encrypted, hint)
	if err != nil {
		fmt.Printf("Update error: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Rows affected: %d\n", tag.RowsAffected())
	fmt.Printf("Hint: %s\n", hint)
	fmt.Printf("Encrypted length: %d\n", len(encrypted))
	fmt.Println("DONE")
}
