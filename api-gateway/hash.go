package main

import (
	"fmt"
	"golang.org/x/crypto/bcrypt"
)

func main() {
	hash, _ := bcrypt.GenerateFromPassword([]byte("YF_Sup3r_Adm1n_2026!"), bcrypt.DefaultCost)
	fmt.Println(string(hash))
}
