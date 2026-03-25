import pool from "@/lib/db";
import type { ProductDetail } from "@/types/models";

function pctChange(cur: number, prev: number): number | null {
  if (prev === 0 && cur === 0) return 0;
  if (prev === 0) return cur > 0 ? 100 : -100;
  return parseFloat((((cur - prev) / prev) * 100).toFixed(1));
}

export async function getProductDetail(productId: number, days: number): Promise<ProductDetail | null> {
  const productRes = await pool.query(`
    SELECT p.id::text, p.name, p.sku, p.barcode, p.cost_price::float,
      COALESCE(p.brand,'YourFit') AS brand, p.image_url,
      p.width, p.height, p.length, p.weight_g,
      p.retail_price::float AS retail_price, p.discount_price::float AS discount_price,
      p.nm_id, c.name AS category, c.slug AS category_slug, p.created_at::text
    FROM products p LEFT JOIN categories c ON c.id=p.category_id WHERE p.id=$1
  `, [productId]);
  if (productRes.rows.length === 0) return null;
  const pr = productRes.rows[0];

  const metricsRes = await pool.query(`
    SELECT
      COALESCE(SUM(CASE WHEN quantity>0 THEN revenue ELSE 0 END),0)::float AS total_revenue,
      COALESCE(SUM(CASE WHEN quantity>0 THEN for_pay ELSE 0 END),0)::float AS total_for_pay,
      COALESCE(SUM(CASE WHEN quantity>0 THEN quantity ELSE 0 END),0)::int AS total_sold,
      COUNT(CASE WHEN quantity>0 THEN 1 END)::int AS total_orders,
      COALESCE(SUM(CASE WHEN quantity>0 THEN commission ELSE 0 END),0)::float AS total_commission,
      COALESCE(SUM(logistics_cost),0)::float AS total_logistics,
      COALESCE(SUM(CASE WHEN quantity<0 THEN ABS(quantity) ELSE 0 END),0)::int AS total_returns,
      COALESCE(SUM(CASE WHEN quantity<0 THEN ABS(revenue) ELSE 0 END),0)::float AS returns_amount,
      COALESCE(SUM(penalty),0)::float AS total_penalty,
      COALESCE(SUM(acquiring_fee),0)::float AS total_acquiring,
      COALESCE(SUM(storage_fee),0)::float AS total_storage,
      COALESCE(SUM(deduction),0)::float AS total_deduction,
      COALESCE(SUM(acceptance_cost),0)::float AS total_acceptance,
      COALESCE(SUM(return_logistic_cost),0)::float AS total_return_logistics,
      COALESCE(SUM(additional_payment),0)::float AS total_additional_payment,
      COALESCE(AVG(CASE WHEN quantity>0 AND spp_percent>0 THEN spp_percent END),0)::float AS avg_spp_pct,
      COALESCE(AVG(CASE WHEN quantity>0 AND commission_percent>0 THEN commission_percent END),0)::float AS avg_commission_pct,
      COALESCE(SUM(net_profit),0)::float AS total_profit
    FROM sales WHERE product_id=$1 AND sale_date>=CURRENT_DATE-$2::int
  `, [productId, days]);
  const m = metricsRes.rows[0];

  const avgPriceRes = await pool.query(`
    SELECT CASE WHEN SUM(quantity)>0 THEN (SUM(revenue)/SUM(quantity))::float ELSE 0 END AS avg_price
    FROM sales WHERE product_id=$1 AND sale_date>=CURRENT_DATE-$2::int AND quantity>0
  `, [productId, days]);
  const avgPrice = avgPriceRes.rows[0]?.avg_price || 0;
  const marginPct = m.total_revenue > 0 ? (m.total_profit / m.total_revenue) * 100 : 0;
  const returnPct = (m.total_sold + m.total_returns) > 0 ? (m.total_returns / (m.total_sold + m.total_returns)) * 100 : 0;

  const prevRes = await pool.query(`
    SELECT COALESCE(SUM(CASE WHEN quantity>0 THEN revenue ELSE 0 END),0)::float AS total_revenue,
      COALESCE(SUM(net_profit),0)::float AS total_profit,
      COALESCE(SUM(CASE WHEN quantity>0 THEN quantity ELSE 0 END),0)::int AS total_sold,
      COUNT(CASE WHEN quantity>0 THEN 1 END)::int AS total_orders
    FROM sales WHERE product_id=$1 AND sale_date>=CURRENT_DATE-($2::int*2) AND sale_date<CURRENT_DATE-$2::int
  `, [productId, days]);
  const prev = prevRes.rows[0];

  const chartRes = await pool.query(`
    SELECT sale_date::text AS date,
      COALESCE(SUM(CASE WHEN quantity>0 THEN revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(net_profit),0)::float AS profit,
      COALESCE(SUM(CASE WHEN quantity>0 THEN quantity ELSE 0 END),0)::int AS quantity,
      COUNT(CASE WHEN quantity>0 THEN 1 END)::int AS orders
    FROM sales WHERE product_id=$1 AND sale_date>=CURRENT_DATE-$2::int
    GROUP BY sale_date ORDER BY sale_date
  `, [productId, days]);

  const inventoryRes = await pool.query(`
    SELECT warehouse, quantity::int AS stock, recorded_at::text AS updated_at
    FROM inventory WHERE product_id=$1 AND quantity>0 ORDER BY quantity DESC
  `, [productId]);
  const totalStock = inventoryRes.rows.reduce((s: number, r: {stock:number}) => s + r.stock, 0);

  const dailyAvgRes = await pool.query(`
    SELECT COALESCE(AVG(dq),0)::float AS avg_daily FROM (
      SELECT SUM(quantity) AS dq FROM sales
      WHERE product_id=$1 AND sale_date>=CURRENT_DATE-30 AND quantity>0 GROUP BY sale_date
    ) d
  `, [productId]);
  const avgDaily = dailyAvgRes.rows[0]?.avg_daily || 0;
  const daysOfStock = avgDaily > 0 ? Math.floor(totalStock / avgDaily) : 999;

  const abcRes = await pool.query(`
    WITH pr AS (SELECT product_id, SUM(revenue)::float AS revenue FROM sales
      WHERE sale_date>=CURRENT_DATE-$1::int AND quantity>0 GROUP BY product_id),
    ranked AS (SELECT product_id, revenue,
      SUM(revenue) OVER (ORDER BY revenue DESC) AS cum,
      SUM(revenue) OVER () AS total FROM pr)
    SELECT CASE WHEN total>0 AND (cum-revenue)/total<0.8 THEN 'A'
      WHEN total>0 AND (cum-revenue)/total<0.95 THEN 'B' ELSE 'C' END AS grade,
      CASE WHEN total>0 THEN (revenue/total*100)::float ELSE 0 END AS revenue_share
    FROM ranked WHERE product_id=$2
  `, [days, productId]);
  const abc = abcRes.rows[0] || { grade: "C", revenue_share: 0 };

  const mpRes = await pool.query(`
    SELECT mp.slug AS marketplace, mp.name,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(s.net_profit),0)::float AS profit,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS quantity
    FROM sales s JOIN marketplaces mp ON mp.id=s.marketplace_id
    WHERE s.product_id=$1 AND s.sale_date>=CURRENT_DATE-$2::int
    GROUP BY mp.slug, mp.name ORDER BY revenue DESC
  `, [productId, days]);

  const geoCountryRes = await pool.query(`
    SELECT COALESCE(s.site_country,'Россия') AS country,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS quantity
    FROM sales s WHERE s.product_id=$1 AND s.sale_date>=CURRENT_DATE-$2::int
    GROUP BY s.site_country ORDER BY revenue DESC LIMIT 10
  `, [productId, days]);

  const geoWhRes = await pool.query(`
    SELECT COALESCE(s.office_name,'Не указан') AS warehouse,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS quantity
    FROM sales s WHERE s.product_id=$1 AND s.sale_date>=CURRENT_DATE-$2::int AND s.office_name IS NOT NULL
    GROUP BY s.office_name ORDER BY revenue DESC LIMIT 10
  `, [productId, days]);

  const priceHistRes = await pool.query(`
    SELECT DATE_TRUNC('week',sale_date)::date::text AS week,
      CASE WHEN SUM(CASE WHEN quantity>0 THEN quantity ELSE 0 END)>0
        THEN (SUM(CASE WHEN quantity>0 THEN revenue ELSE 0 END)/SUM(CASE WHEN quantity>0 THEN quantity ELSE 0 END))::float ELSE 0 END AS avg_price,
      CASE WHEN SUM(CASE WHEN quantity>0 THEN quantity ELSE 0 END)>0
        THEN (SUM(CASE WHEN quantity>0 THEN for_pay ELSE 0 END)/SUM(CASE WHEN quantity>0 THEN quantity ELSE 0 END))::float ELSE 0 END AS avg_for_pay
    FROM sales WHERE product_id=$1 AND sale_date>=CURRENT_DATE-$2::int AND quantity>0
    GROUP BY DATE_TRUNC('week',sale_date) ORDER BY week
  `, [productId, days]);

  const costPrice = pr.cost_price || 0;

  return {
    product: {
      id: pr.id, name: pr.name, sku: pr.sku, barcode: pr.barcode || "",
      cost_price: costPrice, price: avgPrice,
      category: pr.category || "Без категории", category_slug: pr.category_slug || "none",
      created_at: pr.created_at, brand: pr.brand || "YourFit",
      image_url: pr.image_url || null,
      dimensions: (pr.width||pr.height||pr.length) ? {width:pr.width||0,height:pr.height||0,length:pr.length||0} : null,
      weight_g: pr.weight_g || null, nm_id: pr.nm_id || null,
      retail_price: pr.retail_price || 0, discount_price: pr.discount_price || 0,
    },
    metrics: {
      total_revenue: m.total_revenue, total_profit: m.total_profit,
      total_sold: m.total_sold, total_orders: m.total_orders,
      avg_price: parseFloat(avgPrice.toFixed(0)),
      total_commission: m.total_commission, total_logistics: m.total_logistics,
      total_returns: m.total_returns,
      margin_pct: parseFloat(marginPct.toFixed(1)), return_pct: parseFloat(returnPct.toFixed(1)),
    },
    changes: {
      revenue: pctChange(m.total_revenue, prev.total_revenue),
      profit: pctChange(m.total_profit, prev.total_profit),
      quantity: pctChange(m.total_sold, prev.total_sold),
      orders: pctChange(m.total_orders, prev.total_orders),
    },
    chart: chartRes.rows,
    inventory: { items: inventoryRes.rows, total_stock: totalStock,
      avg_daily_sales: parseFloat(avgDaily.toFixed(1)), days_of_stock: daysOfStock },
    abc: { grade: abc.grade, revenue_share: parseFloat(Number(abc.revenue_share).toFixed(1)) },
    by_marketplace: mpRes.rows,
    geography: { by_country: geoCountryRes.rows, by_warehouse: geoWhRes.rows },
    price_history: priceHistRes.rows,
    finance: {
      revenue: m.total_revenue, for_pay: m.total_for_pay,
      commission: m.total_commission, logistics: m.total_logistics,
      penalty: m.total_penalty, acquiring: m.total_acquiring,
      storage: m.total_storage, deduction: m.total_deduction,
      acceptance: m.total_acceptance, return_logistics: m.total_return_logistics,
      additional_payment: m.total_additional_payment, returns_amount: m.returns_amount,
      avg_spp_pct: parseFloat(m.avg_spp_pct.toFixed(1)),
      avg_commission_pct: parseFloat(m.avg_commission_pct.toFixed(1)),
      cogs: costPrice * m.total_sold, net_profit: m.total_profit,
    },
  };
}
