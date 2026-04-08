import { NextRequest, NextResponse } from "next/server";
import { query } from "@/lib/db";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const url = new URL(request.url);
  const selectedDate = url.searchParams.get('date') || new Date().toISOString().split('T')[0];

  try {
    const templates = await query(`
      SELECT 
        t.id,
        p.name as project_name,
        COALESCE(CONCAT(u.first_name, ' ', u.last_name), u.email) as manager_name,
        m.name as marketplace,
        t.year,
        t.month,
        t.status,
        EXTRACT(DAY FROM (DATE_TRUNC('month', make_date(t.year, t.month, 1)) + INTERVAL '1 month - 1 day'))::int as days_in_month,
        LEAST(
          EXTRACT(DAY FROM CURRENT_DATE)::int,
          EXTRACT(DAY FROM (DATE_TRUNC('month', make_date(t.year, t.month, 1)) + INTERVAL '1 month - 1 day'))::int
        ) as days_passed
      FROM rnp_templates t
      JOIN projects p ON p.id = t.project_id
      JOIN marketplaces m ON m.id = t.marketplace_id
      LEFT JOIN users u ON u.id = t.manager_id
      WHERE t.id = $1
    `, [id]);

    if (templates.length === 0) {
      return NextResponse.json({ error: "Шаблон не найден" }, { status: 404 });
    }

    const template = templates[0];
    const monthStart = `${template.year}-${String(template.month).padStart(2, '0')}-01`;
    const monthEnd = `${template.year}-${String(template.month).padStart(2, '0')}-${template.days_in_month}`;
    const weekStart = new Date(selectedDate);
    weekStart.setDate(weekStart.getDate() - 6);
    const weekStartStr = weekStart.toISOString().split('T')[0];

    const items = await query(`
      SELECT 
        i.id, i.product_id,
        COALESCE(i.name, 'Товар') as name,
        COALESCE(i.sku, '') as sku,
        COALESCE(i.photo_url, '') as photo_url,
        COALESCE(i.season, 'all_season') as season,
        COALESCE(i.plan_orders_rub, 0) as plan_orders_rub,
        COALESCE(i.plan_orders_qty, 0) as plan_orders_qty,
        COALESCE(day_data.orders_qty, 0)::int as fact_day_qty,
        COALESCE(day_data.orders_rub, 0)::numeric as fact_day_rub,
        COALESCE(week_data.orders_qty, 0)::int as fact_week_qty,
        COALESCE(week_data.orders_rub, 0)::numeric as fact_week_rub,
        COALESCE(month_data.orders_qty, 0)::int as fact_orders_qty,
        COALESCE(month_data.orders_rub, 0)::numeric as fact_orders_rub,
        COALESCE(i.stock_fbo, 0)::int as stock_fbo,
        COALESCE(i.stock_fbs, 0)::int as stock_fbs,
        CASE WHEN COALESCE(month_data.orders_qty,0)>0 
          THEN ((COALESCE(i.stock_fbo,0)+COALESCE(i.stock_fbs,0))::numeric/(month_data.orders_qty::numeric/GREATEST($6::int,1)))
          ELSE 0 END as turnover_mtd,
        COALESCE(i.reviews_avg_rating, 0)::numeric as reviews_avg_rating,
        i.manager_id,
        COALESCE(i.item_status, 'ok') as item_status,
        COALESCE(i.checklist_done, 0)::int as checklist_done,
        COALESCE(i.checklist_total, 0)::int as checklist_total,
        CASE WHEN COALESCE(i.plan_orders_qty,0)>0 AND $6::int>0
          THEN ROUND((COALESCE(month_data.orders_qty,0)::numeric/(i.plan_orders_qty::numeric*$6::int/$7::int))*100,1)
          ELSE 0 END as completion_pct_qty,
        CASE WHEN COALESCE(i.plan_orders_qty,0)=0 THEN 'ok'
          WHEN (COALESCE(month_data.orders_qty,0)::numeric/(i.plan_orders_qty::numeric*$6::int/$7::int))>=1.0 THEN 'over'
          WHEN (COALESCE(month_data.orders_qty,0)::numeric/(i.plan_orders_qty::numeric*$6::int/$7::int))>=0.8 THEN 'ok'
          ELSE 'under' END as completion_status
      FROM rnp_items i
      LEFT JOIN (SELECT item_id, orders_qty, orders_rub FROM rnp_items_daily WHERE date=$2::date) day_data ON day_data.item_id=i.id
      LEFT JOIN (SELECT item_id, SUM(orders_qty)::int as orders_qty, SUM(orders_rub) as orders_rub FROM rnp_items_daily WHERE date BETWEEN $3::date AND $2::date GROUP BY item_id) week_data ON week_data.item_id=i.id
      LEFT JOIN (SELECT item_id, SUM(orders_qty)::int as orders_qty, SUM(orders_rub) as orders_rub FROM rnp_items_daily WHERE date BETWEEN $4::date AND $5::date GROUP BY item_id) month_data ON month_data.item_id=i.id
      WHERE i.template_id=$1
      ORDER BY i.sort_order, i.id
    `, [id, selectedDate, weekStartStr, monthStart, monthEnd, template.days_passed, template.days_in_month]);

    return NextResponse.json({ template: {...template, selected_date: selectedDate}, items, count: items.length });
  } catch (e) {
    console.error("RNP template detail error:", e);
    return NextResponse.json({ error: "Ошибка сервера" }, { status: 500 });
  }
}
