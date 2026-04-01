package ozon

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

func (p *Provider) Name() string           { return "Ozon" }
func (p *Provider) MarketplaceSlug() string { return "ozon" }

func (p *Provider) SyncSales(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error) {
	client := NewClient(apiKey, cred.ClientID)

	mpID := cred.MarketplaceID
	processed := 0
	var page int64 = 1

	for {
		resp, err := client.GetTransactions(dateFrom, dateTo, page)
		if err != nil {
			return processed, fmt.Errorf("fetch page %d: %w", page, err)
		}
		if len(resp.Result.Operations) == 0 {
			break
		}

		n, err := p.insertOperationsBatch(ctx, resp.Result.Operations, mpID)
		if err != nil {
			log.Printf("[ozon] batch page %d error: %v", page, err)
		}
		processed += n

		if page >= resp.Result.PageCount {
			break
		}
		page++
		time.Sleep(500 * time.Millisecond)
	}
	return processed, nil
}

func (p *Provider) insertOperationsBatch(ctx context.Context, ops []Operation, mpID int) (int, error) {
	var sb strings.Builder
	args := make([]interface{}, 0, len(ops)*10)
	idx := 0
	count := 0

	for _, op := range ops {
		for _, item := range op.Items {
			if item.SKU == 0 {
				continue
			}

			productID := p.resolveProduct(ctx, mpID, item.SKU)
			if productID == 0 {
				continue
			}

			saleDate := op.OperationDate
			if len(saleDate) >= 10 {
				saleDate = saleDate[:10]
			}

			qty := 1
			if op.OperationType == "OperationAgentDeliveredToCustomerReturn" {
				qty = -1
			}

			revenue := op.Accruals
			commission := op.SaleCommission
			logistics := op.DeliveryCharge

			var costPrice float64
			p.db.QueryRow(ctx, "SELECT COALESCE(cost_price,0) FROM products WHERE id=$1", productID).Scan(&costPrice)
			netProfit := revenue - commission - logistics - costPrice*float64(absInt(qty))
			forPay := revenue - commission

			saleID := fmt.Sprintf("ozon_%d_%s", op.OperationID, saleDate)

			if count > 0 {
				sb.WriteString(",")
			}
			sb.WriteString(fmt.Sprintf(
				"($%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d)",
				idx+1, idx+2, idx+3, idx+4, idx+5, idx+6, idx+7, idx+8, idx+9, idx+10,
			))
			args = append(args,
				productID, mpID, saleDate, qty, revenue,
				commission, logistics, netProfit, forPay, saleID,
			)
			idx += 10
			count++
		}
	}

	if count == 0 {
		return 0, nil
	}

	query := `INSERT INTO sales
		(product_id, marketplace_id, sale_date, quantity, revenue,
		 commission, logistics_cost, net_profit, for_pay, sale_id)
		VALUES ` + sb.String() + `
		ON CONFLICT (sale_id, marketplace_id, sale_date)
		DO UPDATE SET
			revenue = EXCLUDED.revenue,
			commission = EXCLUDED.commission,
			logistics_cost = EXCLUDED.logistics_cost,
			net_profit = EXCLUDED.net_profit,
			for_pay = EXCLUDED.for_pay`

	_, err := p.db.Exec(ctx, query, args...)
	if err != nil {
		return 0, fmt.Errorf("insert batch: %w", err)
	}
	return count, nil
}

func (p *Provider) SyncStocks(ctx context.Context, cred *models.Credential, apiKey string) (int, error) {
	client := NewClient(apiKey, cred.ClientID)

	mpID := cred.MarketplaceID

	// Clear old inventory
	_, _ = p.db.Exec(ctx, "DELETE FROM inventory WHERE marketplace_id=$1", mpID)

	processed := 0
	lastID := ""

	for {
		resp, err := client.GetStocks(lastID)
		if err != nil {
			return processed, fmt.Errorf("fetch stocks: %w", err)
		}
		if len(resp.Result.Items) == 0 {
			break
		}

		for _, item := range resp.Result.Items {
			if item.OfferID == "" {
				continue
			}

			productID := p.resolveProduct(ctx, mpID, int64(item.ProductID))
			if productID == 0 {
				var id int
				if err := p.db.QueryRow(ctx, "SELECT id FROM products WHERE sku=$1", item.OfferID).Scan(&id); err != nil {
					continue
				}
				productID = id
			}

			totalQty := 0
			for _, stock := range item.Stocks {
				totalQty += stock.Present
			}

			_, err = p.db.Exec(ctx,
				`INSERT INTO inventory (product_id, marketplace_id, warehouse, quantity, recorded_at)
				 VALUES ($1, $2, $3, $4, NOW())`,
				productID, mpID, "Ozon", totalQty,
			)
			if err == nil {
				processed++
			}
		}

		lastID = resp.Result.LastID
		if lastID == "" || int64(len(resp.Result.Items)) < 1000 {
			break
		}
		time.Sleep(300 * time.Millisecond)
	}
	return processed, nil
}

func (p *Provider) resolveProduct(ctx context.Context, mpID int, sku int64) int {
	var productID int
	err := p.db.QueryRow(ctx,
		"SELECT product_id FROM product_mappings WHERE marketplace_id=$1 AND external_sku=$2",
		mpID, fmt.Sprintf("%d", sku),
	).Scan(&productID)
	if err == nil {
		return productID
	}
	err = p.db.QueryRow(ctx, "SELECT id FROM products WHERE nm_id=$1", sku).Scan(&productID)
	if err == nil {
		return productID
	}
	return 0
}

func absInt(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
