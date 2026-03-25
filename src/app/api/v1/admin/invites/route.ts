import { NextRequest, NextResponse } from "next/server";
import { getUserFromRequest } from "@/lib/auth";
export async function GET(req: NextRequest) {
  const actor = getUserFromRequest(req);
  if (!actor) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  return NextResponse.json({ invites: [] });
}
export async function POST(req: NextRequest) {
  return NextResponse.json({ error: "Not implemented" }, { status: 501 });
}
