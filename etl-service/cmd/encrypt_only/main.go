package main

import (
	"fmt"
	"os"
	"sportdata-etl/internal/crypto"
)

func main() {
	apiKey := os.Args[1]
	encKey := os.Args[2]

	encrypted, err := crypto.Encrypt(apiKey, encKey)
	if err != nil {
		fmt.Printf("Error: %v\n", err)
		os.Exit(1)
	}

	decrypted, err := crypto.Decrypt(encrypted, encKey)
	if err != nil {
		fmt.Printf("Decrypt error: %v\n", err)
		os.Exit(1)
	}
	if decrypted != apiKey {
		os.Exit(1)
	}

	fmt.Println("VERIFY: OK")
	fmt.Printf("ENCRYPTED:%s\n", encrypted)
	fmt.Printf("HINT:%s\n", crypto.Hint(apiKey))
}
