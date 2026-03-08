import { NextRequest, NextResponse } from "next/server";
import pool from "@/lib/db";
import jwt from "jsonwebtoken";
import { createHash, randomBytes, timingSafeEqual } from "crypto";

function getUserFromToken(req: NextRequest) {
  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  try {
    return jwt.verify(auth.slice(7), process.env.JWT_SECRET!) as { sub: string; email: string };
  } catch {
    return null;
  }
}

function validatePassword(password: string): { valid: boolean; errors: string[] } {
  const errors: string[] = [];
  if (password.length < 10) errors.push("Минимум 10 символов");
  if (!/[a-z]/.test(password)) errors.push("Нужна строчная буква (a-z)");
  if (!/[A-Z]/.test(password)) errors.push("Нужна заглавная буква (A-Z)");
  if (!/[0-9]/.test(password)) errors.push("Нужна цифра (0-9)");
  if (!/[^a-zA-Z0-9]/.test(password)) errors.push("Нужен спецсимвол (!@#$%...)");
  return { valid: errors.length === 0, errors };
}

// Simple hash comparison that works with bcrypt hashes from Go backend
// and also supports our own sha256 hashes
async function verifyPassword(password: string, hash: string): Promise<boolean> {
  // Try dynamic import of bcryptjs
  try {
    const bcrypt = await import("bcryptjs");
    return bcrypt.compare(password, hash);
  } catch {
    // Fallback: sha256 comparison
    const [salt, stored] = hash.split(":");
    if (!salt || !stored) return false;
    const computed = createHash("sha256").update(salt + password).digest("hex");
    const a = Buffer.from(stored, "hex");
    const b = Buffer.from(computed, "hex");
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  }
}

async function hashPassword(password: string): Promise<string> {
  try {
    const bcrypt = await import("bcryptjs");
    return bcrypt.hash(password, 12);
  } catch {
    const salt = randomBytes(16).toString("hex");
    const hashed = createHash("sha256").update(salt + password).digest("hex");
    return salt + ":" + hashed;
  }
}

export async function PUT(req: NextRequest) {
  const user = getUserFromToken(req);
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const { current_password, new_password } = await req.json();

    const validation = validatePassword(new_password || "");
    if (!validation.valid) {
      return NextResponse.json({ error: validation.errors.join(". ") }, { status: 400 });
    }

    const { rows } = await pool.query("SELECT password_hash FROM users WHERE id = $1", [user.sub]);
    if (!rows.length) return NextResponse.json({ error: "User not found" }, { status: 404 });

    const valid = await verifyPassword(current_password, rows[0].password_hash);
    if (!valid) return NextResponse.json({ error: "Неверный текущий пароль" }, { status: 400 });

    const hash = await hashPassword(new_password);
    await pool.query("UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2", [hash, user.sub]);

    return NextResponse.json({ success: true });
  } catch (e: unknown) {
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
