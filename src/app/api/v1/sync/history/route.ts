import { NextResponse } from "next/server";
import pool from "@/lib/db";

export async function GET() {
  try {
    const { rows } = await pool.query(`
      SELECT
        sj.id,
        m.slug as marketplace,
        m.name as marketplace_name,
        sj.job_type,
        sj.status,
        sj.started_at,
        sj.completed_at,
        sj.records_processed,
        sj.error_message,
        sj.created_at,
        CASE WHEN sj.completed_at IS NOT NULL AND sj.started_at IS NOT NULL
          THEN EXTRACT(EPOCH FROM (sj.completed_at - sj.started_at))::int
          ELSE NULL END as duration_sec
      FROM sync_jobs sj
      JOIN marketplaces m ON m.id = sj.marketplace_id
      ORDER BY sj.created_at DESC
      LIMIT 50
    `);

    return NextResponse.json(rows);
  } catch (e: unknown) {
    console.error("Sync history error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
