package handlers

import (
	"crypto/rand"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"

	"sportdata/api-gateway/internal/middleware"
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

	token, err := middleware.GenerateToken(middleware.Claims{
		UserID:   userID,
		Email:    email,
		Role:     roleSlug,
		Level:    roleLevel,
		Hidden: isHidden,
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

	err := h.db.QueryRow(ctx, `
		SELECT u.email, u.first_name, u.last_name, r.slug, r.level
		FROM users u
		JOIN roles r ON r.id = u.role_id
		WHERE u.id = $1
	`, userID).Scan(&email, &firstName, &lastName, &roleSlug, &roleLevel)

	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "пользователь не найден"})
		return
	}

	c.JSON(200, gin.H{
		"id":         userID,
		"email":      email,
		"first_name": firstName,
		"last_name":  lastName,
		"role":       roleSlug,
	})
}

// ==================== Register ====================

func (h *Handler) Register(c *gin.Context) {
	var body struct {
		Token    string `json:"token" binding:"required"`
		Password string `json:"password" binding:"required"`
		Name     string `json:"name" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Заполните все поля"})
		return
	}
	if len(body.Password) < 8 {
		c.JSON(400, gin.H{"error": "Пароль минимум 8 символов"})
		return
	}

	ctx := c.Request.Context()

	// Find valid invite
	var inviteID int
	var email, roleName string
	var roleLevel int
	var createdBy *int
	err := h.db.QueryRow(ctx, `
		SELECT i.id, i.email, i.role_level, i.created_by, r.slug
		FROM invites i
		JOIN roles r ON r.level = i.role_level
		WHERE i.token = $1 AND i.used_at IS NULL AND i.expires_at > NOW()
	`, body.Token).Scan(&inviteID, &email, &roleLevel, &createdBy, &roleName)
	if err != nil {
		c.JSON(400, gin.H{"error": "Приглашение не найдено или истекло"})
		return
	}

	// Check existing
	var exists int
	h.db.QueryRow(ctx, `SELECT 1 FROM users WHERE email=$1`, email).Scan(&exists)
	if exists == 1 {
		c.JSON(409, gin.H{"error": "Пользователь с таким email уже существует"})
		return
	}

	// Hash password
	hash, err := bcrypt.GenerateFromPassword([]byte(body.Password), 12)
	if err != nil {
		c.JSON(500, gin.H{"error": "Internal server error"})
		return
	}

	// Create user
	var userID int
	err = h.db.QueryRow(ctx, `
		INSERT INTO users (email, password_hash, name, role, role_level, is_active, invited_by)
		VALUES ($1, $2, $3, $4, $5, true, $6)
		RETURNING id
	`, email, string(hash), strings.TrimSpace(body.Name), roleName, roleLevel, createdBy).Scan(&userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Ошибка создания пользователя"})
		return
	}

	// Copy scopes
	rows, _ := h.db.Query(ctx, `SELECT scope_type, scope_value FROM invite_scopes WHERE invite_id=$1`, inviteID)
	defer rows.Close()
	for rows.Next() {
		var st, sv string
		rows.Scan(&st, &sv)
		h.db.Exec(ctx, `INSERT INTO user_scopes (user_id, scope_type, scope_value) VALUES ($1,$2,$3)`, userID, st, sv)
	}

	// Mark used
	h.db.Exec(ctx, `UPDATE invites SET used_at=NOW() WHERE id=$1`, inviteID)

	// Get scopes for JWT
	type scope struct {
		Type  string `json:"scope_type"`
		Value string `json:"scope_value"`
	}
	var scopes []scope
	scopeRows, _ := h.db.Query(ctx, `SELECT scope_type, scope_value FROM user_scopes WHERE user_id=$1`, userID)
	defer scopeRows.Close()
	for scopeRows.Next() {
		var s scope
		scopeRows.Scan(&s.Type, &s.Value)
		scopes = append(scopes, s)
	}

	// Build JWT
	tokenStr, _ := middleware.GenerateToken(middleware.Claims{
		UserID: fmt.Sprintf("%d", userID),
		Email:  email,
		Role:   roleName,
		Level:  roleLevel,
	})

	// Audit
	h.db.Exec(ctx, `INSERT INTO audit_log (user_id, action, details, ip_address) VALUES ($1,'user.registered',$2,$3)`,
		userID, fmt.Sprintf(`{"invite_id":%d}`, inviteID), c.ClientIP())

	nameParts := strings.SplitN(strings.TrimSpace(body.Name), " ", 2)
	firstName := nameParts[0]
	lastName := ""
	if len(nameParts) > 1 {
		lastName = nameParts[1]
	}

	c.JSON(200, gin.H{
		"token": tokenStr,
		"user": gin.H{
			"id":         fmt.Sprintf("%d", userID),
			"email":      email,
			"first_name": firstName,
			"last_name":  lastName,
			"role":       roleName,
			"role_level": roleLevel,
		},
	})
}

// ==================== ChangePassword ====================

func (h *Handler) ChangePassword(c *gin.Context) {
	userID, _ := c.Get("user_id")

	var body struct {
		CurrentPassword string `json:"current_password" binding:"required"`
		NewPassword     string `json:"new_password" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Оба поля обязательны"})
		return
	}

	if len(body.NewPassword) < 10 || len(body.NewPassword) > 128 {
		c.JSON(400, gin.H{"error": "Пароль от 10 до 128 символов"})
		return
	}
	if body.CurrentPassword == body.NewPassword {
		c.JSON(400, gin.H{"error": "Новый пароль должен отличаться от текущего"})
		return
	}

	ctx := c.Request.Context()
	var currentHash string
	err := h.db.QueryRow(ctx, `SELECT password_hash FROM users WHERE id=$1`, userID).Scan(&currentHash)
	if err != nil {
		c.JSON(404, gin.H{"error": "Пользователь не найден"})
		return
	}

	if err := bcrypt.CompareHashAndPassword([]byte(currentHash), []byte(body.CurrentPassword)); err != nil {
		c.JSON(403, gin.H{"error": "Неверный текущий пароль"})
		return
	}

	newHash, _ := bcrypt.GenerateFromPassword([]byte(body.NewPassword), 12)
	h.db.Exec(ctx, `UPDATE users SET password_hash=$1, updated_at=NOW() WHERE id=$2`, string(newHash), userID)

	h.db.Exec(ctx, `INSERT INTO audit_log (user_id, action, details, ip_address) VALUES ($1,'password_change','{}', $2)`,
		userID, c.ClientIP())

	c.JSON(200, gin.H{"success": true})
}

// ==================== UploadAvatar ====================

func (h *Handler) UploadAvatar(c *gin.Context) {
	userID, _ := c.Get("user_id")

	file, err := c.FormFile("avatar")
	if err != nil {
		c.JSON(400, gin.H{"error": "No file provided"})
		return
	}

	if file.Size > 2*1024*1024 {
		c.JSON(400, gin.H{"error": "Максимум 2MB"})
		return
	}

	ct := file.Header.Get("Content-Type")
	extMap := map[string]string{
		"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif",
	}
	ext, ok := extMap[ct]
	if !ok {
		c.JSON(400, gin.H{"error": "Допустимы: JPEG, PNG, WebP, GIF"})
		return
	}

	src, err := file.Open()
	if err != nil {
		c.JSON(500, gin.H{"error": "Internal server error"})
		return
	}
	defer src.Close()

	buf := make([]byte, file.Size)
	src.Read(buf)

	// Random filename
	rnd := make([]byte, 16)
	rand.Read(rnd)
	filename := fmt.Sprintf("%x.%s", rnd, ext)

	avatarsDir := "public/avatars"
	os.MkdirAll(avatarsDir, 0755)
	if err := os.WriteFile(filepath.Join(avatarsDir, filename), buf, 0644); err != nil {
		c.JSON(500, gin.H{"error": "Ошибка сохранения"})
		return
	}

	avatarURL := "/avatars/" + filename
	h.db.Exec(c.Request.Context(), `UPDATE users SET avatar_url=$1, updated_at=NOW() WHERE id=$2`, avatarURL, userID)

	c.JSON(200, gin.H{"avatar_url": avatarURL})
}
