import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

export async function GET(req: NextRequest) {
  try {
    const { rows } = await pool.query(
      `SELECT id, name, slug FROM categories ORDER BY name`
    );
    return NextResponse.json(rows);
  } catch (e: unknown) {
    console.error("Categories error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
