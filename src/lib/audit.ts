import pool from "@/lib/db";
import type { AuthUser } from "@/lib/auth";

export type AuditAction =
  | "credential_save"
  | "credential_disconnect"
  | "password_change"
  | "profile_update"
  | "avatar_upload"
  | "sync_trigger"
  | "login_success"
  | "login_failed";

/**
 * Write an audit log entry.
 * Non-blocking — errors are logged but never thrown.
 */
export async function auditLog(
  action: AuditAction,
  user: AuthUser | null,
  details?: Record<string, unknown>,
  entityType?: string,
  entityId?: string
): Promise<void> {
  try {
    await pool.query(
      `INSERT INTO audit_log (user_id, action, entity_type, entity_id, details, created_at)
       VALUES ($1, $2, $3, $4, $5, NOW())`,
      [
        user?.id || null,
        action,
        entityType || null,
        entityId || null,
        details ? JSON.stringify(details) : null,
      ]
    );
  } catch (e) {
    console.warn("Audit log write failed:", e instanceof Error ? e.message : e);
  }
}
