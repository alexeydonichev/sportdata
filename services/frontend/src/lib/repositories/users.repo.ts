import pool from "@/lib/db";
import bcrypt from "bcryptjs";

export async function listUsers(actorLevel: number) {
  const { rows } = await pool.query(
    `SELECT u.id, u.email, u.first_name, u.last_name, r.name as role, r.slug as role_slug, r.level as role_level, u.is_active, u.last_login_at::text, u.created_at::text
     FROM users u JOIN roles r ON r.id = u.role_id WHERE r.level >= $1 ORDER BY r.level, u.created_at DESC`, [actorLevel]);
  return rows;
}
export async function getUserById(id: string) {
  const { rows } = await pool.query(
    `SELECT u.id, u.email, u.first_name, u.last_name, r.name as role, r.slug as role_slug, r.level as role_level, u.is_active, u.last_login_at::text, u.created_at::text
     FROM users u JOIN roles r ON r.id = u.role_id WHERE u.id = $1`, [id]);
  return rows[0] || null;
}
export async function createUser(p: { email: string; password: string; first_name: string; last_name: string; role_id: number }) {
  const hash = await bcrypt.hash(p.password, 12);
  const { rows } = await pool.query(`INSERT INTO users (email, password_hash, first_name, last_name, role_id) VALUES ($1,$2,$3,$4,$5) RETURNING id`, [p.email, hash, p.first_name, p.last_name, p.role_id]);
  return getUserById(rows[0].id);
}
export async function updateUser(id: string, p: any) {
  const sets: string[] = []; const vals: any[] = []; let i = 0;
  if (p.first_name !== undefined) { i++; sets.push(`first_name=$${i}`); vals.push(p.first_name); }
  if (p.last_name !== undefined) { i++; sets.push(`last_name=$${i}`); vals.push(p.last_name); }
  if (p.role_id !== undefined) { i++; sets.push(`role_id=$${i}`); vals.push(p.role_id); }
  if (p.is_active !== undefined) { i++; sets.push(`is_active=$${i}`); vals.push(p.is_active); }
  if (sets.length) { i++; vals.push(id); await pool.query(`UPDATE users SET ${sets.join(",")},updated_at=NOW() WHERE id=$${i}`, vals); }
  return getUserById(id);
}
export async function deleteUser(id: string) { const r = await pool.query(`DELETE FROM users WHERE id=$1`, [id]); return (r.rowCount ?? 0) > 0; }
export async function emailExists(email: string) { const { rows } = await pool.query(`SELECT 1 FROM users WHERE email=$1`, [email.toLowerCase()]); return rows.length > 0; }
export async function listRoles() { const { rows } = await pool.query(`SELECT id, slug, name, level FROM roles ORDER BY level`); return rows; }

export async function resetPassword(id: string, newPassword: string) {
  const hash = await bcrypt.hash(newPassword, 12);
  const r = await pool.query('UPDATE users SET password_hash=$1, updated_at=NOW() WHERE id=$2', [hash, id]);
  return (r.rowCount ?? 0) > 0;
}
