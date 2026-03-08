import { NextResponse } from "next/server";
import { notificationsRepo } from "@/lib/repositories";

export async function GET() {
  try {
    const data = await notificationsRepo.getNotifications();
    return NextResponse.json(data);
  } catch (e: unknown) {
    console.error("Notifications error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
