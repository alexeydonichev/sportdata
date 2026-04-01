package wildberries

import (
	"fmt"
	"time"
)

const baseURLReport = "https://statistics-api.wildberries.ru/api/v5/supplier/reportDetailByPeriod"

// ReportItem — полная детализация WB отчёта
type ReportItem struct {
	RealizationReportID int64   `json:"realizationreport_id"`
	RRD_ID              int64   `json:"rrd_id"`
	DateFrom            string  `json:"date_from"`
	DateTo              string  `json:"date_to"`
	CreateDt            string  `json:"create_dt"`
	SupplierArticle     string  `json:"supplierArticle"`
	NmId                int64   `json:"nm_id"`
	Barcode             string  `json:"barcode"`
	DocTypeName         string  `json:"doc_type_name"`
	Quantity            int     `json:"quantity"`
	RetailPrice         float64 `json:"retail_price"`
	RetailAmount        float64 `json:"retail_amount"`
	SalePercent         int     `json:"sale_percent"`
	CommissionPercent   float64 `json:"commission_percent"`
	RetailPriceWDisc    float64 `json:"retail_price_withdisc_rub"`
	DeliveryAmount      int     `json:"delivery_amount"`
	ReturnAmount        int     `json:"return_amount"`
	DeliveryRub         float64 `json:"delivery_rub"`
	PenaltyRub          float64 `json:"penalty"`
	StorageFee          float64 `json:"storage_fee"`
	Acceptance          float64 `json:"acceptance"`
	PPVzForPay          float64 `json:"ppvz_for_pay"`
	PPVzSalesCommission float64 `json:"ppvz_sales_commission"`
	PPVzReward          float64 `json:"ppvz_reward"`
	AcquiringFee        float64 `json:"acquiring_fee"`
	AcquiringPercent    float64 `json:"acquiring_percent"`
	SaleID              string  `json:"srid"`
	Brand               string  `json:"brand_name"`
	SubjectName         string  `json:"sa_name"`
	SiteName            string  `json:"site_country"`
	OfficeName          string  `json:"office_name"`
	SupplierOperName    string  `json:"supplier_oper_name"`
	OrderDt             string  `json:"order_dt"`
	SaleDt              string  `json:"sale_dt"`
}

// GetReportDetail вызывает /api/v5/supplier/reportDetailByPeriod
// WB отдаёт до 100 000 записей, пагинация через rrdid
func (c *Client) GetReportDetail(dateFrom, dateTo time.Time) ([]ReportItem, error) {
	var all []ReportItem
	rrdid := int64(0)
	limit := 100000

	for {
		url := fmt.Sprintf("%s?dateFrom=%s&dateTo=%s&rrdid=%d&limit=%d",
			baseURLReport,
			dateFrom.Format("2006-01-02"),
			dateTo.Format("2006-01-02"),
			rrdid,
			limit,
		)

		var batch []ReportItem
		if err := c.doRequest("GET", url, &batch); err != nil {
			return all, fmt.Errorf("report detail page rrdid=%d: %w", rrdid, err)
		}

		if len(batch) == 0 {
			break
		}

		all = append(all, batch...)

		// Следующая страница — максимальный rrd_id из текущей
		lastRRD := batch[len(batch)-1].RRD_ID
		if lastRRD <= rrdid {
			break // защита от бесконечного цикла
		}
		rrdid = lastRRD

		// Если получили меньше лимита — данных больше нет
		if len(batch) < limit {
			break
		}
	}

	return all, nil
}
