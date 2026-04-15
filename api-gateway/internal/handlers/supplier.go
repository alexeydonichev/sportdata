package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetSupplierSales(c *gin.Context) {
	dateFrom := c.DefaultQuery("dateFrom", time.Now().AddDate(0, 0, -7).Format("2006-01-02"))

	rows, err := h.db.Query(c.Request.Context(),
		`SELECT s.sale_date::text, COALESCE(p.name,''), COALESCE(p.sku,''),
		        s.quantity, s.revenue, COALESCE(m.name,'')
		 FROM sales s
		 LEFT JOIN products p ON p.id = s.product_id
		 LEFT JOIN marketplaces m ON m.id = s.marketplace_id
		 WHERE s.sale_date >= $1
		 ORDER BY s.sale_date DESC LIMIT 500`, dateFrom)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	type sale struct {
		Date        string  `json:"date"`
		ProductName string  `json:"product_name"`
		SKU         string  `json:"sku"`
		Quantity    int     `json:"quantity"`
		Revenue     float64 `json:"revenue"`
		Marketplace string  `json:"marketplace"`
	}

	items := make([]sale, 0)
	for rows.Next() {
		var s sale
		if err := rows.Scan(&s.Date, &s.ProductName, &s.SKU, &s.Quantity, &s.Revenue, &s.Marketplace); err != nil {
			continue
		}
		items = append(items, s)
	}
	c.JSON(http.StatusOK, gin.H{"sales": items, "total": len(items)})
}

func (h *Handler) GetSupplierStocks(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(),
		`SELECT COALESCE(p.name,''), COALESCE(p.sku,''), COALESCE(p.barcode,''),
		        COALESCE(i.warehouse,''), i.quantity, COALESCE(m.name,''),
		        i.recorded_at::text
		 FROM inventory i
		 LEFT JOIN products p ON p.id = i.product_id
		 LEFT JOIN marketplaces m ON m.id = i.marketplace_id
		 WHERE i.quantity > 0
		 ORDER BY i.quantity DESC LIMIT 500`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	type stock struct {
		ProductName string `json:"product_name"`
		SKU         string `json:"sku"`
		Barcode     string `json:"barcode"`
		Warehouse   string `json:"warehouse"`
		Quantity    int    `json:"quantity"`
		Marketplace string `json:"marketplace"`
		UpdatedAt   string `json:"updated_at"`
	}

	items := make([]stock, 0)
	for rows.Next() {
		var s stock
		if err := rows.Scan(&s.ProductName, &s.SKU, &s.Barcode, &s.Warehouse,
			&s.Quantity, &s.Marketplace, &s.UpdatedAt); err != nil {
			continue
		}
		items = append(items, s)
	}
	c.JSON(http.StatusOK, gin.H{"stocks": items, "total": len(items)})
}

func wbAPICall(ctx context.Context, apiKey, url string) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", apiKey)
	client := &http.Client{Timeout: 30 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("WB API returned %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}

var _ = json.Marshal
var _ = fmt.Sprintf
