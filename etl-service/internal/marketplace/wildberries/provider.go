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

func (p *Provider) Name() string           { return "Wildberries" }
func (p *Provider) MarketplaceSlug() string { return "wildberries" }

// ──────────────────────────────────────────
// Sales sync — full WB report fields
// ──────────────────────────────────────────
func (p *Provider) SyncSales(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error) {
	client := NewClient(apiKey)

	sales, err := client.GetSales(dateFrom)
	if err != nil {
		return 0, fmt.Errorf("fetch sales: %w", err)
	}
	if len(sales) == 0 {
		return 0, nil
	}

	mpID := cred.MarketplaceID

	// Batch ensure categories + products (like wb-sync.ts)
	p.ensureCategoriesFromSales(ctx, sales)
	p.ensureProductsFromSales(ctx, sales)

	processed := 0
	const batchSize = 500

	for i := 0; i < len(sales); i += batchSize {
		end := i + batchSize
		if end > len(sales) {
			end = len(sales)
		}
		batch := sales[i:end]

		n, err := p.insertSalesBatch(ctx, batch, mpID)
		if err != nil {
			log.Printf("[wb] batch %d-%d error: %v", i, end, err)
			continue
		}
		processed += n
	}

	return processed, nil
}

func (p *Provider) insertSalesBatch(ctx context.Context, sales []SaleItem, mpID int) (int, error) {
	if len(sales) == 0 {
		return 0, nil
	}

	var sb strings.Builder
	args := make([]interface{}, 0, len(sales)*20)
	idx := 0
	count := 0

	for _, s := range sales {
		if s.SaleID == "" {
			continue
		}

		productID := p.resolveProductByNmId(ctx, s.NmId, s.SupplierArticle)
		if productID == 0 {
			continue
		}

		saleDate := s.Date
		if len(saleDate) >= 10 {
			saleDate = saleDate[:10]
		}

		qty := 1
		if s.IsReturn {
			qty = -1
		}

		revenue := s.FinishedPrice
		if revenue == 0 {
			revenue = s.PriceWithDisc
		}
		forPay := s.ForPay
		commission := revenue - forPay
		if commission < 0 {
			commission = 0
		}

		var costPrice float64
		p.db.QueryRow(ctx, "SELECT COALESCE(cost_price,0) FROM products WHERE id=$1", productID).Scan(&costPrice)
		netProfit := forPay - costPrice*float64(absInt(qty))

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
			0.0,                // 7  logistics_cost
			netProfit,          // 8  net_profit
			forPay,             // 9  for_pay
			s.SaleID,           // 10 sale_id
			0.0,                // 11 penalty
			s.TotalPrice,       // 12 retail_price
			0.0,                // 13 retail_amount
			s.PriceWithDisc,    // 14 discount_price
			s.FinishedPrice,    // 15 finished_price
			s.NmId,             // 16 nm_id
			s.Brand,            // 17 brand
			s.Subject,          // 18 subject_name
			s.SupplierArticle,  // 19 supplier_article
			s.Barcode,          // 20 barcode
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
			revenue = EXCLUDED.revenue,
			for_pay = EXCLUDED.for_pay,
			commission = EXCLUDED.commission,
			net_profit = EXCLUDED.net_profit,
			finished_price = EXCLUDED.finished_price,
			brand = COALESCE(EXCLUDED.brand, sales.brand),
			subject_name = COALESCE(EXCLUDED.subject_name, sales.subject_name)`

	_, err := p.db.Exec(ctx, query, args...)
	if err != nil {
		return 0, fmt.Errorf("insert batch: %w", err)
	}

	return count, nil
}

// ──────────────────────────────────────────
// Stocks sync — writes to inventory table
// ──────────────────────────────────────────
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

	// Clear old inventory for this marketplace (same as wb-sync.ts)
	_, _ = p.db.Exec(ctx, "DELETE FROM inventory WHERE marketplace_id=$1", mpID)

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
			query := `INSERT INTO inventory (product_id, marketplace_id, warehouse, quantity, recorded_at)
				VALUES ` + sb.String()
			_, err := p.db.Exec(ctx, query, args...)
			if err != nil {
				log.Printf("[wb] inventory batch error: %v", err)
				continue
			}
			processed += count
		}
	}

	return processed, nil
}

// ──────────────────────────────────────────
// Product resolution — matches wb-sync.ts logic
// ──────────────────────────────────────────
func (p *Provider) resolveProductByNmId(ctx context.Context, nmId int64, sku string) int {
	if nmId > 0 {
		var id int
		err := p.db.QueryRow(ctx, "SELECT id FROM products WHERE nm_id=$1", nmId).Scan(&id)
		if err == nil {
			return id
		}
	}
	if sku != "" {
		var id int
		err := p.db.QueryRow(ctx, "SELECT id FROM products WHERE sku=$1", sku).Scan(&id)
		if err == nil {
			return id
		}
	}
	return 0
}

func (p *Provider) ensureCategoriesFromSales(ctx context.Context, sales []SaleItem) {
	seen := make(map[string]bool)
	for _, s := range sales {
		name := s.Subject
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

func (p *Provider) ensureProductsFromSales(ctx context.Context, sales []SaleItem) {
	seen := make(map[int64]bool)
	for _, s := range sales {
		if s.NmId == 0 || seen[s.NmId] {
			continue
		}
		seen[s.NmId] = true

		sku := s.SupplierArticle
		if sku == "" {
			sku = fmt.Sprintf("%d", s.NmId)
		}
		name := s.Subject
		if name == "" {
			name = sku
		}
		catSlug := toSlug(s.Subject)
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
			name, sku, nilIfEmpty(s.Barcode), catID, s.NmId, nilIfEmpty(s.Brand))
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
