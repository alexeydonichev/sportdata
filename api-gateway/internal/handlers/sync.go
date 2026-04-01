package handlers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"

	"sportdata-api/internal/crypto"
)

func (h *Handler) GetSyncStatus(c *gin.Context) {
	ctx := context.Background()
	rows, err := h.db.Query(ctx, `
		SELECT sj.id, m.slug, m.name, sj.job_type, sj.status,
			sj.started_at, sj.completed_at, sj.records_processed,
			sj.error_message, sj.created_at
		FROM sync_jobs sj
		JOIN marketplaces m ON m.id = sj.marketplace_id
		ORDER BY sj.created_at DESC LIMIT 20
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()
	var result []gin.H
	for rows.Next() {
		var id int64
		var slug, name, jobType, status string
		var startedAt, completedAt *time.Time
		var recordsProcessed int
		var errorMsg *string
		var createdAt time.Time
		rows.Scan(&id, &slug, &name, &jobType, &status, &startedAt, &completedAt, &recordsProcessed, &errorMsg, &createdAt)
		item := gin.H{
			"id": id, "marketplace": slug, "marketplace_name": name,
			"job_type": jobType, "status": status,
			"records_processed": recordsProcessed, "created_at": createdAt.Format(time.RFC3339),
		}
		if startedAt != nil {
			item["started_at"] = startedAt.Format(time.RFC3339)
		}
		if completedAt != nil {
			item["completed_at"] = completedAt.Format(time.RFC3339)
		}
		if errorMsg != nil {
			item["error_message"] = *errorMsg
		}
		result = append(result, item)
	}
	if result == nil {
		result = []gin.H{}
	}
	c.JSON(200, gin.H{"data": result, "count": len(result)})
}

func (h *Handler) GetSyncCredentials(c *gin.Context) {
	ctx := context.Background()
	rows, err := h.db.Query(ctx, `
		SELECT m.id, m.slug, m.name, m.api_base_url, m.is_active,
			mc.id, mc.name, mc.client_id, mc.is_active, mc.created_at, mc.updated_at, mc.api_key_hint,
			sj.id, sj.job_type, sj.status, sj.started_at, sj.completed_at,
			sj.records_processed, sj.error_message
		FROM marketplaces m
		LEFT JOIN marketplace_credentials mc ON mc.marketplace_id = m.id AND mc.is_active = true
		LEFT JOIN LATERAL (
			SELECT * FROM sync_jobs sj2
			WHERE sj2.marketplace_id = m.id
			ORDER BY sj2.created_at DESC LIMIT 1
		) sj ON true
		ORDER BY m.id
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var mID int
		var mSlug, mName, apiURL string
		var mActive bool
		var credID *int
		var credName, clientID, keyHint *string
		var credActive *bool
		var credCreated, credUpdated *time.Time
		var sjID *int64
		var sjType, sjStatus *string
		var sjStarted, sjCompleted *time.Time
		var sjRecords *int
		var sjError *string

		rows.Scan(&mID, &mSlug, &mName, &apiURL, &mActive,
			&credID, &credName, &clientID, &credActive, &credCreated, &credUpdated, &keyHint,
			&sjID, &sjType, &sjStatus, &sjStarted, &sjCompleted, &sjRecords, &sjError)

		status := "not_connected"
		if credID != nil && credActive != nil && *credActive {
			status = "connected"
		} else if credID != nil {
			status = "disabled"
		}

		item := gin.H{
			"id": mID, "slug": mSlug, "name": mName,
			"api_base_url": apiURL, "marketplace_active": mActive,
			"credential_id": credID, "credential_name": credName,
			"client_id": clientID, "credential_active": credActive,
			"connected_at": credCreated, "updated_at": credUpdated,
			"api_key_hint": keyHint, "status": status, "last_sync": nil,
		}
		if sjID != nil {
			ls := gin.H{
				"id": *sjID, "job_type": sjType, "status": sjStatus,
				"started_at": sjStarted, "completed_at": sjCompleted,
				"records_processed": 0, "error_message": sjError,
			}
			if sjRecords != nil {
				ls["records_processed"] = *sjRecords
			}
			item["last_sync"] = ls
		}
		result = append(result, item)
	}
	if result == nil {
		result = []gin.H{}
	}
	c.JSON(200, result)
}

func (h *Handler) SaveSyncCredential(c *gin.Context) {
	var req struct {
		MarketplaceID int    `json:"marketplace_id" binding:"required"`
		Name          string `json:"name" binding:"required"`
		APIKey        string `json:"api_key" binding:"required"`
		ClientID      string `json:"client_id"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "неверный формат: marketplace_id, name, api_key обязательны"})
		return
	}
	if len(req.APIKey) < 10 {
		c.JSON(400, gin.H{"error": "API ключ слишком короткий"})
		return
	}

	ctx := context.Background()

	var mpSlug string
	if err := h.db.QueryRow(ctx, "SELECT slug FROM marketplaces WHERE id = $1", req.MarketplaceID).Scan(&mpSlug); err != nil {
		c.JSON(400, gin.H{"error": "маркетплейс не найден"})
		return
	}

	if err := testMarketplaceKey(mpSlug, req.APIKey, req.ClientID); err != nil {
		c.JSON(400, gin.H{"error": fmt.Sprintf("API ключ невалиден: %v", err)})
		return
	}

	encKey := os.Getenv("ENCRYPTION_KEY")
	if encKey == "" {
		c.JSON(500, gin.H{"error": "encryption not configured"})
		return
	}
	encrypted, err := crypto.Encrypt(req.APIKey, encKey)
	if err != nil {
		c.JSON(500, gin.H{"error": "encryption error"})
		return
	}
	hint := crypto.Hint(req.APIKey)

	var id int
	err = h.db.QueryRow(ctx, `
		INSERT INTO marketplace_credentials (marketplace_id, name, api_key_encrypted, api_key_hint, client_id, is_active)
		VALUES ($1, $2, $3, $4, NULLIF($5, ''), true)
		ON CONFLICT (marketplace_id) WHERE is_active = true
		DO UPDATE SET name=$2, api_key_encrypted=$3, api_key_hint=$4, client_id=NULLIF($5, ''), updated_at=NOW(), is_active=true
		RETURNING id
	`, req.MarketplaceID, req.Name, encrypted, hint, req.ClientID).Scan(&id)
	if err != nil {
		log.Printf("[sync] save credential error: %v", err)
		c.JSON(500, gin.H{"error": "ошибка сохранения"})
		return
	}

	userID, _ := c.Get("user_id")
	h.auditLog(ctx, userID, "credential_saved", "marketplace_credential", fmt.Sprintf("%d", id),
		fmt.Sprintf(`{"marketplace":"%s","name":"%s"}`, mpSlug, req.Name), c.ClientIP())

	c.JSON(200, gin.H{"id": id, "status": "saved", "api_key_hint": hint})
}

func (h *Handler) DeleteSyncCredential(c *gin.Context) {
	mpID := c.Query("marketplace_id")
	if mpID == "" {
		c.JSON(400, gin.H{"error": "marketplace_id обязателен"})
		return
	}
	ctx := context.Background()
	h.db.Exec(ctx, "UPDATE marketplace_credentials SET is_active = false WHERE marketplace_id = $1", mpID)

	userID, _ := c.Get("user_id")
	h.auditLog(ctx, userID, "credential_deleted", "marketplace_credential", mpID, "{}", c.ClientIP())

	c.JSON(200, gin.H{"status": "disconnected"})
}

func (h *Handler) GetSyncHistory(c *gin.Context) {
	ctx := context.Background()
	rows, err := h.db.Query(ctx, `
		SELECT sj.id, m.slug, m.name, sj.job_type, sj.status,
			sj.started_at, sj.completed_at, sj.records_processed,
			sj.error_message, sj.created_at,
			EXTRACT(EPOCH FROM (sj.completed_at - sj.started_at))::int as duration_sec
		FROM sync_jobs sj
		JOIN marketplaces m ON m.id = sj.marketplace_id
		ORDER BY sj.created_at DESC LIMIT 50
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()
	var result []gin.H
	for rows.Next() {
		var id int64
		var slug, name, jobType, status string
		var startedAt, completedAt *time.Time
		var records int
		var errMsg *string
		var createdAt time.Time
		var durSec *int
		rows.Scan(&id, &slug, &name, &jobType, &status, &startedAt, &completedAt, &records, &errMsg, &createdAt, &durSec)
		item := gin.H{
			"id": id, "marketplace": slug, "marketplace_name": name,
			"job_type": jobType, "status": status,
			"records_processed": records, "created_at": createdAt.Format(time.RFC3339),
			"started_at": nil, "completed_at": nil,
			"error_message": nil, "duration_sec": nil,
		}
		if startedAt != nil {
			item["started_at"] = startedAt.Format(time.RFC3339)
		}
		if completedAt != nil {
			item["completed_at"] = completedAt.Format(time.RFC3339)
		}
		if errMsg != nil {
			item["error_message"] = *errMsg
		}
		if durSec != nil {
			item["duration_sec"] = *durSec
		}
		result = append(result, item)
	}
	if result == nil {
		result = []gin.H{}
	}
	c.JSON(200, result)
}

func (h *Handler) TriggerSync(c *gin.Context) {
	var req struct {
		Marketplace  string `json:"marketplace"`
		CredentialID int    `json:"credential_id"`
	}
	c.ShouldBindJSON(&req)

	etlURL := os.Getenv("ETL_SERVICE_URL")
	if etlURL == "" {
		etlURL = "http://etl-worker:8081"
	}
	etlSecret := os.Getenv("ETL_SERVICE_SECRET")

	body, _ := json.Marshal(map[string]interface{}{
		"marketplace":   req.Marketplace,
		"credential_id": req.CredentialID,
	})

	httpReq, err := http.NewRequest("POST", etlURL+"/api/trigger", bytes.NewReader(body))
	if err != nil {
		c.JSON(500, gin.H{"error": "internal error"})
		return
	}
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("X-ETL-Secret", etlSecret)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(httpReq)
	if err != nil {
		log.Printf("[sync] ETL service unreachable: %v", err)
		c.JSON(503, gin.H{"error": "ETL service unavailable"})
		return
	}
	defer resp.Body.Close()

	respBody, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		c.JSON(resp.StatusCode, gin.H{"error": "ETL error", "details": string(respBody)})
		return
	}

	userID, _ := c.Get("user_id")
	h.auditLog(context.Background(), userID, "sync_triggered", "sync", "0",
		fmt.Sprintf(`{"marketplace":"%s","credential_id":%d}`, req.Marketplace, req.CredentialID), c.ClientIP())

	var result map[string]interface{}
	json.Unmarshal(respBody, &result)
	c.JSON(200, result)
}

func (h *Handler) auditLog(ctx context.Context, userID interface{}, action, entityType, entityID, details, ip string) {
	h.db.Exec(ctx, `
		INSERT INTO audit_log (user_id, action, entity_type, entity_id, details, ip_address)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, userID, action, entityType, entityID, details, ip)
}

func testMarketplaceKey(slug, apiKey, clientID string) error {
	client := &http.Client{Timeout: 15 * time.Second}

	switch slug {
	case "wb":
		req, _ := http.NewRequest("GET", "https://statistics-api.wildberries.ru/api/v1/supplier/stocks?dateFrom=2024-01-01", nil)
		req.Header.Set("Authorization", apiKey)
		resp, err := client.Do(req)
		if err != nil {
			return fmt.Errorf("connection error: %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode == 401 || resp.StatusCode == 403 {
			return fmt.Errorf("невалидный API ключ (HTTP %d)", resp.StatusCode)
		}
		return nil

	case "ozon":
		if clientID == "" {
			return fmt.Errorf("для Ozon нужен Client-Id")
		}
		body, _ := json.Marshal(map[string]interface{}{"limit": 1})
		req, _ := http.NewRequest("POST", "https://api-seller.ozon.ru/v2/product/list", bytes.NewReader(body))
		req.Header.Set("Client-Id", clientID)
		req.Header.Set("Api-Key", apiKey)
		req.Header.Set("Content-Type", "application/json")
		resp, err := client.Do(req)
		if err != nil {
			return fmt.Errorf("connection error: %w", err)
		}
		defer resp.Body.Close()
		if resp.StatusCode == 401 || resp.StatusCode == 403 {
			return fmt.Errorf("невалидный API ключ (HTTP %d)", resp.StatusCode)
		}
		return nil

	default:
		return nil
	}
}
