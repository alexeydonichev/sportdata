import pool from "@/lib/db";
import crypto from "crypto";

export interface InviteRow {
  id: number;
  token: string;
  email: string;
  role_level: number;
  role_name: string;
  scopes: { scope_type: string; scope_value: string | null }[];
  created_by: number;
  creator_email: string;
  expires_at: string;
  used_at: string | null;
  created_at: string;
}

/**
 * Create invite token
 */
export async function createInvite(params: {
  email: string;
  role_level: number;
  scopes: { scope_type: string; scope_value: string | null }[];
  created_by: number;
  expires_hours?: number;
}): Promise<InviteRow> {
  const token = crypto.randomBytes(32).toString("hex");
  const expiresHours = params.expires_hours || 72;

  const { rows } = await pool.query(
    `INSERT INTO invite_tokens (token, email, role_level, scopes, created_by, expires_at)
     VALUES ($1, $2, $3, $4::jsonb, $5, NOW() + $6::interval)
     RETURNING id`,
    [
      token,
      params.email.toLowerCase(),
      params.role_level,
      JSON.stringify(params.scopes),
      params.created_by,
      `${expiresHours} hours`,
    ]
  );

  return (await getInviteById(rows[0].id))!;
}

/**
 * Get invite by ID with joined data
 */
export async function getInviteById(id: number): Promise<InviteRow | null> {
  const { rows } = await pool.query(
    `SELECT
      it.id, it.token, it.email, it.role_level,
      rd.name AS role_name,
      it.scopes,
      it.created_by,
      u.email AS creator_email,
      it.expires_at::text,
      it.used_at::text,
      it.created_at::text
    FROM invite_tokens it
    JOIN users u ON u.id = it.created_by
    LEFT JOIN role_definitions rd ON rd.level = it.role_level
    WHERE it.id = $1`,
    [id]
  );
  return rows[0] || null;
}

/**
 * Get invite by token (for registration)
 */
export async function getInviteByToken(token: string): Promise<InviteRow | null> {
  const { rows } = await pool.query(
    `SELECT
      it.id, it.token, it.email, it.role_level,
      rd.name AS role_name,
      it.scopes,
      it.created_by,
      u.email AS creator_email,
      it.expires_at::text,
      it.used_at::text,
      it.created_at::text
    FROM invite_tokens it
    JOIN users u ON u.id = it.created_by
    LEFT JOIN role_definitions rd ON rd.level = it.role_level
    WHERE it.token = $1 AND it.used_at IS NULL AND it.expires_at > NOW()`,
    [token]
  );
  return rows[0] || null;
}

/**
 * Mark invite as used
 */
export async function markUsed(id: number): Promise<void> {
  await pool.query(
    `UPDATE invite_tokens SET used_at = NOW() WHERE id = $1`,
    [id]
  );
}

/**
 * List invites created by users with level >= actorLevel
 */
export async function listInvites(actorLevel: number): Promise<InviteRow[]> {
  const { rows } = await pool.query(
    `SELECT
      it.id, it.token, it.email, it.role_level,
      rd.name AS role_name,
      it.scopes,
      it.created_by,
      u.email AS creator_email,
      it.expires_at::text,
      it.used_at::text,
      it.created_at::text
    FROM invite_tokens it
    JOIN users u ON u.id = it.created_by
    LEFT JOIN role_definitions rd ON rd.level = it.role_level
    WHERE it.role_level >= $1
    ORDER BY it.created_at DESC
    LIMIT 100`,
    [actorLevel]
  );
  return rows;
}

/**
 * Delete invite
 */
export async function deleteInvite(id: number): Promise<boolean> {
  const { rowCount } = await pool.query(
    `DELETE FROM invite_tokens WHERE id = $1`,
    [id]
  );
  return (rowCount ?? 0) > 0;
}
