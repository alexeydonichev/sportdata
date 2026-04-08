import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

export async function GET(req: NextRequest) {
  try {
    const { rows } = await pool.query(
      `SELECT sj.id, m.name as marketplace, sj.job_type, sj.status,
              sj.started_at, sj.completed_at, sj.records_processed, sj.error_message, sj.created_at
       FROM sync_jobs sj
       LEFT JOIN marketplaces m ON m.id = sj.marketplace_id
       ORDER BY sj.created_at DESC
       LIMIT 50`
    );
    return NextResponse.json(rows);
  } catch (e: unknown) {
    console.error("Sync history error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
