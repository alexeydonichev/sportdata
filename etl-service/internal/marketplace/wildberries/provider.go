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

	var lastSaleDate *time.Time
	err := p.db.QueryRow(ctx, "SELECT MAX(sale_dt) FROM wb_sales WHERE credential_id = $1", cred.ID).Scan(&lastSaleDate)
	if err == nil && lastSaleDate != nil {
		incrementalFrom := lastSaleDate.AddDate(0, 0, -3)
		if incrementalFrom.After(dateFrom) {
			dateFrom = incrementalFrom
			log.Printf("[wb] Incremental sync from %s (last sale: %s)", dateFrom.Format("2006-01-02"), lastSaleDate.Format("2006-01-02"))
		}
	} else {
		log.Printf("[wb] Full sync (no previous data for credential %d)", cred.ID)
	}

	log.Printf("[wb] Fetching sales: %s to %s", dateFrom.Format("2006-01-02"), dateTo.Format("2006-01-02"))
	items, err := client.GetReportDetailByWeeks(dateFrom, dateTo)
	if err != nil {
		return 0, fmt.Errorf("fetch: %w", err)
	}
	if len(items) == 0 {
		log.Printf("[wb] No new items from API")
		return 0, nil
	}
	log.Printf("[wb] Got %d items from API", len(items))

	seen := make(map[string]bool)
	unique := make([]ReportDetailItem, 0, len(items))
	for _, it := range items {
		if it.SRId == "" {
			continue
		}
		sd := it.SaleDt
		if sd == "" {
			sd = it.RRDt
		}
		if len(sd) >= 10 {
			sd = sd[:10]
		}
		key := it.SRId + "|" + sd
		if !seen[key] {
			seen[key] = true
			unique = append(unique, it)
		}
	}
	log.Printf("[wb] After dedup: %d unique items", len(unique))

	processed := 0
	for i := 0; i < len(unique); i += 500 {
		end := i + 500
		if end > len(unique) {
			end = len(unique)
		}
		n, err := p.insertWbSalesBatch(ctx, unique[i:end], cred.ID)
		if err != nil {
			log.Printf("[wb] batch error: %v", err)
			continue
		}
		processed += n
	}
	log.Printf("[wb] Processed %d into wb_sales", processed)
	return processed, nil
}

func (p *Provider) insertWbSalesBatch(ctx context.Context, items []ReportDetailItem, credID int) (int, error) {
	if len(items) == 0 {
		return 0, nil
	}
	var sb strings.Builder
	args := make([]interface{}, 0, len(items)*55)
	idx, cnt := 0, 0
	for _, it := range items {
		if it.SRId == "" {
			continue
		}
		sd := it.SaleDt
		if sd == "" {
			sd = it.RRDt
		}
		if len(sd) >= 10 {
			sd = sd[:10]
		}
		if cnt > 0 {
			sb.WriteString(",")
		}
		sb.WriteString(fmt.Sprintf("($%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d,$%d)",
			idx+1, idx+2, idx+3, idx+4, idx+5, idx+6, idx+7, idx+8, idx+9, idx+10, idx+11, idx+12, idx+13, idx+14, idx+15, idx+16, idx+17, idx+18, idx+19, idx+20, idx+21, idx+22, idx+23, idx+24, idx+25, idx+26, idx+27, idx+28, idx+29, idx+30, idx+31, idx+32, idx+33, idx+34, idx+35, idx+36, idx+37, idx+38, idx+39, idx+40, idx+41, idx+42, idx+43, idx+44, idx+45, idx+46, idx+47, idx+48, idx+49, idx+50, idx+51, idx+52, idx+53, idx+54, idx+55))
		args = append(args, nz(it.RRDtID), ne(it.SRId), nz(it.RID), nz(it.GiID), nz(it.ShkID), sd, pt(it.OrderDt), pt(it.RRDt), pt(it.CreateDt), nz(it.NmId), ne(it.SAName), ne(it.Barcode), ne(it.BrandName), ne(it.SubjectName), ne(it.TSName), ne(it.DocTypeName), ne(it.SupplierOperName), it.Quantity, it.RetailPrice, it.RetailAmount, it.RetailPriceWithDisc, it.SalePercent, it.CommissionPercent, it.PPVZSppPrc, it.PPVZKVWPrc, it.PPVZKVWPrcBase, it.PPVZSalesCommission, it.PPVZForPay, it.PPVZReward, it.PPVZVW, it.PPVZVWNDS, it.AcquiringFee, it.AcquiringPercent, ne(it.AcquiringBank), it.DeliveryAmount, it.ReturnAmount, it.DeliveryRub, it.RebillLogisticCost, it.Penalty, it.AdditionalPayment, it.Deduction, it.StorageFee, it.Acceptance, ne(it.CountryName), ne(it.OblastOkrugName), ne(it.RegionName), ne(it.OfficeName), nz(it.PPVZOfficeID), ne(it.PPVZOfficeName), nz(it.PPVZSupplierID), ne(it.PPVZSupplierName), ne(it.PPVZINN), ne(it.StickCode), ne(it.Kiz), credID)
		idx += 55
		cnt++
	}
	if cnt == 0 {
		return 0, nil
	}
	q := `INSERT INTO wb_sales(rrd_id,srid,rid,gi_id,shk_id,sale_dt,order_dt,rr_dt,create_dt,nm_id,supplier_article,barcode,brand,subject_name,ts_name,doc_type_name,supplier_oper_name,quantity,retail_price,retail_amount,retail_price_withdisc_rub,sale_percent,commission_percent,ppvz_spp_prc,ppvz_kvw_prc,ppvz_kvw_prc_base,ppvz_sales_commission,ppvz_for_pay,ppvz_reward,ppvz_vw,ppvz_vw_nds,acquiring_fee,acquiring_percent,acquiring_bank,delivery_amount,return_amount,delivery_rub,rebill_logistic_cost,penalty,additional_payment,deduction,storage_fee,acceptance,country_name,oblast_okrug_name,region_name,office_name,ppvz_office_id,ppvz_office_name,ppvz_supplier_id,ppvz_supplier_name,ppvz_inn,sticker_id,kiz,credential_id) VALUES ` + sb.String() + ` ON CONFLICT(srid,sale_dt) WHERE srid IS NOT NULL DO UPDATE SET quantity=EXCLUDED.quantity,retail_amount=EXCLUDED.retail_amount,ppvz_for_pay=EXCLUDED.ppvz_for_pay,ppvz_reward=EXCLUDED.ppvz_reward,delivery_rub=EXCLUDED.delivery_rub,penalty=EXCLUDED.penalty,updated_at=NOW()`
	_, err := p.db.Exec(ctx, q, args...)
	if err != nil {
		return 0, err
	}
	return cnt, nil
}

func (p *Provider) SyncStocks(ctx context.Context, cred *models.Credential, apiKey string) (int, error) {
	client := NewClient(apiKey)
	stocks, err := client.GetStocks(time.Now().AddDate(0, 0, -1))
	if err != nil {
		return 0, err
	}
	if len(stocks) == 0 {
		return 0, nil
	}
	mpID := cred.MarketplaceID
	p.db.Exec(ctx, "DELETE FROM inventory WHERE marketplace_id=$1", mpID)
	cnt := 0
	for _, s := range stocks {
		if s.NmId == 0 {
			continue
		}
		p.ensureProduct(ctx, s.NmId, s.SupplierArticle, s.Barcode)
		var pid int
		if err := p.db.QueryRow(ctx, "SELECT id FROM products WHERE nm_id=$1", s.NmId).Scan(&pid); err != nil {
			continue
		}
		wh := s.WarehouseName
		if wh == "" {
			wh = "WB"
		}
		p.db.Exec(ctx, "INSERT INTO inventory(product_id,marketplace_id,warehouse,quantity,recorded_at) VALUES($1,$2,$3,$4,NOW())", pid, mpID, wh, s.Quantity)
		cnt++
	}
	return cnt, nil
}

func (p *Provider) ensureProduct(ctx context.Context, nmId int64, sku, barcode string) {
	if sku == "" {
		sku = fmt.Sprintf("%d", nmId)
	}
	p.db.Exec(ctx, `INSERT INTO products(name,sku,barcode,cost_price,nm_id) VALUES($1,$2,$3,0,$4) ON CONFLICT(nm_id) DO UPDATE SET barcode=COALESCE(EXCLUDED.barcode,products.barcode),updated_at=NOW()`, sku, sku, ne(barcode), nmId)
}

func (p *Provider) SyncReport(ctx context.Context, cred *models.Credential, apiKey string, dateFrom, dateTo time.Time) (int, error) {
	return p.SyncSales(ctx, cred, apiKey, dateFrom, dateTo)
}

func pt(s string) interface{} {
	if s == "" {
		return nil
	}
	for _, f := range []string{"2006-01-02T15:04:05Z", "2006-01-02T15:04:05", "2006-01-02"} {
		if t, err := time.Parse(f, s); err == nil {
			return t
		}
	}
	return nil
}

func ne(s string) interface{} {
	if s == "" {
		return nil
	}
	return s
}

func nz(n int64) interface{} {
	if n == 0 {
		return nil
	}
	return n
}
