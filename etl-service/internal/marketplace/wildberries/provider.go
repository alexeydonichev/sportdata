package wildberries

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"sportdata-etl/internal/models"
)

type Provider struct {
	db *pgxpool.Pool
}

func NewProvider(db *pgxpool.Pool) *Provider {
	return &Provider{db: db}
}

func (p *Provider) Name() string            { return "Wildberries" }
func (p *Provider) MarketplaceSlug() string { return "wildberries" }

func (p *Provider) SyncSales(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error) {
	client := NewClient(apiKey)

	log.Printf("[wb] Fetching sales from Report Detail API: %s to %s", dateFrom.Format("2006-01-02"), dateTo.Format("2006-01-02"))

	items, err := client.GetReportDetailByWeeks(dateFrom, dateTo)
	if err != nil {
		return 0, fmt.Errorf("fetch report detail: %w", err)
	}

	if len(items) == 0 {
		log.Printf("[wb] No items found")
		return 0, nil
	}

	log.Printf("[wb] Got %d report items, processing...", len(items))

	mpID := cred.MarketplaceID

	p.ensureCategoriesFromReport(ctx, items)
	p.ensureProductsFromReport(ctx, items)

	// Дедуплицируем по ключу (srid + sale_date) ПЕРЕД батчами
	dedupItems := p.deduplicateItems(items)
	log.Printf("[wb] After dedup: %d unique records", len(dedupItems))

	processed := 0
	const batchSize = 500

	for i := 0; i < len(dedupItems); i += batchSize {
		end := i + batchSize
		if end > len(dedupItems) {
			end = len(dedupItems)
		}
		batch := dedupItems[i:end]

		n, err := p.insertSalesFromReportBatch(ctx, batch, mpID)
		if err != nil {
			log.Printf("[wb] batch %d-%d error: %v", i, end, err)
			continue
		}
		processed += n
	}

	log.Printf("[wb] Processed %d sales records", processed)
	return processed, nil
}

// deduplicateItems убирает дубликаты по ключу srid+sale_date
func (p *Provider) deduplicateItems(items []ReportDetailItem) []ReportDetailItem {
	seen := make(map[string]int)
	result := make([]ReportDetailItem, 0, len(items))

	for _, item := range items {
		srid := item.SRId
		if srid == "" {
			continue
		}

		saleDate := item.SaleDt
		if saleDate == "" {
			saleDate = item.RRDt
		}
		if len(saleDate) >= 10 {
			saleDate = saleDate[:10]
		}

		key := srid + "|" + saleDate

		if idx, exists := seen[key]; exists {
			result[idx].Quantity += item.Quantity
			result[idx].RetailAmount += item.RetailAmount
			result[idx].PPVZForPay += item.PPVZForPay
			result[idx].PPVZSalesCommission += item.PPVZSalesCommission
			result[idx].DeliveryRub += item.DeliveryRub
			result[idx].RebillLogisticCost += item.RebillLogisticCost
			result[idx].Penalty += item.Penalty
		} else {
			seen[key] = len(result)
			result = append(result, item)
		}
	}

	return result
}

func (p *Provider) insertSalesFromReportBatch(ctx context.Context, items []ReportDetailItem, mpID int) (int, error) {
	if len(items) == 0 {
		return 0, nil
	}

	var sb strings.Builder
	args := make([]interface{}, 0, len(items)*27)
	idx := 0
	count := 0

	for _, item := range items {
		srid := item.SRId
		if srid == "" {
			continue
		}

		productID := p.resolveProductByNmId(ctx, item.NmId, item.SAName)
		if productID == 0 {
			continue
		}

		saleDate := item.SaleDt
		if saleDate == "" {
			saleDate = item.RRDt
		}
		if len(saleDate) >= 10 {
			saleDate = saleDate[:10]
		}

		qty := item.Quantity
		if item.DocTypeName == "Возврат" || item.ReturnAmount > 0 {
			if qty > 0 {
				qty = -qty
			}
		}

		revenue := item.RetailPriceWithDisc
		if revenue == 0 {
			revenue = item.RetailAmount
		}

		forPay := item.PPVZForPay
		commission := item.PPVZSalesCommission
		logistics := item.DeliveryRub + item.RebillLogisticCost
		penalty := item.Penalty

		var costPrice float64
		p.db.QueryRow(ctx, "SELECT COALESCE(cost_price,0) FROM products WHERE id=$1", productID).Scan(&costPrice)
		netProfit := forPay - costPrice*float64(absInt(qty)) - logistics

		if count > 0 {
			sb.WriteString(",")
		}

		sb.WriteString(fmt.Sprintf(
			"($%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d)",
			idx+1, idx+2, idx+3, idx+4, idx+5, idx+6, idx+7, idx+8, idx+9, idx+10,
			idx+11, idx+12, idx+13, idx+14, idx+15, idx+16, idx+17, idx+18, idx+19, idx+20,
			idx+21, idx+22, idx+23, idx+24, idx+25, idx+26, idx+27,
		))

		args = append(args,
			productID, mpID, saleDate, qty, revenue, commission, logistics, netProfit, forPay, srid,
			penalty, item.RetailPrice, item.RetailAmount, item.RetailPriceWithDisc, item.RetailPriceWithDisc,
			item.NmId, nilIfEmpty(item.BrandName), nilIfEmpty(item.SubjectName), nilIfEmpty(item.SAName),
			nilIfEmpty(item.Barcode), nilIfEmpty(item.CountryName), nilIfEmpty(item.OblastOkrugName),
			nilIfEmpty(item.OfficeName), nilIfEmpty(item.DocTypeName), nilIfEmpty(item.SupplierOperName),
			nilIfEmpty(item.OrderDt), nilIfEmpty(srid),
		)

		idx += 27
		count++
	}

	if count == 0 {
		return 0, nil
	}

	query := `INSERT INTO sales
		(product_id, marketplace_id, sale_date, quantity, revenue, commission,
		 logistics_cost, net_profit, for_pay, sale_id, penalty, retail_price,
		 retail_amount, discount_price, finished_price, nm_id, brand,
		 subject_name, supplier_article, barcode, country, region, warehouse,
		 doc_type_name, supplier_oper_name, order_dt, srid)
		VALUES ` + sb.String() + `
		ON CONFLICT (sale_id, marketplace_id, sale_date)
		DO UPDATE SET
			quantity = EXCLUDED.quantity,
			revenue = EXCLUDED.revenue,
			for_pay = EXCLUDED.for_pay,
			commission = EXCLUDED.commission,
			logistics_cost = EXCLUDED.logistics_cost,
			net_profit = EXCLUDED.net_profit,
			finished_price = EXCLUDED.finished_price,
			discount_price = EXCLUDED.discount_price,
			penalty = EXCLUDED.penalty,
			country = COALESCE(EXCLUDED.country, sales.country),
			region = COALESCE(EXCLUDED.region, sales.region),
			warehouse = COALESCE(EXCLUDED.warehouse, sales.warehouse),
			doc_type_name = COALESCE(EXCLUDED.doc_type_name, sales.doc_type_name),
			supplier_oper_name = COALESCE(EXCLUDED.supplier_oper_name, sales.supplier_oper_name),
			brand = COALESCE(EXCLUDED.brand, sales.brand),
			subject_name = COALESCE(EXCLUDED.subject_name, sales.subject_name)`

	_, err := p.db.Exec(ctx, query, args...)
	if err != nil {
		return 0, fmt.Errorf("insert batch: %w", err)
	}

	return count, nil
}

func (p *Provider) SyncStocks(ctx context.Context, cred *models.Credential, apiKey string) (int, error) {
	client := NewClient(apiKey)

	stocks, err := client.GetStocks(time.Now().AddDate(0, 0, -1))
	if err != nil {
		return 0, fmt.Errorf("fetch stocks: %w", err)
	}
	if len(stocks) == 0 {
		return 0, nil
	}

	mpID := cred.MarketplaceID
	p.db.Exec(ctx, "DELETE FROM inventory WHERE marketplace_id=$1", mpID)
	p.ensureProductsFromStocks(ctx, stocks)

	processed := 0
	const batchSize = 500

	for i := 0; i < len(stocks); i += batchSize {
		end := i + batchSize
		if end > len(stocks) {
			end = len(stocks)
		}
		batch := stocks[i:end]

		var sb strings.Builder
		args := make([]interface{}, 0, len(batch)*4)
		idx := 0
		count := 0

		for _, s := range batch {
			productID := p.resolveProductByNmId(ctx, s.NmId, s.SupplierArticle)
			if productID == 0 {
				continue
			}
			wh := s.WarehouseName
			if wh == "" {
				wh = "WB"
			}
			if count > 0 {
				sb.WriteString(",")
			}
			sb.WriteString(fmt.Sprintf("($%d,$%d,$%d,$%d,NOW())", idx+1, idx+2, idx+3, idx+4))
			args = append(args, productID, mpID, wh, s.Quantity)
			idx += 4
			count++
		}

		if count > 0 {
			query := `INSERT INTO inventory (product_id, marketplace_id, warehouse, quantity, recorded_at) VALUES ` + sb.String()
			if _, err := p.db.Exec(ctx, query, args...); err != nil {
				log.Printf("[wb] inventory batch error: %v", err)
				continue
			}
			processed += count
		}
	}

	return processed, nil
}

func (p *Provider) resolveProductByNmId(ctx context.Context, nmId int64, sku string) int {
	if nmId > 0 {
		var id int
		if err := p.db.QueryRow(ctx, "SELECT id FROM products WHERE nm_id=$1", nmId).Scan(&id); err == nil {
			return id
		}
	}
	if sku != "" {
		var id int
		if err := p.db.QueryRow(ctx, "SELECT id FROM products WHERE sku=$1", sku).Scan(&id); err == nil {
			return id
		}
	}
	return 0
}

func (p *Provider) ensureCategoriesFromReport(ctx context.Context, items []ReportDetailItem) {
	seen := make(map[string]bool)
	for _, item := range items {
		name := item.SubjectName
		if name == "" {
			name = "Другое"
		}
		slug := toSlug(name)
		if seen[slug] {
			continue
		}
		seen[slug] = true
		p.db.Exec(ctx, "INSERT INTO categories (slug, name) VALUES ($1, $2) ON CONFLICT (slug) DO NOTHING", slug, name)
	}
}

func (p *Provider) ensureProductsFromReport(ctx context.Context, items []ReportDetailItem) {
	seen := make(map[int64]bool)
	for _, item := range items {
		if item.NmId == 0 || seen[item.NmId] {
			continue
		}
		seen[item.NmId] = true

		sku := item.SAName
		if sku == "" {
			sku = fmt.Sprintf("%d", item.NmId)
		}
		name := item.SubjectName
		if name == "" {
			name = sku
		}
		catSlug := toSlug(item.SubjectName)
		if catSlug == "" {
			catSlug = "drugoe"
		}

		var catID int
		p.db.QueryRow(ctx, "SELECT id FROM categories WHERE slug=$1", catSlug).Scan(&catID)

		p.db.Exec(ctx,
			`INSERT INTO products (name, sku, barcode, cost_price, category_id, nm_id, brand)
			 VALUES ($1, $2, $3, 0, $4, $5, $6)
			 ON CONFLICT (nm_id) DO UPDATE SET
				name=EXCLUDED.name, sku=EXCLUDED.sku,
				barcode=COALESCE(EXCLUDED.barcode, products.barcode),
				category_id=EXCLUDED.category_id,
				brand=COALESCE(EXCLUDED.brand, products.brand),
				updated_at=NOW()`,
			name, sku, nilIfEmpty(item.Barcode), catID, item.NmId, nilIfEmpty(item.BrandName))
	}
}

func (p *Provider) ensureProductsFromStocks(ctx context.Context, stocks []StockItem) {
	seen := make(map[int64]bool)
	for _, s := range stocks {
		if s.NmId == 0 || seen[s.NmId] {
			continue
		}
		seen[s.NmId] = true
		sku := s.SupplierArticle
		if sku == "" {
			sku = fmt.Sprintf("%d", s.NmId)
		}
		p.db.Exec(ctx,
			`INSERT INTO products (name, sku, barcode, cost_price, nm_id)
			 VALUES ($1, $2, $3, 0, $4)
			 ON CONFLICT (nm_id) DO UPDATE SET
				barcode=COALESCE(EXCLUDED.barcode, products.barcode),
				updated_at=NOW()`,
			sku, sku, nilIfEmpty(s.Barcode), s.NmId)
	}
}

func (p *Provider) SyncReport(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error) {
	return p.SyncSales(ctx, cred, apiKey, dateFrom, dateTo)
}

func toSlug(name string) string {
	if name == "" {
		return "drugoe"
	}
	s := strings.ToLower(name)
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'а' && r <= 'я') || r == 'ё' || (r >= '0' && r <= '9') {
			b.WriteRune(r)
		} else {
			b.WriteRune('_')
		}
	}
	result := strings.Trim(b.String(), "_")
	if len(result) > 50 {
		result = result[:50]
	}
	return result
}

func nilIfEmpty(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}

func absInt(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
