package middleware

import (
	"github.com/gin-gonic/gin"
)

// SecurityHeaders — защита от основных атак
func SecurityHeaders() gin.HandlerFunc {
	return func(c *gin.Context) {
		// Запрет iframe (clickjacking)
		c.Header("X-Frame-Options", "DENY")
		// XSS protection
		c.Header("X-Content-Type-Options", "nosniff")
		c.Header("X-XSS-Protection", "1; mode=block")
		// HSTS
		c.Header("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
		// CSP
		c.Header("Content-Security-Policy", "default-src 'self'")
		// Referrer
		c.Header("Referrer-Policy", "strict-origin-when-cross-origin")
		// Убираем server header
		c.Header("Server", "")

		c.Next()
	}
}
