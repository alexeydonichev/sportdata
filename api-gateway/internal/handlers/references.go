package handlers

import (
	"github.com/gin-gonic/gin"
)

func (h *Handler) GetMarketplaces(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := h.db.Query(ctx, "SELECT id, slug, name, is_active FROM marketplaces ORDER BY id")
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		var isActive bool
		if err := rows.Scan(&id, &slug, &name, &isActive); err != nil {
			continue
		}
		result = append(result, gin.H{"id": id, "slug": slug, "name": name, "is_active": isActive})
	}
	c.JSON(200, gin.H{"data": result, "count": len(result)})
}

func (h *Handler) GetCategories(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := h.db.Query(ctx, `
		SELECT c.id, c.slug, c.name, c.parent_id,
			COUNT(p.id) as product_count,
			COALESCE(SUM(sub.revenue), 0) as revenue
		FROM categories c
		LEFT JOIN products p ON p.category_id = c.id AND p.is_active = true
		LEFT JOIN (
			SELECT s.product_id, SUM(s.revenue) as revenue
			FROM sales s WHERE s.sale_date >= NOW() - INTERVAL '90 days'
			GROUP BY s.product_id
		) sub ON sub.product_id = p.id
		GROUP BY c.id, c.slug, c.name, c.parent_id
		ORDER BY c.sort_order, c.name
	`)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	var result []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		var parentID *int
		var productCount int
		var revenue float64
		if err := rows.Scan(&id, &slug, &name, &parentID, &productCount, &revenue); err != nil {
			continue
		}
		item := gin.H{"slug": slug, "name": name, "product_count": productCount, "revenue": round2(revenue)}
		if parentID != nil {
			item["parent_id"] = *parentID
		}
		result = append(result, item)
	}
	c.JSON(200, result)
}
