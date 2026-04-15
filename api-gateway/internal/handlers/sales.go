package handlers

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetSales(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "7d")
	categorySlug := c.Query("category")
	marketplaceSlug := c.Query("marketplace")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if page < 1 {
		page = 1
	}
	if limit < 1 || limit > 200 {
		limit = 50
	}
	offset := (page - 1) * limit

	dateFrom, dateTo := h.parsePeriod(period)

	conditions := []string{"s.sale_date >= $1", "s.sale_date <= $2"}
	args := []any{dateFrom, dateTo}
	argN := 3

	if categorySlug != "" && categorySlug != "all" {
		conditions = append(conditions, fmt.Sprintf("c.slug = $%d", argN))
		args = append(args, categorySlug)
		argN++
	}
	if marketplaceSlug != "" && marketplaceSlug != "all" {
		conditions = append(conditions, fmt.Sprintf("m.slug = $%d", argN))
		args = append(args, marketplaceSlug)
		argN++
	}

	where := "WHERE " + strings.Join(conditions, " AND ")

	joinClause := `FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id`

	var total int
	countQ := fmt.Sprintf(`SELECT COUNT(*) %s %s`, joinClause, where)
	h.db.QueryRow(ctx, countQ, args...).Scan(&total)

	pages := int(math.Ceil(float64(total) / float64(limit)))
	if pages < 1 {
		pages = 1
	}

	dataArgs := append(args, limit, offset)
	q := fmt.Sprintf(`
		SELECT s.id::text, s.sale_date, COALESCE(p.name,''), COALESCE(p.sku,''),
			COALESCE(c.name,''), s.quantity, s.revenue, s.net_profit,
			COALESCE(s.commission,0), COALESCE(s.logistics_cost,0),
			COALESCE(m.name,''), COALESCE(m.slug,'')
		%s %s
		ORDER BY s.sale_date DESC, s.id DESC
		LIMIT $%d OFFSET $%d`, joinClause, where, argN, argN+1)

	rows, err := h.db.Query(ctx, q, dataArgs...)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	var items []gin.H
	for rows.Next() {
		var sid, pName, pSku, cName, mName, mSlug string
		var saleDate time.Time
		var qty int
		var rev, prof, comm, logi float64
		if err := rows.Scan(&sid, &saleDate, &pName, &pSku, &cName, &qty, &rev, &prof, &comm, &logi, &mName, &mSlug); err != nil {
			continue
		}
		items = append(items, gin.H{
			"id": sid, "date": saleDate.Format("2006-01-02"),
			"product_name": pName, "sku": pSku, "category": cName,
			"quantity": qty, "revenue": round2(rev), "profit": round2(prof),
			"commission": round2(comm), "logistics": round2(logi),
			"marketplace": mName, "marketplace_slug": mSlug,
		})
	}
	if items == nil {
		items = []gin.H{}
	}

	c.JSON(200, gin.H{
		"items": items, "total": total, "page": page, "limit": limit, "pages": pages,
	})
}

func (h *Handler) GetInventory(c *gin.Context) {
	ctx := c.Request.Context()
	categorySlug := c.Query("category")

	conditions := []string{}
	args := []any{}
	argN := 1
	if categorySlug != "" && categorySlug != "all" {
		conditions = append(conditions, fmt.Sprintf("c.slug = $%d", argN))
		args = append(args, categorySlug)
		argN++
	}

	where := ""
	if len(conditions) > 0 {
		where = "WHERE " + strings.Join(conditions, " AND ")
	}

	q := fmt.Sprintf(`
		SELECT p.id::text, p.name, p.sku,
			COALESCE(c.name, '') as category,
			COALESCE(i.warehouse, 'Основной') as warehouse,
			i.quantity as stock,
			i.recorded_at,
			COALESCE(daily.avg_qty, 0) as avg_daily_sales
		FROM inventory i
		JOIN products p ON p.id = i.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN (
			SELECT product_id, AVG(daily_qty) as avg_qty FROM (
				SELECT product_id, SUM(quantity) as daily_qty
				FROM sales WHERE quantity > 0 AND sale_date >= NOW() - INTERVAL '30 days'
				GROUP BY product_id, sale_date
			) d GROUP BY product_id
		) daily ON daily.product_id = p.id
		%s
		ORDER BY CASE WHEN COALESCE(daily.avg_qty,0) > 0
			THEN i.quantity / daily.avg_qty ELSE 9999 END ASC
	`, where)

	rows, err := h.db.Query(ctx, q, args...)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error: " + err.Error()})
		return
	}
	defer rows.Close()

	var items []gin.H
	totalStock := 0
	warehouses := map[string]bool{}
	products := map[string]bool{}

	for rows.Next() {
		var pid, name, sku, cat, wh string
		var stock int
		var recordedAt time.Time
		var avgDaily float64
		if err := rows.Scan(&pid, &name, &sku, &cat, &wh, &stock, &recordedAt, &avgDaily); err != nil {
			continue
		}
		dos := 999
		if avgDaily > 0 {
			dos = int(float64(stock) / avgDaily)
		}
		items = append(items, gin.H{
			"product_id": pid, "name": name, "sku": sku, "category": cat,
			"warehouse": wh, "stock": stock, "avg_daily_sales": round2(avgDaily),
			"days_of_stock": dos,
		})
		totalStock += stock
		warehouses[wh] = true
		products[pid] = true
	}
	if items == nil {
		items = []gin.H{}
	}

	c.JSON(200, gin.H{
		"items": items,
		"summary": gin.H{
			"total_stock":       totalStock,
			"products_in_stock": len(products),
			"warehouses":        len(warehouses),
		},
	})
}

func (h *Handler) ExportSalesCSV(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "30d")
	categorySlug := c.Query("category")
	marketplaceSlug := c.Query("marketplace")

	dateFrom, dateTo := h.parsePeriod(period)

	conditions := []string{"s.sale_date >= $1", "s.sale_date <= $2"}
	args := []any{dateFrom, dateTo}
	argN := 3

	if categorySlug != "" && categorySlug != "all" {
		conditions = append(conditions, fmt.Sprintf("c.slug = $%d", argN))
		args = append(args, categorySlug)
		argN++
	}
	if marketplaceSlug != "" && marketplaceSlug != "all" {
		conditions = append(conditions, fmt.Sprintf("m.slug = $%d", argN))
		args = append(args, marketplaceSlug)
		argN++
	}

	where := "WHERE " + strings.Join(conditions, " AND ")

	q := fmt.Sprintf(`
		SELECT s.sale_date, COALESCE(p.name,''), COALESCE(p.sku,''),
			COALESCE(c.name,''), COALESCE(m.name,''), s.quantity, 
			s.revenue, s.net_profit, COALESCE(s.commission,0), COALESCE(s.logistics_cost,0)
		FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id
		%s ORDER BY s.sale_date DESC`, where)

	rows, err := h.db.Query(ctx, q, args...)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error"})
		return
	}
	defer rows.Close()

	var csv strings.Builder
	csv.WriteString("\xEF\xBB\xBF")
	csv.WriteString("Дата,Товар,SKU,Категория,Маркетплейс,Кол-во,Выручка,Прибыль,Комиссия,Логистика\n")

	for rows.Next() {
		var saleDate time.Time
		var pName, pSku, cName, mName string
		var qty int
		var rev, prof, comm, logi float64
		if err := rows.Scan(&saleDate, &pName, &pSku, &cName, &mName, &qty, &rev, &prof, &comm, &logi); err != nil {
			continue
		}

		pName = csvEscape(pName)
		pSku = csvEscape(pSku)
		cName = csvEscape(cName)
		mName = csvEscape(mName)

		csv.WriteString(fmt.Sprintf("%s,%s,%s,%s,%s,%d,%.2f,%.2f,%.2f,%.2f\n",
			saleDate.Format("2006-01-02"), pName, pSku, cName, mName,
			qty, rev, prof, comm, logi))
	}

	c.Header("Content-Type", "text/csv; charset=utf-8")
	c.Header("Content-Disposition", "attachment; filename=sales-export.csv")
	c.String(200, csv.String())
}

func csvEscape(s string) string {
	if strings.ContainsAny(s, ",\"\n") {
		return "\"" + strings.ReplaceAll(s, "\"", "\"\"") + "\""
	}
	return s
}
