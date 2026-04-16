package handlers

import (
	"context"
	"log"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"sportdata/api-gateway/internal/middleware"
)

func (h *Handler) LoginDebug(c *gin.Context) {
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		log.Printf("DEBUG: bind error: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный формат запроса"})
		return
	}

	log.Printf("DEBUG: trying login for email: %s, password length: %d", req.Email, len(req.Password))

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
		WHERE u.email = $1 AND u.deleted_at IS NULL
	`, req.Email).Scan(&userID, &email, &firstName, &lastName, &passwordHash,
		&isHidden, &isActive, &roleSlug, &roleLevel)

	if err != nil {
		log.Printf("DEBUG: DB error: %v", err)
		time.Sleep(500 * time.Millisecond)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "неверный email или пароль"})
		return
	}

	log.Printf("DEBUG: found user %s, hash: %s", userID, passwordHash[:20]+"...")

	if !isActive {
		log.Printf("DEBUG: user not active")
		c.JSON(http.StatusForbidden, gin.H{"error": "аккаунт деактивирован"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(passwordHash), []byte(req.Password)); err != nil {
		log.Printf("DEBUG: bcrypt error: %v", err)
		time.Sleep(500 * time.Millisecond)
		c.JSON(http.StatusUnauthorized, gin.H{"error": "неверный email или пароль"})
		return
	}

	log.Printf("DEBUG: password OK!")

	token, err := middleware.GenerateToken(middleware.Claims{
		UserID:   userID,
		Email:    email,
		Role:     roleSlug,
		Level:    roleLevel,
		Hidden:   isHidden,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "ошибка генерации токена"})
		return
	}

	h.db.Exec(ctx, "UPDATE users SET last_login_at = NOW() WHERE id = $1", userID)

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
