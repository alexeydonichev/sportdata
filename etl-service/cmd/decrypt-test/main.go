package main

import (
	"fmt"
	"os"
	"sportdata-etl/internal/crypto"
)

func main() {
	if len(os.Args) < 3 {
		fmt.Println("usage: decrypt-test <encrypted> <key>")
		os.Exit(1)
	}
	result, err := crypto.Decrypt(os.Args[1], os.Args[2])
	if err != nil {
		fmt.Printf("ERROR: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("Length: %d\n", len(result))
	fmt.Printf("First 30: [%s]\n", result[:min(30, len(result))])
	fmt.Printf("Last 20: [%s]\n", result[max(0, len(result)-20):])
	for i, b := range []byte(result) {
		if b < 32 || b > 126 {
			fmt.Printf("BAD BYTE at %d: 0x%02x\n", i, b)
		}
	}
	fmt.Println("DONE")
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}
