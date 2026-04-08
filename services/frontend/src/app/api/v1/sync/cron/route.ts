import { NextRequest, NextResponse } from "next/server";

const ETL_URL = process.env.ETL_SERVICE_URL || "http://localhost:8081";
const ETL_SECRET = process.env.ETL_SECRET || "";

export async function GET(req: NextRequest) {
  const secret =
    req.headers.get("x-cron-secret") ||
    req.nextUrl.searchParams.get("secret");

  if (!secret || secret !== process.env.CRON_SECRET) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    const res = await fetch(`${ETL_URL}/api/trigger`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-ETL-Secret": ETL_SECRET,
      },
      body: JSON.stringify({}),
      signal: AbortSignal.timeout(10000),
    });

    if (!res.ok) {
      const text = await res.text();
      console.error(`[cron] ETL responded ${res.status}: ${text}`);
      return NextResponse.json(
        { error: `ETL error: ${res.status}` },
        { status: 502 }
      );
    }

    const data = await res.json();

    return NextResponse.json({
      success: true,
      message: "Cron: синхронизация запущена через ETL сервис",
      etl: data,
    });
  } catch (e: unknown) {
    console.error("Cron sync error:", e);
    return NextResponse.json(
      { error: "ETL сервис недоступен" },
      { status: 503 }
    );
  }
}
