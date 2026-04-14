package handlers

import (
	"github.com/gin-gonic/gin"
)

func (h *Handler) GetCategories(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := h.db.Query(ctx, `SELECT id, slug, name, parent_id
		FROM categories ORDER BY name`)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	var items []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		var parentID *int
		if rows.Scan(&id, &slug, &name, &parentID) == nil {
			item := gin.H{"id": id, "slug": slug, "name": name}
			if parentID != nil {
				item["parent_id"] = *parentID
			}
			items = append(items, item)
		}
	}
	if items == nil { items = []gin.H{} }
	c.JSON(200, items)
}

func (h *Handler) GetMarketplaces(c *gin.Context) {
	ctx := c.Request.Context()
	rows, err := h.db.Query(ctx, `SELECT id, slug, name FROM marketplaces ORDER BY name`)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	var items []gin.H
	for rows.Next() {
		var id int
		var slug, name string
		if rows.Scan(&id, &slug, &name) == nil {
			items = append(items, gin.H{"id": id, "slug": slug, "name": name})
		}
	}
	if items == nil { items = []gin.H{} }
	c.JSON(200, items)
}

