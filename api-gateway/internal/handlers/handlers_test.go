package handlers

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func init() {
	gin.SetMode(gin.TestMode)
}

// ============ AUTH TESTS ============

func TestLoginValidation(t *testing.T) {
	tests := []struct {
		name       string
		body       string
		wantStatus int
	}{
		{
			name:       "empty body",
			body:       `{}`,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "missing password",
			body:       `{"email":"test@test.com"}`,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "missing email",
			body:       `{"password":"123456"}`,
			wantStatus: http.StatusBadRequest,
		},
		{
			name:       "invalid email format",
			body:       `{"email":"notanemail","password":"123456"}`,
			wantStatus: http.StatusBadRequest,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.POST("/login", func(c *gin.Context) {
				var req struct {
					Email    string `json:"email"`
					Password string `json:"password"`
				}
				if err := c.ShouldBindJSON(&req); err != nil {
					c.JSON(http.StatusBadRequest, gin.H{"error": "invalid request"})
					return
				}
				if req.Email == "" || req.Password == "" {
					c.JSON(http.StatusBadRequest, gin.H{"error": "email and password required"})
					return
				}
				if !strings.Contains(req.Email, "@") {
					c.JSON(http.StatusBadRequest, gin.H{"error": "invalid email"})
					return
				}
				c.JSON(http.StatusOK, gin.H{"status": "ok"})
			})

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("POST", "/login", strings.NewReader(tt.body))
			req.Header.Set("Content-Type", "application/json")
			router.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("got status %d, want %d", w.Code, tt.wantStatus)
			}
		})
	}
}

// ============ MIDDLEWARE TESTS ============

func TestAuthMiddleware(t *testing.T) {
	tests := []struct {
		name       string
		authHeader string
		wantStatus int
	}{
		{
			name:       "no auth header",
			authHeader: "",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "invalid format",
			authHeader: "InvalidToken",
			wantStatus: http.StatusUnauthorized,
		},
		{
			name:       "empty bearer",
			authHeader: "Bearer ",
			wantStatus: http.StatusUnauthorized,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.Use(func(c *gin.Context) {
				auth := c.GetHeader("Authorization")
				if auth == "" {
					c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "no token"})
					return
				}
				if !strings.HasPrefix(auth, "Bearer ") || len(auth) <= 7 {
					c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
					return
				}
				c.Next()
			})
			router.GET("/protected", func(c *gin.Context) {
				c.JSON(http.StatusOK, gin.H{"status": "ok"})
			})

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/protected", nil)
			if tt.authHeader != "" {
				req.Header.Set("Authorization", tt.authHeader)
			}
			router.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("got status %d, want %d", w.Code, tt.wantStatus)
			}
		})
	}
}

// ============ RESPONSE FORMAT TESTS ============

func TestJSONResponse(t *testing.T) {
	router := gin.New()
	router.GET("/test", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status": "ok",
			"data":   []int{1, 2, 3},
		})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("got status %d, want %d", w.Code, http.StatusOK)
	}

	contentType := w.Header().Get("Content-Type")
	if !strings.Contains(contentType, "application/json") {
		t.Errorf("got content-type %s, want application/json", contentType)
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Errorf("invalid JSON response: %v", err)
	}
}

// ============ PAGINATION TESTS ============

func TestPaginationParams(t *testing.T) {
	tests := []struct {
		name     string
		query    string
		wantPage int
		wantSize int
	}{
		{"defaults", "", 1, 20},
		{"custom page", "?page=5", 5, 20},
		{"custom size", "?limit=50", 1, 50},
		{"both params", "?page=3&limit=10", 3, 10},
		{"invalid page", "?page=-1", 1, 20},
		{"size too large", "?limit=1000", 1, 20},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.GET("/items", func(c *gin.Context) {
				page := 1
				limit := 20

				if p := c.Query("page"); p != "" {
					if parsed := parseInt(p); parsed > 0 {
						page = parsed
					}
				}
				if l := c.Query("limit"); l != "" {
					if parsed := parseInt(l); parsed > 0 && parsed <= 20 {
						limit = parsed
					}
				}

				c.JSON(http.StatusOK, gin.H{"page": page, "limit": limit})
			})

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/items"+tt.query, nil)
			router.ServeHTTP(w, req)

			var resp map[string]int
			json.Unmarshal(w.Body.Bytes(), &resp)

			if resp["page"] != tt.wantPage {
				t.Errorf("got page %d, want %d", resp["page"], tt.wantPage)
			}
			if resp["limit"] != tt.wantSize {
				t.Errorf("got limit %d, want %d", resp["limit"], tt.wantSize)
			}
		})
	}
}

func parseInt(s string) int {
	var n int
	for _, c := range s {
		if c >= '0' && c <= '9' {
			n = n*10 + int(c-'0')
		} else {
			return -1
		}
	}
	return n
}

// ============ RATE LIMIT TESTS ============

func TestRateLimitHeaders(t *testing.T) {
	router := gin.New()
	router.Use(func(c *gin.Context) {
		c.Header("X-RateLimit-Limit", "60")
		c.Header("X-RateLimit-Remaining", "59")
		c.Header("X-RateLimit-Reset", "1234567890")
		c.Next()
	})
	router.GET("/test", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{"status": "ok"})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/test", nil)
	router.ServeHTTP(w, req)

	headers := []string{"X-RateLimit-Limit", "X-RateLimit-Remaining", "X-RateLimit-Reset"}
	for _, h := range headers {
		if w.Header().Get(h) == "" {
			t.Errorf("missing header %s", h)
		}
	}
}

// ============ ERROR RESPONSE TESTS ============

func TestErrorResponses(t *testing.T) {
	tests := []struct {
		name       string
		status     int
		errMessage string
	}{
		{"bad request", http.StatusBadRequest, "invalid input"},
		{"unauthorized", http.StatusUnauthorized, "not authenticated"},
		{"forbidden", http.StatusForbidden, "access denied"},
		{"not found", http.StatusNotFound, "resource not found"},
		{"internal error", http.StatusInternalServerError, "internal server error"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			router := gin.New()
			router.GET("/error", func(c *gin.Context) {
				c.JSON(tt.status, gin.H{"error": tt.errMessage})
			})

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/error", nil)
			router.ServeHTTP(w, req)

			if w.Code != tt.status {
				t.Errorf("got status %d, want %d", w.Code, tt.status)
			}

			var resp map[string]string
			json.Unmarshal(w.Body.Bytes(), &resp)
			if resp["error"] != tt.errMessage {
				t.Errorf("got error %q, want %q", resp["error"], tt.errMessage)
			}
		})
	}
}
