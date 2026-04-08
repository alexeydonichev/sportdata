import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

export async function GET(req: NextRequest) {
  try {
    const { rows: [last] } = await pool.query(
      `SELECT sj.id, m.name as marketplace, sj.job_type, sj.status, 
              sj.started_at, sj.completed_at, sj.records_processed, sj.error_message
       FROM sync_jobs sj
       LEFT JOIN marketplaces m ON m.id = sj.marketplace_id
       ORDER BY sj.created_at DESC LIMIT 1`
    );
    const { rows: [counts] } = await pool.query(
      `SELECT COUNT(*)::int AS total,
         COUNT(CASE WHEN status='completed' THEN 1 END)::int AS completed,
         COUNT(CASE WHEN status='failed' THEN 1 END)::int AS failed,
         COUNT(CASE WHEN status='pending' THEN 1 END)::int AS pending
       FROM sync_jobs`
    );
    return NextResponse.json({
      last_sync: last || null,
      stats: counts,
    });
  } catch (e: unknown) {
    console.error("Sync status error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
