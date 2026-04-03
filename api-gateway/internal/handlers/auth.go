package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"sportdata-api/internal/middleware"
)

type LoginRequest struct {
	Email    string `json:"email" binding:"required,email"`
	Password string `json:"password" binding:"required,min=8"`
}

func (h *Handler) Login(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный формат запроса"})
		return
	}

	ctx := context.Background()

	var userID, email, firstName, lastName, passwordHash string
	var roleSlug string
	var roleLevel int
	var isHidden, isActive bool

	err := h.db.QueryRow(ctx, `
		SELECT u.id, u.email, u.first_name, u.last_name, u.password_hash,
		       u.is_hidden, u.is_active, r.slug, r.level
		FROM users u
		JOIN roles r ON r.id = u.role_id
		WHERE u.email = $1
	`, req.Email).Scan(&userID, &email, &firstName, &lastName, &passwordHash,
		&isHidden, &isActive, &roleSlug, &roleLevel)

	if err != nil {
		time.Sleep(500 * time.Millisecond)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "неверный email или пароль"})
		return
	}

	if !isActive {
		c.JSON(http.StatusForbidden, gin.H{"error": "аккаунт деактивирован"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		time.Sleep(500 * time.Millisecond)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "неверный email или пароль"})
		return
	}

	token, err := middleware.GenerateJWT(middleware.JWTClaims{
		UserID:   userID,
		Email:    email,
		Role:     roleSlug,
		Level:    roleLevel,
		IsHidden: isHidden,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка генерации токена"})
		return
	}

	h.db.Exec(ctx, "UPDATE users SET last_login_at = NOW() WHERE id = $1", userID)
	h.db.Exec(ctx, `
		INSERT INTO audit_log (user_id, action, details, ip_address)
		VALUES ($1, 'login', '{}', $2)
	`, userID, c.ClientIP())

	displayRole := roleSlug
	if isHidden {
		displayRole = "owner"
	}

	c.JSON(http.StatusOK, gin.H{
		"token": token,
		"user": gin.H{
			"id":         userID,
			"email":      email,
			"first_name": firstName,
			"last_name":  lastName,
			"role":       displayRole,
		},
	})
}

func (h *Handler) GetMe(c *gin.Context) {
	userID, _ := c.Get("user_id")
	ctx := context.Background()

	var id, email, firstName, lastName, roleSlug string
	var roleLevel int
	var isActive, isHidden bool
	var lastLoginAt *time.Time

	err := h.db.QueryRow(ctx, `
		SELECT u.id, u.email, u.first_name, u.last_name,
		       u.is_active, u.is_hidden, u.last_login_at,
		       r.slug, r.level
		FROM users u
		JOIN roles r ON r.id = u.role_id
		WHERE u.id = $1
	`, userID).Scan(&id, &email, &firstName, &lastName,
		&isActive, &isHidden, &lastLoginAt,
		&roleSlug, &roleLevel)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "пользователь не найден"})
		return
	}

	displayRole := roleSlug
	if isHidden {
		displayRole = "owner"
	}

	result := gin.H{
		"id":         id,
		"email":      email,
		"first_name": firstName,
		"last_name":  lastName,
		"role":       displayRole,
		"is_active":  isActive,
	}

	if lastLoginAt != nil {
		result["last_login_at"] = lastLoginAt.Format(time.RFC3339)
	}

	c.JSON(http.StatusOK, result)
}

func (h *Handler) GetProfile(c *gin.Context) {
	userID, _ := c.Get("user_id")
	ctx := context.Background()

	var email, firstName, lastName, roleSlug string
	var roleLevel int

	h.db.QueryRow(ctx, `
		SELECT u.email, u.first_name, u.last_name, r.slug, r.level
		FROM users u
		JOIN roles r ON r.id = u.role_id
		WHERE u.id = $1
	`, userID).Scan(&email, &firstName, &lastName, &roleSlug, &roleLevel)

	c.JSON(200, gin.H{
		"id":         userID,
		"email":      email,
		"first_name": firstName,
		"last_name":  lastName,
		"role":       roleSlug,
	})
}
