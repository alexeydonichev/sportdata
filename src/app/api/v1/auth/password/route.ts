import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import { getUserFromRequest } from "@/lib/auth";
import { auditLog } from "@/lib/audit";
import { createHash, randomBytes, timingSafeEqual } from "crypto";

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

async function verifyPassword(password: string, hash: string): Promise<boolean> {
  try {
    const bcrypt = await import("bcryptjs");
    return bcrypt.compare(password, hash);
  } catch {
    // Fallback: SHA-256 with salt (salt:hash format)
    const [salt, storedHash] = hash.split(":");
    if (!salt || !storedHash) return false;
    const computed = createHash("sha256").update(salt + password).digest("hex");
    const a = Buffer.from(computed, "hex");
    const b = Buffer.from(storedHash, "hex");
    return a.length === b.length && timingSafeEqual(a, b);
  }
}

function hashPassword(password: string): string {
  const salt = randomBytes(32).toString("hex");
  const hash = createHash("sha256").update(salt + password).digest("hex");
  return salt + ":" + hash;
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

    const isValid = await verifyPassword(current_password, rows[0].password_hash);
    if (!isValid) {
      return NextResponse.json({ error: "Неверный текущий пароль" }, { status: 403 });
    }

    const newHash = hashPassword(new_password);
    await pool.query("UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2", [newHash, user.id]);

    await auditLog("password_change", user, {}, "user", user.id);

    return NextResponse.json({ success: true });
  } catch (e) {
    console.error("Password change error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
