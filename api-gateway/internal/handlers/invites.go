package handlers

import (
	"fmt"
	"time"

	"crypto/rand"
	"encoding/hex"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetInvites(c *gin.Context) {
	userID := c.GetString("user_id")
	ctx := c.Request.Context()

	rows, err := h.db.Query(ctx, `
		SELECT i.id, i.email, i.token, i.role_level, r.slug as role_name,
		       i.expires_at, i.used_at, i.created_at,
		       u.first_name || ' ' || u.last_name as created_by_name
		FROM invites i
		JOIN roles r ON r.level = i.role_level
		LEFT JOIN users u ON u.id = i.created_by
		WHERE i.created_by = $1
		ORDER BY i.created_at DESC
		LIMIT 100
	`, userID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Internal server error"})
		return
	}
	defer rows.Close()

	var invites []gin.H
	for rows.Next() {
		var id int
		var email, token, roleName string
		var roleLevel int
		var expiresAt, createdAt time.Time
		var usedAt *time.Time
		var createdByName *string

		rows.Scan(&id, &email, &token, &roleLevel, &roleName, &expiresAt, &usedAt, &createdAt, &createdByName)

		inv := gin.H{
			"id":         id,
			"email":      email,
			"token":      token,
			"role_level": roleLevel,
			"role_name":  roleName,
			"expires_at": expiresAt,
			"used_at":    usedAt,
			"created_at": createdAt,
		}
		if createdByName != nil {
			inv["created_by_name"] = *createdByName
		}
		invites = append(invites, inv)
	}

	if invites == nil {
		invites = []gin.H{}
	}
	c.JSON(200, gin.H{"invites": invites})
}

func (h *Handler) CreateInvite(c *gin.Context) {
	userID := c.GetString("user_id")
	actorLevel := c.GetInt("role_level")
	ctx := c.Request.Context()

	var body struct {
		Email     string `json:"email" binding:"required,email"`
		RoleLevel int    `json:"role_level" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(400, gin.H{"error": "Укажите email и role_level"})
		return
	}

	// Нельзя приглашать выше своего уровня (меньше = выше)
	if body.RoleLevel < actorLevel {
		c.JSON(403, gin.H{"error": "Нельзя приглашать с уровнем выше вашего"})
		return
	}

	tokenBytes := make([]byte, 32)
	rand.Read(tokenBytes)
	invToken := hex.EncodeToString(tokenBytes)

	expiresAt := time.Now().Add(72 * time.Hour)

	var inviteID int
	err := h.db.QueryRow(ctx, `
		INSERT INTO invites (email, token, role_level, created_by, expires_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id
	`, body.Email, invToken, body.RoleLevel, userID, expiresAt).Scan(&inviteID)
	if err != nil {
		c.JSON(500, gin.H{"error": fmt.Sprintf("Ошибка создания приглашения: %v", err)})
		return
	}

	c.JSON(201, gin.H{
		"id":         inviteID,
		"email":      body.Email,
		"token":      invToken,
		"role_level": body.RoleLevel,
		"expires_at": expiresAt,
	})
}
