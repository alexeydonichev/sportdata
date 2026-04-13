package handlers

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) CronSync(c *gin.Context) {
	secret := c.GetHeader("X-Cron-Secret")
	if secret == "" {
		secret = c.Query("secret")
	}

	cronSecret := os.Getenv("CRON_SECRET")
	if secret == "" || secret != cronSecret {
		c.JSON(401, gin.H{"error": "Unauthorized"})
		return
	}

	etlURL := os.Getenv("ETL_SERVICE_URL")
	if etlURL == "" {
		etlURL = "http://etl-worker:8081"
	}
	etlSecret := os.Getenv("ETL_SECRET")

	client := &http.Client{Timeout: 10 * time.Second}
	req, _ := http.NewRequest("POST", etlURL+"/api/trigger", nil)
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("X-ETL-Secret", etlSecret)

	resp, err := client.Do(req)
	if err != nil {
		c.JSON(503, gin.H{"error": fmt.Sprintf("ETL сервис недоступен: %v", err)})
		return
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != 200 {
		c.JSON(502, gin.H{"error": fmt.Sprintf("ETL error: %d", resp.StatusCode)})
		return
	}

	var etlData interface{}
	json.Unmarshal(body, &etlData)

	c.JSON(200, gin.H{
		"success": true,
		"message": "Cron: синхронизация запущена через ETL сервис",
		"etl":     etlData,
	})
}
