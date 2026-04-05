import { NextRequest, NextResponse } from "next/server";
import { query } from "@/lib/db";

interface RnpTemplate {
  id: number;
  project_id: number;
  project_name: string;
  manager_id: string;
  manager_name: string;
  marketplace_id: number;
  marketplace: string;
  year: number;
  month: number;
  status: string;
  items_count: number;
  plan_total: number;
  fact_total: number;
  created_at: string;
}

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const year = searchParams.get("year");
  const month = searchParams.get("month");

  try {
    const conditions: string[] = [];
    const params: (string | number)[] = [];
    let paramIndex = 1;

    if (year) {
      conditions.push(`t.year = $${paramIndex++}`);
      params.push(parseInt(year));
    }

    if (month) {
      conditions.push(`t.month = $${paramIndex++}`);
      params.push(parseInt(month));
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";

    const templates = await query<RnpTemplate>(`
      SELECT 
        t.id,
        t.project_id,
        p.name as project_name,
        t.manager_id::text,
        COALESCE(CONCAT(u.first_name, ' ', u.last_name), u.email, 'Manager') as manager_name,
        t.marketplace_id,
        m.name as marketplace,
        t.year,
        t.month,
        t.status,
        (SELECT COUNT(*) FROM rnp_items WHERE template_id = t.id) as items_count,
        (SELECT COALESCE(SUM(plan_orders_rub), 0) FROM rnp_items WHERE template_id = t.id) as plan_total,
        (SELECT COALESCE(SUM(fact_orders_rub), 0) FROM rnp_items WHERE template_id = t.id) as fact_total,
        t.created_at
      FROM rnp_templates t
      JOIN projects p ON p.id = t.project_id
      JOIN marketplaces m ON m.id = t.marketplace_id
      LEFT JOIN users u ON u.id = t.manager_id
      ${where}
      ORDER BY t.year DESC, t.month DESC, p.name, m.name
    `, params);

    return NextResponse.json({ templates });
  } catch (e: unknown) {
    console.error("RNP templates error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { project_id, manager_id, marketplace_id, year, month } = body;

    if (!project_id || !manager_id || !marketplace_id || !year || !month) {
      return NextResponse.json({ error: "Missing required fields" }, { status: 400 });
    }

    // Check if template already exists
    const existing = await query(
      `SELECT id FROM rnp_templates WHERE project_id = $1 AND manager_id = $2 AND marketplace_id = $3 AND year = $4 AND month = $5`,
      [project_id, manager_id, marketplace_id, year, month]
    );

    if (existing.length > 0) {
      return NextResponse.json({ error: "Шаблон с такими параметрами уже существует" }, { status: 409 });
    }

    const result = await query(
      `INSERT INTO rnp_templates (project_id, manager_id, marketplace_id, year, month, status, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, 'draft', NOW(), NOW())
       RETURNING id`,
      [project_id, manager_id, marketplace_id, year, month]
    );

    return NextResponse.json({ id: result[0].id, message: "Template created" }, { status: 201 });
  } catch (e: unknown) {
    console.error("RNP template create error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
