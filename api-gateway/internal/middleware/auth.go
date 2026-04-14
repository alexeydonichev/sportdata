package middleware

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

type Claims struct {
	Sub    string `json:"sub,omitempty"`
	UserID string `json:"user_id"`
	Email  string `json:"email"`
	Role   string `json:"role"`
	Level  int    `json:"level"`
	Hidden bool   `json:"hidden,omitempty"`
	Exp    int64  `json:"exp"`
}

func AuthRequired() gin.HandlerFunc {
	return func(c *gin.Context) {
		auth := c.GetHeader("Authorization")
		if auth == "" || !strings.HasPrefix(auth, "Bearer ") {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Требуется авторизация"})
			return
		}

		token := strings.TrimPrefix(auth, "Bearer ")
		claims, err := parseToken(token)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Невалидный токен"})
			return
		}

		if claims.Exp > 0 && claims.Exp < time.Now().Unix() {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "Токен истёк"})
			return
		}

		c.Set("user_id", claims.UserID)
		c.Set("user_email", claims.Email)
		c.Set("user_role", claims.Role)
		c.Set("user_level", claims.Level)
		c.Set("role_level", claims.Level)
		c.Set("user_hidden", claims.Hidden)
		c.Next()
	}
}

func RoleRequired(maxLevel int) gin.HandlerFunc {
	return func(c *gin.Context) {
		level, exists := c.Get("user_level")
		if !exists {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "Нет информации о роли"})
			return
		}
		userLevel, ok := level.(int)
		if !ok {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "Неверный формат роли"})
			return
		}
		if userLevel > maxLevel {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "Недостаточно прав"})
			return
		}
		c.Next()
	}
}

func SuperAdminOnly() gin.HandlerFunc {
	return func(c *gin.Context) {
		level, _ := c.Get("user_level")
		hidden, _ := c.Get("user_hidden")
		userLevel, _ := level.(int)
		isHidden, _ := hidden.(bool)
		if userLevel != 0 || !isHidden {
			c.AbortWithStatusJSON(http.StatusForbidden, gin.H{"error": "Только для суперадмина"})
			return
		}
		c.Next()
	}
}

func GenerateToken(claims Claims) (string, error) {
	// ✅ ГЛАВНЫЙ ФИКС: устанавливаем exp
	if claims.Exp == 0 {
		hours := 24
		if h := os.Getenv("JWT_EXPIRY_HOURS"); h != "" {
			if parsed, err := strconv.Atoi(h); err == nil {
				hours = parsed
			}
		}
		claims.Exp = time.Now().Add(time.Duration(hours) * time.Hour).Unix()
	}

	// Дублируем UserID в sub для совместимости с jose/jsonwebtoken
	if claims.Sub == "" {
		claims.Sub = claims.UserID
	}

	secret := os.Getenv("JWT_SECRET")
	header := base64url([]byte(`{"alg":"HS256","typ":"JWT"}`))
	claimsJSON, _ := json.Marshal(claims)
	payload := base64url(claimsJSON)
	sig := sign(header+"."+payload, secret)
	return header + "." + payload + "." + sig, nil
}

func parseToken(token string) (*Claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, http.ErrAbortHandler
	}

	secret := os.Getenv("JWT_SECRET")
	expectedSig := sign(parts[0]+"."+parts[1], secret)
	if !hmac.Equal([]byte(parts[2]), []byte(expectedSig)) {
		return nil, http.ErrAbortHandler
	}

	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return nil, err
	}

	var claims Claims
	if err := json.Unmarshal(payload, &claims); err != nil {
		return nil, err
	}

	return &claims, nil
}

func sign(data, secret string) string {
	h := hmac.New(sha256.New, []byte(secret))
	h.Write([]byte(data))
	return base64url(h.Sum(nil))
}

func base64url(data []byte) string {
	return strings.TrimRight(base64.URLEncoding.EncodeToString(data), "=")
}
