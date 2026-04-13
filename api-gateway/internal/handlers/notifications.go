package handlers

import (
	"fmt"
	"math"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

func (h *Handler) GetNotifications(c *gin.Context) {
	ctx := c.Request.Context()

	var alerts []gin.H
	var criticalCount, warningCount, infoCount int
	alertID := 1

	// === Stock alerts ===
	stockRows, _ := h.db.Query(ctx, `
		SELECT p.id::text, p.name, p.sku, i.quantity,
			COALESCE(daily.avg_qty, 0) as avg_daily
		FROM inventory i
		JOIN products p ON p.id = i.product_id AND p.is_active = true
		LEFT JOIN (
			SELECT product_id, AVG(daily_qty) as avg_qty FROM (
				SELECT product_id, SUM(quantity) as daily_qty
				FROM sales WHERE quantity > 0 AND sale_date >= NOW() - INTERVAL '30 days'
				GROUP BY product_id, sale_date
			) d GROUP BY product_id
		) daily ON daily.product_id = p.id
		WHERE COALESCE(daily.avg_qty, 0) > 0
		ORDER BY i.quantity / daily.avg_qty ASC
	`)
	if stockRows != nil {
		defer stockRows.Close()
		for stockRows.Next() {
			var pid, name, sku string
			var stock int
			var avgDaily float64
			stockRows.Scan(&pid, &name, &sku, &stock, &avgDaily)
			if avgDaily <= 0 {
				continue
			}
			dos := int(float64(stock) / avgDaily)
			if dos > 21 {
				continue
			}
			severity := "warning"
			alertType := "stock_low"
			title := fmt.Sprintf("Низкий остаток: %s", name)
			if dos <= 7 {
				severity = "critical"
				alertType = "stock_critical"
				title = fmt.Sprintf("Критический остаток: %s", name)
				criticalCount++
			} else {
				warningCount++
			}
			alerts = append(alerts, gin.H{
				"id": strconv.Itoa(alertID), "type": alertType, "severity": severity,
				"title":      title,
				"message":    fmt.Sprintf("Остаток %d шт, хватит на %d дней (продажи %.1f шт/день)", stock, dos, avgDaily),
				"product_id": pid, "product_name": name, "sku": sku,
				"value": dos, "threshold": 7, "created_at": time.Now().Format(time.RFC3339),
			})
			alertID++
		}
	}

	// === Sales spikes / drops ===
	salesRows, _ := h.db.Query(ctx, `
		WITH current_period AS (
			SELECT product_id, SUM(quantity) as qty, SUM(revenue) as rev
			FROM sales WHERE sale_date >= NOW() - INTERVAL '7 days' AND quantity > 0
			GROUP BY product_id
		),
		prev_period AS (
			SELECT product_id, SUM(quantity) as qty, SUM(revenue) as rev
			FROM sales WHERE sale_date >= NOW() - INTERVAL '14 days'
				AND sale_date < NOW() - INTERVAL '7 days' AND quantity > 0
			GROUP BY product_id
		)
		SELECT p.id::text, p.name, p.sku,
			COALESCE(c.qty, 0), COALESCE(pp.qty, 0),
			COALESCE(c.rev, 0), COALESCE(pp.rev, 0)
		FROM products p
		LEFT JOIN current_period c ON c.product_id = p.id
		LEFT JOIN prev_period pp ON pp.product_id = p.id
		WHERE p.is_active = true AND (COALESCE(c.qty,0) > 0 OR COALESCE(pp.qty,0) > 0)
		ORDER BY ABS(COALESCE(c.rev,0) - COALESCE(pp.rev,0)) DESC
		LIMIT 20
	`)
	if salesRows != nil {
		defer salesRows.Close()
		for salesRows.Next() {
			var pid, name, sku string
			var curQty, prevQty int
			var curRev, prevRev float64
			salesRows.Scan(&pid, &name, &sku, &curQty, &prevQty, &curRev, &prevRev)
			if prevRev <= 0 && curRev <= 0 {
				continue
			}
			chVal := 0.0
			if prevRev > 0 {
				chVal = (curRev - prevRev) / prevRev * 100
			} else if curRev > 0 {
				chVal = 100
			}
			if math.Abs(chVal) < 30 {
				continue
			}
			if chVal > 0 {
				infoCount++
				alerts = append(alerts, gin.H{
					"id": strconv.Itoa(alertID), "type": "sales_spike", "severity": "info",
					"title":      fmt.Sprintf("Всплеск продаж: %s", name),
					"message":    fmt.Sprintf("Выручка выросла на %.0f%% за последнюю неделю", chVal),
					"product_id": pid, "product_name": name, "sku": sku,
					"value": int(chVal), "created_at": time.Now().Format(time.RFC3339),
				})
			} else {
				sev := "warning"
				warningCount++
				if chVal < -60 {
					sev = "critical"
					warningCount--
					criticalCount++
				}
				alerts = append(alerts, gin.H{
					"id": strconv.Itoa(alertID), "type": "sales_drop", "severity": sev,
					"title":      fmt.Sprintf("Падение продаж: %s", name),
					"message":    fmt.Sprintf("Выручка упала на %.0f%% за последнюю неделю", math.Abs(chVal)),
					"product_id": pid, "product_name": name, "sku": sku,
					"value": int(chVal), "created_at": time.Now().Format(time.RFC3339),
				})
			}
			alertID++
		}
	}

	// === High returns ===
	retRows, _ := h.db.Query(ctx, `
		SELECT p.id::text, p.name, p.sku,
			SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) as sold,
			SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END) as returned
		FROM sales s JOIN products p ON p.id = s.product_id
		WHERE s.sale_date >= NOW() - INTERVAL '30 days' AND p.is_active = true
		GROUP BY p.id, p.name, p.sku
		HAVING SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
			AND SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)::float /
				NULLIF(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0) > 0.10
		ORDER BY SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)::float /
			NULLIF(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0) DESC
		LIMIT 10
	`)
	if retRows != nil {
		defer retRows.Close()
		for retRows.Next() {
			var pid, name, sku string
			var sold, returned int
			retRows.Scan(&pid, &name, &sku, &sold, &returned)
			retPct := float64(returned) / float64(sold) * 100
			sev := "warning"
			warningCount++
			if retPct > 25 {
				sev = "critical"
				warningCount--
				criticalCount++
			}
			alerts = append(alerts, gin.H{
				"id": strconv.Itoa(alertID), "type": "high_returns", "severity": sev,
				"title":      fmt.Sprintf("Высокий возврат: %s", name),
				"message":    fmt.Sprintf("%d возвратов из %d продаж (%.1f%%)", returned, sold, retPct),
				"product_id": pid, "product_name": name, "sku": sku,
				"value": int(retPct), "threshold": 10,
				"created_at": time.Now().Format(time.RFC3339),
			})
			alertID++
		}
	}

	if alerts == nil {
		alerts = []gin.H{}
	}

	c.JSON(200, gin.H{
		"alerts": alerts,
		"summary": gin.H{
			"total":    len(alerts),
			"critical": criticalCount,
			"warning":  warningCount,
			"info":     infoCount,
		},
	})
}
