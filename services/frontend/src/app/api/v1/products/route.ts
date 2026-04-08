import { NextRequest, NextResponse } from "next/server";
import { productsRepo } from "@/lib/repositories";

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;

  try {
    const products = await productsRepo.getProducts({
      category: sp.get("category") || undefined,
      marketplace: sp.get("marketplace") || undefined,
      search: sp.get("search") || undefined,
      sort: sp.get("sort") || undefined,
      order: (sp.get("order") as "asc" | "desc") || undefined,
    });
    return NextResponse.json(products);
  } catch (e: unknown) {
    console.error("Products error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
