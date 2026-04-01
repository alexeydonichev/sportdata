package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"io"
)

const (
	ivLength  = 12
	tagLength = 16
)

// Encrypt produces base64(iv + ciphertext + tag) — same as Next.js frontend
func Encrypt(plaintext, keyHex string) (string, error) {
	key, err := hex.DecodeString(keyHex)
	if err != nil || len(key) != 32 {
		return "", fmt.Errorf("invalid key: must be 64 hex chars (32 bytes)")
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("new cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("new gcm: %w", err)
	}

	nonce := make([]byte, ivLength)
	if _, err := io.ReadFull(rand.Reader, nonce); err != nil {
		return "", fmt.Errorf("nonce: %w", err)
	}

	// gcm.Seal appends ciphertext+tag after nonce
	sealed := gcm.Seal(nonce, nonce, []byte(plaintext), nil)
	return base64.StdEncoding.EncodeToString(sealed), nil
}

// Decrypt decodes base64(iv + ciphertext + tag) — compatible with Next.js frontend
func Decrypt(encryptedBase64, keyHex string) (string, error) {
	key, err := hex.DecodeString(keyHex)
	if err != nil || len(key) != 32 {
		return "", fmt.Errorf("invalid key: must be 64 hex chars (32 bytes)")
	}

	data, err := base64.StdEncoding.DecodeString(encryptedBase64)
	if err != nil {
		// Try base64 URL encoding as fallback
		data, err = base64.RawStdEncoding.DecodeString(encryptedBase64)
		if err != nil {
			return "", fmt.Errorf("decode base64: %w", err)
		}
	}

	if len(data) < ivLength+tagLength+1 {
		return "", fmt.Errorf("ciphertext too short (%d bytes)", len(data))
	}

	block, err := aes.NewCipher(key)
	if err != nil {
		return "", fmt.Errorf("new cipher: %w", err)
	}

	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return "", fmt.Errorf("new gcm: %w", err)
	}

	nonce := data[:ivLength]
	ciphertext := data[ivLength:]

	plaintext, err := gcm.Open(nil, nonce, ciphertext, nil)
	if err != nil {
		return "", fmt.Errorf("decrypt: %w", err)
	}

	return string(plaintext), nil
}

func Hint(apiKey string) string {
	if len(apiKey) <= 8 {
		return "****"
	}
	return apiKey[:4] + "..." + apiKey[len(apiKey)-4:]
}
