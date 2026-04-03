import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import { getUserFromRequest } from "@/lib/auth";
import bcrypt from "bcryptjs";

function validatePassword(password: string): { valid: boolean; errors: string[] } {
  const errors: string[] = [];
  if (password.length < 10) errors.push("Минимум 10 символов");
  if (password.length > 128) errors.push("Максимум 128 символов");
  if (!/[a-z]/.test(password)) errors.push("Нужна строчная буква (a-z)");
  if (!/[A-Z]/.test(password)) errors.push("Нужна заглавная буква (A-Z)");
  if (!/[0-9]/.test(password)) errors.push("Нужна цифра (0-9)");
  if (!/[^a-zA-Z0-9]/.test(password)) errors.push("Нужен спецсимвол (!@#$%...)");
  return { valid: errors.length === 0, errors };
}

export async function PUT(req: NextRequest) {
  const user = getUserFromRequest(req);
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const body = await req.json();
    const { current_password, new_password } = body;

    if (!current_password || !new_password) {
      return NextResponse.json({ error: "Оба поля обязательны" }, { status: 400 });
    }

    const validation = validatePassword(new_password);
    if (!validation.valid) {
      return NextResponse.json({ error: validation.errors.join(". ") }, { status: 400 });
    }

    if (current_password === new_password) {
      return NextResponse.json({ error: "Новый пароль должен отличаться от текущего" }, { status: 400 });
    }

    const { rows } = await pool.query("SELECT password_hash FROM users WHERE id = $1", [user.id]);
    if (rows.length === 0) {
      return NextResponse.json({ error: "Пользователь не найден" }, { status: 404 });
    }

    const isValid = await bcrypt.compare(current_password, rows[0].password_hash);
    if (!isValid) {
      return NextResponse.json({ error: "Неверный текущий пароль" }, { status: 403 });
    }

    const newHash = await bcrypt.hash(new_password, 12);
    await pool.query("UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2", [newHash, user.id]);

    // Audit log
    try {
      await pool.query(
        `INSERT INTO audit_log (user_id, action, details, ip_address)
         VALUES ($1, 'password_change', '{}', $2)`,
        [user.id, req.headers.get("x-forwarded-for") || "unknown"]
      );
    } catch { /* non-critical */ }

    return NextResponse.json({ success: true });
  } catch (e) {
    console.error("Password change error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
