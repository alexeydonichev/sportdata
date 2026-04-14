package crypto

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"encoding/base64"
	"errors"
	"io"
	"strings"
)

func Encrypt(plaintext, key string) (string, error) {
	plaintext = strings.TrimSpace(plaintext)
	keyBytes := padKey([]byte(key))
	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return "", err
	}
	plainBytes := []byte(plaintext)
	ciphertext := make([]byte, aes.BlockSize+len(plainBytes))
	iv := ciphertext[:aes.BlockSize]
	if _, err := io.ReadFull(rand.Reader, iv); err != nil {
		return "", err
	}
	stream := cipher.NewCFBEncrypter(block, iv)
	stream.XORKeyStream(ciphertext[aes.BlockSize:], plainBytes)
	return base64.StdEncoding.EncodeToString(ciphertext), nil
}

func Decrypt(encrypted, key string) (string, error) {
	keyBytes := padKey([]byte(key))
	ciphertext, err := base64.StdEncoding.DecodeString(encrypted)
	if err != nil {
		return "", err
	}
	block, err := aes.NewCipher(keyBytes)
	if err != nil {
		return "", err
	}
	if len(ciphertext) < aes.BlockSize {
		return "", errors.New("ciphertext too short")
	}
	iv := ciphertext[:aes.BlockSize]
	ciphertext = ciphertext[aes.BlockSize:]
	stream := cipher.NewCFBDecrypter(block, iv)
	stream.XORKeyStream(ciphertext, ciphertext)
	return strings.TrimSpace(string(ciphertext)), nil
}

func Hint(apiKey string) string {
	if len(apiKey) <= 8 {
		return "****"
	}
	return apiKey[:4] + "..." + apiKey[len(apiKey)-4:]
}

func padKey(key []byte) []byte {
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
