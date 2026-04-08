import { NextResponse } from "next/server";
import { productsRepo } from "@/lib/repositories";

export async function GET() {
  try {
    const categories = await productsRepo.getCategories();
    return NextResponse.json(categories);
  } catch (e: unknown) {
    console.error("Categories error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
