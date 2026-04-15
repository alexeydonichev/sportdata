package middleware

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func init() { gin.SetMode(gin.TestMode) }

func TestGenerateAndParseToken(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret-key-unit")
	defer os.Unsetenv("JWT_SECRET")

	token, err := GenerateToken(Claims{
		UserID: "123", Email: "test@example.com",
		Role: "owner", Level: 1,
	})
	if err != nil {
		t.Fatalf("GenerateToken: %v", err)
	}
	if token == "" {
		t.Fatal("token is empty")
	}

	parsed, err := parseToken(token)
	if err != nil {
		t.Fatalf("parseToken: %v", err)
	}
	if parsed.UserID != "123" {
		t.Errorf("UserID = %q, want 123", parsed.UserID)
	}
	if parsed.Email != "test@example.com" {
		t.Errorf("Email = %q", parsed.Email)
	}
	if parsed.Role != "owner" {
		t.Errorf("Role = %q", parsed.Role)
	}
	if parsed.Exp == 0 {
		t.Error("Exp should be auto-set")
	}
	if parsed.Sub != "123" {
		t.Errorf("Sub should equal UserID, got %q", parsed.Sub)
	}
}

func TestParseTokenInvalid(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret")
	defer os.Unsetenv("JWT_SECRET")

	for _, tok := range []string{"", "not-jwt", "a.b", "a.b.wrongsig"} {
		if _, err := parseToken(tok); err == nil {
			t.Errorf("expected error for token %q", tok)
		}
	}
}

func TestAuthRequired_NoHeader(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret")
	defer os.Unsetenv("JWT_SECRET")

	r := gin.New()
	r.Use(AuthRequired())
	r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/t", nil)
	r.ServeHTTP(w, req)
	if w.Code != 401 {
		t.Errorf("got %d, want 401", w.Code)
	}
}

func TestAuthRequired_InvalidToken(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret")
	defer os.Unsetenv("JWT_SECRET")

	r := gin.New()
	r.Use(AuthRequired())
	r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/t", nil)
	req.Header.Set("Authorization", "Bearer garbage")
	r.ServeHTTP(w, req)
	if w.Code != 401 {
		t.Errorf("got %d, want 401", w.Code)
	}
}

func TestAuthRequired_ExpiredToken(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret")
	defer os.Unsetenv("JWT_SECRET")

	token, _ := GenerateToken(Claims{
		UserID: "1", Email: "x@x.com", Role: "v", Level: 4,
		Exp: time.Now().Add(-1 * time.Hour).Unix(),
	})

	r := gin.New()
	r.Use(AuthRequired())
	r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/t", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)
	if w.Code != 401 {
		t.Errorf("expired: got %d, want 401", w.Code)
	}
}

func TestAuthRequired_ValidToken(t *testing.T) {
	os.Setenv("JWT_SECRET", "test-secret")
	defer os.Unsetenv("JWT_SECRET")

	token, _ := GenerateToken(Claims{
		UserID: "42", Email: "a@b.com", Role: "admin", Level: 1,
	})

	r := gin.New()
	r.Use(AuthRequired())
	r.GET("/t", func(c *gin.Context) {
		uid, _ := c.Get("user_id")
		lvl, _ := c.Get("user_level")
		c.JSON(200, gin.H{"user_id": uid, "level": lvl})
	})

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/t", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	r.ServeHTTP(w, req)

	if w.Code != 200 {
		t.Fatalf("valid token: got %d", w.Code)
	}
	var resp map[string]interface{}
	json.Unmarshal(w.Body.Bytes(), &resp)
	if resp["user_id"] != "42" {
		t.Errorf("user_id = %v", resp["user_id"])
	}
}

func TestRoleRequired(t *testing.T) {
	tests := []struct {
		name       string
		userLevel  int
		maxLevel   int
		wantStatus int
	}{
		{"superadmin→4", 0, 4, 200},
		{"owner→4", 1, 4, 200},
		{"viewer→4", 4, 4, 200},
		{"viewer→2", 4, 2, 403},
		{"viewer→1", 4, 1, 403},
		{"manager→2", 3, 2, 403},
		{"admin→2", 2, 2, 200},
		{"admin→1", 2, 1, 403},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := gin.New()
			r.Use(func(c *gin.Context) {
				c.Set("user_level", tt.userLevel)
				c.Next()
			})
			r.Use(RoleRequired(tt.maxLevel))
			r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/t", nil)
			r.ServeHTTP(w, req)
			if w.Code != tt.wantStatus {
				t.Errorf("got %d, want %d", w.Code, tt.wantStatus)
			}
		})
	}
}

func TestSuperAdminOnly(t *testing.T) {
	tests := []struct {
		name       string
		level      int
		hidden     bool
		wantStatus int
	}{
		{"sa", 0, true, 200},
		{"owner", 1, false, 403},
		{"level0 not hidden", 0, false, 403},
		{"level1 hidden", 1, true, 403},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			r := gin.New()
			r.Use(func(c *gin.Context) {
				c.Set("user_level", tt.level)
				c.Set("user_hidden", tt.hidden)
				c.Next()
			})
			r.Use(SuperAdminOnly())
			r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

			w := httptest.NewRecorder()
			req, _ := http.NewRequest("GET", "/t", nil)
			r.ServeHTTP(w, req)
			if w.Code != tt.wantStatus {
				t.Errorf("got %d, want %d", w.Code, tt.wantStatus)
			}
		})
	}
}

func TestRateLimiter_BurstExceeded(t *testing.T) {
	rl := NewRateLimiter(10, 5)
	r := gin.New()
	r.Use(rl.RateLimit())
	r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

	for i := 0; i < 5; i++ {
		w := httptest.NewRecorder()
		req, _ := http.NewRequest("GET", "/t", nil)
		req.RemoteAddr = "1.2.3.4:1234"
		r.ServeHTTP(w, req)
		if w.Code != 200 {
			t.Errorf("request %d: got %d", i+1, w.Code)
		}
	}

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/t", nil)
	req.RemoteAddr = "1.2.3.4:1234"
	r.ServeHTTP(w, req)
	if w.Code != 429 {
		t.Errorf("burst exceeded: got %d, want 429", w.Code)
	}
}

func TestSecurityHeaders(t *testing.T) {
	r := gin.New()
	r.Use(SecurityHeaders())
	r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/t", nil)
	r.ServeHTTP(w, req)
	if w.Header().Get("Content-Security-Policy") == "" {
		t.Error("missing CSP header")
	}
}

func TestCORS_AllowedOrigin(t *testing.T) {
	os.Setenv("ALLOWED_ORIGINS", "http://localhost:3000,https://app.test.com")
	defer os.Unsetenv("ALLOWED_ORIGINS")

	r := gin.New()
	r.Use(CORS())
	r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("GET", "/t", nil)
	req.Header.Set("Origin", "http://localhost:3000")
	r.ServeHTTP(w, req)
	if w.Header().Get("Access-Control-Allow-Origin") != "http://localhost:3000" {
		t.Error("allowed origin not reflected")
	}

	w2 := httptest.NewRecorder()
	req2, _ := http.NewRequest("GET", "/t", nil)
	req2.Header.Set("Origin", "http://evil.com")
	r.ServeHTTP(w2, req2)
	if w2.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Error("disallowed origin should not be reflected")
	}
}

func TestCORS_Preflight(t *testing.T) {
	os.Setenv("ALLOWED_ORIGINS", "http://localhost:3000")
	defer os.Unsetenv("ALLOWED_ORIGINS")

	r := gin.New()
	r.Use(CORS())
	r.GET("/t", func(c *gin.Context) { c.JSON(200, nil) })

	w := httptest.NewRecorder()
	req, _ := http.NewRequest("OPTIONS", "/t", nil)
	req.Header.Set("Origin", "http://localhost:3000")
	r.ServeHTTP(w, req)
	if w.Code != 204 {
		t.Errorf("OPTIONS: got %d, want 204", w.Code)
	}
}
