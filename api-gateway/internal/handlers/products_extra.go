package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetProductDetail(c *gin.Context) {
	h.GetProduct(c)
}

func (h *Handler) UpdateProduct(c *gin.Context) {
	id := c.Param("id")
	var body map[string]interface{}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if costPrice, ok := body["cost_price"]; ok {
		_, err := h.db.Exec(c.Request.Context(),
			`UPDATE products SET cost_price = $1, updated_at = now() WHERE id = $2`,
			costPrice, id)
		if err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	c.JSON(http.StatusOK, gin.H{"success": true})
}

func (h *Handler) BulkUpdateCostPrice(c *gin.Context) {
	var body struct {
		Items []struct {
			ProductID int     `json:"product_id"`
			CostPrice float64 `json:"cost_price"`
		} `json:"items"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	updated := 0
	for _, item := range body.Items {
		_, err := h.db.Exec(c.Request.Context(),
			`UPDATE products SET cost_price = $1, updated_at = now() WHERE id = $2`,
			item.CostPrice, item.ProductID)
		if err == nil {
			updated++
		}
	}
	c.JSON(http.StatusOK, gin.H{"success": true, "updated": updated})
}

func (h *Handler) GetPnL(c *gin.Context) {
	h.GetPnLFull(c)
}

func (h *Handler) GetABC(c *gin.Context) {
	h.GetAnalyticsABC(c)
}

func (h *Handler) GetUnitEconomics(c *gin.Context) {
	h.GetUnitEconomicsFull(c)
}

func (h *Handler) GetFinance(c *gin.Context) {
	h.GetFinanceFull(c)
}
