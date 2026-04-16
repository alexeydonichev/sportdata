package main

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"strings"

	"github.com/jackc/pgx/v5/pgxpool"
)

func oldPadKey(key []byte) []byte {
	if len(key) == 32 {
		return key
	}
	if len(key) < 32 {
		padded := make([]byte, 32)
		copy(padded, key)
		return padded
	}
	return key[:32]
}

func oldDecrypt(encrypted, key string) (string, error) {
	keyBytes := oldPadKey([]byte(key))
	data, err := base64.StdEncoding.DecodeString(encrypted)
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return "", err
	}
	if len(data) < aes.BlockSize {
		return "", errors.New("ciphertext too short")
	}
	iv := data[:aes.BlockSize]
	ct := make([]byte, len(data[aes.BlockSize:]))
	copy(ct, data[aes.BlockSize:])
	stream := cipher.NewCFBDecrypter(block, iv)
	stream.XORKeyStream(ct, ct)
	return strings.TrimSpace(string(ct)), nil
}

func newEncrypt(plaintext, key string) (string, error) {
	h := sha256.Sum256([]byte(key))
	block, err := aes.NewCipher(h[:])
	if err != nil {
		return "", err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", err
	}
	ct := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(ct), nil
}

func main() {
	dbURL := os.Getenv("DATABASE_URL")
	encKey := os.Getenv("ENCRYPTION_KEY")
	if dbURL == "" || encKey == "" {
		log.Fatal("Set DATABASE_URL and ENCRYPTION_KEY")
	}

	ctx := context.Background()
	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		log.Fatal("DB connect: ", err)
	}
	defer pool.Close()

	rows, err := pool.Query(ctx,
		`SELECT id, api_key_encrypted FROM marketplace_credentials WHERE api_key_encrypted IS NOT NULL AND api_key_encrypted != ''`)
	if err != nil {
		log.Fatal("Query: ", err)
	}
	defer rows.Close()

	type rec struct {
		id  int
		enc string
	}
	var recs []rec
	for rows.Next() {
		var r rec
		if err := rows.Scan(&r.id, &r.enc); err != nil {
			log.Fatal("Scan: ", err)
		}
		recs = append(recs, r)
	}

	fmt.Printf("Found %d credentials to migrate\n", len(recs))

	ok, fail := 0, 0
	for _, r := range recs {
		plain, err := oldDecrypt(r.enc, encKey)
		if err != nil {
			log.Printf("SKIP id=%d: old decrypt failed: %v", r.id, err)
			fail++
			continue
		}

		newEnc, err := newEncrypt(plain, encKey)
		if err != nil {
			log.Printf("SKIP id=%d: new encrypt failed: %v", r.id, err)
			fail++
			continue
		}

		_, err = pool.Exec(ctx,
			`UPDATE marketplace_credentials SET api_key_encrypted = $1 WHERE id = $2`,
			newEnc, r.id)
		if err != nil {
			log.Printf("SKIP id=%d: update failed: %v", r.id, err)
			fail++
			continue
		}

		hint := plain[:4] + "..."
		fmt.Printf("  OK id=%d hint=%s\n", r.id, hint)
		ok++
	}

	fmt.Printf("\nDone: %d success, %d failed\n", ok, fail)
}
