package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

func (h *Handler) GetUsers(c *gin.Context) {
	ctx := context.Background()

	rows, err := h.db.Query(ctx, `
		SELECT u.id, u.email, u.first_name, u.last_name, r.slug, r.name, u.is_active, u.last_login_at
		FROM users u
		JOIN roles r ON r.id = u.role_id
		WHERE u.is_hidden = false
		ORDER BY r.level, u.last_name
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": "ошибка БД"})
		return
	}
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id, email, fn, ln, rSlug, rName string
		var isActive bool
		var lastLogin *time.Time
		rows.Scan(&id, &email, &fn, &ln, &rSlug, &rName, &isActive, &lastLogin)
		item := gin.H{
			"id": id, "email": email, "first_name": fn, "last_name": ln,
			"role": rSlug, "role_name": rName, "is_active": isActive,
		}
		if lastLogin != nil {
			item["last_login_at"] = *lastLogin
		}
		result = append(result, item)
	}

	c.JSON(200, gin.H{"data": result, "count": len(result)})
}

type CreateUserRequest struct {
	Email     string `json:"email" binding:"required,email"`
	Password  string `json:"password" binding:"required,min=10"`
	FirstName string `json:"first_name" binding:"required"`
	LastName  string `json:"last_name" binding:"required"`
	RoleSlug  string `json:"role" binding:"required"`
}

func (h *Handler) CreateUser(c *gin.Context) {
	var req CreateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный формат"})
		return
	}

	if req.RoleSlug == "super_admin" || req.RoleSlug == "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "нельзя создать пользователя с этой ролью"})
		return
	}

	ctx := context.Background()
	hash, _ := bcrypt.GenerateFromPassword([]byte(req.Password), bcrypt.DefaultCost)

	var userID string
	err := h.db.QueryRow(ctx, `
		INSERT INTO users (email, password_hash, first_name, last_name, role_id)
		SELECT $1, $2, $3, $4, r.id
		FROM roles r WHERE r.slug = $5
		RETURNING id
	`, req.Email, string(hash), req.FirstName, req.LastName, req.RoleSlug).Scan(&userID)

	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "пользователь с таким email уже существует"})
		return
	}

	callerID, _ := c.Get("user_id")
	h.db.Exec(ctx, `
		INSERT INTO audit_log (user_id, action, entity_type, entity_id, ip_address)
		VALUES ($1, 'create_user', 'user', $2, $3)
	`, callerID, userID, c.ClientIP())

	c.JSON(http.StatusCreated, gin.H{"id": userID, "email": req.Email, "role": req.RoleSlug})
}

func (h *Handler) GetAllUsersIncludingHidden(c *gin.Context) {
	ctx := context.Background()
	rows, _ := h.db.Query(ctx, `
		SELECT u.id, u.email, u.first_name, u.last_name, r.slug, u.is_hidden, u.is_active, u.last_login_at
		FROM users u
		JOIN roles r ON r.id = u.role_id
		ORDER BY r.level, u.last_name
	`)
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id, email, fn, ln, rSlug string
		var isHidden, isActive bool
		var lastLogin *time.Time
		rows.Scan(&id, &email, &fn, &ln, &rSlug, &isHidden, &isActive, &lastLogin)
		item := gin.H{
			"id": id, "email": email, "first_name": fn, "last_name": ln,
			"role": rSlug, "is_hidden": isHidden, "is_active": isActive,
		}
		if lastLogin != nil {
			item["last_login_at"] = *lastLogin
		}
		result = append(result, item)
	}
	c.JSON(200, gin.H{"data": result, "count": len(result)})
}

func (h *Handler) GetAuditLog(c *gin.Context) {
	ctx := context.Background()
	rows, _ := h.db.Query(ctx, `
		SELECT a.id, u.email, a.action, a.entity_type, a.entity_id, a.ip_address::text, a.created_at
		FROM audit_log a
		LEFT JOIN users u ON u.id = a.user_id
		ORDER BY a.created_at DESC
		LIMIT 100
	`)
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id int64
		var email, action, entityType, entityID, ipAddr *string
		var createdAt time.Time
		rows.Scan(&id, &email, &action, &entityType, &entityID, &ipAddr, &createdAt)
		item := gin.H{"id": id, "created_at": createdAt}
		if email != nil {
			item["user_email"] = *email
		}
		if action != nil {
			item["action"] = *action
		}
		if entityType != nil {
			item["entity_type"] = *entityType
		}
		if entityID != nil {
			item["entity_id"] = *entityID
		}
		if ipAddr != nil {
			item["ip_address"] = *ipAddr
		}
		result = append(result, item)
	}
	c.JSON(200, gin.H{"data": result, "count": len(result)})
}

func (h *Handler) GetSystemInfo(c *gin.Context) {
	ctx := context.Background()

	var dbSize string
	h.db.QueryRow(ctx, "SELECT pg_size_pretty(pg_database_size(current_database()))").Scan(&dbSize)

	var tableCount int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public'").Scan(&tableCount)

	var userCount int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&userCount)

	var productCount int
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM products").Scan(&productCount)

	var salesCount int64
	h.db.QueryRow(ctx, "SELECT COUNT(*) FROM sales").Scan(&salesCount)

	c.JSON(200, gin.H{
		"db_size":       dbSize,
		"tables":        tableCount,
		"users":         userCount,
		"products":      productCount,
		"sales_records": salesCount,
		"time":          time.Now(),
	})
}

