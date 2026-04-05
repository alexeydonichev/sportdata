import { NextRequest, NextResponse } from "next/server";
import { query } from "@/lib/db";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;

  try {
    // Get template info
    const templates = await query(`
      SELECT 
        t.id, t.year, t.month, t.status,
        EXTRACT(DAY FROM NOW()) as days_passed,
        EXTRACT(DAY FROM (DATE_TRUNC('month', MAKE_DATE(t.year, t.month, 1)) + INTERVAL '1 month - 1 day')) as days_in_month
      FROM rnp_templates t
      WHERE t.id = $1
    `, [id]);

    if (templates.length === 0) {
      return NextResponse.json({ error: "Шаблон не найден" }, { status: 404 });
    }

    const template = templates[0];

    // Get items - use only columns that exist in rnp_items
    const items = await query(`
      SELECT 
        i.id,
        i.product_id,
        i.nm_id,
        i.name,
        COALESCE(i.sku, '') as sku,
        COALESCE(i.barcode, '') as barcode,
        COALESCE(i.photo_url, '') as photo_url,
        COALESCE(i.season, 'allseason') as season,
        COALESCE(i.size, '') as size,
        COALESCE(i.category, '') as category,
        COALESCE(i.plan_orders_qty, 0) as plan_orders_qty,
        COALESCE(i.plan_orders_rub, 0) as plan_orders_rub,
        COALESCE(i.fact_orders_qty, 0) as fact_orders_qty,
        COALESCE(i.fact_orders_rub, 0) as fact_orders_rub,
        COALESCE(i.stock_fbo, 0) as stock_fbo,
        COALESCE(i.stock_fbs, 0) as stock_fbs,
        COALESCE(i.stock_in_transit, 0) as stock_in_transit,
        COALESCE(i.stock_1c, 0) as stock_1c,
        COALESCE(i.turnover_mtd, 0) as turnover_mtd,
        COALESCE(i.turnover_7d, 0) as turnover_7d,
        COALESCE(i.reviews_avg_rating, 0) as reviews_avg_rating,
        COALESCE(i.reviews_status, '') as reviews_status,
        i.content_task_url,
        i.checklist_url,
        i.monitoring_url,
        i.weekly_tasks,
        i.notes
      FROM rnp_items i
      WHERE i.template_id = $1
      ORDER BY i.plan_orders_rub DESC
    `, [id]);

    // Calculate completion stats for each item
    const daysPassed = Math.min(Number(template.days_passed), Number(template.days_in_month));
    const daysInMonth = Number(template.days_in_month);

    const itemsWithStats = items.map((item: Record<string, unknown>) => {
      const planQty = Number(item.plan_orders_qty) || 0;
      const planRub = Number(item.plan_orders_rub) || 0;
      const factQty = Number(item.fact_orders_qty) || 0;
      const factRub = Number(item.fact_orders_rub) || 0;
      const stockFbo = Number(item.stock_fbo) || 0;
      const stockFbs = Number(item.stock_fbs) || 0;

      const expectedPct = daysInMonth > 0 ? daysPassed / daysInMonth : 0;
      const expectedQty = planQty * expectedPct;
      const expectedRub = planRub * expectedPct;
      
      const completionPctQty = expectedQty > 0 ? (factQty / expectedQty) * 100 : 0;
      const completionPctRub = expectedRub > 0 ? (factRub / expectedRub) * 100 : 0;
      
      let completionStatus = 'under';
      if (completionPctQty >= 100) completionStatus = 'over';
      else if (completionPctQty >= 80) completionStatus = 'ok';

      return {
        ...item,
        plan_orders_qty: planQty,
        plan_orders_rub: planRub,
        fact_orders_qty: factQty,
        fact_orders_rub: factRub,
        stock_fbo: stockFbo,
        stock_fbs: stockFbs,
        stock_in_transit: Number(item.stock_in_transit) || 0,
        stock_1c: Number(item.stock_1c) || 0,
        turnover_mtd: Number(item.turnover_mtd) || 0,
        turnover_7d: Number(item.turnover_7d) || 0,
        completion_pct_qty: completionPctQty,
        completion_pct_rub: completionPctRub,
        completion_status: completionStatus,
        reviews_avg_rating: Number(item.reviews_avg_rating) || 0,
      };
    });

    return NextResponse.json({
      template: {
        id: template.id,
        year: template.year,
        month: template.month,
        status: template.status,
        days_passed: daysPassed,
        days_in_month: daysInMonth,
      },
      items: itemsWithStats,
      count: itemsWithStats.length,
    });
  } catch (e) {
    console.error("RNP items error:", e);
    return NextResponse.json({ error: "Ошибка сервера" }, { status: 500 });
  }
}
