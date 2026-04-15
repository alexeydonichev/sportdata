package middleware

import (
	"github.com/gin-gonic/gin"
)

// SecurityHeaders — дополнительные заголовки (основные ставит Nginx)
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// CSP — только Go знает какие ресурсы нужны приложению
		c.Header("Content-Security-Policy", "default-src 'self'")

		// Убираем server header (Gin)
		c.Header("Server", "")

		c.Next()
	}
}
