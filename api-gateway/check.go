package main

import (
	"fmt"
	"golang.org/x/crypto/bcrypt"
)

func main() {
	hash := "$2a$10$cxAmV9Ojkx7CMz97Q.JOAe5VF3pE2aQcDvqfWwCidxwxXjaKUk.PW"
	err := bcrypt.CompareHashAndPassword([]byte(hash), []byte("admin123"))
	fmt.Println(err)
}
