import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import { encrypt } from "@/lib/crypto";
import { getUserFromRequest } from "@/lib/auth";
import { auditLog } from "@/lib/audit";

export async function GET(req: NextRequest) {
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
        mc.is_active as credential_active,
        mc.created_at as connected_at,
        mc.updated_at,
        mc.api_key_hint as api_key_masked,
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
        WHERE sj.credential_id = mc.id
        ORDER BY sj.created_at DESC LIMIT 1) as last_sync
      FROM marketplaces m
      LEFT JOIN marketplace_credentials mc ON mc.marketplace_id = m.id AND mc.is_active = true
      ORDER BY m.id
    `);

    return NextResponse.json(rows);
  } catch (e: unknown) {
    console.error("Sync credentials error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

export async function POST(req: NextRequest) {
  const user = getUserFromRequest(req);

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
    if (key.length < 10 || key.length > 2000) {
      return NextResponse.json({ error: "API ключ должен быть от 10 до 2000 символов" }, { status: 400 });
    }

    const safeName = String(name || "API Key").slice(0, 100).replace(/[<>&"']/g, "");
    const encryptedKey = encrypt(key);

    const existing = await pool.query(
      "SELECT id FROM marketplace_credentials WHERE marketplace_id = $1",
      [mpId]
    );

    let credentialId: number;

    if (existing.rows.length > 0) {
      const res = await pool.query(
        `UPDATE marketplace_credentials
         SET api_key_encrypted = $1, client_id = $2, name = $3, is_active = true, updated_at = NOW()
         WHERE marketplace_id = $4
         RETURNING id`,
        [encryptedKey, client_id || null, safeName, mpId]
      );
      credentialId = res.rows[0].id;
    } else {
      const res = await pool.query(
        `INSERT INTO marketplace_credentials (marketplace_id, name, api_key_encrypted, client_id, is_active)
         VALUES ($1, $2, $3, $4, true)
         RETURNING id`,
        [mpId, safeName, encryptedKey, client_id || null]
      );
      credentialId = res.rows[0].id;
    }

    await auditLog("credential_save", user, { marketplace_id: mpId, credential_id: credentialId });
    return NextResponse.json({ success: true, credential_id: credentialId });
  } catch (e: unknown) {
    console.error("Save credential error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

export async function DELETE(req: NextRequest) {
  const user = getUserFromRequest(req);

  try {
    const mpId = parseInt(req.nextUrl.searchParams.get("marketplace_id") || "");
    if (isNaN(mpId) || mpId < 1) {
      return NextResponse.json({ error: "marketplace_id обязателен" }, { status: 400 });
    }

    await pool.query(
      "UPDATE marketplace_credentials SET is_active = false, updated_at = NOW() WHERE marketplace_id = $1",
      [mpId]
    );

    await auditLog("credential_disconnect", user, { marketplace_id: mpId });
    return NextResponse.json({ success: true });
  } catch (e: unknown) {
    console.error("Disconnect marketplace error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
