import { NextRequest, NextResponse } from "next/server";
import jwt from "jsonwebtoken";

// Simple in-memory rate limiter
const loginAttempts = new Map<string, { count: number; resetAt: number }>();
const MAX_ATTEMPTS = 5;
const WINDOW_MS = 15 * 60 * 1000; // 15 minutes

function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = loginAttempts.get(ip);

  if (!entry || now > entry.resetAt) {
    loginAttempts.set(ip, { count: 1, resetAt: now + WINDOW_MS });
    return true;
  }

  if (entry.count >= MAX_ATTEMPTS) {
    return false;
  }

  entry.count++;
  return true;
}

function resetRateLimit(ip: string) {
  loginAttempts.delete(ip);
}

// Cleanup old entries periodically
setInterval(() => {
  const now = Date.now();
  for (const [ip, entry] of loginAttempts.entries()) {
    if (now > entry.resetAt) loginAttempts.delete(ip);
  }
}, 60000);

export async function POST(req: NextRequest) {
  const ip = req.headers.get("x-forwarded-for") || req.headers.get("x-real-ip") || "unknown";

  if (!checkRateLimit(ip)) {
    return NextResponse.json(
      { error: "Слишком много попыток. Повторите через 15 минут" },
      { status: 429 }
    );
  }

  try {
    const body = await req.json();
    const email = String(body.email || "").trim().toLowerCase();
    const password = String(body.password || "");

    if (!email || !password) {
      return NextResponse.json({ error: "Email и пароль обязательны" }, { status: 400 });
    }

    const adminEmail = process.env.ADMIN_EMAIL?.toLowerCase();
    const adminPassword = process.env.ADMIN_PASSWORD;
    const jwtSecret = process.env.JWT_SECRET;

    if (!jwtSecret || jwtSecret.length < 32) {
      console.error("JWT_SECRET is missing or too short");
      return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
    }

    if (email === adminEmail && password === adminPassword) {
      resetRateLimit(ip);

      const user = {
        id: "1",
        email: adminEmail!,
        first_name: "Алексей",
        last_name: "Донич",
        role: "admin",
      };

      const token = jwt.sign(
        { sub: user.id, email: user.email, role: user.role },
        jwtSecret,
        { expiresIn: "7d" }
      );

      return NextResponse.json({ token, user });
    }

    // Generic error message — don't reveal whether email exists
    return NextResponse.json({ error: "Неверный email или пароль" }, { status: 401 });
  } catch (e: unknown) {
    console.error("Login error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
