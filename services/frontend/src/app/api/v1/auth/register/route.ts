import { NextRequest, NextResponse } from "next/server";
import jwt from "jsonwebtoken";
import bcrypt from "bcryptjs";
import pool from "@/lib/db";
import { logAudit } from "@/lib/audit";

export async function POST(req: NextRequest) {
  try {
    const { token, password, name } = await req.json();

    if (!token || !password || !name) {
      return NextResponse.json({ error: "Заполните все поля" }, { status: 400 });
    }
    if (password.length < 8) {
      return NextResponse.json({ error: "Пароль минимум 8 символов" }, { status: 400 });
    }

    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret || jwtSecret.length < 32) {
      return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
    }

    // Find valid invite
    const invResult = await pool.query(
      `SELECT i.id, i.email, i.role_level, i.created_by,
              r.slug as role_name
       FROM invites i
       JOIN roles r ON r.level = i.role_level
       WHERE i.token = $1 AND i.used_at IS NULL AND i.expires_at > NOW()`,
      [token]
    );

    if (invResult.rows.length === 0) {
      return NextResponse.json({ error: "Приглашение не найдено или истекло" }, { status: 400 });
    }

    const invite = invResult.rows[0];

    // Check if user already exists
    const existCheck = await pool.query(
      `SELECT id FROM users WHERE email = $1`, [invite.email]
    );
    if (existCheck.rows.length > 0) {
      return NextResponse.json({ error: "Пользователь с таким email уже существует" }, { status: 409 });
    }

    // Create user
    const passwordHash = await bcrypt.hash(password, 12);

    const userResult = await pool.query(
      `INSERT INTO users (email, password_hash, name, role, role_level, is_active, invited_by)
       VALUES ($1, $2, $3, $4, $5, true, $6)
       RETURNING id, email, name, role, role_level`,
      [invite.email, passwordHash, name.trim(), invite.role_name, invite.role_level, invite.created_by]
    );

    const dbUser = userResult.rows[0];

    // Copy scopes from invite
    const invScopes = await pool.query(
      `SELECT scope_type, scope_value FROM invite_scopes WHERE invite_id = $1`,
      [invite.id]
    );
    for (const s of invScopes.rows) {
      await pool.query(
        `INSERT INTO user_scopes (user_id, scope_type, scope_value) VALUES ($1, $2, $3)`,
        [dbUser.id, s.scope_type, s.scope_value]
      );
    }

    // Mark invite as used
    await pool.query(
      `UPDATE invites SET used_at = NOW() WHERE id = $1`,
      [invite.id]
    );

    // Get scopes for JWT
    const scopesResult = await pool.query(
      `SELECT scope_type, scope_value FROM user_scopes WHERE user_id = $1`,
      [dbUser.id]
    );

    // Parse name
    const nameParts = (dbUser.name || "").split(" ");
    const firstName = nameParts[0] || "";
    const lastName = nameParts.slice(1).join(" ") || "";

    const user = {
      id: String(dbUser.id),
      email: dbUser.email,
      first_name: firstName,
      last_name: lastName,
      role: dbUser.role,
      role_level: dbUser.role_level,
    };

    const jwtToken = jwt.sign(
      {
        sub: user.id,
        email: user.email,
        role: user.role,
        role_level: user.role_level,
        scopes: scopesResult.rows,
        is_active: true,
      },
      jwtSecret,
      { expiresIn: "7d" }
    );

    await logAudit({
      userId: dbUser.id,
      userEmail: dbUser.email,
      action: "user.registered",
      details: { invite_id: invite.id, invited_by: invite.created_by },
    });

    return NextResponse.json({ token: jwtToken, user });
  } catch (e) {
    console.error("Register error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
