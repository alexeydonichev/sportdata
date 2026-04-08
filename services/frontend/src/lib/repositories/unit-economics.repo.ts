import pool from "@/lib/db";

export interface UnitEconomicsItem {
  id: number; name: string; sku: string; category: string; category_slug: string;
  cost_price: number; avg_price: number; revenue: number; returns_amount: number;
  commission: number; logistics: number; for_pay: number; profit: number;
  units_sold: number; units_returned: number; margin_pct: number;
  profit_per_unit: number; roi: number; return_rate: number;
}

export interface UnitEconomicsSummary {
  total_revenue: number; total_profit: number; total_commission: number;
  total_logistics: number; total_cogs: number; total_for_pay: number;
  total_units: number; total_returns: number; avg_margin: number;
  avg_roi: number; products_count: number; warnings: string[];
}

export interface UnitEconomicsData { items: UnitEconomicsItem[]; summary: UnitEconomicsSummary; }

const SORTS: Record<string,string> = { revenue:"revenue", profit:"profit", margin:"margin_pct", quantity:"units_sold", name:"p.name", roi:"roi" };

export async function getUnitEconomics(
  days: number, opts: { sort?: string; order?: string; category?: string; marketplace?: string } = {}
): Promise<UnitEconomicsData> {
  const sortCol = SORTS[opts.sort||"revenue"]||"revenue";
  const sortDir = opts.order==="asc"?"ASC":"DESC";
  const params: (number|string)[] = [days];
  let catW="", mpJ="", mpW="";
  if (opts.category&&opts.category!=="all") { params.push(opts.category); catW=`AND c.slug=$${params.length}`; }
  if (opts.marketplace&&opts.marketplace!=="all") { params.push(opts.marketplace); mpJ="JOIN marketplaces mp ON mp.id=s.marketplace_id"; mpW=`AND mp.slug=$${params.length}`; }

  const res = await pool.query(`
    SELECT p.id, p.name, p.sku, COALESCE(p.cost_price,0)::float AS cost_price,
      COALESCE(c.name,'Без категории') AS category, COALESCE(c.slug,'none') AS category_slug,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.revenue) ELSE 0 END),0)::float AS returns_amount,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.commission ELSE 0 END),0)::float AS commission,
      COALESCE(SUM(s.logistics_cost),0)::float AS logistics,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN (s.revenue-s.commission-s.logistics_cost) ELSE 0 END),0)::float AS for_pay,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS units_sold,
      COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int AS units_returned,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN (s.revenue-s.commission-s.logistics_cost) ELSE 0 END),0)::float
        - (COALESCE(p.cost_price,0)*COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0))::float AS profit,
      CASE WHEN SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END)>0
        THEN ((COALESCE(SUM(CASE WHEN s.quantity>0 THEN (s.revenue-s.commission-s.logistics_cost) ELSE 0 END),0)
              -COALESCE(p.cost_price,0)*COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0))
              /SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END)*100) ELSE 0 END::float AS margin_pct,
      CASE WHEN SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END)>0
        THEN SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END)/SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END)
        ELSE 0 END::float AS avg_price,
      CASE WHEN SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END)>0
        THEN (COALESCE(SUM(CASE WHEN s.quantity>0 THEN (s.revenue-s.commission-s.logistics_cost) ELSE 0 END),0)
              -COALESCE(p.cost_price,0)*COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0))
             /SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END) ELSE 0 END::float AS profit_per_unit,
      CASE WHEN (COALESCE(p.cost_price,0)*COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)
                +COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.commission ELSE 0 END),0)
                +COALESCE(SUM(s.logistics_cost),0))>0
        THEN ((COALESCE(SUM(CASE WHEN s.quantity>0 THEN (s.revenue-s.commission-s.logistics_cost) ELSE 0 END),0)
              -COALESCE(p.cost_price,0)*COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0))
             /(COALESCE(p.cost_price,0)*COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)
                +COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.commission ELSE 0 END),0)
                +COALESCE(SUM(s.logistics_cost),0))*100) ELSE 0 END::float AS roi,
      CASE WHEN (SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END)+SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END))>0
        THEN (SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END)::float
             /(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END)+SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END))*100)
        ELSE 0 END::float AS return_rate
    FROM products p JOIN sales s ON s.product_id=p.id AND s.sale_date>=CURRENT_DATE-$1::int
    LEFT JOIN categories c ON c.id=p.category_id ${mpJ}
    WHERE 1=1 ${catW} ${mpW}
    GROUP BY p.id,p.name,p.sku,p.cost_price,c.name,c.slug
    HAVING SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END)>0
    ORDER BY ${sortCol} ${sortDir}
  `, params);

  const items: UnitEconomicsItem[] = res.rows.map((r: Record<string,number|string>) => ({
    id:+r.id, name:String(r.name), sku:String(r.sku), category:String(r.category),
    category_slug:String(r.category_slug), cost_price:+r.cost_price||0,
    avg_price:+Number(r.avg_price).toFixed(0), revenue:+r.revenue,
    returns_amount:+r.returns_amount, commission:+r.commission, logistics:+r.logistics,
    for_pay:+r.for_pay, profit:+r.profit, units_sold:+r.units_sold,
    units_returned:+r.units_returned, margin_pct:+Number(r.margin_pct).toFixed(1),
    profit_per_unit:+Number(r.profit_per_unit).toFixed(0),
    roi:+Number(r.roi).toFixed(1), return_rate:+Number(r.return_rate).toFixed(1),
  }));

  const t = items.reduce((a,r) => {
    a.rev+=r.revenue; a.prof+=r.profit; a.comm+=r.commission; a.logi+=r.logistics;
    a.cogs+=r.cost_price*r.units_sold; a.fp+=r.for_pay; a.u+=r.units_sold; a.ret+=r.units_returned;
    return a;
  }, {rev:0,prof:0,comm:0,logi:0,cogs:0,fp:0,u:0,ret:0});

  const w: string[] = [];
  if (t.cogs===0) w.push("Себестоимость не заполнена. Прибыль = выплата WB. Заполните в разделе Товары.");
  const tc = t.cogs+t.comm+t.logi;

  return { items, summary: { total_revenue:t.rev, total_profit:t.prof, total_commission:t.comm,
    total_logistics:t.logi, total_cogs:t.cogs, total_for_pay:t.fp, total_units:t.u,
    total_returns:t.ret, avg_margin:t.rev>0?+(t.prof/t.rev*100).toFixed(1):0,
    avg_roi:tc>0?+(t.prof/tc*100).toFixed(1):0, products_count:items.length, warnings:w } };
}
