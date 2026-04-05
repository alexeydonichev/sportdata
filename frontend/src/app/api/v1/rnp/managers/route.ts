import { NextResponse } from "next/server";
import { query } from "@/lib/db";

export async function GET() {
  try {
    const managers = await query(`
      SELECT 
        u.id, 
        u.first_name, 
        u.last_name, 
        u.email,
        COALESCE(u.first_name || ' ' || u.last_name, u.email) as full_name
      FROM users u
      JOIN roles r ON u.role_id = r.id
      WHERE r.name IN ('Менеджер', 'Аналитик', 'Собственник', 'Супер-администратор')
        AND u.is_active = true
      ORDER BY u.first_name, u.last_name
    `);
    return NextResponse.json({ managers });
  } catch (e) {
    console.error("RNP managers error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
