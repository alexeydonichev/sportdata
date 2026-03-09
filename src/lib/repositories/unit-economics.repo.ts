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
  for_pay: number;
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
  total_for_pay: number;
  total_units: number;
  total_returns: number;
  avg_margin: number;
  avg_roi: number;
  products_count: number;
  warnings: string[];
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
      COALESCE(c.name, 'Без категории') AS category,
      COALESCE(c.slug, 'none') AS category_slug,

      -- Revenue & returns
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END), 0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.revenue) ELSE 0 END), 0)::float AS returns_amount,

      -- Real WB commission = revenue - for_pay
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue - s.for_pay ELSE 0 END), 0)::float AS commission,
      COALESCE(SUM(s.logistics_cost), 0)::float AS logistics,

      -- For pay = what WB pays seller
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.for_pay ELSE 0 END), 0)::float AS for_pay,

      -- Units
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)::int AS units_sold,
      COALESCE(SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END), 0)::int AS units_returned,

      -- Profit = for_pay - cogs
      COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.for_pay ELSE 0 END), 0)::float
        - (COALESCE(p.cost_price, 0) * COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0))::float AS profit,

      -- Margin % = profit / revenue * 100
      CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END) > 0
        THEN ((COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.for_pay ELSE 0 END), 0)
              - COALESCE(p.cost_price, 0) * COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0))
              / SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END) * 100)
        ELSE 0 END::float AS margin_pct,

      -- Avg selling price
      CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
        THEN SUM(CASE WHEN s.quantity > 0 THEN s.revenue ELSE 0 END)
             / SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END)
        ELSE 0 END::float AS avg_price,

      -- Profit per unit
      CASE WHEN SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
        THEN (COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.for_pay ELSE 0 END), 0)
              - COALESCE(p.cost_price, 0) * COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0))
             / SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END)
        ELSE 0 END::float AS profit_per_unit,

      -- ROI = profit / (cogs + commission + logistics) * 100
      CASE WHEN (COALESCE(p.cost_price, 0) * COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)
                + COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue - s.for_pay ELSE 0 END), 0)
                + COALESCE(SUM(s.logistics_cost), 0)) > 0
        THEN ((COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.for_pay ELSE 0 END), 0)
              - COALESCE(p.cost_price, 0) * COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0))
             / (COALESCE(p.cost_price, 0) * COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END), 0)
                + COALESCE(SUM(CASE WHEN s.quantity > 0 THEN s.revenue - s.for_pay ELSE 0 END), 0)
                + COALESCE(SUM(s.logistics_cost), 0)) * 100)
        ELSE 0 END::float AS roi,

      -- Return rate
      CASE WHEN (SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END)
                + SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)) > 0
        THEN (SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)::float
             / (SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END)
                + SUM(CASE WHEN s.quantity < 0 THEN ABS(s.quantity) ELSE 0 END)) * 100)
        ELSE 0 END::float AS return_rate

    FROM products p
    JOIN sales s ON s.product_id = p.id AND s.sale_date >= CURRENT_DATE - $1::int
    LEFT JOIN categories c ON c.id = p.category_id
    ${mpJoin}
    WHERE 1=1 ${catWhere} ${mpWhere}
    GROUP BY p.id, p.name, p.sku, p.cost_price, c.name, c.slug
    HAVING SUM(CASE WHEN s.quantity > 0 THEN s.quantity ELSE 0 END) > 0
    ORDER BY ${sortCol} ${sortDir}
  `, params);

  const items: UnitEconomicsItem[] = res.rows.map((r: Record<string, number | string>) => ({
    id: Number(r.id),
    name: String(r.name),
    sku: String(r.sku),
    category: String(r.category),
    category_slug: String(r.category_slug),
    cost_price: Number(r.cost_price) || 0,
    avg_price: parseFloat(Number(r.avg_price).toFixed(0)),
    revenue: Number(r.revenue),
    returns_amount: Number(r.returns_amount),
    commission: Number(r.commission),
    logistics: Number(r.logistics),
    for_pay: Number(r.for_pay),
    profit: Number(r.profit),
    units_sold: Number(r.units_sold),
    units_returned: Number(r.units_returned),
    margin_pct: parseFloat(Number(r.margin_pct).toFixed(1)),
    profit_per_unit: parseFloat(Number(r.profit_per_unit).toFixed(0)),
    roi: parseFloat(Number(r.roi).toFixed(1)),
    return_rate: parseFloat(Number(r.return_rate).toFixed(1)),
  }));

  const totals = items.reduce(
    (acc, r) => {
      acc.revenue += r.revenue;
      acc.profit += r.profit;
      acc.commission += r.commission;
      acc.logistics += r.logistics;
      acc.cogs += r.cost_price * r.units_sold;
      acc.for_pay += r.for_pay;
      acc.units += r.units_sold;
      acc.returns += r.units_returned;
      return acc;
    },
    { revenue: 0, profit: 0, commission: 0, logistics: 0, cogs: 0, for_pay: 0, units: 0, returns: 0 }
  );

  const totalCosts = totals.cogs + totals.commission + totals.logistics;

  const warnings: string[] = [];
  if (totals.cogs === 0) {
    warnings.push("Себестоимость товаров не заполнена. Прибыль = сумма к выплате от WB. Заполните себестоимость в разделе Товары.");
  }

  return {
    items,
    summary: {
      total_revenue: totals.revenue,
      total_profit: totals.profit,
      total_commission: totals.commission,
      total_logistics: totals.logistics,
      total_cogs: totals.cogs,
      total_for_pay: totals.for_pay,
      total_units: totals.units,
      total_returns: totals.returns,
      avg_margin: totals.revenue > 0 ? parseFloat((totals.profit / totals.revenue * 100).toFixed(1)) : 0,
      avg_roi: totalCosts > 0 ? parseFloat((totals.profit / totalCosts * 100).toFixed(1)) : 0,
      products_count: items.length,
      warnings,
    },
  };
}
