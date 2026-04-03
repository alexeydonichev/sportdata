package handlers

import (
	"context"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
)

// ============================================
// ПОЛЬЗОВАТЕЛИ
// ============================================

func (h *Handler) GetUsers(c *gin.Context) {
	ctx := context.Background()

	rows, err := h.db.Query(ctx, `
		SELECT u.id, u.email, u.first_name, u.last_name, r.slug, r.name, r.level, u.is_active, u.last_login_at
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
		var rLevel int
		var isActive bool
		var lastLogin *time.Time
		rows.Scan(&id, &email, &fn, &ln, &rSlug, &rName, &rLevel, &isActive, &lastLogin)

		departments := h.getUserDepartments(ctx, id)
		marketplaces := h.getUserMarketplaceAccess(ctx, id)

		item := gin.H{
			"id": id, "email": email, "first_name": fn, "last_name": ln,
			"role": rSlug, "role_name": rName, "role_level": rLevel,
			"is_active": isActive,
			"departments": departments,
			"marketplace_access": marketplaces,
		}
		if lastLogin != nil {
			item["last_login_at"] = *lastLogin
		}
		result = append(result, item)
	}

	c.JSON(200, gin.H{"data": result, "count": len(result)})
}

func (h *Handler) getUserDepartments(ctx context.Context, userID string) []gin.H {
	rows, err := h.db.Query(ctx, `
		SELECT d.id, d.slug, d.name
		FROM departments d
		JOIN user_departments ud ON ud.department_id = d.id
		WHERE ud.user_id = $1
		ORDER BY d.name
	`, userID)
	if err != nil {
		return []gin.H{}
	}
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		rows.Scan(&id, &slug, &name)
		result = append(result, gin.H{"id": id, "slug": slug, "name": name})
	}
	return result
}

func (h *Handler) getUserMarketplaceAccess(ctx context.Context, userID string) []gin.H {
	rows, err := h.db.Query(ctx, `
		SELECT m.id, m.slug, m.name
		FROM marketplaces m
		JOIN user_marketplace_access uma ON uma.marketplace_id = m.id
		WHERE uma.user_id = $1
		ORDER BY m.name
	`, userID)
	if err != nil {
		return []gin.H{}
	}
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		rows.Scan(&id, &slug, &name)
		result = append(result, gin.H{"id": id, "slug": slug, "name": name})
	}
	return result
}

type CreateUserRequest struct {
	Email             string `json:"email" binding:"required,email"`
	Password          string `json:"password" binding:"required,min=10"`
	FirstName         string `json:"first_name" binding:"required"`
	LastName          string `json:"last_name" binding:"required"`
	RoleSlug          string `json:"role" binding:"required"`
	DepartmentIDs     []int  `json:"department_ids"`
	MarketplaceIDs    []int  `json:"marketplace_ids"`
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

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "ошибка БД"})
		return
	}
	defer tx.Rollback(ctx)

	var userID string
	err = tx.QueryRow(ctx, `
		INSERT INTO users (email, password_hash, first_name, last_name, role_id)
		SELECT $1, $2, $3, $4, r.id
		FROM roles r WHERE r.slug = $5
		RETURNING id
	`, req.Email, string(hash), req.FirstName, req.LastName, req.RoleSlug).Scan(&userID)

	if err != nil {
		c.JSON(http.StatusConflict, gin.H{"error": "пользователь с таким email уже существует"})
		return
	}

	for _, deptID := range req.DepartmentIDs {
		tx.Exec(ctx, `
			INSERT INTO user_departments (user_id, department_id) VALUES ($1, $2)
			ON CONFLICT DO NOTHING
		`, userID, deptID)
	}

	for _, mpID := range req.MarketplaceIDs {
		tx.Exec(ctx, `
			INSERT INTO user_marketplace_access (user_id, marketplace_id) VALUES ($1, $2)
			ON CONFLICT DO NOTHING
		`, userID, mpID)
	}

	tx.Commit(ctx)

	callerID, _ := c.Get("user_id")
	h.db.Exec(ctx, `
		INSERT INTO audit_log (user_id, action, entity_type, entity_id, ip_address)
		VALUES ($1, 'create_user', 'user', $2, $3)
	`, callerID, userID, c.ClientIP())

	c.JSON(http.StatusCreated, gin.H{"id": userID, "email": req.Email, "role": req.RoleSlug})
}

type UpdateUserRequest struct {
	FirstName         *string `json:"first_name"`
	LastName          *string `json:"last_name"`
	RoleSlug          *string `json:"role"`
	IsActive          *bool   `json:"is_active"`
	DepartmentIDs     []int   `json:"department_ids"`
	MarketplaceIDs    []int   `json:"marketplace_ids"`
}

func (h *Handler) UpdateUser(c *gin.Context) {
	userID := c.Param("id")
	var req UpdateUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "неверный формат"})
		return
	}

	ctx := context.Background()

	var targetRoleSlug string
	err := h.db.QueryRow(ctx, `
		SELECT r.slug FROM users u
		JOIN roles r ON r.id = u.role_id
		WHERE u.id = $1
	`, userID).Scan(&targetRoleSlug)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "пользователь не найден"})
		return
	}

	if targetRoleSlug == "super_admin" {
		c.JSON(http.StatusForbidden, gin.H{"error": "нельзя изменить системного пользователя"})
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "ошибка БД"})
		return
	}
	defer tx.Rollback(ctx)

	if req.FirstName != nil {
		tx.Exec(ctx, "UPDATE users SET first_name = $1 WHERE id = $2", *req.FirstName, userID)
	}
	if req.LastName != nil {
		tx.Exec(ctx, "UPDATE users SET last_name = $1 WHERE id = $2", *req.LastName, userID)
	}
	if req.IsActive != nil {
		tx.Exec(ctx, "UPDATE users SET is_active = $1 WHERE id = $2", *req.IsActive, userID)
	}
	if req.RoleSlug != nil && *req.RoleSlug != "super_admin" && *req.RoleSlug != "owner" {
		tx.Exec(ctx, `
			UPDATE users SET role_id = (SELECT id FROM roles WHERE slug = $1) WHERE id = $2
		`, *req.RoleSlug, userID)
	}

	if req.DepartmentIDs != nil {
		tx.Exec(ctx, "DELETE FROM user_departments WHERE user_id = $1", userID)
		for _, deptID := range req.DepartmentIDs {
			tx.Exec(ctx, `
				INSERT INTO user_departments (user_id, department_id) VALUES ($1, $2)
				ON CONFLICT DO NOTHING
			`, userID, deptID)
		}
	}

	if req.MarketplaceIDs != nil {
		tx.Exec(ctx, "DELETE FROM user_marketplace_access WHERE user_id = $1", userID)
		for _, mpID := range req.MarketplaceIDs {
			tx.Exec(ctx, `
				INSERT INTO user_marketplace_access (user_id, marketplace_id) VALUES ($1, $2)
				ON CONFLICT DO NOTHING
			`, userID, mpID)
		}
	}

	tx.Commit(ctx)

	callerID, _ := c.Get("user_id")
	h.db.Exec(ctx, `
		INSERT INTO audit_log (user_id, action, entity_type, entity_id, ip_address)
		VALUES ($1, 'update_user', 'user', $2, $3)
	`, callerID, userID, c.ClientIP())

	c.JSON(http.StatusOK, gin.H{"status": "updated"})
}

func (h *Handler) DeleteUser(c *gin.Context) {
	userID := c.Param("id")
	ctx := context.Background()

	var roleSlug string
	err := h.db.QueryRow(ctx, `
		SELECT r.slug FROM users u
		JOIN roles r ON r.id = u.role_id
		WHERE u.id = $1
	`, userID).Scan(&roleSlug)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "пользователь не найден"})
		return
	}

	if roleSlug == "super_admin" || roleSlug == "owner" {
		c.JSON(http.StatusForbidden, gin.H{"error": "нельзя удалить этого пользователя"})
		return
	}

	h.db.Exec(ctx, "DELETE FROM users WHERE id = $1", userID)

	callerID, _ := c.Get("user_id")
	h.db.Exec(ctx, `
		INSERT INTO audit_log (user_id, action, entity_type, entity_id, ip_address)
		VALUES ($1, 'delete_user', 'user', $2, $3)
	`, callerID, userID, c.ClientIP())

	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

// ============================================
// СПРАВОЧНИКИ
// ============================================

func (h *Handler) GetRoles(c *gin.Context) {
	ctx := context.Background()
	rows, _ := h.db.Query(ctx, `
		SELECT id, slug, name, level FROM roles
		WHERE is_hidden = false
		ORDER BY level
	`)
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id, level int
		var slug, name string
		rows.Scan(&id, &slug, &name, &level)
		result = append(result, gin.H{"id": id, "slug": slug, "name": name, "level": level})
	}
	c.JSON(200, gin.H{"data": result})
}

func (h *Handler) GetDepartments(c *gin.Context) {
	ctx := context.Background()
	rows, _ := h.db.Query(ctx, `
		SELECT id, slug, name FROM departments ORDER BY name
	`)
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		rows.Scan(&id, &slug, &name)
		result = append(result, gin.H{"id": id, "slug": slug, "name": name})
	}
	c.JSON(200, gin.H{"data": result})
}

// ============================================
// СИСТЕМНОЕ
// ============================================

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
