import pool from "@/lib/db";
import type { SaleRow, SalesPage } from "@/types/models";

const MAX_LIMIT = 200;

interface SalesQueryParams {
  days: number;
  category?: string;
  marketplace?: string;
  page?: number;
  limit?: number;
}

/**
 * Продажи с пагинацией
 */
export async function getSales(params: SalesQueryParams): Promise<SalesPage> {
  const { days, category, marketplace } = params;
  const page = Math.max(1, params.page || 1);
  const limit = Math.min(MAX_LIMIT, Math.max(1, params.limit || 50));
  const offset = (page - 1) * limit;

  const conditions: string[] = [];
  const queryParams: (string | number)[] = [];
  let idx = 0;

  idx++;
  conditions.push(`s.sale_date >= CURRENT_DATE - $${idx}::int`);
  queryParams.push(days);

  if (category && category !== "all") {
    idx++;
    conditions.push(`c.slug = $${idx}`);
    queryParams.push(category);
  }

  if (marketplace && marketplace !== "all") {
    idx++;
    conditions.push(`mp.slug = $${idx}`);
    queryParams.push(marketplace);
  }

  const where = "WHERE " + conditions.join(" AND ");

  const countResult = await pool.query(
    `SELECT COUNT(*)::int AS total
     FROM sales s
     JOIN products p ON p.id = s.product_id
     JOIN categories c ON c.id = p.category_id
     JOIN marketplaces mp ON mp.id = s.marketplace_id
     ${where}`,
    queryParams
  );

  const dataParams = [...queryParams, limit, offset];
  const result = await pool.query(
    `SELECT
      s.id::text,
      s.sale_date::text              AS date,
      p.name                         AS product_name,
      p.sku,
      c.name                         AS category,
      s.quantity,
      s.revenue::float,
      s.net_profit::float            AS profit,
      s.commission::float,
      s.logistics_cost::float        AS logistics,
      mp.name                        AS marketplace,
      mp.slug                        AS marketplace_slug
    FROM sales s
    JOIN products p ON p.id = s.product_id
    JOIN categories c ON c.id = p.category_id
    JOIN marketplaces mp ON mp.id = s.marketplace_id
    ${where}
    ORDER BY s.sale_date DESC, s.id DESC
    LIMIT $${idx + 1} OFFSET $${idx + 2}`,
    dataParams
  );

  const total = countResult.rows[0].total;
  return {
    items: result.rows as SaleRow[],
    total,
    page,
    limit,
    pages: Math.ceil(total / limit),
  };
}

/**
 * Все продажи для CSV-экспорта (без пагинации)
 */
export async function getSalesForExport(
  days: number,
  category?: string,
  marketplace?: string
): Promise<SaleRow[]> {
  const conditions: string[] = [];
  const params: (string | number)[] = [];
  let idx = 0;

  idx++;
  conditions.push(`s.sale_date >= CURRENT_DATE - $${idx}::int`);
  params.push(days);

  if (category && category !== "all") {
    idx++;
    conditions.push(`c.slug = $${idx}`);
    params.push(category);
  }

  if (marketplace && marketplace !== "all") {
    idx++;
    conditions.push(`mp.slug = $${idx}`);
    params.push(marketplace);
  }

  const where = "WHERE " + conditions.join(" AND ");

  const { rows } = await pool.query(
    `SELECT
      s.sale_date::text              AS date,
      p.name                         AS product_name,
      p.sku,
      c.name                         AS category,
      mp.name                        AS marketplace,
      s.quantity,
      s.revenue::float,
      s.net_profit::float            AS profit,
      s.commission::float,
      s.logistics_cost::float        AS logistics
    FROM sales s
    JOIN products p ON p.id = s.product_id
    JOIN categories c ON c.id = p.category_id
    JOIN marketplaces mp ON mp.id = s.marketplace_id
    ${where}
    ORDER BY s.sale_date DESC, s.id DESC`,
    params
  );

  return rows;
}
