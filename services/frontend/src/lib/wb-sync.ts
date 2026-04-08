import { normalizeWbSale } from "./wb-normalize";
import { copySales } from "./pg-copy";
import https from "https";
import pool from "./db";
import { Agent } from "undici";
import { decrypt } from "./crypto";

const WB_INITIAL_DELAY = 5000;
const WB_CONCURRENCY = 2;
const WB_STATS_API = "https://statistics-api.wildberries.ru";
const WB_CONTENT_API = "https://content-api.wildberries.ru";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const dispatcher = new Agent({
  connections: 5,
});

const agent = new https.Agent({
  keepAlive: true,
  maxSockets: 10,
});

function filterWbRows(rows: any[]) {
  return rows.filter(
    (r: any) =>
      r &&
      (r.saleID || r.nmId || r.supplierArticle || r.barcode) &&
      (r.date || r.lastChangeDate)
  );
}

async function wbRequest<T>(
  url: string,
  apiKey: string,
  options: RequestInit = {},
  maxRetries = 5
): Promise<T> {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);

    try {
      await sleep(350 + Math.random() * 400);

      const res = await fetch(url, {
        ...options,
        headers: {
          Authorization: apiKey,
          "Content-Type": "application/json",
          "User-Agent": "sportdata-sync/1.0",
          ...(options.headers || {}),
        },
        dispatcher,
        signal: controller.signal,
      } as RequestInit);

      clearTimeout(timeout);

      if (res.status === 429) {
        const wait = Math.min(60 * attempt, 300);
        console.warn(`[WB] 429 retry in ${wait}s`);
        await sleep(wait * 1000);
        continue;
      }

      if (res.status >= 500) {
        await sleep(10 * attempt * 1000);
        continue;
      }

      if (!res.ok) {
        const txt = await res.text();
        throw new Error(`WB ${res.status}: ${txt}`);
      }

      return res.json();
    } catch (e) {
      clearTimeout(timeout);
      if (attempt === maxRetries) throw e;
      await sleep(5 * attempt * 1000);
    }
  }

  throw new Error("WB request failed");
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

async function getWBCredentials() {
  const { rows } = await pool.query(`
    SELECT mc.api_key_encrypted, mc.marketplace_id
    FROM marketplace_credentials mc
    JOIN marketplaces m ON m.id = mc.marketplace_id
    WHERE m.slug = 'wildberries'
    AND mc.is_active = true
    LIMIT 1
  `);

  if (!rows.length) throw new Error("WB credentials not found");

  return {
    apiKey: decrypt(rows[0].api_key_encrypted),
    marketplaceId: rows[0].marketplace_id,
  };
}

const categoryCache = new Map<string, number>();
const productCache = new Map<string, number>();

async function ensureCategoryBatch(names: string[]) {
  const unique = [...new Set(names.map((n) => n || "Другое"))];
  const slugs = unique.map(toSlug);

  const { rows } = await pool.query(
    `SELECT id, slug FROM categories WHERE slug = ANY($1)`,
    [slugs]
  );

  for (const r of rows) {
    categoryCache.set(r.slug, r.id);
  }

  const missing = unique.filter((n) => !categoryCache.has(toSlug(n)));
  if (!missing.length) return;

  const values: any[] = [];
  const ph: string[] = [];
  let p = 1;

  for (const name of missing) {
    ph.push(`($${p},$${p + 1})`);
    values.push(toSlug(name), name);
    p += 2;
  }

  const ins = await pool.query(
    `INSERT INTO categories (slug,name)
     VALUES ${ph.join(",")}
     ON CONFLICT (slug) DO NOTHING
     RETURNING id, slug`,
    values
  );

  for (const r of ins.rows) {
    categoryCache.set(r.slug, r.id);
  }
}

async function ensureProductBatch(
  items: {
    sku: string;
    name: string;
    barcode: string | null;
    subjectName: string;
    nmId: number;
    brand?: string;
  }[]
) {
  const uniqueNm = [...new Set(items.map((i) => i.nmId).filter(Boolean))];

  const { rows } = await pool.query(
    `SELECT id, nm_id, sku FROM products WHERE nm_id = ANY($1)`,
    [uniqueNm]
  );

  for (const r of rows) {
    productCache.set(`nm_${r.nm_id}`, r.id);
    productCache.set(`sku_${r.sku}`, r.id);
  }

  const insertRows: {
    name: string;
    sku: string;
    barcode: string | null;
    nmId: number;
    brand: string | null;
    categoryId: number;
  }[] = [];

  for (const item of items) {
    if (!item.nmId) continue;
    if (productCache.has(`nm_${item.nmId}`)) continue;

    const catId = categoryCache.get(toSlug(item.subjectName || "Другое"));
    if (!catId) continue;

    insertRows.push({
      name: item.name,
      sku: item.sku,
      barcode: item.barcode,
      nmId: item.nmId,
      brand: item.brand || null,
      categoryId: catId,
    });
  }

  if (!insertRows.length) return;

  const values: any[] = [];
  const ph: string[] = [];
  let p = 1;

  for (const r of insertRows) {
    ph.push(`($${p},$${p + 1},$${p + 2},0,$${p + 3},$${p + 4},$${p + 5})`);
    values.push(r.name, r.sku, r.barcode, r.categoryId, r.nmId, r.brand);
    p += 6;
  }

  const ins = await pool.query(
    `INSERT INTO products
     (name,sku,barcode,cost_price,category_id,nm_id,brand)
     VALUES ${ph.join(",")}
     ON CONFLICT (nm_id)
     DO UPDATE SET
       name = EXCLUDED.name,
       sku = EXCLUDED.sku,
       barcode = COALESCE(EXCLUDED.barcode,products.barcode),
       category_id = EXCLUDED.category_id,
       brand = COALESCE(EXCLUDED.brand,products.brand),
       updated_at = NOW()
     RETURNING id,nm_id,sku`,
    values
  );

  for (const r of ins.rows) {
    productCache.set(`nm_${r.nm_id}`, r.id);
    productCache.set(`sku_${r.sku}`, r.id);
  }
}

function getProductId(nmId: number, sku?: string): number | null {
  if (nmId && productCache.has(`nm_${nmId}`)) {
    return productCache.get(`nm_${nmId}`)!;
  }
  if (sku && productCache.has(`sku_${sku}`)) {
    return productCache.get(`sku_${sku}`)!;
  }
  return null;
}

async function syncSales(apiKey: string, marketplaceId: number, _daysBack = 90) {
  const url = `${WB_STATS_API}/api/v1/supplier/sales?dateFrom=${dateNDaysAgo(365)}`;
  const sales = await wbRequest<any[]>(url, apiKey);

  const copyRows = sales.map((s: any) =>
    [s.sale_id ?? 0, s.date ?? 0, s.sku ?? 0, s.quantity ?? 0, s.price ?? 0].join("\t")
  );

  await copySales(copyRows);

  if (!sales || !sales.length) return 0;

  await ensureCategoryBatch(sales.map((s: any) => s.subject || "Другое"));

  await ensureProductBatch(
    Array.from(
      new Map(
        sales.map((s: any) => [
          s.nmId,
          {
            sku: s.supplierArticle || String(s.nmId),
            name: s.subject || s.supplierArticle,
            barcode: s.barcode,
            subjectName: s.subject,
            nmId: s.nmId,
            brand: s.brand,
          },
        ])
      ).values()
    )
  );

  const BATCH = 2000;
  let synced = 0;

  for (let i = 0; i < sales.length; i += BATCH) {
    const batch = sales.slice(i, i + BATCH);
    const values: any[] = [];
    const ph: string[] = [];
    let p = 1;

    for (const s of batch) {
      if (s.IsStorno === 1) continue;

      const pid = getProductId(s.nmId, s.supplierArticle);
      if (!pid) continue;

      const rev = s.priceWithDisc || s.finishedPrice || 0;
      const fp = s.forPay || 0;

      ph.push(
        `($${p},$${p + 1},$${p + 2},1,$${p + 3},$${p + 4},$${p + 5},$${p + 6},0,$${p + 7})`
      );

      values.push(
        pid,
        marketplaceId,
        s.date.split("T")[0],
        rev,
        fp,
        fp,
        Math.max(rev - fp, 0),
        s.saleID || null
      );

      p += 8;
      synced++;
    }

    if (ph.length) {
      await pool.query(
        `INSERT INTO sales
         (product_id,marketplace_id,sale_date,quantity,revenue,for_pay,net_profit,commission,logistics_cost,sale_id)
         VALUES ${ph.join(",")}
         ON CONFLICT (sale_id, marketplace_id, sale_date)
         DO UPDATE SET
           revenue = EXCLUDED.revenue,
           for_pay = EXCLUDED.for_pay,
           commission = EXCLUDED.commission`,
        values
      );
    }
  }

  console.log(`[WB] Sales synced: ${synced}`);
  return synced;
}

async function syncStocks(apiKey: string, marketplaceId: number) {
  const url = `${WB_STATS_API}/api/v1/supplier/stocks?dateFrom=${dateNDaysAgo(1)}`;
  const stocks = await wbRequest<any[]>(url, apiKey);

  if (!stocks || !stocks.length) return 0;

  await ensureCategoryBatch(stocks.map((s: any) => s.subject || "Другое"));

  await ensureProductBatch(
    Array.from(
      new Map(
        stocks.map((s: any) => [
          s.nmId,
          {
            sku: s.supplierArticle || String(s.nmId),
            name: s.subject || s.supplierArticle,
            barcode: s.barcode,
            subjectName: s.subject,
            nmId: s.nmId,
            brand: s.brand,
          },
        ])
      ).values()
    )
  );

  await pool.query(`DELETE FROM inventory WHERE marketplace_id=$1`, [marketplaceId]);

  const BATCH = 2000;
  let synced = 0;

  for (let i = 0; i < stocks.length; i += BATCH) {
    const batch = stocks.slice(i, i + BATCH);
    const values: any[] = [];
    const ph: string[] = [];
    let p = 1;

    for (const s of batch) {
      const pid = getProductId(s.nmId, s.supplierArticle);
      if (!pid) continue;

      ph.push(`($${p},$${p + 1},$${p + 2},$${p + 3},NOW())`);
      values.push(pid, marketplaceId, s.warehouseName || "WB", Math.round(s.quantity));
      p += 4;
      synced++;
    }

    if (ph.length) {
      await pool.query(
        `INSERT INTO inventory
         (product_id,marketplace_id,warehouse,quantity,recorded_at)
         VALUES ${ph.join(",")}`,
        values
      );
    }
  }

  console.log(`[WB] Stocks synced: ${synced}`);
  return synced;
}

export async function runWBSync(jobId?: number) {
  const { apiKey, marketplaceId } = await getWBCredentials();

  // Mark job as running
  if (jobId) {
    await pool.query(
      `UPDATE sync_jobs SET status='running', started_at=NOW() WHERE id=$1`,
      [jobId]
    );
  }

  console.log("[WB] Sync started");

  try {
    const sales = await syncSales(apiKey, marketplaceId);
    const stocks = await syncStocks(apiKey, marketplaceId);

    categoryCache.clear();
    productCache.clear();

    // Mark job as completed
    if (jobId) {
      await pool.query(
        `UPDATE sync_jobs SET status='completed', completed_at=NOW(), records_processed=$1 WHERE id=$2`,
        [sales + stocks, jobId]
      );
    }

    console.log("[WB] Sync complete", { sales, stocks });
    return { sales, stocks };
  } catch (err) {
    // Mark job as failed
    if (jobId) {
      await pool.query(
        `UPDATE sync_jobs SET status='failed', completed_at=NOW(), error_message=$1 WHERE id=$2`,
        [err instanceof Error ? err.message : String(err), jobId]
      );
    }
    console.error("[WB] Sync failed:", err);
    throw err;
  }
}
