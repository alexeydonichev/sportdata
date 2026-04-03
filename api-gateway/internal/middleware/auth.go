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

// JWTClaims — внутренние claims для генерации токенов Go API
type JWTClaims struct {
	UserID   string `json:"sub"`
	Email    string `json:"email"`
	Role     string `json:"role"`
	Level    int    `json:"role_level"`
	IsHidden bool   `json:"hid,omitempty"`
	Exp      int64  `json:"exp"`
	Iat      int64  `json:"iat"`
}

// rawClaims — для парсинга токенов от обоих источников
type rawClaims struct {
	// Go API format
	Sub   string `json:"sub"`
	UID   string `json:"uid"`
	Email string `json:"email"`
	Role  string `json:"role"`
	// Frontend: role_level, Go: level
	RoleLevel *int  `json:"role_level,omitempty"`
	Level     *int  `json:"level,omitempty"`
	IsHidden  bool  `json:"hid,omitempty"`
	Exp       int64 `json:"exp"`
	Iat       int64 `json:"iat"`
}

func (r *rawClaims) getUserID() string {
	if r.Sub != "" {
		return r.Sub
	}
	return r.UID
}

func (r *rawClaims) getLevel() int {
	if r.RoleLevel != nil {
		return *r.RoleLevel
	}
	if r.Level != nil {
		return *r.Level
	}
	return 99
}

func getJWTSecret() string {
	if s := os.Getenv("JWT_SECRET"); s != "" {
		return s
	}
	return os.Getenv("PASETO_SECRET_KEY")
}

// AuthRequired — проверяет JWT токен (совместим с Frontend и Go API)
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

		userID := claims.getUserID()
		level := claims.getLevel()

		c.Set("user_id", userID)
		c.Set("user_email", claims.Email)
		c.Set("user_role", claims.Role)
		c.Set("user_level", level)
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

		isHidden, _ := hidden.(bool)

		if role != "super_admin" || !isHidden {
			c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}

		c.Next()
	}
}

// GenerateJWT — создаёт токен (формат совместим с Frontend)
func GenerateJWT(claims JWTClaims) (string, error) {
	secret := getJWTSecret()

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

func validateJWT(token string) (*rawClaims, error) {
	secret := getJWTSecret()
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

	var claims rawClaims
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
