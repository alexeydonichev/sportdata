import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import { runWBSync } from "@/lib/wb-sync";

export async function GET(req: NextRequest) {
  const secret =
    req.headers.get("x-cron-secret") ||
    req.nextUrl.searchParams.get("secret");

  if (!secret || secret !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const { rows: marketplaces } = await pool.query(
      `SELECT m.id, m.slug FROM marketplaces m
       JOIN marketplace_credentials mc ON mc.marketplace_id = m.id
       WHERE mc.is_active = true`
    );

    const jobs = [];
    for (const mp of marketplaces) {
      const { rows } = await pool.query(
        `INSERT INTO sync_jobs (marketplace_id, job_type, status, created_at)
         VALUES ($1, 'full_sync', 'pending', NOW())
         RETURNING id`,
        [mp.id]
      );
      const jobId = rows[0].id;
      jobs.push({ id: jobId, slug: mp.slug });

      if (mp.slug === "wildberries") {
        runWBSync(jobId).catch((err) =>
          console.error(`[Cron] WB job ${jobId} failed:`, err)
        );
      }
    }

    return NextResponse.json({
      success: true,
      message: `Cron: запущено ${jobs.length} синхронизаций`,
      jobs,
    });
  } catch (e: unknown) {
    console.error("Cron sync error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
