import { NextResponse } from "next/server";
import { query } from "@/lib/db";

export async function GET() {
  try {
    const projects = await query(`
      SELECT id, name, slug AS code, is_active
      FROM projects
      WHERE is_active = true
      ORDER BY name
    `);
    return NextResponse.json({ projects });
  } catch (e) {
    console.error("Projects error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
