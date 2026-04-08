import { NextRequest, NextResponse } from "next/server";
import { getUserFromRequest } from "@/lib/auth";
import pool from "@/lib/db";

export async function GET(req: NextRequest) {
  const actor = getUserFromRequest(req);
  if (!actor) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  const { rows } = await pool.query(
    `SELECT u.id, u.email, u.first_name, u.last_name, r.slug as role, r.name as role_name, r.level as role_level, u.is_active, u.last_login_at::text, u.created_at::text
     FROM users u JOIN roles r ON r.id = u.role_id WHERE u.id = $1`, [actor.id]);
  if (!rows.length) return NextResponse.json({ error: "Not found" }, { status: 404 });
  return NextResponse.json({ user: rows[0] });
}
