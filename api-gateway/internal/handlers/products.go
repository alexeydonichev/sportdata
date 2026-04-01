package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type Product struct {
	ID   int    `json:"id"`
	Name string `json:"name"`
	SKU  string `json:"sku"`
}

func (h *Handler) GetProducts(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT id, name, sku
		FROM products
		ORDER BY id
		LIMIT 100
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"status":  "error",
			"message": err.Error(),
		})
		return
	}
	defer rows.Close()

	products := make([]Product, 0, 100)

	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.Name, &p.SKU); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{
				"status":  "error",
				"message": err.Error(),
			})
			return
		}
		products = append(products, p)
	}

	c.JSON(http.StatusOK, gin.H{
		"status": "ok",
		"count":  len(products),
		"data":   products,
	})
}

func (h *Handler) BulkUpdateCostPrice(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h *Handler) GetProductDetail(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func (h *Handler) UpdateProduct(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}
