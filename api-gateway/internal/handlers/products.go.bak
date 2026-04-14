package handlers

import (
	"context"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetProducts(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 15*time.Second)
	defer cancel()

	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 200 {
		limit = 50
	}
	offset := (page - 1) * limit

	categorySlug := c.Query("category")
	marketplaceSlug := c.Query("marketplace")
	search := c.Query("search")
	sortBy := c.DefaultQuery("sort", "revenue")
	sortDir := c.DefaultQuery("dir", "desc")
	if sortDir != "asc" {
		sortDir = "desc"
	}

	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := parsePeriod(period)

	// Build WHERE conditions for products
	conditions := []string{"p.is_active = true"}
	args := []any{dateFrom, dateTo} // $1, $2 reserved for date range in subqueries
	argN := 3

	if categorySlug != "" && categorySlug != "all" {
		conditions = append(conditions, fmt.Sprintf("c.slug = $%d", argN))
		args = append(args, categorySlug)
		argN++
	}
	if marketplaceSlug != "" && marketplaceSlug != "all" {
		conditions = append(conditions, fmt.Sprintf(
			"EXISTS (SELECT 1 FROM sales sf WHERE sf.product_id = p.id AND sf.marketplace_id = (SELECT id FROM marketplaces WHERE slug = $%d LIMIT 1))", argN))
		args = append(args, marketplaceSlug)
		argN++
	}
	if search != "" {
		conditions = append(conditions, fmt.Sprintf("(p.name ILIKE $%d OR p.sku ILIKE $%d)", argN, argN))
		args = append(args, "%"+search+"%")
		argN++
	}

	where := strings.Join(conditions, " AND ")

	// Sort field mapping
	orderField := "COALESCE(metrics.revenue, 0)"
	switch sortBy {
	case "name":
		orderField = "p.name"
	case "sku":
		orderField = "p.sku"
	case "profit":
		orderField = "COALESCE(metrics.profit, 0)"
	case "quantity":
		orderField = "COALESCE(metrics.quantity, 0)"
	case "stock":
		orderField = "COALESCE(inv.stock, 0)"
	case "margin":
		orderField = "CASE WHEN COALESCE(metrics.revenue,0) > 0 THEN COALESCE(metrics.profit,0) / metrics.revenue ELSE 0 END"
	case "cost_price":
		orderField = "COALESCE(p.cost_price, 0)"
	}

	// Count total
	countQ := fmt.Sprintf(`
		SELECT COUNT(*)
		FROM products p
		LEFT JOIN categories c ON c.id = p.category_id
		WHERE %s`, where)
	var total int
	h.db.QueryRow(ctx, countQ, args...).Scan(&total)

	pages := int(math.Ceil(float64(total) / float64(limit)))
	if pages < 1 {
		pages = 1
	}

	// Main query with metrics
	dataArgs := make([]any, len(args))
	copy(dataArgs, args)
	limitArgN := argN
	dataArgs = append(dataArgs, limit)
	offsetArgN := argN + 1
	dataArgs = append(dataArgs, offset)

	q := fmt.Sprintf(`
		SELECT
			p.id, p.sku, p.name, COALESCE(p.brand, '') as brand,
			COALESCE(c.name, '') as category, COALESCE(c.slug, '') as category_slug,
			COALESCE(p.cost_price, 0) as cost_price,
			p.is_active, p.created_at,
			COALESCE(metrics.revenue, 0) as revenue,
			COALESCE(metrics.profit, 0) as profit,
			COALESCE(metrics.quantity, 0) as quantity,
			COALESCE(metrics.orders_count, 0) as orders_count,
			COALESCE(metrics.commission, 0) as commission,
			COALESCE(metrics.logistics, 0) as logistics,
			COALESCE(metrics.returns_qty, 0) as returns_qty,
			COALESCE(inv.stock, 0) as stock,
			COALESCE(inv.warehouse, '') as warehouse
		FROM products p
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN (
			SELECT s.product_id,
				SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END) as revenue,
				SUM(s.net_profit) as profit,
				SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) as quantity,
				COUNT(CASE WHEN s.quantity > 0 THEN 1 END) as orders_count,
				SUM(COALESCE(s.commission, 0)) as commission,
				SUM(COALESCE(s.logistics_cost, 0)) as logistics,
				SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END) as returns_qty
			FROM sales s
			WHERE s.sale_date >= $1 AND s.sale_date <= $2
			GROUP BY s.product_id
		) metrics ON metrics.product_id = p.id
		LEFT JOIN (
			SELECT DISTINCT ON (product_id) product_id, quantity as stock, warehouse
			FROM inventory ORDER BY product_id, recorded_at DESC
		) inv ON inv.product_id = p.id
		WHERE %s
		ORDER BY %s %s NULLS LAST
		LIMIT $%d OFFSET $%d
	`, where, orderField, sortDir, limitArgN, offsetArgN)

	rows, err := h.db.Query(ctx, q, dataArgs...)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	var items []gin.H
	for rows.Next() {
		var id int
		var sku, name, brand, category, categorySlugVal, warehouse string
		var costPrice, revenue, profit, commission, logistics float64
		var quantity, ordersCount, returnsQty, stock int
		var isActive bool
		var createdAt time.Time

		if err := rows.Scan(&id, &sku, &name, &brand, &category, &categorySlugVal,
			&costPrice, &isActive, &createdAt,
			&revenue, &profit, &quantity, &ordersCount, &commission, &logistics,
			&returnsQty, &stock, &warehouse); err != nil {
			continue
		}

		marginPct := pct(profit, revenue)
		avgPrice := div(revenue, float64(quantity))

		items = append(items, gin.H{
			"id": id, "sku": sku, "name": name, "brand": brand,
			"category": category, "category_slug": categorySlugVal,
			"cost_price": round2(costPrice), "is_active": isActive,
			"created_at": createdAt.Format("2006-01-02"),
			"revenue":    round2(revenue), "profit": round2(profit),
			"quantity": quantity, "orders": ordersCount,
			"commission": round2(commission), "logistics": round2(logistics),
			"returns": returnsQty, "stock": stock, "warehouse": warehouse,
			"margin_pct": round2(marginPct), "avg_price": round2(avgPrice),
		})
	}
	if items == nil {
		items = []gin.H{}
	}

	c.JSON(200, gin.H{
		"items": items, "total": total, "page": page, "limit": limit, "pages": pages,
	})
}

func (h *Handler) GetProductDetail(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	idStr := c.Param("id")
	productID, err := strconv.Atoi(idStr)
	if err != nil {
		c.JSON(400, gin.H{"error": "невалидный ID"})
		return
	}

	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := parsePeriod(period)

	// Basic product info
	var id int
	var sku, name string
	var brand, barcode *string
	var categoryName, categorySlug string
	var costPrice float64
	var weightG *int
	var isActive bool
	var createdAt time.Time

	err = h.db.QueryRow(ctx, `
		SELECT p.id, p.sku, p.name, p.brand, p.barcode,
			COALESCE(c.name,''), COALESCE(c.slug,''),
			COALESCE(p.cost_price,0), p.weight_g, p.is_active, p.created_at
		FROM products p
		LEFT JOIN categories c ON c.id = p.category_id
		WHERE p.id = $1
	`, productID).Scan(&id, &sku, &name, &brand, &barcode, &categoryName, &categorySlug,
		&costPrice, &weightG, &isActive, &createdAt)
	if err != nil {
		c.JSON(404, gin.H{"error": "товар не найден"})
		return
	}

	// Sales metrics for period
	var revenue, profit, commission, logistics float64
	var quantity, ordersCount, returnsQty int
	h.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(CASE WHEN quantity > 0 THEN revenue ELSE 0 END),0),
			COALESCE(SUM(net_profit),0),
			COALESCE(SUM(commission),0),
			COALESCE(SUM(logistics_cost),0),
			COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END),0),
			COUNT(CASE WHEN quantity > 0 THEN 1 END),
			COALESCE(SUM(CASE WHEN quantity < 0 THEN ABS(quantity) ELSE 0 END),0)
		FROM sales WHERE product_id = $1 AND sale_date >= $2 AND sale_date <= $3
	`, productID, dateFrom, dateTo).Scan(&revenue, &profit, &commission, &logistics,
		&quantity, &ordersCount, &returnsQty)

	// Previous period
	prevFrom, prevTo := prevPeriod(dateFrom, dateTo)
	var prevRevenue, prevProfit float64
	var prevQuantity int
	h.db.QueryRow(ctx, `
		SELECT COALESCE(SUM(CASE WHEN quantity > 0 THEN revenue ELSE 0 END),0),
			COALESCE(SUM(net_profit),0),
			COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END),0)
		FROM sales WHERE product_id = $1 AND sale_date >= $2 AND sale_date <= $3
	`, productID, prevFrom, prevTo).Scan(&prevRevenue, &prevProfit, &prevQuantity)

	// Daily chart
	chartRows, _ := h.db.Query(ctx, `
		SELECT sale_date,
			COALESCE(SUM(CASE WHEN quantity > 0 THEN revenue ELSE 0 END),0),
			COALESCE(SUM(net_profit),0),
			COALESCE(SUM(CASE WHEN quantity > 0 THEN quantity ELSE 0 END),0)
		FROM sales WHERE product_id = $1 AND sale_date >= $2 AND sale_date <= $3
		GROUP BY sale_date ORDER BY sale_date
	`, productID, dateFrom, dateTo)
	var daily []gin.H
	if chartRows != nil {
		defer chartRows.Close()
		for chartRows.Next() {
			var d time.Time
			var r, p float64
			var q int
			if err := chartRows.Scan(&d, &r, &p, &q); err != nil {
				continue
			}
			daily = append(daily, gin.H{
				"date": d.Format("2006-01-02"), "revenue": round2(r),
				"profit": round2(p), "quantity": q,
			})
		}
	}
	if daily == nil {
		daily = []gin.H{}
	}

	// Marketplace breakdown (from sales, not from mapping table)
	mpRows, _ := h.db.Query(ctx, `
		SELECT m.slug, m.name,
			COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END),0),
			COALESCE(SUM(s.net_profit),0),
			COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END),0)
		FROM sales s
		JOIN marketplaces m ON m.id = s.marketplace_id
		WHERE s.product_id = $1 AND s.sale_date >= $2 AND s.sale_date <= $3
		GROUP BY m.slug, m.name ORDER BY SUM(s.revenue) DESC
	`, productID, dateFrom, dateTo)
	var marketplaces []gin.H
	if mpRows != nil {
		defer mpRows.Close()
		for mpRows.Next() {
			var slug, mname string
			var rev, prof float64
			var qty int
			if err := mpRows.Scan(&slug, &mname, &rev, &prof, &qty); err != nil {
				continue
			}
			marketplaces = append(marketplaces, gin.H{
				"marketplace": slug, "name": mname,
				"revenue": round2(rev), "profit": round2(prof), "quantity": qty,
			})
		}
	}
	if marketplaces == nil {
		marketplaces = []gin.H{}
	}

	// Inventory
	var stock int
	var warehouse string
	err = h.db.QueryRow(ctx, `
		SELECT COALESCE(quantity, 0), COALESCE(warehouse, '')
		FROM inventory WHERE product_id = $1 ORDER BY recorded_at DESC LIMIT 1
	`, productID).Scan(&stock, &warehouse)
	if err != nil {
		stock = 0
		warehouse = ""
	}

	avgPrice := div(revenue, float64(quantity))
	marginPct := pct(profit, revenue)
	returnRate := pct(float64(returnsQty), float64(quantity+returnsQty))

	brandStr := ""
	if brand != nil {
		brandStr = *brand
	}
	barcodeStr := ""
	if barcode != nil {
		barcodeStr = *barcode
	}

	result := gin.H{
		"id": id, "sku": sku, "name": name, "brand": brandStr, "barcode": barcodeStr,
		"category": categoryName, "category_slug": categorySlug,
		"cost_price": round2(costPrice), "is_active": isActive,
		"created_at": createdAt.Format("2006-01-02"),
		"weight_g":   weightG,
		"metrics": gin.H{
			"revenue": round2(revenue), "profit": round2(profit),
			"quantity": quantity, "orders": ordersCount,
			"commission": round2(commission), "logistics": round2(logistics),
			"returns": returnsQty, "avg_price": round2(avgPrice),
			"margin_pct": round2(marginPct), "return_rate": round2(returnRate),
		},
		"changes": gin.H{
			"revenue":  changePct(revenue, prevRevenue),
			"profit":   changePct(profit, prevProfit),
			"quantity": changePct(float64(quantity), float64(prevQuantity)),
		},
		"inventory": gin.H{
			"stock": stock, "warehouse": warehouse,
		},
		"marketplaces": marketplaces,
		"daily":        daily,
		"period":       gin.H{"from": dateFrom, "to": dateTo},
	}

	c.JSON(200, result)
}

func (h *Handler) UpdateProduct(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()

	idStr := c.Param("id")
	productID, err := strconv.Atoi(idStr)
	if err != nil {
		c.JSON(400, gin.H{"error": "невалидный ID"})
		return
	}

	var req struct {
		Name      *string  `json:"name"`
		Brand     *string  `json:"brand"`
		CostPrice *float64 `json:"cost_price"`
		IsActive  *bool    `json:"is_active"`
		Barcode   *string  `json:"barcode"`
		WeightG   *int     `json:"weight_g"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "невалидные данные"})
		return
	}

	sets := []string{}
	args := []any{}
	argN := 1

	if req.Name != nil {
		sets = append(sets, fmt.Sprintf("name = $%d", argN))
		args = append(args, *req.Name)
		argN++
	}
	if req.Brand != nil {
		sets = append(sets, fmt.Sprintf("brand = $%d", argN))
		args = append(args, *req.Brand)
		argN++
	}
	if req.CostPrice != nil {
		sets = append(sets, fmt.Sprintf("cost_price = $%d", argN))
		args = append(args, *req.CostPrice)
		argN++
	}
	if req.IsActive != nil {
		sets = append(sets, fmt.Sprintf("is_active = $%d", argN))
		args = append(args, *req.IsActive)
		argN++
	}
	if req.Barcode != nil {
		sets = append(sets, fmt.Sprintf("barcode = $%d", argN))
		args = append(args, *req.Barcode)
		argN++
	}
	if req.WeightG != nil {
		sets = append(sets, fmt.Sprintf("weight_g = $%d", argN))
		args = append(args, *req.WeightG)
		argN++
	}

	if len(sets) == 0 {
		c.JSON(400, gin.H{"error": "нет полей для обновления"})
		return
	}

	sets = append(sets, "updated_at = NOW()")
	args = append(args, productID)

	q := fmt.Sprintf("UPDATE products SET %s WHERE id = $%d RETURNING id", strings.Join(sets, ", "), argN)
	var updatedID int
	err = h.db.QueryRow(ctx, q, args...).Scan(&updatedID)
	if err != nil {
		c.JSON(404, gin.H{"error": "товар не найден"})
		return
	}

	userID, _ := c.Get("user_id")
	h.auditLog(ctx, userID, "product_updated", "product", idStr, "{}", c.ClientIP())

	c.JSON(200, gin.H{"status": "updated", "id": updatedID})
}

func (h *Handler) BulkUpdateCostPrice(c *gin.Context) {
	ctx, cancel := context.WithTimeout(c.Request.Context(), 10*time.Second)
	defer cancel()

	var req struct {
		Items []struct {
			ProductID int     `json:"product_id"`
			CostPrice float64 `json:"cost_price"`
		} `json:"items"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": "невалидные данные"})
		return
	}

	if len(req.Items) == 0 {
		c.JSON(400, gin.H{"error": "пустой список"})
		return
	}
	if len(req.Items) > 500 {
		c.JSON(400, gin.H{"error": "максимум 500 позиций"})
		return
	}

	tx, err := h.db.Begin(ctx)
	if err != nil {
		c.JSON(500, gin.H{"error": "transaction error"})
		return
	}
	defer tx.Rollback(ctx)

	updated := 0
	var errors []gin.H
	for _, item := range req.Items {
		if item.CostPrice < 0 {
			errors = append(errors, gin.H{"product_id": item.ProductID, "error": "отрицательная себестоимость"})
			continue
		}
		tag, err := tx.Exec(ctx,
			"UPDATE products SET cost_price = $1, updated_at = NOW() WHERE id = $2 AND is_active = true",
			item.CostPrice, item.ProductID)
		if err != nil {
			errors = append(errors, gin.H{"product_id": item.ProductID, "error": err.Error()})
			continue
		}
		if tag.RowsAffected() > 0 {
			updated++
		} else {
			errors = append(errors, gin.H{"product_id": item.ProductID, "error": "не найден или неактивен"})
		}
	}

	if err := tx.Commit(ctx); err != nil {
		c.JSON(500, gin.H{"error": "commit error"})
		return
	}

	userID, _ := c.Get("user_id")
	h.auditLog(ctx, userID, "bulk_cost_update", "products", "",
		fmt.Sprintf(`{"updated":%d,"total":%d}`, updated, len(req.Items)), c.ClientIP())

	result := gin.H{
		"status":  "ok",
		"updated": updated,
		"total":   len(req.Items),
	}
	if len(errors) > 0 {
		result["errors"] = errors
	}

	c.JSON(200, result)
}
