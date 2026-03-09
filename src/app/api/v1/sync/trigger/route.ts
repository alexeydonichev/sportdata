import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import { getUserFromRequest } from "@/lib/auth";
import { auditLog } from "@/lib/audit";
import { runWBSync } from "@/lib/wb-sync";

export async function POST(req: NextRequest) {
  const user = getUserFromRequest(req);

  try {
    const body = await req.json();
    const marketplace = body.marketplace ? String(body.marketplace).trim() : "";

    // Determine which marketplaces to sync
    let marketplaceIds: { id: number; slug: string }[] = [];

    if (marketplace && marketplace !== "all") {
      const { rows } = await pool.query(
        `SELECT m.id, m.slug FROM marketplaces m
         JOIN marketplace_credentials mc ON mc.marketplace_id = m.id
         WHERE m.slug = $1 AND mc.is_active = true`,
        [marketplace]
      );
      marketplaceIds = rows;
    } else {
      const { rows } = await pool.query(
        `SELECT m.id, m.slug FROM marketplaces m
         JOIN marketplace_credentials mc ON mc.marketplace_id = m.id
         WHERE mc.is_active = true`
      );
      marketplaceIds = rows;
    }

    if (marketplaceIds.length === 0) {
      return NextResponse.json(
        { error: "Нет подключённых маркетплейсов для синхронизации" },
        { status: 400 }
      );
    }

    // Create sync jobs for each marketplace
    const jobs = [];
    for (const mp of marketplaceIds) {
      const { rows } = await pool.query(
        `INSERT INTO sync_jobs (marketplace_id, job_type, status, created_at)
         VALUES ($1, 'full_sync', 'pending', NOW())
         RETURNING id, marketplace_id, job_type, status, created_at`,
        [mp.id]
      );
      jobs.push({ ...rows[0], slug: mp.slug });
    }

    await auditLog("sync_trigger", user, {
      marketplace: marketplace || "all",
      jobs_created: jobs.length,
    });

    // Fire and forget — run syncs in background
    for (const job of jobs) {
      if (job.slug === "wildberries") {
        runWBSync(job.id).catch((err) =>
          console.error(`[Sync] WB job ${job.id} failed:`, err)
        );
      }
      // TODO: add ozon, yandex_market handlers here
    }

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
