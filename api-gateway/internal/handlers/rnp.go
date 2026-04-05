package handlers

import (
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
)

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
			(SELECT COUNT(*) FROM rnp_items WHERE template_id = t.id) as items_count,
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
		ID            int       `json:"id"`
		ProjectID     int       `json:"project_id"`
		ProjectName   string    `json:"project_name"`
		ManagerID     string    `json:"manager_id"`
		ManagerName   string    `json:"manager_name"`
		MarketplaceID int       `json:"marketplace_id"`
		Marketplace   string    `json:"marketplace"`
		Year          int       `json:"year"`
		Month         int       `json:"month"`
		Status        string    `json:"status"`
		DaysPassed    int       `json:"days_passed"`
		DaysLeft      int       `json:"days_left"`
		DaysInMonth   int       `json:"days_in_month"`
		ItemsCount    int       `json:"items_count"`
		CreatedAt     time.Time `json:"created_at"`
	}

	templates := []Template{}
	for rows.Next() {
		var t Template
		err := rows.Scan(&t.ID, &t.ProjectID, &t.ProjectName, &t.ManagerID, &t.ManagerName,
			&t.MarketplaceID, &t.Marketplace, &t.Year, &t.Month, &t.Status, &t.ItemsCount, &t.CreatedAt)
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

func (h *Handler) GetRNPItems(c *gin.Context) {
	templateID, _ := strconv.Atoi(c.Param("id"))

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
		SELECT id, nm_id, COALESCE(sku,''), COALESCE(size,'0'), COALESCE(name,''),
			COALESCE(category,''), COALESCE(season,'all_season'), COALESCE(photo_url,''),
			plan_orders_qty, plan_orders_rub, plan_price,
			fact_orders_qty, fact_orders_rub, fact_avg_price,
			stock_fbo, stock_fbs, stock_in_transit, stock_1c,
			turnover_mtd, turnover_7d, reviews_avg_rating, COALESCE(reviews_status,'')
		FROM rnp_items WHERE template_id = $1 AND is_active = true
		ORDER BY fact_orders_rub DESC NULLS LAST
	`

	rows, err := h.db.Query(c, query, templateID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	type Item struct {
		ID               int     `json:"id"`
		NmID             int64   `json:"nm_id"`
		SKU              string  `json:"sku"`
		Size             string  `json:"size"`
		Name             string  `json:"name"`
		Category         string  `json:"category"`
		Season           string  `json:"season"`
		PhotoURL         string  `json:"photo_url"`
		PlanOrdersQty    int     `json:"plan_orders_qty"`
		PlanOrdersRub    float64 `json:"plan_orders_rub"`
		PlanPrice        float64 `json:"plan_price"`
		PlanDailyAvg     float64 `json:"plan_daily_avg"`
		FactOrdersQty    int     `json:"fact_orders_qty"`
		FactOrdersRub    float64 `json:"fact_orders_rub"`
		FactAvgPrice     float64 `json:"fact_avg_price"`
		FactDailyAvg     float64 `json:"fact_daily_avg"`
		CompletionPctQty float64 `json:"completion_pct_qty"`
		CompletionStatus string  `json:"completion_status"`
		StockFBO         int     `json:"stock_fbo"`
		StockFBS         int     `json:"stock_fbs"`
		StockInTransit   int     `json:"stock_in_transit"`
		Stock1C          int     `json:"stock_1c"`
		TurnoverMTD      float64 `json:"turnover_mtd"`
		Turnover7D       float64 `json:"turnover_7d"`
		ReviewsAvgRating float64 `json:"reviews_avg_rating"`
		ReviewsStatus    string  `json:"reviews_status"`
	}

	items := []Item{}
	for rows.Next() {
		var i Item
		var turnMTD, turn7D, revRating *float64
		rows.Scan(&i.ID, &i.NmID, &i.SKU, &i.Size, &i.Name, &i.Category, &i.Season, &i.PhotoURL,
			&i.PlanOrdersQty, &i.PlanOrdersRub, &i.PlanPrice,
			&i.FactOrdersQty, &i.FactOrdersRub, &i.FactAvgPrice,
			&i.StockFBO, &i.StockFBS, &i.StockInTransit, &i.Stock1C,
			&turnMTD, &turn7D, &revRating, &i.ReviewsStatus)

		if daysInMonth > 0 {
			i.PlanDailyAvg = float64(i.PlanOrdersQty) / float64(daysInMonth)
		}
		if daysPassed > 0 {
			i.FactDailyAvg = float64(i.FactOrdersQty) / float64(daysPassed)
			expected := i.PlanDailyAvg * float64(daysPassed)
			if expected > 0 {
				i.CompletionPctQty = (float64(i.FactOrdersQty) / expected) * 100
			}
		}

		switch {
		case i.CompletionPctQty >= 100:
			i.CompletionStatus = "over"
		case i.CompletionPctQty >= 80:
			i.CompletionStatus = "ok"
		default:
			i.CompletionStatus = "under"
		}

		if turnMTD != nil {
			i.TurnoverMTD = *turnMTD
		} else if i.FactDailyAvg > 0 {
			i.TurnoverMTD = float64(i.StockFBO+i.StockFBS) / i.FactDailyAvg
		}
		if turn7D != nil {
			i.Turnover7D = *turn7D
		}
		if revRating != nil {
			i.ReviewsAvgRating = *revRating
		}

		items = append(items, i)
	}

	c.JSON(http.StatusOK, gin.H{
		"template": gin.H{
			"id": templateID, "year": year, "month": month,
			"days_passed": daysPassed, "days_left": daysInMonth - daysPassed, "days_in_month": daysInMonth,
		},
		"items": items,
		"count": len(items),
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

func (h *Handler) UpdateRNPItem(c *gin.Context) {
	itemID, _ := strconv.Atoi(c.Param("itemId"))

	var req struct {
		PlanOrdersQty *int     `json:"plan_orders_qty"`
		PlanOrdersRub *float64 `json:"plan_orders_rub"`
		PlanPrice     *float64 `json:"plan_price"`
		Season        *string  `json:"season"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, err := h.db.Exec(c, `
		UPDATE rnp_items SET 
			plan_orders_qty = COALESCE($1, plan_orders_qty),
			plan_orders_rub = COALESCE($2, plan_orders_rub),
			plan_price = COALESCE($3, plan_price),
			season = COALESCE($4, season),
			updated_at = NOW()
		WHERE id = $5
	`, req.PlanOrdersQty, req.PlanOrdersRub, req.PlanPrice, req.Season, itemID)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Обновлено"})
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

func (h *Handler) CreateRNPItem(c *gin.Context) {
	templateID, _ := strconv.Atoi(c.Param("id"))

	var req struct {
		NmID          int64   `json:"nm_id"`
		SKU           string  `json:"sku"`
		Size          string  `json:"size"`
		Name          string  `json:"name" binding:"required"`
		Category      string  `json:"category"`
		Season        string  `json:"season"`
		PhotoURL      string  `json:"photo_url"`
		PlanOrdersQty int     `json:"plan_orders_qty"`
		PlanOrdersRub float64 `json:"plan_orders_rub"`
		PlanPrice     float64 `json:"plan_price"`
	}

	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Проверяем существование шаблона
	var exists bool
	err := h.db.QueryRow(c, `SELECT EXISTS(SELECT 1 FROM rnp_templates WHERE id = $1)`, templateID).Scan(&exists)
	if err != nil || !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "Template not found"})
		return
	}

	var id int
	err = h.db.QueryRow(c, `
		INSERT INTO rnp_items (template_id, nm_id, sku, size, name, category, season, photo_url, 
			plan_orders_qty, plan_orders_rub, plan_price)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id
	`, templateID, req.NmID, req.SKU, req.Size, req.Name, req.Category, req.Season, req.PhotoURL,
		req.PlanOrdersQty, req.PlanOrdersRub, req.PlanPrice).Scan(&id)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{"id": id, "message": "Товар добавлен в РНП"})
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
