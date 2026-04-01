import { NextRequest, NextResponse } from "next/server";
import { inventoryRepo } from "@/lib/repositories";

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const category = sp.get("category") || undefined;
  const marketplace = sp.get("marketplace") || undefined;

  try {
    const data = await inventoryRepo.getInventory(category, marketplace);
    return NextResponse.json(data);
  } catch (e: unknown) {
    console.error("Inventory error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
