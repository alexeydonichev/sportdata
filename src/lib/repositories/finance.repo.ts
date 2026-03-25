import pool from "@/lib/db";

export interface FinanceData {
  pnl: {
    gross_revenue: number; returns_amount: number; net_revenue: number; for_pay: number;
    commission: number; logistics: number; acquiring: number; storage: number;
    penalty: number; deduction: number; acceptance: number; return_logistics: number;
    additional_payment: number; cogs: number; net_profit: number;
  };
  margins: { gross_margin: number; net_margin: number; commission_pct: number; logistics_pct: number; return_rate: number };
  changes: Record<string, number>;
  weekly: { week: string; revenue: number; for_pay: number; commission: number; logistics: number; storage: number; penalty: number; net_profit: number }[];
  by_category: { category: string; slug: string; revenue: number; for_pay: number; commission: number; logistics: number; storage: number; penalty: number; cogs: number; net_profit: number; units: number }[];
  warnings: string[];
}

function pct(c: number, p: number): number {
  if (p===0&&c===0) return 0; if (p===0) return c>0?100:-100;
  return parseFloat((((c-p)/Math.abs(p))*100).toFixed(1));
}

export async function getFinance(days: number, category?: string, marketplace?: string): Promise<FinanceData> {
  const params: (number|string)[] = [days];
  let catF="", mpJ="", mpF="";
  if (category&&category!=="all") { params.push(category); catF=`AND c.slug=$${params.length}`; }
  if (marketplace&&marketplace!=="all") { params.push(marketplace); mpJ="JOIN marketplaces mp ON mp.id=s.marketplace_id"; mpF=`AND mp.slug=$${params.length}`; }

  const r = await pool.query(`
    WITH cur AS (
      SELECT
        COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS gross_revenue,
        COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.revenue) ELSE 0 END),0)::float AS returns_amount,
        COALESCE(SUM(s.revenue),0)::float AS net_revenue,
        COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.for_pay ELSE 0 END),0)::float AS for_pay,
        COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.commission ELSE 0 END),0)::float AS commission,
        COALESCE(SUM(s.logistics_cost),0)::float AS logistics,
        COALESCE(SUM(s.acquiring_fee),0)::float AS acquiring,
        COALESCE(SUM(s.storage_fee),0)::float AS storage,
        COALESCE(SUM(s.penalty),0)::float AS penalty,
        COALESCE(SUM(s.deduction),0)::float AS deduction,
        COALESCE(SUM(s.acceptance_cost),0)::float AS acceptance,
        COALESCE(SUM(s.return_logistic_cost),0)::float AS return_logistics,
        COALESCE(SUM(s.additional_payment),0)::float AS additional_payment,
        COALESCE(SUM(CASE WHEN s.quantity>0 THEN COALESCE(p.cost_price,0)*s.quantity ELSE 0 END),0)::float AS cogs,
        COALESCE(SUM(s.net_profit),0)::float AS net_profit,
        COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS units_sold,
        COALESCE(SUM(CASE WHEN s.quantity<0 THEN ABS(s.quantity) ELSE 0 END),0)::int AS units_returned
      FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id ${mpJ}
      WHERE s.sale_date>=CURRENT_DATE-$1::int ${catF} ${mpF}
    ),
    prev AS (
      SELECT
        COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS gross_revenue,
        COALESCE(SUM(s.net_profit),0)::float AS net_profit,
        COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.commission ELSE 0 END),0)::float AS commission,
        COALESCE(SUM(s.logistics_cost),0)::float AS logistics
      FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id ${mpJ}
      WHERE s.sale_date>=CURRENT_DATE-($1::int*2) AND s.sale_date<CURRENT_DATE-$1::int ${catF} ${mpF}
    )
    SELECT cur.*, prev.gross_revenue AS p_rev, prev.net_profit AS p_profit, prev.commission AS p_com, prev.logistics AS p_log
    FROM cur, prev
  `, params);
  const m = r.rows[0];

  const wkRes = await pool.query(`
    SELECT DATE_TRUNC('week',s.sale_date)::date::text AS week,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.for_pay ELSE 0 END),0)::float AS for_pay,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.commission ELSE 0 END),0)::float AS commission,
      COALESCE(SUM(s.logistics_cost),0)::float AS logistics,
      COALESCE(SUM(s.storage_fee),0)::float AS storage,
      COALESCE(SUM(s.penalty),0)::float AS penalty,
      COALESCE(SUM(s.net_profit),0)::float AS net_profit
    FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id ${mpJ}
    WHERE s.sale_date>=CURRENT_DATE-$1::int ${catF} ${mpF}
    GROUP BY DATE_TRUNC('week',s.sale_date) ORDER BY week
  `, params);

  const catRes = await pool.query(`
    SELECT COALESCE(c.name,'Без категории') AS category, COALESCE(c.slug,'none') AS slug,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.revenue ELSE 0 END),0)::float AS revenue,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.for_pay ELSE 0 END),0)::float AS for_pay,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.commission ELSE 0 END),0)::float AS commission,
      COALESCE(SUM(s.logistics_cost),0)::float AS logistics,
      COALESCE(SUM(s.storage_fee),0)::float AS storage,
      COALESCE(SUM(s.penalty),0)::float AS penalty,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN COALESCE(p.cost_price,0)*s.quantity ELSE 0 END),0)::float AS cogs,
      COALESCE(SUM(s.net_profit),0)::float AS net_profit,
      COALESCE(SUM(CASE WHEN s.quantity>0 THEN s.quantity ELSE 0 END),0)::int AS units
    FROM sales s JOIN products p ON p.id=s.product_id LEFT JOIN categories c ON c.id=p.category_id ${mpJ}
    WHERE s.sale_date>=CURRENT_DATE-$1::int ${catF} ${mpF}
    GROUP BY c.name, c.slug ORDER BY revenue DESC
  `, params);

  const gm = m.gross_revenue>0 ? ((m.net_revenue-m.cogs)/m.gross_revenue*100) : 0;
  const nm = m.gross_revenue>0 ? (m.net_profit/m.gross_revenue*100) : 0;
  const cp = m.gross_revenue>0 ? (m.commission/m.gross_revenue*100) : 0;
  const lp = m.gross_revenue>0 ? (m.logistics/m.gross_revenue*100) : 0;
  const rr = (m.units_sold+m.units_returned)>0 ? (m.units_returned/(m.units_sold+m.units_returned)*100) : 0;

  const warnings: string[] = [];
  if (m.cogs===0) warnings.push("Себестоимость не заполнена. Заполните в разделе «Товары».");
  if (m.logistics===0) warnings.push("Логистика = 0. Запустите синхронизацию reportDetail.");

  return {
    pnl: {
      gross_revenue:m.gross_revenue, returns_amount:m.returns_amount, net_revenue:m.net_revenue,
      for_pay:m.for_pay, commission:m.commission, logistics:m.logistics, acquiring:m.acquiring,
      storage:m.storage, penalty:m.penalty, deduction:m.deduction, acceptance:m.acceptance,
      return_logistics:m.return_logistics, additional_payment:m.additional_payment,
      cogs:m.cogs, net_profit:m.net_profit,
    },
    margins: { gross_margin:+gm.toFixed(1), net_margin:+nm.toFixed(1), commission_pct:+cp.toFixed(1), logistics_pct:+lp.toFixed(1), return_rate:+rr.toFixed(1) },
    changes: { gross_revenue:pct(m.gross_revenue,m.p_rev), net_profit:pct(m.net_profit,m.p_profit), commission:pct(m.commission,m.p_com), logistics:pct(m.logistics,m.p_log) },
    weekly: wkRes.rows,
    by_category: catRes.rows,
    warnings,
  };
}
