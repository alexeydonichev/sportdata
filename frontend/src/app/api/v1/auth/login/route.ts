import { NextRequest, NextResponse } from "next/server";
import jwt from "jsonwebtoken";
import bcrypt from "bcryptjs";
import pool from "@/lib/db";

export async function POST(req: NextRequest) {
  try {
    const { email, password } = await req.json();
    if (!email || !password) return NextResponse.json({ error: "Email и пароль обязательны" }, { status: 400 });

    const { rows } = await pool.query(
      `SELECT u.id, u.email, u.password_hash, u.first_name, u.last_name, u.is_active,
              r.slug as role, r.level as role_level
       FROM users u JOIN roles r ON r.id = u.role_id
       WHERE u.email = $1`, [email.toLowerCase()]
    );

    if (!rows.length) return NextResponse.json({ error: "Неверный email или пароль" }, { status: 401 });
    const user = rows[0];
    if (!user.is_active) return NextResponse.json({ error: "Аккаунт деактивирован" }, { status: 403 });

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) return NextResponse.json({ error: "Неверный email или пароль" }, { status: 401 });

    await pool.query(`UPDATE users SET last_login_at = NOW() WHERE id = $1`, [user.id]);

    const token = jwt.sign(
      { sub: user.id, email: user.email, role: user.role, role_level: user.role_level },
      process.env.JWT_SECRET!,
      { expiresIn: "7d" }
    );

    return NextResponse.json({
      token,
      user: { id: user.id, email: user.email, first_name: user.first_name, last_name: user.last_name, role: user.role }
    });
  } catch (e) {
    console.error("Login error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
