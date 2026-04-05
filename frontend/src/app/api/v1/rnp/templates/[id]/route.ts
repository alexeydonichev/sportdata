import { NextRequest, NextResponse } from "next/server";
import { query } from "@/lib/db";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;

  try {
    const templates = await query(`
      SELECT 
        t.id,
        p.name as project_name,
        COALESCE(CONCAT(u.first_name, ' ', u.last_name), u.email) as manager_name,
        m.name as marketplace,
        t.year,
        t.month,
        t.status
      FROM rnp_templates t
      JOIN projects p ON p.id = t.project_id
      JOIN marketplaces m ON m.id = t.marketplace_id
      LEFT JOIN users u ON u.id = t.manager_id
      WHERE t.id = $1
    `, [id]);

    if (templates.length === 0) {
      return NextResponse.json({ error: "Шаблон не найден" }, { status: 404 });
    }

    const items = await query(`
      SELECT 
        i.id,
        i.product_id,
        COALESCE(pr.name, 'Товар') as product_name,
        COALESCE(pr.sku, '') as sku,
        i.plan_orders_rub,
        i.fact_orders_rub,
        i.plan_quantity,
        i.fact_quantity
      FROM rnp_items i
      LEFT JOIN products pr ON pr.id = i.product_id
      WHERE i.template_id = $1
      ORDER BY i.id
    `, [id]);

    return NextResponse.json({ template: templates[0], items });
  } catch (e) {
    console.error("RNP template detail error:", e);
    return NextResponse.json({ error: "Ошибка сервера" }, { status: 500 });
  }
}
