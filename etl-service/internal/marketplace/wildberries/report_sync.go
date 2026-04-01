package wildberries

import (
	"context"
	"fmt"
	"log"
	"strings"
	"time"

	"sportdata-etl/internal/models"
)

// SyncReport — синхронизация через Report Detail API (полные данные)
func (p *Provider) SyncReport(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error) {
	client := NewClient(apiKey)

	items, err := client.GetReportDetail(dateFrom, dateTo)
	if err != nil {
		return 0, fmt.Errorf("fetch report: %w", err)
	}

	if len(items) == 0 {
		log.Printf("[wb-report] no data for %s — %s",
			dateFrom.Format("2006-01-02"), dateTo.Format("2006-01-02"))
		return 0, nil
	}

	log.Printf("[wb-report] fetched %d rows", len(items))

	// Фильтруем только продажи и возвраты
	var sales []ReportItem
	for _, item := range items {
		op := item.SupplierOperName
		if op == "Продажа" || op == "Возврат" {
			sales = append(sales, item)
		}
	}

	if len(sales) == 0 {
		log.Printf("[wb-report] no sales/returns in %d rows", len(items))
		return 0, nil
	}

	// Ensure categories + products
	p.ensureCategoriesFromReport(ctx, sales)
	p.ensureProductsFromReport(ctx, sales)

	mpID := cred.MarketplaceID
	processed := 0
	const batchSize = 500

	for i := 0; i < len(sales); i += batchSize {
		end := i + batchSize
		if end > len(sales) {
			end = len(sales)
		}

		n, err := p.insertReportBatch(ctx, sales[i:end], mpID)
		if err != nil {
			log.Printf("[wb-report] batch %d-%d error: %v", i, end, err)
			continue
		}
		processed += n
	}

	log.Printf("[wb-report] upserted %d sales records", processed)
	return processed, nil
}

func (p *Provider) insertReportBatch(ctx context.Context, items []ReportItem, mpID int) (int, error) {
	if len(items) == 0 {
		return 0, nil
	}

	var sb strings.Builder
	args := make([]interface{}, 0, len(items)*20)
	idx := 0
	count := 0

	for _, r := range items {
		if r.SaleID == "" {
			continue
		}

		productID := p.resolveProductByNmId(ctx, r.NmId, r.SupplierArticle)
		if productID == 0 {
			continue
		}

		saleDate := r.SaleDt
		if saleDate == "" {
			saleDate = r.OrderDt
		}
		if len(saleDate) >= 10 {
			saleDate = saleDate[:10]
		}
		if saleDate == "" {
			continue
		}

		qty := r.Quantity
		if r.ReturnAmount > 0 {
			qty = -r.ReturnAmount
		}

		revenue := r.RetailPriceWDisc
		if revenue == 0 {
			revenue = r.RetailAmount
		}

		forPay := r.PPVzForPay
		commission := r.PPVzSalesCommission
		logistics := r.DeliveryRub
		penalty := r.PenaltyRub
		storageFee := r.StorageFee
		acceptance := r.Acceptance

		// Себестоимость из products
		var costPrice float64
		p.db.QueryRow(ctx, "SELECT COALESCE(cost_price,0) FROM products WHERE id=$1", productID).Scan(&costPrice)

		netProfit := forPay - logistics - penalty - storageFee - acceptance - costPrice*float64(absInt(qty))

		if count > 0 {
			sb.WriteString(",")
		}

		sb.WriteString(fmt.Sprintf(
			"($%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d)",
			idx+1, idx+2, idx+3, idx+4, idx+5, idx+6, idx+7, idx+8, idx+9, idx+10,
			idx+11, idx+12, idx+13, idx+14, idx+15, idx+16, idx+17, idx+18, idx+19, idx+20,
		))

		args = append(args,
			productID,          // 1  product_id
			mpID,               // 2  marketplace_id
			saleDate,           // 3  sale_date
			qty,                // 4  quantity
			revenue,            // 5  revenue
			commission,         // 6  commission
			logistics,          // 7  logistics_cost
			netProfit,          // 8  net_profit
			forPay,             // 9  for_pay
			r.SaleID,           // 10 sale_id
			penalty,            // 11 penalty
			r.RetailPrice,      // 12 retail_price
			r.RetailAmount,     // 13 retail_amount
			r.RetailPriceWDisc, // 14 discount_price
			revenue,            // 15 finished_price
			r.NmId,             // 16 nm_id
			r.Brand,            // 17 brand
			r.SubjectName,      // 18 subject_name
			r.SupplierArticle,  // 19 supplier_article
			r.Barcode,          // 20 barcode
		)

		idx += 20
		count++
	}

	if count == 0 {
		return 0, nil
	}

	query := `INSERT INTO sales
		(product_id, marketplace_id, sale_date, quantity, revenue, commission,
		 logistics_cost, net_profit, for_pay, sale_id, penalty, retail_price,
		 retail_amount, discount_price, finished_price, nm_id, brand,
		 subject_name, supplier_article, barcode)
		VALUES ` + sb.String() + `
		ON CONFLICT (sale_id, marketplace_id, sale_date)
		DO UPDATE SET
			revenue       = EXCLUDED.revenue,
			for_pay       = EXCLUDED.for_pay,
			commission    = EXCLUDED.commission,
			logistics_cost= EXCLUDED.logistics_cost,
			penalty       = EXCLUDED.penalty,
			net_profit    = EXCLUDED.net_profit,
			finished_price= EXCLUDED.finished_price,
			retail_amount = EXCLUDED.retail_amount,
			brand         = COALESCE(EXCLUDED.brand, sales.brand),
			subject_name  = COALESCE(EXCLUDED.subject_name, sales.subject_name)`

	_, err := p.db.Exec(ctx, query, args...)
	if err != nil {
		return 0, fmt.Errorf("insert report batch: %w", err)
	}

	return count, nil
}

func (p *Provider) ensureCategoriesFromReport(ctx context.Context, items []ReportItem) {
	seen := make(map[string]bool)
	for _, r := range items {
		name := r.SubjectName
		if name == "" {
			name = "Другое"
		}
		slug := toSlug(name)
		if seen[slug] {
			continue
		}
		seen[slug] = true
		p.db.Exec(ctx,
			"INSERT INTO categories (slug, name) VALUES ($1, $2) ON CONFLICT (slug) DO NOTHING",
			slug, name)
	}
}

func (p *Provider) ensureProductsFromReport(ctx context.Context, items []ReportItem) {
	seen := make(map[int64]bool)
	for _, r := range items {
		if r.NmId == 0 || seen[r.NmId] {
			continue
		}
		seen[r.NmId] = true

		sku := r.SupplierArticle
		if sku == "" {
			sku = fmt.Sprintf("%d", r.NmId)
		}
		name := r.SubjectName
		if name == "" {
			name = sku
		}
		catSlug := toSlug(r.SubjectName)
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
			name, sku, nilIfEmpty(r.Barcode), catID, r.NmId, nilIfEmpty(r.Brand))
	}
}
