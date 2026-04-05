import { NextResponse } from "next/server";
import { query } from "@/lib/db";

export async function GET() {
  try {
    const marketplaces = await query(`
      SELECT id, name, slug AS code
      FROM marketplaces
      ORDER BY name
    `);
    return NextResponse.json({ marketplaces });
  } catch (e) {
    console.error("Marketplaces error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
