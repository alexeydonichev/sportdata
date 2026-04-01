package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

type visitor struct {
	tokens   float64
	lastSeen time.Time
}

type RateLimiter struct {
	mu       sync.RWMutex
	visitors map[string]*visitor
	rate     float64 // tokens per second
	burst    float64
}

func NewRateLimiter(rps, burst int) *RateLimiter {
	rl := &RateLimiter{
		visitors: make(map[string]*visitor),
		rate:     float64(rps),
		burst:    float64(burst),
	}
	// Очистка старых записей каждые 3 минуты
	go rl.cleanup()
	return rl
}

func (rl *RateLimiter) RateLimit() gin.HandlerFunc {
	return func(c *gin.Context) {
		ip := c.ClientIP()

		rl.mu.Lock()
		v, exists := rl.visitors[ip]
		now := time.Now()

		if !exists {
			rl.visitors[ip] = &visitor{tokens: rl.burst - 1, lastSeen: now}
			rl.mu.Unlock()
			c.Next()
			return
		}

		elapsed := now.Sub(v.lastSeen).Seconds()
		v.tokens += elapsed * rl.rate
		if v.tokens > rl.burst {
			v.tokens = rl.burst
		}
		v.lastSeen = now

		if v.tokens < 1 {
			rl.mu.Unlock()
			c.Header("Retry-After", "1")
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "слишком много запросов, попробуйте позже",
			})
			return
		}

		v.tokens--
		rl.mu.Unlock()
		c.Next()
	}
}

func (rl *RateLimiter) cleanup() {
	for {
		time.Sleep(3 * time.Minute)
		rl.mu.Lock()
		for ip, v := range rl.visitors {
			if time.Since(v.lastSeen) > 5*time.Minute {
				delete(rl.visitors, ip)
			}
		}
		rl.mu.Unlock()
	}
}
