package cache

import (
	"crypto/sha256"
	"encoding/hex"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"
)

func CacheMiddleware(rdb *redis.Client, ttl time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		if rdb == nil || c.Request.Method != http.MethodGet {
			c.Next()
			return
		}

		userID, _ := c.Get("user_id")
		raw := c.Request.URL.RequestURI() + "|" + toStr(userID)
		sum := sha256.Sum256([]byte(raw))
		key := "apicache:" + hex.EncodeToString(sum[:16])

		ctx := c.Request.Context()
		data, err := rdb.Get(ctx, key).Bytes()
		if err == nil && len(data) > 0 {
			c.Header("X-Cache", "HIT")
			c.Data(http.StatusOK, "application/json; charset=utf-8", data)
			c.Abort()
			return
		}

		w := &respCapture{ResponseWriter: c.Writer, body: make([]byte, 0, 8192), code: 0}
		c.Writer = w
		c.Next()

		if w.code == http.StatusOK && len(w.body) > 0 {
			rdb.Set(ctx, key, w.body, ttl)
		}
		c.Header("X-Cache", "MISS")
	}
}

func toStr(v interface{}) string {
	if s, ok := v.(string); ok {
		return s
	}
	return "anon"
}

type respCapture struct {
	gin.ResponseWriter
	body []byte
	code int
}

func (w *respCapture) Write(b []byte) (int, error) {
	w.body = append(w.body, b...)
	return w.ResponseWriter.Write(b)
}

func (w *respCapture) WriteHeader(code int) {
	w.code = code
	w.ResponseWriter.WriteHeader(code)
}
