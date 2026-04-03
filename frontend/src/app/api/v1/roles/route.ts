import { NextRequest, NextResponse } from "next/server";

const API_URL = process.env.API_GATEWAY_URL || "http://localhost:8080";

export async function GET(req: NextRequest) {
  const token = req.headers.get("authorization");
  const res = await fetch(`${API_URL}/api/v1/roles`, {
    headers: { Authorization: token || "" },
  });
  const data = await res.json();
  return NextResponse.json(data, { status: res.status });
}
