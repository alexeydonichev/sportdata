import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import { encrypt, maskKey, decrypt } from "@/lib/crypto";

export async function GET() {
  try {
    const { rows } = await pool.query(`
      SELECT
        m.id,
        m.slug,
        m.name,
        m.api_base_url,
        m.is_active as marketplace_active,
        mc.id as credential_id,
        mc.name as credential_name,
        mc.client_id,
        mc.api_key_encrypted,
        mc.is_active as credential_active,
        mc.created_at as connected_at,
        mc.updated_at,
        CASE WHEN mc.id IS NOT NULL AND mc.is_active THEN 'connected'
             WHEN mc.id IS NOT NULL AND NOT mc.is_active THEN 'disabled'
             ELSE 'not_connected' END as status,
        (SELECT json_build_object(
          'id', sj.id,
          'job_type', sj.job_type,
          'status', sj.status,
          'started_at', sj.started_at,
          'completed_at', sj.completed_at,
          'records_processed', sj.records_processed,
          'error_message', sj.error_message
        ) FROM sync_jobs sj
        WHERE sj.marketplace_id = m.id
        ORDER BY sj.created_at DESC LIMIT 1) as last_sync
      FROM marketplaces m
      LEFT JOIN marketplace_credentials mc ON mc.marketplace_id = m.id
      ORDER BY m.id
    `);

    // Mask API keys — never send raw keys to frontend
    const safeRows = rows.map((row: Record<string, unknown>) => {
      const r = { ...row };
      if (r.api_key_encrypted) {
        try {
          const decrypted = decrypt(String(r.api_key_encrypted));
          r.api_key_masked = maskKey(decrypted);
        } catch {
          // Legacy plaintext key — mask it directly
          r.api_key_masked = maskKey(String(r.api_key_encrypted));
        }
      } else {
        r.api_key_masked = null;
      }
      delete r.api_key_encrypted; // Never expose to frontend
      return r;
    });

    return NextResponse.json(safeRows);
  } catch (e: unknown) {
    console.error("Sync credentials error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  try {
    const body = await req.json();
    const { marketplace_id, name, api_key, client_id } = body;

    if (!marketplace_id || !api_key) {
      return NextResponse.json({ error: "marketplace_id и api_key обязательны" }, { status: 400 });
    }

    const mpId = parseInt(String(marketplace_id));
    if (isNaN(mpId) || mpId < 1) {
      return NextResponse.json({ error: "Некорректный marketplace_id" }, { status: 400 });
    }

    const key = String(api_key).trim();
    if (key.length < 10 || key.length > 500) {
      return NextResponse.json({ error: "API ключ должен быть от 10 до 500 символов" }, { status: 400 });
    }

    const safeName = String(name || "API Key").slice(0, 100).replace(/[<>&"']/g, "");

    // Encrypt the API key before storing
    const encryptedKey = encrypt(key);

    const existing = await pool.query(
      "SELECT id FROM marketplace_credentials WHERE marketplace_id = $1",
      [mpId]
    );

    if (existing.rows.length > 0) {
      await pool.query(
        `UPDATE marketplace_credentials
         SET api_key_encrypted = $1, client_id = $2, name = $3, is_active = true, updated_at = NOW()
         WHERE marketplace_id = $4`,
        [encryptedKey, client_id || null, safeName, mpId]
      );
    } else {
      await pool.query(
        `INSERT INTO marketplace_credentials (marketplace_id, name, api_key_encrypted, client_id, is_active)
         VALUES ($1, $2, $3, $4, true)`,
        [mpId, safeName, encryptedKey, client_id || null]
      );
    }

    return NextResponse.json({ success: true });
  } catch (e: unknown) {
    console.error("Save credential error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

export async function DELETE(req: NextRequest) {
  try {
    const mpId = parseInt(req.nextUrl.searchParams.get("marketplace_id") || "");
    if (isNaN(mpId) || mpId < 1) {
      return NextResponse.json({ error: "marketplace_id обязателен" }, { status: 400 });
    }

    await pool.query(
      "UPDATE marketplace_credentials SET is_active = false, updated_at = NOW() WHERE marketplace_id = $1",
      [mpId]
    );

    return NextResponse.json({ success: true });
  } catch (e: unknown) {
    console.error("Disconnect marketplace error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
