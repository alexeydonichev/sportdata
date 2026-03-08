import pool from "@/lib/db";

export interface UnitEconomicsItem {
  id: number;
  name: string;
  sku: string;
  category: string;
  category_slug: string;
  cost_price: number;
  avg_price: number;
  revenue: number;
  returns_amount: number;
  commission: number;
  logistics: number;
  profit: number;
  units_sold: number;
  units_returned: number;
  margin_pct: number;
  profit_per_unit: number;
  roi: number;
  return_rate: number;
}

export interface UnitEconomicsSummary {
  total_revenue: number;
  total_profit: number;
  total_commission: number;
  total_logistics: number;
  total_cogs: number;
  total_units: number;
  total_returns: number;
  avg_margin: number;
  avg_roi: number;
  products_count: number;
}

export interface UnitEconomicsData {
  items: UnitEconomicsItem[];
  summary: UnitEconomicsSummary;
}

const ALLOWED_SORTS: Record<string, string> = {
  revenue: "revenue",
  profit: "profit",
  margin: "margin_pct",
  quantity: "units_sold",
  name: "p.name",
  roi: "roi",
};

export async function getUnitEconomics(
  days: number,
  opts: { sort?: string; order?: string; category?: string; marketplace?: string } = {}
): Promise<UnitEconomicsData> {
  const sortCol = ALLOWED_SORTS[opts.sort || "revenue"] || "revenue";
  const sortDir = opts.order === "asc" ? "ASC" : "DESC";

  const params: (number | string)[] = [days];
  let catWhere = "";
  let mpJoin = "";
  let mpWhere = "";

  if (opts.category && opts.category !== "all") {
    params.push(opts.category);
    catWhere = `AND c.slug = $${params.length}`;
  }

  if (opts.marketplace && opts.marketplace !== "all") {
    params.push(opts.marketplace);
    mpJoin = "JOIN marketplaces mp ON mp.id = s.marketplace_id";
    mpWhere = `AND mp.slug = $${params.length}`;
  }

  const res = await pool.query(`
    SELECT
      p.id, p.name, p.sku, COALESCE(p.cost_price, 0)::float AS cost_price,
      COALESCE(c.name, 'Without category') AS category,
      COALESCE(c.slug, 'none') AS category_slug,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS returns_amount,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.commission ELSE 0 END), 0)::float AS commission,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.logistics_cost ELSE 0 END), 0)::float AS logistics,
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS units_sold,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS units_returned,
      COALESCE(SUM(s.net_profit), 0)::float AS profit,
      CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END) > 0
        THEN (SUM(s.net_profit) / SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END) * 100) ELSE 0 END::float AS margin_pct,
      CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
        THEN SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END) / SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) ELSE 0 END::float AS avg_price,
      CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
        THEN SUM(s.net_profit) / SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) ELSE 0 END::float AS profit_per_unit,
      CASE WHEN (COALESCE(p.cost_price,0) * SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) +
                  SUM(CASE WHEN s.quantity > 0 THEN s.commission + s.logistics_cost ELSE 0 END)) > 0
        THEN (SUM(s.net_profit) / (COALESCE(p.cost_price,0) * SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) +
               SUM(CASE WHEN s.quantity > 0 THEN s.commission + s.logistics_cost ELSE 0 END)) * 100) ELSE 0 END::float AS roi,
      CASE WHEN (SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) + SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)) > 0
        THEN (SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)::float /
              (SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) + SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)) * 100) ELSE 0 END::float AS return_rate
    FROM products p
    JOIN sales s ON s.product_id = p.id AND s.sale_date >= CURRENT_DATE - $1::int
    LEFT JOIN categories c ON c.id = p.category_id
    ${mpJoin}
    WHERE 1=1 ${catWhere} ${mpWhere}
    GROUP BY p.id, p.name, p.sku, p.cost_price, c.name, c.slug
    HAVING SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
    ORDER BY ${sortCol} ${sortDir}
  `, params);

  const totals = res.rows.reduce((acc: any, r: any) => {
    acc.revenue += r.revenue;
    acc.profit += r.profit;
    acc.commission += r.commission;
    acc.logistics += r.logistics;
    acc.cogs += (r.cost_price || 0) * r.units_sold;
    acc.units += r.units_sold;
    acc.returns += r.units_returned;
    return acc;
  }, { revenue: 0, profit: 0, commission: 0, logistics: 0, cogs: 0, units: 0, returns: 0 });

  const items = res.rows.map((r: any) => ({
    id: r.id,
    name: r.name,
    sku: r.sku,
    category: r.category,
    category_slug: r.category_slug,
    cost_price: r.cost_price || 0,
    avg_price: parseFloat(r.avg_price.toFixed(0)),
    revenue: r.revenue,
    returns_amount: r.returns_amount,
    commission: r.commission,
    logistics: r.logistics,
    profit: r.profit,
    units_sold: r.units_sold,
    units_returned: r.units_returned,
    margin_pct: parseFloat(r.margin_pct.toFixed(1)),
    profit_per_unit: parseFloat(r.profit_per_unit.toFixed(0)),
    roi: parseFloat(r.roi.toFixed(1)),
    return_rate: parseFloat(r.return_rate.toFixed(1)),
  }));

  const totalCosts = totals.cogs + totals.commission + totals.logistics;

  return {
    items,
    summary: {
      total_revenue: totals.revenue,
      total_profit: totals.profit,
      total_commission: totals.commission,
      total_logistics: totals.logistics,
      total_cogs: totals.cogs,
      total_units: totals.units,
      total_returns: totals.returns,
      avg_margin: totals.revenue > 0 ? parseFloat((totals.profit / totals.revenue * 100).toFixed(1)) : 0,
      avg_roi: totalCosts > 0 ? parseFloat((totals.profit / totalCosts * 100).toFixed(1)) : 0,
      products_count: res.rows.length,
    },
  };
}
