package middleware

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

type JWTClaims struct {
	UserID   string `json:"uid"`
	Email    string `json:"email"`
	Role     string `json:"role"`
	Level    int    `json:"level"`
	IsHidden bool   `json:"hid,omitempty"`
	Exp      int64  `json:"exp"`
	Iat      int64  `json:"iat"`
}

// AuthRequired — проверяет JWT токен
func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		header := c.GetHeader("Authorization")
		if header == "" || !strings.HasPrefix(header, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "токен не предоставлен"})
			return
		}

		token := strings.TrimPrefix(header, "Bearer ")
		claims, err := validateJWT(token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "невалидный токен"})
			return
		}

		if time.Now().Unix() > claims.Exp {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "токен истёк"})
			return
		}

		// Сохраняем claims в контекст
		c.Set("user_id", claims.UserID)
		c.Set("user_email", claims.Email)
		c.Set("user_role", claims.Role)
		c.Set("user_level", claims.Level)
		c.Set("user_hidden", claims.IsHidden)

		c.Next()
	}
}

// RoleRequired — минимальный уровень доступа (0=super_admin, 4=manager)
func RoleRequired(maxLevel int) gin.HandlerFunc {
	return func(c *gin.Context) {
		level, exists := c.Get("user_level")
		if !exists {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "доступ запрещён"})
			return
		}

		userLevel, ok := level.(int)
		if !ok || userLevel > maxLevel {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "недостаточно прав"})
			return
		}

		c.Next()
	}
}

// SuperAdminOnly — только скрытый супер-админ
func SuperAdminOnly() gin.HandlerFunc {
	return func(c *gin.Context) {
		role, _ := c.Get("user_role")
		hidden, _ := c.Get("user_hidden")

		if role != "super_admin" || hidden != true {
			// Возвращаем 404, не 403 — чтобы не выдать существование эндпоинта
			c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}

		c.Next()
	}
}

// GenerateJWT — создаёт токен
func GenerateJWT(claims JWTClaims) (string, error) {
	secret := os.Getenv("JWT_SECRET")

	header := base64URLEncode([]byte(`{"alg":"HS256","typ":"JWT"}`))

	claims.Iat = time.Now().Unix()
	if claims.Exp == 0 {
		claims.Exp = time.Now().Add(8 * time.Hour).Unix()
	}
	payloadBytes, _ := json.Marshal(claims)
	payload := base64URLEncode(payloadBytes)

	sig := signHMAC(header+"."+payload, secret)

	return header + "." + payload + "." + sig, nil
}

func validateJWT(token string) (*JWTClaims, error) {
	secret := os.Getenv("JWT_SECRET")
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, http.ErrAbortHandler
	}

	expectedSig := signHMAC(parts[0]+"."+parts[1], secret)
	if !hmac.Equal([]byte(parts[2]), []byte(expectedSig)) {
		return nil, http.ErrAbortHandler
	}

	payloadBytes, err := base64URLDecode(parts[1])
	if err != nil {
		return nil, err
	}

	var claims JWTClaims
	if err := json.Unmarshal(payloadBytes, &claims); err != nil {
		return nil, err
	}

	return &claims, nil
}

func signHMAC(data, secret string) string {
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(data))
	return base64URLEncode(h.Sum(nil))
}

func base64URLEncode(data []byte) string {
	return strings.TrimRight(base64.URLEncoding.EncodeToString(data), "=")
}

func base64URLDecode(s string) ([]byte, error) {
	switch len(s) % 4 {
	case 2:
		s += "=="
	case 3:
		s += "="
	}
	return base64.URLEncoding.DecodeString(s)
}
