import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";

interface BulkItem {
  id?: string;
  sku?: string;
  cost_price: number;
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const items: BulkItem[] = body.items;

    if (!Array.isArray(items) || items.length === 0) {
      return NextResponse.json({ error: "items array is required" }, { status: 400 });
    }

    if (items.length > 5000) {
      return NextResponse.json({ error: "Maximum 5000 items per request" }, { status: 400 });
    }

    const results: { updated: number; errors: string[] } = { updated: 0, errors: [] };

    // Use transaction for bulk update
    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      for (const item of items) {
        const cp = parseFloat(String(item.cost_price));
        if (isNaN(cp) || cp < 0) {
          results.errors.push(`Invalid cost_price for ${item.sku || item.id}: ${item.cost_price}`);
          continue;
        }

        let res;
        if (item.id) {
          res = await client.query(
            "UPDATE products SET cost_price = $1, updated_at = NOW() WHERE id = $2",
            [cp, parseInt(item.id)]
          );
        } else if (item.sku) {
          res = await client.query(
            "UPDATE products SET cost_price = $1, updated_at = NOW() WHERE sku = $2",
            [cp, item.sku]
          );
        } else {
          results.errors.push("Item must have id or sku");
          continue;
        }

        if (res.rowCount && res.rowCount > 0) {
          results.updated += res.rowCount;
        } else {
          results.errors.push(`Product not found: ${item.sku || item.id}`);
        }
      }

      await client.query("COMMIT");
    } catch (e) {
      await client.query("ROLLBACK");
      throw e;
    } finally {
      client.release();
    }

    return NextResponse.json(results);
  } catch (e: unknown) {
    console.error("Bulk cost update error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
