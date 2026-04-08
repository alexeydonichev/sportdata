package handlers

import (
	"encoding/csv"
	"encoding/json"
	"fmt"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/xuri/excelize/v2"
)

type ExportData struct {
	Title     string
	Period    string
	Generated time.Time
	Headers   []string
	Rows      [][]interface{}
	Summary   map[string]interface{}
}

func parsePeriodDays(p string) int {
	switch p {
	case "7d":
		return 7
	case "14d":
		return 14
	case "90d":
		return 90
	default:
		return 30
	}
}

func periodLabel(p string) string {
	switch p {
	case "7d":
		return "7 дней"
	case "14d":
		return "14 дней"
	case "90d":
		return "90 дней"
	default:
		return "30 дней"
	}
}

type csvBuffer struct{ buf *[]byte }

func (b *csvBuffer) Write(p []byte) (int, error) {
	*b.buf = append(*b.buf, p...)
	return len(p), nil
}

func generateCSV(data *ExportData) []byte {
	var buf []byte
	w := csv.NewWriter(&csvBuffer{buf: &buf})
	w.Write(data.Headers)
	for _, row := range data.Rows {
		strRow := make([]string, len(row))
		for i, v := range row {
			strRow[i] = fmt.Sprintf("%v", v)
		}
		w.Write(strRow)
	}
	w.Flush()
	return buf
}

func generateJSON(data *ExportData) ([]byte, error) {
	return json.Marshal(map[string]interface{}{
		"title": data.Title, "period": data.Period, "generated": data.Generated,
		"headers": data.Headers, "rows": data.Rows, "summary": data.Summary,
	})
}

func generateExcel(data *ExportData) ([]byte, error) {
	f := excelize.NewFile()
	sheet := "Report"
	f.SetSheetName("Sheet1", sheet)
	for i, h := range data.Headers {
		cell, _ := excelize.CoordinatesToCellName(i+1, 1)
		f.SetCellValue(sheet, cell, h)
	}
	for ri, row := range data.Rows {
		for ci, val := range row {
			cell, _ := excelize.CoordinatesToCellName(ci+1, ri+2)
			f.SetCellValue(sheet, cell, val)
		}
	}
	buf, err := f.WriteToBuffer()
	if err != nil {
		return nil, err
	}
	return buf.Bytes(), nil
}

func (h *Handler) sendExport(c *gin.Context, data *ExportData, fname string) {
	format := c.DefaultQuery("format", "xlsx")
	switch format {
	case "json":
		d, _ := generateJSON(data)
		c.Data(200, "application/json", d)
	case "csv":
		c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s.csv", fname))
		c.Data(200, "text/csv", generateCSV(data))
	default:
		d, _ := generateExcel(data)
		c.Header("Content-Disposition", fmt.Sprintf("attachment; filename=%s.xlsx", fname))
		c.Data(200, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", d)
	}
}

func (h *Handler) ExportSales(c *gin.Context) {
	period := c.DefaultQuery("period", "30d")
	days := parsePeriodDays(period)
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT s.id, s.sale_date, COALESCE(p.name,''), s.quantity, s.revenue
		FROM sales s
		LEFT JOIN products p ON s.product_id=p.id
		WHERE s.sale_date >= NOW() - INTERVAL '1 day' * $1
		ORDER BY s.sale_date DESC`, days)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error", "details": err.Error()})
		return
	}
	defer rows.Close()
	data := &ExportData{Title: "Продажи", Period: periodLabel(period), Generated: time.Now(),
		Headers: []string{"ID", "Дата", "Товар", "Колво", "Сумма"}}
	for rows.Next() {
		var id int
		var name string
		var qty int
		var amt float64
		var dt time.Time
		rows.Scan(&id, &dt, &name, &qty, &amt)
		data.Rows = append(data.Rows, []interface{}{id, dt.Format("2006-01-02"), name, qty, amt})
	}
	h.sendExport(c, data, "sales")
}

func (h *Handler) ExportProducts(c *gin.Context) {
	format := c.DefaultQuery("format", "xlsx")
	rows, err := h.db.Query(c.Request.Context(), `
		SELECT p.id, p.sku, p.name, COALESCE(p.brand,''), 
		COALESCE(c.name,'') as category,
		COALESCE(p.cost_price,0), p.is_active, p.created_at
		FROM products p 
		LEFT JOIN categories c ON p.category_id=c.id 
		ORDER BY p.name`)
	if err != nil {
		c.JSON(500, gin.H{"error": "db error", "details": err.Error()})
		return
	}
	defer rows.Close()
	type P struct {
		ID, SKU, Name, Brand, Category, Created string
		CostPrice                               float64
		IsActive                                bool
	}
	var ps []P
	for rows.Next() {
		var p P
		var id int
		var dt time.Time
		var cost string
		if err := rows.Scan(&id, &p.SKU, &p.Name, &p.Brand, &p.Category, &cost, &p.IsActive, &dt); err != nil {
			c.JSON(500, gin.H{"error": "scan", "details": err.Error()})
			return
		}
		p.ID = fmt.Sprintf("%d", id)
		fmt.Sscanf(cost, "%f", &p.CostPrice)
		p.Created = dt.Format("2006-01-02")
		ps = append(ps, p)
	}
	if format == "json" {
		c.JSON(200, gin.H{"products": ps, "total": len(ps)})
		return
	}
	f := excelize.NewFile()
	f.SetSheetName("Sheet1", "Products")
	hdrs := []string{"ID", "SKU", "Название", "Бренд", "Категория", "Себестоимость", "Активен", "Создан"}
	for i, h := range hdrs {
		cell, _ := excelize.CoordinatesToCellName(i+1, 1)
		f.SetCellValue("Products", cell, h)
	}
	for i, p := range ps {
		r := i + 2
		f.SetCellValue("Products", fmt.Sprintf("A%d", r), p.ID)
		f.SetCellValue("Products", fmt.Sprintf("B%d", r), p.SKU)
		f.SetCellValue("Products", fmt.Sprintf("C%d", r), p.Name)
		f.SetCellValue("Products", fmt.Sprintf("D%d", r), p.Brand)
		f.SetCellValue("Products", fmt.Sprintf("E%d", r), p.Category)
		f.SetCellValue("Products", fmt.Sprintf("F%d", r), p.CostPrice)
		f.SetCellValue("Products", fmt.Sprintf("G%d", r), p.IsActive)
		f.SetCellValue("Products", fmt.Sprintf("H%d", r), p.Created)
	}
	buf, _ := f.WriteToBuffer()
	c.Header("Content-Disposition", "attachment; filename=products.xlsx")
	c.Data(200, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", buf.Bytes())
}

func (h *Handler) ExportAnalytics(c *gin.Context) {
	format := c.DefaultQuery("format", "xlsx")
	period := c.DefaultQuery("period", "30d")
	days := parsePeriodDays(period)
	row := h.db.QueryRow(c.Request.Context(), `
		SELECT COALESCE(SUM(revenue),0), COUNT(*), COALESCE(AVG(revenue),0)
		FROM sales WHERE sale_date >= NOW() - INTERVAL '1 day' * $1`, days)
	var rev, avg float64
	var cnt int
	row.Scan(&rev, &cnt, &avg)
	if format == "json" {
		c.JSON(200, gin.H{"period": periodLabel(period), "revenue": rev, "orders": cnt, "avg": avg})
		return
	}
	f := excelize.NewFile()
	f.SetSheetName("Sheet1", "Analytics")
	f.SetCellValue("Analytics", "A1", "Показатель")
	f.SetCellValue("Analytics", "B1", "Значение")
	f.SetCellValue("Analytics", "A2", "Период")
	f.SetCellValue("Analytics", "B2", periodLabel(period))
	f.SetCellValue("Analytics", "A3", "Выручка")
	f.SetCellValue("Analytics", "B3", rev)
	f.SetCellValue("Analytics", "A4", "Заказы")
	f.SetCellValue("Analytics", "B4", cnt)
	f.SetCellValue("Analytics", "A5", "Ср.чек")
	f.SetCellValue("Analytics", "B5", avg)
	buf, _ := f.WriteToBuffer()
	c.Header("Content-Disposition", "attachment; filename=analytics.xlsx")
	c.Data(200, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", buf.Bytes())
}
