import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import { getUserFromRequest } from "@/lib/auth";
import { auditLog } from "@/lib/audit";

const ETL_URL = process.env.ETL_SERVICE_URL || "http://localhost:8081";
const ETL_SECRET = process.env.ETL_SECRET || "";

export async function POST(req: NextRequest) {
  const user = getUserFromRequest(req);

  try {
    const body = await req.json();
    const marketplace = body.marketplace ? String(body.marketplace).trim() : "";
    const credentialId = body.credential_id ? Number(body.credential_id) : 0;

    // Build ETL trigger payload
    const etlPayload: Record<string, unknown> = {};

    if (credentialId > 0) {
      etlPayload.credential_id = credentialId;
    } else if (marketplace && marketplace !== "all") {
      etlPayload.marketplace = marketplace;
    }
    // empty payload = sync all

    // Verify at least one active credential exists
    const { rows: creds } = await pool.query(
      `SELECT mc.id, m.slug
       FROM marketplace_credentials mc
       JOIN marketplaces m ON m.id = mc.marketplace_id
       WHERE mc.is_active = true
       ${marketplace && marketplace !== "all" ? "AND m.slug = $1" : ""}
       ORDER BY mc.id`,
      marketplace && marketplace !== "all" ? [marketplace] : []
    );

    if (creds.length === 0) {
      return NextResponse.json(
        { error: "Нет подключённых маркетплейсов для синхронизации" },
        { status: 400 }
      );
    }

    // Call Go ETL service
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10000);

    let etlResponse: { status: string; message: string };

    try {
      const res = await fetch(`${ETL_URL}/api/trigger`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-ETL-Secret": ETL_SECRET,
        },
        body: JSON.stringify(etlPayload),
        signal: controller.signal,
      });

      clearTimeout(timeout);

      if (!res.ok) {
        const text = await res.text();
        console.error(`[sync] ETL responded ${res.status}: ${text}`);
        return NextResponse.json(
          { error: `ETL сервис вернул ошибку: ${res.status}` },
          { status: 502 }
        );
      }

      etlResponse = await res.json();
    } catch (fetchErr) {
      clearTimeout(timeout);
      console.error("[sync] ETL service unreachable:", fetchErr);
      return NextResponse.json(
        { error: "ETL сервис недоступен. Убедитесь что etl-service запущен." },
        { status: 503 }
      );
    }

    await auditLog("sync_trigger", user, {
      marketplace: marketplace || "all",
      credential_id: credentialId || null,
      etl_status: etlResponse.status,
    });

    return NextResponse.json({
      success: true,
      message: etlResponse.message || "Синхронизация запущена",
      credentials: creds.map((c) => ({ id: c.id, marketplace: c.slug })),
    });
  } catch (e: unknown) {
    console.error("Trigger sync error:", e);
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 }
    );
  }
}
