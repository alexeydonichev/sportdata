package main

import (
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/gin-gonic/gin"
)

func TestLoginValidation(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.POST("/login", func(c *gin.Context) {
		var req struct {
			Email    string `json:"email" binding:"required,email"`
			Password string `json:"password" binding:"required"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(400, gin.H{"error": "Validation failed"})
			return
		}
		c.JSON(200, gin.H{"status": "ok"})
	})

	tests := []struct {
		name       string
		body       string
		wantStatus int
	}{
		{"empty_body", "{}", 400},
		{"missing_password", "{\"email\":\"test@test.com\"}", 400},
		{"missing_email", "{\"password\":\"123456\"}", 400},
		{"invalid_email", "{\"email\":\"notanemail\",\"password\":\"123456\"}", 400},
		{"valid_input", "{\"email\":\"test@test.com\",\"password\":\"123456\"}", 200},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest("POST", "/login", strings.NewReader(tt.body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("got %d, want %d", w.Code, tt.wantStatus)
			}
		})
	}
}

func TestRegisterValidation(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.POST("/register", func(c *gin.Context) {
		var req struct {
			Email    string `json:"email" binding:"required,email"`
			Password string `json:"password" binding:"required,min=6"`
			Name     string `json:"name" binding:"required"`
		}
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(400, gin.H{"error": "Validation failed"})
			return
		}
		c.JSON(200, gin.H{"status": "ok"})
	})

	tests := []struct {
		name       string
		body       string
		wantStatus int
	}{
		{"empty_body", "{}", 400},
		{"missing_name", "{\"email\":\"test@test.com\",\"password\":\"123456\"}", 400},
		{"short_password", "{\"email\":\"test@test.com\",\"password\":\"123\",\"name\":\"Test\"}", 400},
		{"invalid_email", "{\"email\":\"notanemail\",\"password\":\"123456\",\"name\":\"Test\"}", 400},
		{"valid_input", "{\"email\":\"test@test.com\",\"password\":\"123456\",\"name\":\"Test User\"}", 200},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest("POST", "/register", strings.NewReader(tt.body))
			req.Header.Set("Content-Type", "application/json")
			w := httptest.NewRecorder()
			router.ServeHTTP(w, req)

			if w.Code != tt.wantStatus {
				t.Errorf("got %d, want %d", w.Code, tt.wantStatus)
			}
		})
	}
}
