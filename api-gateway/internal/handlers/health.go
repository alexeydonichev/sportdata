package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) Health(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 3*time.Second)
	defer cancel()

	dbOK := h.db.Ping(ctx) == nil
	redisOK := h.redis.Ping(ctx).Err() == nil

	status := "healthy"
	code := http.StatusOK
	if !dbOK || !redisOK {
		status = "degraded"
		code = http.StatusServiceUnavailable
	}

	c.JSON(code, gin.H{
		"status":   status,
		"service":  "yourfit-analytics",
		"version":  "2.0.0",
		"postgres": dbOK,
		"redis":    redisOK,
		"time":     time.Now().Format(time.RFC3339),
	})
}
