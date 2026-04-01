package wildberries

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

const baseURLStats = "https://statistics-api.wildberries.ru/api/v1/supplier"

type Client struct {
	apiKey     string
	httpClient *http.Client
}

func NewClient(apiKey string) *Client {
	return &Client{
		apiKey:     apiKey,
		httpClient: &http.Client{Timeout: 60 * time.Second},
	}
}

func (c *Client) doRequest(method, url string, result interface{}) error {
	req, err := http.NewRequest(method, url, nil)
	if err != nil {
		return fmt.Errorf("create request: %w", err)
	}
	req.Header.Set("Authorization", c.apiKey)
	req.Header.Set("Content-Type", "application/json")

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("do request: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode == 429 {
		return fmt.Errorf("rate limited (429)")
	}
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		limit := len(body)
		if limit > 200 {
			limit = 200
		}
		return fmt.Errorf("HTTP %d: %s", resp.StatusCode, string(body[:limit]))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return fmt.Errorf("read body: %w", err)
	}
	return json.Unmarshal(body, result)
}

type SaleItem struct {
	Date            string  `json:"date"`
	SupplierArticle string  `json:"supplierArticle"`
	Barcode         string  `json:"barcode"`
	TotalPrice      float64 `json:"totalPrice"`
	ForPay          float64 `json:"forPay"`
	FinishedPrice   float64 `json:"finishedPrice"`
	PriceWithDisc   float64 `json:"priceWithDisc"`
	SaleID          string  `json:"saleID"`
	IsReturn        bool    `json:"IsReturn"`
	NmId            int64   `json:"nmId"`
	Subject         string  `json:"subject"`
	Category        string  `json:"category"`
	Brand           string  `json:"brand"`
}

func (c *Client) GetSales(dateFrom time.Time) ([]SaleItem, error) {
	url := fmt.Sprintf("%s/sales?dateFrom=%s", baseURLStats, dateFrom.Format("2006-01-02"))
	var result []SaleItem
	err := c.doRequest("GET", url, &result)
	return result, err
}

type StockItem struct {
	SupplierArticle string `json:"supplierArticle"`
	Barcode         string `json:"barcode"`
	Quantity        int    `json:"quantity"`
	WarehouseName   string `json:"warehouseName"`
	NmId            int64  `json:"nmId"`
}

func (c *Client) GetStocks(dateFrom time.Time) ([]StockItem, error) {
	url := fmt.Sprintf("%s/stocks?dateFrom=%s", baseURLStats, dateFrom.Format("2006-01-02"))
	var result []StockItem
	err := c.doRequest("GET", url, &result)
	return result, err
}
