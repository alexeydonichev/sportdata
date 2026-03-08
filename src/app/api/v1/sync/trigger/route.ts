import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import { getUserFromRequest } from "@/lib/auth";
import { auditLog } from "@/lib/audit";

export async function POST(req: NextRequest) {
  const user = getUserFromRequest(req);

  try {
    const body = await req.json();
    const marketplace = body.marketplace ? String(body.marketplace).trim() : "";

    // Determine which marketplaces to sync
    let marketplaceIds: number[] = [];

    if (marketplace && marketplace !== "all") {
      const { rows } = await pool.query(
        `SELECT m.id FROM marketplaces m
         JOIN marketplace_credentials mc ON mc.marketplace_id = m.id
         WHERE m.slug = $1 AND mc.is_active = true`,
        [marketplace]
      );
      marketplaceIds = rows.map(r => r.id);
    } else {
      const { rows } = await pool.query(
        `SELECT m.id FROM marketplaces m
         JOIN marketplace_credentials mc ON mc.marketplace_id = m.id
         WHERE mc.is_active = true`
      );
      marketplaceIds = rows.map(r => r.id);
    }

    if (marketplaceIds.length === 0) {
      return NextResponse.json(
        { error: "Нет подключённых маркетплейсов для синхронизации" },
        { status: 400 }
      );
    }

    // Create sync jobs for each marketplace
    const jobs = [];
    for (const mpId of marketplaceIds) {
      const { rows } = await pool.query(
        `INSERT INTO sync_jobs (marketplace_id, job_type, status, created_at)
         VALUES ($1, 'full_sync', 'pending', NOW())
         RETURNING id, marketplace_id, job_type, status, created_at`,
        [mpId]
      );
      jobs.push(rows[0]);
    }

    await auditLog("sync_trigger", user, {
      marketplace: marketplace || "all",
      jobs_created: jobs.length,
    });

    return NextResponse.json({
      success: true,
      message: `Создано ${jobs.length} задач синхронизации`,
      jobs,
    });
  } catch (e: unknown) {
    console.error("Trigger sync error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
