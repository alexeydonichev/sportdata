package handlers

import (
	"fmt"
	"math"
	"strconv"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetProducts(c *gin.Context) {
	ctx := c.Request.Context()
	period := c.DefaultQuery("period", "7d")
	catSlug := c.Query("category")
	mpSlug := c.Query("marketplace")
	search := c.Query("search")
	sortBy := c.DefaultQuery("sort", "revenue")
	order := c.DefaultQuery("order", "desc")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "20"))
	if page < 1 { page = 1 }
	if limit < 1 || limit > 100 { limit = 20 }
	offset := (page - 1) * limit

	dateFrom, dateTo := h.parsePeriod(period)
	prevFrom, prevTo := prevPeriod(dateFrom, dateTo)

	allowed := map[string]string{
		"revenue": "revenue", "profit": "profit",
		"quantity": "quantity", "name": "p.name",
		"margin": "margin", "orders": "orders",
	}
	col, ok := allowed[sortBy]
	if !ok { col = "revenue" }
	if order != "asc" { order = "desc" }

	j := ` FROM sales s
		LEFT JOIN products p ON p.id = s.product_id
		LEFT JOIN categories c ON c.id = p.category_id
		LEFT JOIN marketplaces m ON m.id = s.marketplace_id`

	w, a := buildSalesWhere(dateFrom, dateTo, catSlug, mpSlug)
	if search != "" {
		w += fmt.Sprintf(" AND (p.name ILIKE $%d OR p.sku ILIKE $%d)", len(a)+1, len(a)+1)
		a = append(a, "%"+search+"%")
	}

	var total int
	cntQ := fmt.Sprintf("SELECT COUNT(DISTINCT p.id) %s %s", j, w)
	_ = h.db.QueryRow(ctx, cntQ, a...).Scan(&total)

	q := fmt.Sprintf(`SELECT p.id, p.sku, p.name,
		COALESCE(SUM(s.revenue),0) as revenue,
		COALESCE(SUM(s.net_profit),0) as profit,
		COALESCE(SUM(s.quantity),0) as quantity,
		COUNT(*) as orders,
		CASE WHEN SUM(s.revenue)>0 THEN SUM(s.net_profit)/SUM(s.revenue)*100 ELSE 0 END as margin
		%s %s
		GROUP BY p.id, p.sku, p.name
		ORDER BY %s %s NULLS LAST
		LIMIT %d OFFSET %d`, j, w, col, order, limit, offset)

	rows, err := h.db.Query(ctx, q, a...)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error", "detail": err.Error()})
		return
	}
	defer rows.Close()

	pw, pa := buildSalesWhere(prevFrom, prevTo, catSlug, mpSlug)
	prevMap := map[int]gin.H{}
	pq := fmt.Sprintf(`SELECT p.id,
		COALESCE(SUM(s.revenue),0), COALESCE(SUM(s.net_profit),0),
		COALESCE(SUM(s.quantity),0)
		%s %s GROUP BY p.id`, j, pw)
	prows, perr := h.db.Query(ctx, pq, pa...)
	if perr == nil {
		defer prows.Close()
		for prows.Next() {
			var pid int
			var pr, pp float64
			var pqt int
			if prows.Scan(&pid, &pr, &pp, &pqt) == nil {
				prevMap[pid] = gin.H{"revenue": pr, "profit": pp, "quantity": pqt}
			}
		}
	}

	var items []gin.H
	for rows.Next() {
		var id int
		var sku, name string
		var rev, prof, marg float64
		var qty, ord int
		if rows.Scan(&id, &sku, &name, &rev, &prof, &qty, &ord, &marg) != nil {
			continue
		}
		item := gin.H{
			"product_id": id, "sku": sku, "name": name,
			"revenue": round2(rev), "profit": round2(prof),
			"quantity": qty, "orders": ord,
			"margin_pct": round2(marg),
		}
		if prev, ok := prevMap[id]; ok {
			pr := prev["revenue"].(float64)
			pp := prev["profit"].(float64)
			pq := prev["quantity"].(int)
			item["changes"] = gin.H{
				"revenue":  changePct(rev, pr),
				"profit":   changePct(prof, pp),
				"quantity": changePct(float64(qty), float64(pq)),
			}
		}
		items = append(items, item)
	}
	if items == nil { items = []gin.H{} }

	totalPages := int(math.Ceil(float64(total) / float64(limit)))
	c.JSON(200, gin.H{
		"items": items, "total": total, "page": page,
		"limit": limit, "total_pages": totalPages,
	})
}

func (h *Handler) GetProduct(c *gin.Context) {
	ctx := c.Request.Context()
	idStr := c.Param("id")
	id, err := strconv.Atoi(idStr)
	if err != nil {
		c.JSON(400, gin.H{"error": "invalid id"})
		return
	}

	var sku, name string
	var catName *string
	var catID *int
	var isActive bool
	var costPrice *float64
	err = h.db.QueryRow(ctx, `SELECT p.id, p.sku, p.name,
		c.name, c.id, p.cost_price, p.is_active
		FROM products p
		LEFT JOIN categories c ON c.id = p.category_id
		WHERE p.id = $1`, id).Scan(&id, &sku, &name,
		&catName, &catID, &costPrice, &isActive)
	if err != nil {
		c.JSON(404, gin.H{"error": "product not found"})
		return
	}

	var detectedMP *string
	var detectedMPID *int
	_ = h.db.QueryRow(ctx, `SELECT m.name, m.id FROM sales s
		JOIN marketplaces m ON m.id = s.marketplace_id
		WHERE s.product_id = $1 LIMIT 1`, id).Scan(&detectedMP, &detectedMPID)

	period := c.DefaultQuery("period", "30d")
	dateFrom, dateTo := h.parsePeriod(period)

	var rev, prof, comm, logi float64
	var qty, orders int
	_ = h.db.QueryRow(ctx, `SELECT COALESCE(SUM(revenue),0),
		COALESCE(SUM(net_profit),0), COALESCE(SUM(commission),0),
		COALESCE(SUM(logistics_cost),0), COALESCE(SUM(quantity),0), COUNT(*)
		FROM sales WHERE product_id=$1 AND sale_date>=$2 AND sale_date<=$3`,
		id, dateFrom, dateTo).Scan(&rev, &prof, &comm, &logi, &qty, &orders)

	catNameStr := ""
	catIDVal := 0
	mpNameStr := ""
	mpIDVal := 0
	costPriceVal := 0.0
	if catName != nil { catNameStr = *catName }
	if catID != nil { catIDVal = *catID }
	if detectedMP != nil { mpNameStr = *detectedMP }
	if detectedMPID != nil { mpIDVal = *detectedMPID }
	if costPrice != nil { costPriceVal = *costPrice }

	c.JSON(200, gin.H{
		"product_id": id, "sku": sku, "name": name,
		"category": catNameStr, "category_id": catIDVal,
		"marketplace": mpNameStr, "marketplace_id": mpIDVal,
		"is_active": isActive, "cost_price": round2(costPriceVal),
		"revenue": round2(rev), "profit": round2(prof),
		"commission": round2(comm), "logistics": round2(logi),
		"quantity": qty, "orders": orders,
		"margin_pct": round2(pct(prof, rev)),
	})
}
