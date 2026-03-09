import pool from "@/lib/db";
import { decrypt } from "@/lib/crypto";

const WB_STATS_API = "https://statistics-api.wildberries.ru";
const WB_CONTENT_API = "https://content-api.wildberries.ru";

interface WBSale {
  date: string;
  supplierArticle: string;
  barcode: string;
  totalPrice: number;
  discountPercent: number;
  forPay: number;
  finishedPrice: number;
  priceWithDisc: number;
  saleID: string;
  spp: number;
  nmId: number;
  subject: string;
  brand: string;
  IsStorno: number;
  warehouseName: string;
}

interface WBStock {
  supplierArticle: string;
  barcode: string;
  quantity: number;
  warehouseName: string;
  nmId: number;
  subject: string;
  brand: string;
  Price: number;
  Discount: number;
}

interface WBOrder {
  date: string;
  supplierArticle: string;
  barcode: string;
  totalPrice: number;
  discountPercent: number;
  finishedPrice: number;
  priceWithDisc: number;
  nmId: number;
  subject: string;
  brand: string;
  isCancel: boolean;
  cancelDate: string;
  warehouseName: string;
}

interface WBCardListResponse {
  cards: {
    nmID: number;
    vendorCode: string;
    title: string;
    subjectName: string;
    brand: string;
    barcodes: string[];
    sizes: { price: number; discountedPrice: number }[];
  }[];
  cursor: { total: number; updatedAt: string; nmID: number };
}

// WB Report Detail — содержит логистику, комиссию, штрафы
interface WBReportDetail {
  realizationreport_id: number;
  rrd_id: number;
  nm_id: number;
  sa_name: string;           // supplierArticle
  barcode: string;
  subject_name: string;
  brand_name: string;
  doc_type_name: string;     // "Продажа" | "Возврат"
  quantity: number;
  retail_price: number;
  retail_amount: number;
  retail_price_withdisc_rub: number;
  delivery_rub: number;              // ← ЛОГИСТИКА
  ppvz_sales_commission: number;     // ← КОМИССИЯ WB в рублях
  ppvz_for_pay: number;              // ← К выплате продавцу
  penalty: number;                   // ← Штрафы
  additional_payment: number;        // ← Доплаты
  acquiring_fee: number;             // ← Эквайринг
  supplier_oper_name: string;        // "Продажа" | "Логистика" | "Возврат" | ...
  order_dt: string;
  sale_dt: string;
  office_name: string;
  date_from: string;
  date_to: string;
}

async function wbFetch<T>(url: string, apiKey: string): Promise<T> {
  const res = await fetch(url, {
    headers: { Authorization: apiKey },
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`WB API ${res.status}: ${text.slice(0, 500)}`);
  }
  return res.json() as Promise<T>;
}

async function wbPost<T>(url: string, apiKey: string, body: unknown): Promise<T> {
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`WB API POST ${res.status}: ${text.slice(0, 500)}`);
  }
  return res.json() as Promise<T>;
}

function dateNDaysAgo(n: number): string {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().split("T")[0];
}

function toSlug(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-zа-яё0-9]+/gi, "_")
    .replace(/^_|_$/g, "")
    .slice(0, 50);
}

async function getWBCredentials(): Promise<{ apiKey: string; marketplaceId: number }> {
  const { rows } = await pool.query(
    `SELECT mc.api_key_encrypted, mc.marketplace_id
     FROM marketplace_credentials mc
     JOIN marketplaces m ON m.id = mc.marketplace_id
     WHERE m.slug = 'wildberries' AND mc.is_active = true
     LIMIT 1`
  );
  if (rows.length === 0) throw new Error("WB credentials not found");
  return {
    apiKey: decrypt(rows[0].api_key_encrypted),
    marketplaceId: rows[0].marketplace_id,
  };
}

async function ensureCategory(subjectName: string): Promise<number> {
  if (!subjectName) subjectName = "Другое";
  const slug = toSlug(subjectName);
  const { rows: existing } = await pool.query("SELECT id FROM categories WHERE slug = $1", [slug]);
  if (existing.length > 0) return existing[0].id;
  const { rows: inserted } = await pool.query(
    "INSERT INTO categories (slug, name) VALUES ($1, $2) ON CONFLICT (slug) DO UPDATE SET name = $2 RETURNING id",
    [slug, subjectName]
  );
  return inserted[0].id;
}

async function ensureProduct(
  sku: string, name: string, barcode: string | null, categoryId: number
): Promise<number> {
  const { rows: existing } = await pool.query("SELECT id FROM products WHERE sku = $1", [sku]);
  if (existing.length > 0) {
    await pool.query(
      `UPDATE products SET name = $2, barcode = COALESCE($3, barcode), category_id = $4, updated_at = NOW() WHERE id = $1`,
      [existing[0].id, name, barcode, categoryId]
    );
    return existing[0].id;
  }
  const { rows: inserted } = await pool.query(
    `INSERT INTO products (name, sku, barcode, cost_price, category_id) VALUES ($1, $2, $3, 0, $4) RETURNING id`,
    [name, sku, barcode, categoryId]
  );
  return inserted[0].id;
}

// ============================================================
// SALES SYNC — from /api/v1/supplier/sales
// ============================================================
async function syncSales(apiKey: string, marketplaceId: number, daysBack: number = 30): Promise<number> {
  const dateFrom = dateNDaysAgo(daysBack);
  const url = `${WB_STATS_API}/api/v1/supplier/sales?dateFrom=${dateFrom}`;
  const sales = await wbFetch<WBSale[]>(url, apiKey);
  if (!sales || sales.length === 0) return 0;

  let synced = 0;

  for (const sale of sales) {
    if (sale.IsStorno === 1) continue;

    const sku = sale.supplierArticle || String(sale.nmId);
    const categoryId = await ensureCategory(sale.subject);
    const productId = await ensureProduct(sku, sale.subject || sku, sale.barcode, categoryId);

    const saleDate = sale.date.split("T")[0];
    const revenue = sale.priceWithDisc || sale.finishedPrice || 0;
    const forPay = sale.forPay || 0;
    const commission = Math.max(revenue - forPay, 0);
    const netProfit = forPay;

    await pool.query(
      `INSERT INTO sales (product_id, marketplace_id, sale_date, quantity, revenue, for_pay, net_profit, commission, logistics_cost)
       VALUES ($1, $2, $3, 1, $4, $5, $6, $7, 0)
       ON CONFLICT DO NOTHING`,
      [productId, marketplaceId, saleDate, revenue, forPay, netProfit, commission]
    );
    synced++;
  }

  return synced;
}

// ============================================================
// REPORT DETAIL SYNC — gets logistics, commissions, penalties
// WB API: GET /api/v5/supplier/reportDetailByPeriod
// This is the MAIN source for accurate P&L data
// ============================================================
async function syncReportDetail(apiKey: string, marketplaceId: number, daysBack: number = 30): Promise<number> {
  const dateFrom = dateNDaysAgo(daysBack);
  const dateTo = new Date().toISOString().split("T")[0];

  // WB Report API uses rrdid for pagination
  let rrdid = 0;
  let totalProcessed = 0;
  const logisticsByProductDate = new Map<string, number>();
  const commissionByProductDate = new Map<string, number>();
  const penaltiesByProductDate = new Map<string, number>();

  console.log(`[WB Report] Fetching detail report ${dateFrom} → ${dateTo}...`);

  while (true) {
    const url = `${WB_STATS_API}/api/v5/supplier/reportDetailByPeriod?dateFrom=${dateFrom}&dateTo=${dateTo}&rrdid=${rrdid}&limit=100000`;
    const rows = await wbFetch<WBReportDetail[]>(url, apiKey);

    if (!rows || rows.length === 0) break;

    for (const row of rows) {
      const sku = row.sa_name || String(row.nm_id);
      const saleDate = (row.sale_dt || row.order_dt || "").split("T")[0];
      if (!saleDate) continue;

      const key = `${sku}|${saleDate}`;
      const operName = (row.supplier_oper_name || "").toLowerCase();

      // Accumulate logistics
      if (row.delivery_rub && row.delivery_rub > 0) {
        logisticsByProductDate.set(key, (logisticsByProductDate.get(key) || 0) + row.delivery_rub);
      }

      // Accumulate WB commission from report (more accurate than revenue - forPay)
      if (row.ppvz_sales_commission && row.ppvz_sales_commission > 0) {
        // Only for sales, not logistics rows
        if (operName.includes("продажа") || row.doc_type_name === "Продажа") {
          commissionByProductDate.set(key, (commissionByProductDate.get(key) || 0) + row.ppvz_sales_commission);
        }
      }

      // Penalties
      if (row.penalty && row.penalty > 0) {
        penaltiesByProductDate.set(key, (penaltiesByProductDate.get(key) || 0) + row.penalty);
      }

      rrdid = row.rrd_id;
    }

    totalProcessed += rows.length;
    console.log(`[WB Report] Processed ${totalProcessed} rows (rrdid=${rrdid})...`);

    if (rows.length < 100000) break;
  }

  // Now update sales rows with logistics data
  let updated = 0;

  for (const [key, logistics] of logisticsByProductDate) {
    const [sku, saleDate] = key.split("|");

    // Find product_id by sku
    const { rows: products } = await pool.query("SELECT id FROM products WHERE sku = $1", [sku]);
    if (products.length === 0) continue;
    const productId = products[0].id;

    // Get commission for same key
    const commission = commissionByProductDate.get(key) || 0;
    const penalty = penaltiesByProductDate.get(key) || 0;

    // Update all sales for this product+date with proportional logistics
    const { rows: salesRows } = await pool.query(
      `SELECT id, revenue FROM sales 
       WHERE product_id = $1 AND sale_date = $2 AND marketplace_id = $3`,
      [productId, saleDate, marketplaceId]
    );

    if (salesRows.length === 0) continue;

    // Distribute logistics evenly across sales on that date
    const logisticsPerSale = logistics / salesRows.length;
    const penaltyPerSale = penalty / salesRows.length;

    for (const sale of salesRows) {
      // Update logistics_cost; optionally update commission from report
      const updateFields: string[] = [];
      const updateValues: (number | string)[] = [];
      let paramIdx = 1;

      updateFields.push(`logistics_cost = $${paramIdx}`);
      updateValues.push(parseFloat(logisticsPerSale.toFixed(2)));
      paramIdx++;

      // If we have commission data from report, use it (more accurate)
      if (commission > 0 && salesRows.length > 0) {
        const commPerSale = commission / salesRows.length;
        updateFields.push(`commission = $${paramIdx}`);
        updateValues.push(parseFloat(commPerSale.toFixed(2)));
        paramIdx++;
      }

      // Recalculate net_profit = for_pay - logistics - penalty
      updateFields.push(`net_profit = for_pay - $${paramIdx} - $${paramIdx + 1}`);
      updateValues.push(parseFloat(logisticsPerSale.toFixed(2)));
      updateValues.push(parseFloat(penaltyPerSale.toFixed(2)));
      paramIdx += 2;

      updateValues.push(sale.id);

      await pool.query(
        `UPDATE sales SET ${updateFields.join(", ")} WHERE id = $${paramIdx}`,
        updateValues
      );
      updated++;
    }
  }

  // Also handle logistics rows that don't have matching sales
  // (WB charges logistics even for returns, storage, etc.)
  console.log(`[WB Report] Updated ${updated} sales with logistics data from ${totalProcessed} report rows`);
  console.log(`[WB Report] Unique product-dates with logistics: ${logisticsByProductDate.size}`);

  return totalProcessed;
}

async function syncCards(apiKey: string): Promise<number> {
  let synced = 0;
  let cursor = { updatedAt: "", nmID: 0 };
  const limit = 100;

  while (true) {
    const body: Record<string, unknown> = {
      settings: {
        cursor: { limit },
        filter: { withPhoto: -1 },
      },
    };
    if (cursor.updatedAt) {
      (body.settings as Record<string, unknown>).cursor = {
        limit, updatedAt: cursor.updatedAt, nmID: cursor.nmID,
      };
    }

    const data = await wbPost<WBCardListResponse>(
      `${WB_CONTENT_API}/content/v2/get/cards/list`, apiKey, body
    );
    if (!data.cards || data.cards.length === 0) break;

    for (const card of data.cards) {
      const sku = card.vendorCode || String(card.nmID);
      const name = card.title || sku;
      const barcode = card.barcodes?.[0] || null;
      const categoryId = await ensureCategory(card.subjectName);
      await ensureProduct(sku, name, barcode, categoryId);
      synced++;
    }

    if (data.cards.length < limit) break;
    cursor = { updatedAt: data.cursor.updatedAt, nmID: data.cursor.nmID };
  }

  return synced;
}

async function syncStocks(apiKey: string, marketplaceId: number): Promise<number> {
  const url = `${WB_STATS_API}/api/v1/supplier/stocks?dateFrom=${dateNDaysAgo(1)}`;
  const stocks = await wbFetch<WBStock[]>(url, apiKey);
  if (!stocks || stocks.length === 0) return 0;

  await pool.query("DELETE FROM inventory WHERE marketplace_id = $1", [marketplaceId]);

  let synced = 0;
  for (const stock of stocks) {
    const sku = stock.supplierArticle || String(stock.nmId);
    const categoryId = await ensureCategory(stock.subject);
    const productId = await ensureProduct(sku, stock.subject || sku, stock.barcode, categoryId);
    await pool.query(
      `INSERT INTO inventory (product_id, marketplace_id, warehouse, quantity, recorded_at) VALUES ($1, $2, $3, $4, NOW())`,
      [productId, marketplaceId, stock.warehouseName || "WB", stock.quantity]
    );
    synced++;
  }

  return synced;
}

async function syncReturns(apiKey: string, marketplaceId: number, daysBack: number = 30): Promise<number> {
  const dateFrom = dateNDaysAgo(daysBack);
  const url = `${WB_STATS_API}/api/v1/supplier/orders?dateFrom=${dateFrom}`;
  const orders = await wbFetch<WBOrder[]>(url, apiKey);
  if (!orders || orders.length === 0) return 0;

  let synced = 0;
  for (const order of orders) {
    if (!order.isCancel) continue;
    const sku = order.supplierArticle || String(order.nmId);
    const categoryId = await ensureCategory(order.subject);
    const productId = await ensureProduct(sku, order.subject || sku, order.barcode, categoryId);
    const returnDate = (order.cancelDate || order.date).split("T")[0];
    await pool.query(
      `INSERT INTO returns (product_id, marketplace_id, quantity, return_date) VALUES ($1, $2, 1, $3)`,
      [productId, marketplaceId, returnDate]
    );
    synced++;
  }

  return synced;
}

async function updateJob(jobId: number, status: string, records: number, error?: string): Promise<void> {
  if (status === "running") {
    await pool.query("UPDATE sync_jobs SET status = $2, started_at = NOW() WHERE id = $1", [jobId, status]);
  } else {
    await pool.query(
      `UPDATE sync_jobs SET status = $2, completed_at = NOW(), records_processed = $3, error_message = $4 WHERE id = $1`,
      [jobId, status, records, error || null]
    );
  }
}

export async function runWBSync(jobId: number): Promise<void> {
  let totalRecords = 0;
  try {
    await updateJob(jobId, "running", 0);
    const { apiKey, marketplaceId } = await getWBCredentials();

    console.log("[WB Sync] Cards...");
    totalRecords += await syncCards(apiKey);

    console.log("[WB Sync] Sales...");
    totalRecords += await syncSales(apiKey, marketplaceId, 30);

    console.log("[WB Sync] Report Detail (logistics, commissions)...");
    totalRecords += await syncReportDetail(apiKey, marketplaceId, 30);

    console.log("[WB Sync] Stocks...");
    totalRecords += await syncStocks(apiKey, marketplaceId);

    console.log("[WB Sync] Returns...");
    totalRecords += await syncReturns(apiKey, marketplaceId, 30);

    await updateJob(jobId, "completed", totalRecords);
    console.log(`[WB Sync] Done! ${totalRecords} records`);
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[WB Sync] Error:", message);
    await updateJob(jobId, "failed", totalRecords, message);
  }
}
