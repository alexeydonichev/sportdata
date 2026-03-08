import { NextRequest, NextResponse } from "next/server";
import { notificationsRepo } from "@/lib/repositories";

export async function GET(req: NextRequest) {
  const marketplace = req.nextUrl.searchParams.get("marketplace") || undefined;

  try {
    const data = await notificationsRepo.getNotifications(marketplace);
    return NextResponse.json(data);
  } catch (e: unknown) {
    console.error("Notifications error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
