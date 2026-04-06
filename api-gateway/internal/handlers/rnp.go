package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

// ============================================
// TEMPLATES
// ============================================

func (h *Handler) GetRNPTemplates(c *gin.Context) {
	userID := c.GetString("user_id")
	roleLevel := c.GetInt("role_level")

	year, _ := strconv.Atoi(c.DefaultQuery("year", strconv.Itoa(time.Now().Year())))
	month, _ := strconv.Atoi(c.DefaultQuery("month", strconv.Itoa(int(time.Now().Month()))))

	now := time.Now()
	daysInMonth := time.Date(year, time.Month(month)+1, 0, 0, 0, 0, 0, time.UTC).Day()
	daysPassed := 0
	if year == now.Year() && int(now.Month()) == month {
		daysPassed = now.Day()
	} else if time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC).Before(now) {
		daysPassed = daysInMonth
	}

	query := `
		SELECT 
			t.id, t.project_id, p.name as project_name,
			t.manager_id, COALESCE(u.first_name || ' ' || u.last_name, u.email) as manager_name,
			t.marketplace_id, m.name as marketplace,
			t.year, t.month, t.status,
			(SELECT COUNT(*) FROM rnp_items WHERE template_id = t.id AND is_active = true) as items_count,
			(SELECT COUNT(*) FROM rnp_items WHERE template_id = t.id AND needs_attention = true) as attention_count,
			t.created_at
		FROM rnp_templates t
		JOIN projects p ON t.project_id = p.id
		JOIN users u ON t.manager_id = u.id
		JOIN marketplaces m ON t.marketplace_id = m.id
		WHERE t.year = $1 AND t.month = $2
		AND ($3 <= 2 OR t.manager_id = $4 OR t.project_id IN (
			SELECT project_id FROM project_members WHERE user_id = $4
		))
		ORDER BY p.name, u.last_name
	`

	rows, err := h.db.Query(c, query, year, month, roleLevel, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type Template struct {
		ID             int       `json:"id"`
		ProjectID      int       `json:"project_id"`
		ProjectName    string    `json:"project_name"`
		ManagerID      string    `json:"manager_id"`
		ManagerName    string    `json:"manager_name"`
		MarketplaceID  int       `json:"marketplace_id"`
		Marketplace    string    `json:"marketplace"`
		Year           int       `json:"year"`
		Month          int       `json:"month"`
		Status         string    `json:"status"`
		DaysPassed     int       `json:"days_passed"`
		DaysLeft       int       `json:"days_left"`
		DaysInMonth    int       `json:"days_in_month"`
		ItemsCount     int       `json:"items_count"`
		AttentionCount int       `json:"attention_count"`
		CreatedAt      time.Time `json:"created_at"`
	}

	templates := []Template{}
	for rows.Next() {
		var t Template
		err := rows.Scan(&t.ID, &t.ProjectID, &t.ProjectName, &t.ManagerID, &t.ManagerName,
			&t.MarketplaceID, &t.Marketplace, &t.Year, &t.Month, &t.Status,
			&t.ItemsCount, &t.AttentionCount, &t.CreatedAt)
		if err != nil {
			continue
		}
		t.DaysInMonth = daysInMonth
		t.DaysPassed = daysPassed
		t.DaysLeft = daysInMonth - daysPassed
		templates = append(templates, t)
	}

	c.JSON(http.StatusOK, gin.H{
		"year":      year,
		"month":     month,
		"templates": templates,
	})
}

func (h *Handler) CreateRNPTemplate(c *gin.Context) {
	var req struct {
		ProjectID     int    `json:"project_id" binding:"required"`
		ManagerID     string `json:"manager_id" binding:"required"`
		MarketplaceID int    `json:"marketplace_id" binding:"required"`
		Year          int    `json:"year"`
		Month         int    `json:"month"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	if req.Year == 0 {
		req.Year = time.Now().Year()
	}
	if req.Month == 0 {
		req.Month = int(time.Now().Month())
	}

	var id int
	err := h.db.QueryRow(c, `
		INSERT INTO rnp_templates (project_id, manager_id, marketplace_id, year, month)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (manager_id, marketplace_id, year, month) DO UPDATE SET status = 'active'
		RETURNING id
	`, req.ProjectID, req.ManagerID, req.MarketplaceID, req.Year, req.Month).Scan(&id)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"id": id, "message": "РНП создан"})
}

func (h *Handler) GetProjects(c *gin.Context) {
	rows, err := h.db.Query(c, `SELECT id, name, slug FROM projects WHERE is_active = true ORDER BY name`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type Project struct {
		ID   int    `json:"id"`
		Name string `json:"name"`
		Slug string `json:"slug"`
	}
	projects := []Project{}
	for rows.Next() {
		var p Project
		rows.Scan(&p.ID, &p.Name, &p.Slug)
		projects = append(projects, p)
	}
	c.JSON(http.StatusOK, gin.H{"data": projects})
}

func (h *Handler) GetManagers(c *gin.Context) {
	query := `
		SELECT u.id, u.first_name, u.last_name, u.email, r.name as role
		FROM users u
		JOIN roles r ON u.role_id = r.id
		WHERE u.is_active = true AND u.is_hidden = false
		ORDER BY u.last_name, u.first_name
	`

	rows, err := h.db.Query(c, query)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type Manager struct {
		ID        string `json:"id"`
		FirstName string `json:"first_name"`
		LastName  string `json:"last_name"`
		Email     string `json:"email"`
		Role      string `json:"role"`
		FullName  string `json:"full_name"`
	}

	managers := []Manager{}
	for rows.Next() {
		var m Manager
		rows.Scan(&m.ID, &m.FirstName, &m.LastName, &m.Email, &m.Role)
		m.FullName = m.FirstName + " " + m.LastName
		managers = append(managers, m)
	}

	c.JSON(http.StatusOK, gin.H{"data": managers})
}

// ============================================
// ITEMS - Рука на пульсе
// ============================================

func (h *Handler) GetRNPItems(c *gin.Context) {
	templateID, _ := strconv.Atoi(c.Param("id"))

	status := c.Query("status")
	needsAttention := c.Query("attention")
	reviewsOk := c.Query("reviews_ok")

	var year, month int
	err := h.db.QueryRow(c, `SELECT year, month FROM rnp_templates WHERE id = $1`, templateID).Scan(&year, &month)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	now := time.Now()
	daysInMonth := time.Date(year, time.Month(month)+1, 0, 0, 0, 0, 0, time.UTC).Day()
	daysPassed := 0
	if year == now.Year() && int(now.Month()) == month {
		daysPassed = now.Day()
	} else if time.Date(year, time.Month(month), 1, 0, 0, 0, 0, time.UTC).Before(now) {
		daysPassed = daysInMonth
	}

	query := `
		SELECT 
			id, nm_id, COALESCE(sku,''), COALESCE(size,''), COALESCE(name,''),
			COALESCE(category,''), COALESCE(photo_url,''),
			COALESCE(status::text, 'liquidation'),
			plan_orders_qty, target_orders_day, plan_price, weekly_task_plan,
			fact_orders_qty, fact_orders_rub, fact_avg_price, spp_percent,
			stock_fbo, stock_fbs, days_of_stock, days_of_stock_7d,
			review_1_stars, review_2_stars, review_3_stars, reviews_ok,
			COALESCE(content_task_url,''), COALESCE(checklist_url,''), COALESCE(monitoring_url,''),
			has_discount, needs_attention,
			COALESCE(notes,''),
			(SELECT COUNT(*) FILTER (WHERE is_done) FROM rnp_checklist_items ci WHERE ci.item_id = rnp_items.id),
			(SELECT COUNT(*) FROM rnp_checklist_items ci WHERE ci.item_id = rnp_items.id)
		FROM rnp_items 
		WHERE template_id = $1 AND is_active = true
		AND ($2 = '' OR status::text = $2)
		AND ($3 = '' OR needs_attention = ($3 = 'true'))
		AND ($4 = '' OR reviews_ok = ($4 = 'true'))
		ORDER BY needs_attention DESC, fact_orders_rub DESC NULLS LAST
	`

	rows, err := h.db.Query(c, query, templateID, status, needsAttention, reviewsOk)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type Item struct {
		ID                int      `json:"id"`
		NmID              *int64   `json:"nm_id"`
		SKU               string   `json:"sku"`
		Size              string   `json:"size"`
		Name              string   `json:"name"`
		Category          string   `json:"category"`
		PhotoURL          string   `json:"photo_url"`
		Status            string   `json:"status"`
		TargetOrdersMonth int      `json:"target_orders_month"`
		TargetOrdersDay   int      `json:"target_orders_day"`
		PlanPrice         *float64 `json:"plan_price"`
		WeeklyTaskPlan    int      `json:"weekly_task_plan"`
		FactOrdersQty     int      `json:"fact_orders_qty"`
		FactOrdersRub     *float64 `json:"fact_orders_rub"`
		FactPrice         *float64 `json:"fact_price"`
		SPPPercent        float64  `json:"spp_percent"`
		StockFBO          int      `json:"stock_fbo"`
		StockFBS          int      `json:"stock_fbs"`
		StockTotal        int      `json:"stock_total"`
		DaysOfStock       int      `json:"days_of_stock"`
		DaysOfStock7D     int      `json:"days_of_stock_7d"`
		Review1Stars      *int     `json:"review_1_stars"`
		Review2Stars      *int     `json:"review_2_stars"`
		Review3Stars      *int     `json:"review_3_stars"`
		ReviewsOk         bool     `json:"reviews_ok"`
		TZContentURL      string   `json:"tz_content_url"`
		ChecklistURL      string   `json:"checklist_url"`
		MonitoringURL     string   `json:"monitoring_url"`
		HasDiscount       bool     `json:"has_discount"`
		NeedsAttention    bool     `json:"needs_attention"`
		Comment           string   `json:"comment"`
		ChecklistDone     int      `json:"checklist_done"`
		ChecklistTotal    int      `json:"checklist_total"`
		CompletionPercent float64  `json:"completion_percent"`
		CompletionStatus  string   `json:"completion_status"`
		PlanDailyAvg      float64  `json:"plan_daily_avg"`
		FactDailyAvg      float64  `json:"fact_daily_avg"`
	}

	items := []Item{}
	for rows.Next() {
		var i Item
		err := rows.Scan(
			&i.ID, &i.NmID, &i.SKU, &i.Size, &i.Name, &i.Category, &i.PhotoURL, &i.Status,
			&i.TargetOrdersMonth, &i.TargetOrdersDay, &i.PlanPrice, &i.WeeklyTaskPlan,
			&i.FactOrdersQty, &i.FactOrdersRub, &i.FactPrice, &i.SPPPercent,
			&i.StockFBO, &i.StockFBS, &i.DaysOfStock, &i.DaysOfStock7D,
			&i.Review1Stars, &i.Review2Stars, &i.Review3Stars, &i.ReviewsOk,
			&i.TZContentURL, &i.ChecklistURL, &i.MonitoringURL,
			&i.HasDiscount, &i.NeedsAttention, &i.Comment,
			&i.ChecklistDone, &i.ChecklistTotal,
		)
		if err != nil {
			continue
		}

		i.StockTotal = i.StockFBO + i.StockFBS

		if daysInMonth > 0 {
			i.PlanDailyAvg = float64(i.TargetOrdersMonth) / float64(daysInMonth)
		}
		if daysPassed > 0 {
			i.FactDailyAvg = float64(i.FactOrdersQty) / float64(daysPassed)
			expected := i.PlanDailyAvg * float64(daysPassed)
			if expected > 0 {
				i.CompletionPercent = (float64(i.FactOrdersQty) / expected) * 100
			}
		}

		switch {
		case i.CompletionPercent >= 100:
			i.CompletionStatus = "over"
		case i.CompletionPercent >= 80:
			i.CompletionStatus = "ok"
		case i.CompletionPercent >= 50:
			i.CompletionStatus = "warning"
		default:
			i.CompletionStatus = "under"
		}

		items = append(items, i)
	}

	var totalItems, attentionItems, reviewsIssues int
	for _, i := range items {
		totalItems++
		if i.NeedsAttention {
			attentionItems++
		}
		if !i.ReviewsOk {
			reviewsIssues++
		}
	}

	c.JSON(http.StatusOK, gin.H{
		"template": gin.H{
			"id": templateID, "year": year, "month": month,
			"days_passed": daysPassed, "days_left": daysInMonth - daysPassed, "days_in_month": daysInMonth,
		},
		"stats": gin.H{
			"total": totalItems, "needs_attention": attentionItems, "reviews_issues": reviewsIssues,
		},
		"items": items,
		"count": len(items),
	})
}

// ============================================
// CREATE / UPDATE / DELETE ITEMS
// ============================================

func (h *Handler) CreateRNPItem(c *gin.Context) {
	templateID, _ := strconv.Atoi(c.Param("id"))

	var req struct {
		NmID              int64   `json:"nm_id"`
		SKU               string  `json:"sku"`
		Size              string  `json:"size"`
		Name              string  `json:"name" binding:"required"`
		Category          string  `json:"category"`
		PhotoURL          string  `json:"photo_url"`
		Status            string  `json:"status"`
		TargetOrdersMonth int     `json:"target_orders_month"`
		TargetOrdersDay   int     `json:"target_orders_day"`
		PlanPrice         float64 `json:"plan_price"`
		TZContentURL      string  `json:"tz_content_url"`
		MonitoringURL     string  `json:"monitoring_url"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var exists bool
	err := h.db.QueryRow(c, `SELECT EXISTS(SELECT 1 FROM rnp_templates WHERE id = $1)`, templateID).Scan(&exists)
	if err != nil || !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	if req.Status == "" {
		req.Status = "liquidation"
	}

	if req.TargetOrdersDay == 0 && req.TargetOrdersMonth > 0 {
		req.TargetOrdersDay = (req.TargetOrdersMonth + 29) / 30
	}

	var id int
	err = h.db.QueryRow(c, `
		INSERT INTO rnp_items (
			template_id, nm_id, sku, size, name, category, photo_url, status,
			plan_orders_qty, target_orders_day, plan_price,
			content_task_url, monitoring_url
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8::rnp_status, $9, $10, $11, $12, $13)
		RETURNING id
	`, templateID, req.NmID, req.SKU, req.Size, req.Name, req.Category, req.PhotoURL, req.Status,
		req.TargetOrdersMonth, req.TargetOrdersDay, req.PlanPrice,
		req.TZContentURL, req.MonitoringURL).Scan(&id)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"id": id, "message": "Товар добавлен в РНП"})
}

func (h *Handler) UpdateRNPItem(c *gin.Context) {
	itemID, _ := strconv.Atoi(c.Param("itemId"))

	var req struct {
		Status            *string  `json:"status"`
		TargetOrdersMonth *int     `json:"target_orders_month"`
		TargetOrdersDay   *int     `json:"target_orders_day"`
		PlanPrice         *float64 `json:"plan_price"`
		WeeklyTaskPlan    *int     `json:"weekly_task_plan"`
		FactPrice         *float64 `json:"fact_price"`
		SPPPercent        *float64 `json:"spp_percent"`
		StockFBO          *int     `json:"stock_fbo"`
		StockFBS          *int     `json:"stock_fbs"`
		DaysOfStock       *int     `json:"days_of_stock"`
		DaysOfStock7D     *int     `json:"days_of_stock_7d"`
		Review1Stars      *int     `json:"review_1_stars"`
		Review2Stars      *int     `json:"review_2_stars"`
		Review3Stars      *int     `json:"review_3_stars"`
		HasDiscount       *bool    `json:"has_discount"`
		TZContentURL      *string  `json:"tz_content_url"`
		MonitoringURL     *string  `json:"monitoring_url"`
		Comment           *string  `json:"comment"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.db.Exec(c, `
		UPDATE rnp_items SET 
			status = COALESCE($1::rnp_status, status),
			plan_orders_qty = COALESCE($2, plan_orders_qty),
			target_orders_day = COALESCE($3, target_orders_day),
			plan_price = COALESCE($4, plan_price),
			weekly_task_plan = COALESCE($5, weekly_task_plan),
			fact_avg_price = COALESCE($6, fact_avg_price),
			spp_percent = COALESCE($7, spp_percent),
			stock_fbo = COALESCE($8, stock_fbo),
			stock_fbs = COALESCE($9, stock_fbs),
			days_of_stock = COALESCE($10, days_of_stock),
			days_of_stock_7d = COALESCE($11, days_of_stock_7d),
			review_1_stars = COALESCE($12, review_1_stars),
			review_2_stars = COALESCE($13, review_2_stars),
			review_3_stars = COALESCE($14, review_3_stars),
			has_discount = COALESCE($15, has_discount),
			content_task_url = COALESCE($16, content_task_url),
			monitoring_url = COALESCE($17, monitoring_url),
			notes = COALESCE($18, notes),
			updated_at = NOW()
		WHERE id = $19
	`, req.Status, req.TargetOrdersMonth, req.TargetOrdersDay, req.PlanPrice, req.WeeklyTaskPlan,
		req.FactPrice, req.SPPPercent, req.StockFBO, req.StockFBS, req.DaysOfStock, req.DaysOfStock7D,
		req.Review1Stars, req.Review2Stars, req.Review3Stars, req.HasDiscount,
		req.TZContentURL, req.MonitoringURL, req.Comment, itemID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Обновлено"})
}

func (h *Handler) DeleteRNPItem(c *gin.Context) {
	itemID, _ := strconv.Atoi(c.Param("itemId"))

	_, err := h.db.Exec(c, `UPDATE rnp_items SET is_active = false, updated_at = NOW() WHERE id = $1`, itemID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Удалено"})
}

// ============================================
// DAILY STATS
// ============================================

func (h *Handler) GetRNPDailyStats(c *gin.Context) {
	itemID, _ := strconv.Atoi(c.Param("itemId"))
	days, _ := strconv.Atoi(c.DefaultQuery("days", "30"))

	rows, err := h.db.Query(c, `
		SELECT fact_date, target_orders_qty, fact_orders_qty, fact_orders_rub,
			   stock_fbo, stock_fbs, current_price, discount_percent, spp_percent,
			   COALESCE(comment, '')
		FROM rnp_daily_facts
		WHERE item_id = $1 AND fact_date >= CURRENT_DATE - INTERVAL '1 day' * $2
		ORDER BY fact_date DESC
	`, itemID, days)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type DailyStat struct {
		Date            string   `json:"date"`
		TargetOrders    int      `json:"target_orders"`
		FactOrders      int      `json:"fact_orders"`
		FactOrdersRub   *float64 `json:"fact_orders_rub"`
		StockFBO        int      `json:"stock_fbo"`
		StockFBS        int      `json:"stock_fbs"`
		CurrentPrice    *float64 `json:"current_price"`
		DiscountPercent float64  `json:"discount_percent"`
		SPPPercent      float64  `json:"spp_percent"`
		Comment         string   `json:"comment"`
	}

	stats := []DailyStat{}
	for rows.Next() {
		var s DailyStat
		var date time.Time
		rows.Scan(&date, &s.TargetOrders, &s.FactOrders, &s.FactOrdersRub,
			&s.StockFBO, &s.StockFBS, &s.CurrentPrice, &s.DiscountPercent, &s.SPPPercent, &s.Comment)
		s.Date = date.Format("2006-01-02")
		stats = append(stats, s)
	}

	c.JSON(http.StatusOK, gin.H{"item_id": itemID, "stats": stats})
}

func (h *Handler) SaveRNPDailyStat(c *gin.Context) {
	itemID, _ := strconv.Atoi(c.Param("itemId"))

	var req struct {
		Date            string   `json:"date" binding:"required"`
		TargetOrders    *int     `json:"target_orders"`
		FactOrders      *int     `json:"fact_orders"`
		FactOrdersRub   *float64 `json:"fact_orders_rub"`
		StockFBO        *int     `json:"stock_fbo"`
		StockFBS        *int     `json:"stock_fbs"`
		CurrentPrice    *float64 `json:"current_price"`
		DiscountPercent *float64 `json:"discount_percent"`
		SPPPercent      *float64 `json:"spp_percent"`
		Comment         *string  `json:"comment"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.db.Exec(c, `
		INSERT INTO rnp_daily_facts (item_id, fact_date, target_orders_qty, fact_orders_qty, fact_orders_rub,
			stock_fbo, stock_fbs, current_price, discount_percent, spp_percent, comment)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		ON CONFLICT (item_id, fact_date) DO UPDATE SET
			target_orders_qty = COALESCE($3, rnp_daily_facts.target_orders_qty),
			fact_orders_qty = COALESCE($4, rnp_daily_facts.fact_orders_qty),
			fact_orders_rub = COALESCE($5, rnp_daily_facts.fact_orders_rub),
			stock_fbo = COALESCE($6, rnp_daily_facts.stock_fbo),
			stock_fbs = COALESCE($7, rnp_daily_facts.stock_fbs),
			current_price = COALESCE($8, rnp_daily_facts.current_price),
			discount_percent = COALESCE($9, rnp_daily_facts.discount_percent),
			spp_percent = COALESCE($10, rnp_daily_facts.spp_percent),
			comment = COALESCE($11, rnp_daily_facts.comment)
	`, itemID, req.Date, req.TargetOrders, req.FactOrders, req.FactOrdersRub,
		req.StockFBO, req.StockFBS, req.CurrentPrice, req.DiscountPercent, req.SPPPercent, req.Comment)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Сохранено"})
}

// ============================================
// CHECKLIST
// ============================================

func (h *Handler) GetRNPChecklist(c *gin.Context) {
	itemID, _ := strconv.Atoi(c.Param("itemId"))

	rows, err := h.db.Query(c, `
		SELECT ci.id, ci.template_id, ct.name, ci.is_done, ci.done_at,
			   COALESCE(u.first_name || ' ' || u.last_name, ''), COALESCE(ci.comment, '')
		FROM rnp_checklist_items ci
		JOIN rnp_checklist_templates ct ON ct.id = ci.template_id
		LEFT JOIN users u ON u.id = ci.done_by
		WHERE ci.item_id = $1
		ORDER BY ct.sort_order
	`, itemID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type ChecklistItem struct {
		ID         int        `json:"id"`
		TemplateID int        `json:"template_id"`
		Name       string     `json:"name"`
		IsDone     bool       `json:"is_done"`
		DoneAt     *time.Time `json:"done_at"`
		DoneBy     string     `json:"done_by"`
		Comment    string     `json:"comment"`
	}

	items := []ChecklistItem{}
	for rows.Next() {
		var i ChecklistItem
		rows.Scan(&i.ID, &i.TemplateID, &i.Name, &i.IsDone, &i.DoneAt, &i.DoneBy, &i.Comment)
		items = append(items, i)
	}

	c.JSON(http.StatusOK, gin.H{"item_id": itemID, "checklist": items})
}

func (h *Handler) InitRNPChecklist(c *gin.Context) {
	itemID, _ := strconv.Atoi(c.Param("itemId"))

	_, err := h.db.Exec(c, `
		INSERT INTO rnp_checklist_items (item_id, template_id)
		SELECT $1, id FROM rnp_checklist_templates WHERE is_active = true
		ON CONFLICT (item_id, template_id) DO NOTHING
	`, itemID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Чек-лист инициализирован"})
}

func (h *Handler) UpdateRNPChecklistItem(c *gin.Context) {
	checklistID, _ := strconv.Atoi(c.Param("checklistId"))
	userID := c.GetString("user_id")

	var req struct {
		IsDone  *bool   `json:"is_done"`
		Comment *string `json:"comment"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var doneAt interface{} = nil
	var doneBy interface{} = nil
	if req.IsDone != nil && *req.IsDone {
		doneAt = time.Now()
		doneBy = userID
	}

	_, err := h.db.Exec(c, `
		UPDATE rnp_checklist_items SET
			is_done = COALESCE($1, is_done),
			done_at = CASE WHEN $1 = true THEN $2 ELSE done_at END,
			done_by = CASE WHEN $1 = true THEN $3 ELSE done_by END,
			comment = COALESCE($4, comment)
		WHERE id = $5
	`, req.IsDone, doneAt, doneBy, req.Comment, checklistID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Обновлено"})
}

func (h *Handler) GetChecklistTemplates(c *gin.Context) {
	rows, err := h.db.Query(c, `
		SELECT id, name, sort_order FROM rnp_checklist_templates 
		WHERE is_active = true ORDER BY sort_order
	`)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type Template struct {
		ID        int    `json:"id"`
		Name      string `json:"name"`
		SortOrder int    `json:"sort_order"`
	}

	templates := []Template{}
	for rows.Next() {
		var t Template
		rows.Scan(&t.ID, &t.Name, &t.SortOrder)
		templates = append(templates, t)
	}

	c.JSON(http.StatusOK, gin.H{"templates": templates})
}
