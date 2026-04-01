package handlers

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type TrendingProduct struct {
	ProductID   int    `json:"product_id"`
	Name        string `json:"name"`
	CategoryID  int    `json:"category_id"`
	Sales7d     int    `json:"sales_7d"`
	PrevSales7d int    `json:"prev_sales_7d"`
	Growth      int    `json:"growth"`
}

func (h *Handler) GetTrending(c *gin.Context) {
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT 
			product_id,
			name,
			category_id,
			sales_7d,
			prev_sales_7d,
			sales_7d - prev_sales_7d AS growth
		FROM trending_products
		ORDER BY growth DESC
		LIMIT 50
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	var products []TrendingProduct

	for rows.Next() {
		var p TrendingProduct

		err := rows.Scan(
			&p.ProductID,
			&p.Name,
			&p.CategoryID,
			&p.Sales7d,
			&p.PrevSales7d,
			&p.Growth,
		)

		if err != nil {
			continue
		}

		products = append(products, p)
	}

	if err := rows.Err(); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"products": products,
	})
}
