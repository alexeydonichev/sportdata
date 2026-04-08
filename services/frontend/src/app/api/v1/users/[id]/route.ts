import { NextRequest, NextResponse } from "next/server";

const API_URL = process.env.API_GATEWAY_URL || "http://localhost:8080";

export async function PATCH(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const token = req.headers.get("authorization");
  const body = await req.json();
  const res = await fetch(`${API_URL}/api/v1/users/${id}`, {
    method: "PATCH",
    headers: { Authorization: token || "", "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  return NextResponse.json(data, { status: res.status });
}

export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const token = req.headers.get("authorization");
  const res = await fetch(`${API_URL}/api/v1/users/${id}`, {
    method: "DELETE",
    headers: { Authorization: token || "" },
  });
  const data = await res.json();
  return NextResponse.json(data, { status: res.status });
}
