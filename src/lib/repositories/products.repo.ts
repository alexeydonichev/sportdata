import pool from "@/lib/db";
import type { ProductListItem, ABCProduct, Category } from "@/types/models";

// ============================================================
// Products Repository
// ============================================================

const ALLOWED_SORTS: Record<string, string> = {
  revenue: "revenue",
  profit: "profit",
  quantity: "quantity",
  name: "p.name",
  price: "avg_price",
  margin: "margin_pct",
  stock: "stock",
};

interface ProductQueryParams {
  category?: string;
  search?: string;
  sort?: string;
  order?: "asc" | "desc";
  salesDays?: number;
}

/**
 * Список товаров с метриками
 */
export async function getProducts(
  params: ProductQueryParams = {}
): Promise<ProductListItem[]> {
  const { category, search, sort = "revenue", order = "desc" } = params;
  const salesDays = params.salesDays || 90;

  const conditions: string[] = [];
  const queryParams: (string | number)[] = [];
  let idx = 0;

  // Период для подзапроса sales
  idx++;
  queryParams.push(salesDays);

  if (category && category !== "all") {
    idx++;
    conditions.push(`c.slug = $${idx}`);
    queryParams.push(category);
  }

  if (search && search.length <= 100) {
    idx++;
    conditions.push(`(p.name ILIKE $${idx} OR p.sku ILIKE $${idx})`);
    queryParams.push(`%${search}%`);
  }

  const where = conditions.length > 0 ? "WHERE " + conditions.join(" AND ") : "";
  const sortCol = ALLOWED_SORTS[sort] || "revenue";
  const sortDir = order === "asc" ? "ASC" : "DESC";

  const { rows } = await pool.query(
    `SELECT
      p.id::text AS id,
      p.name,
      p.sku,
      p.cost_price::float,
      c.name AS category,
      c.slug AS category_slug,
      COALESCE(s.revenue, 0)::float AS revenue,
      COALESCE(s.profit, 0)::float AS profit,
      COALESCE(s.quantity, 0)::int AS quantity,
      COALESCE(s.orders, 0)::int AS orders,
      CASE WHEN COALESCE(s.quantity, 0) > 0
        THEN ROUND((s.revenue / s.quantity)::numeric, 0)::float
        ELSE COALESCE(p.cost_price::float, 0)
      END AS avg_price,
      CASE WHEN COALESCE(s.revenue, 0) > 0
        THEN ROUND((s.profit / s.revenue * 100)::numeric, 1)::float
        ELSE 0
      END AS margin_pct,
      COALESCE(inv.total_stock, 0)::int AS stock,
      COALESCE(ret.total_returns, 0)::int AS returns,
      CASE WHEN COALESCE(s.quantity, 0) > 0
        THEN ROUND((COALESCE(ret.total_returns, 0)::numeric / s.quantity * 100), 1)::float
        ELSE 0
      END AS return_pct
    FROM products p
    JOIN categories c ON c.id = p.category_id
    LEFT JOIN (
      SELECT product_id,
        SUM(revenue) AS revenue,
        SUM(net_profit) AS profit,
        SUM(quantity) AS quantity,
        COUNT(*) AS orders
      FROM sales
      WHERE sale_date >= CURRENT_DATE - $1::int
      GROUP BY product_id
    ) s ON s.product_id = p.id
    LEFT JOIN (
      SELECT product_id, SUM(quantity) AS total_stock
      FROM inventory GROUP BY product_id
    ) inv ON inv.product_id = p.id
    LEFT JOIN (
      SELECT product_id, SUM(quantity) AS total_returns
      FROM returns GROUP BY product_id
    ) ret ON ret.product_id = p.id
    ${where}
    ORDER BY ${sortCol} ${sortDir} NULLS LAST`,
    queryParams
  );

  return rows as ProductListItem[];
}

/**
 * Товары для ABC-анализа
 */
export async function getProductsForABC(days: number): Promise<ABCProduct[]> {
  const { rows } = await pool.query(
    `SELECT
      p.id::text AS id,
      p.name,
      p.sku,
      c.name AS category,
      COALESCE(s.revenue, 0)::float AS revenue,
      COALESCE(s.profit, 0)::float AS profit,
      COALESCE(s.quantity, 0)::int AS quantity,
      COALESCE(s.orders, 0)::int AS orders
    FROM products p
    JOIN categories c ON c.id = p.category_id
    LEFT JOIN (
      SELECT product_id,
        SUM(revenue) AS revenue,
        SUM(net_profit) AS profit,
        SUM(quantity) AS quantity,
        COUNT(*) AS orders
      FROM sales
      WHERE sale_date >= CURRENT_DATE - $1::int
      GROUP BY product_id
    ) s ON s.product_id = p.id
    ORDER BY revenue DESC NULLS LAST`,
    [days]
  );
  return rows as ABCProduct[];
}

/**
 * Категории с кол-вом товаров и выручкой
 */
export async function getCategories(): Promise<Category[]> {
  const { rows } = await pool.query(`
    SELECT
      c.slug,
      c.name,
      COUNT(p.id)::int AS product_count,
      COALESCE(SUM(s.revenue), 0)::float AS revenue
    FROM categories c
    LEFT JOIN products p ON p.category_id = c.id
    LEFT JOIN (
      SELECT product_id, SUM(revenue) AS revenue
      FROM sales WHERE sale_date >= CURRENT_DATE - 90
      GROUP BY product_id
    ) s ON s.product_id = p.id
    GROUP BY c.slug, c.name
    ORDER BY revenue DESC
  `);
  return rows as Category[];
}
