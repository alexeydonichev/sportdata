package crypto

import "testing"

func TestEncryptDecrypt(t *testing.T) {
	plaintext := "hello world"
	key := "mysecretkey12345678901234567890ab"

	encrypted, err := Encrypt(plaintext, key)
	if err != nil {
		t.Fatalf("Encrypt failed: %v", err)
	}

	decrypted, err := Decrypt(encrypted, key)
	if err != nil {
		t.Fatalf("Decrypt failed: %v", err)
	}

	if decrypted != plaintext {
		t.Errorf("got %q, want %q", decrypted, plaintext)
	}
}

func TestHint(t *testing.T) {
	if got := Hint("sk-1234567890abcdef"); got != "sk-1...cdef" {
		t.Errorf("got %q", got)
	}
	if got := Hint("short"); got != "****" {
		t.Errorf("got %q", got)
	}
}
