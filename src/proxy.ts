import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";

const PUBLIC_PATHS = [
  "/api/v1/auth/login",
];

const PROTECTED_PREFIX = "/api/v1/";

function getCorsOrigins(): string[] {
  const raw = process.env.CORS_ORIGINS || "";
  if (!raw) return [];
  return raw.split(",").map((s) => s.trim()).filter(Boolean);
}

function addCorsHeaders(res: NextResponse, req: NextRequest): NextResponse {
  const origins = getCorsOrigins();
  const origin = req.headers.get("origin");

  if (origins.length === 0) return res;

  if (origin && origins.includes(origin)) {
    res.headers.set("Access-Control-Allow-Origin", origin);
    res.headers.set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    res.headers.set("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.headers.set("Access-Control-Max-Age", "86400");
    res.headers.set("Vary", "Origin");
  }

  return res;
}

function addSecurityHeaders(res: NextResponse): NextResponse {
  res.headers.set("X-Content-Type-Options", "nosniff");
  res.headers.set("X-Frame-Options", "DENY");
  res.headers.set("X-XSS-Protection", "1; mode=block");
  res.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  res.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  return res;
}

export default async function proxy(req: NextRequest) {
  const { pathname } = req.nextUrl;

  // Handle CORS preflight for API routes
  if (req.method === "OPTIONS" && pathname.startsWith(PROTECTED_PREFIX)) {
    const res = new NextResponse(null, { status: 204 });
    addCorsHeaders(res, req);
    return res;
  }

  // Only protect API routes
  if (!pathname.startsWith(PROTECTED_PREFIX)) {
    const res = NextResponse.next();
    addSecurityHeaders(res);
    return res;
  }

  // Allow public paths
  if (PUBLIC_PATHS.some((p) => pathname === p)) {
    const res = NextResponse.next();
    addCorsHeaders(res, req);
    addSecurityHeaders(res);
    return res;
  }

  // Verify JWT
  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) {
    const res = NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    addCorsHeaders(res, req);
    return res;
  }

  const token = auth.slice(7);
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    return NextResponse.json({ error: "Server misconfigured" }, { status: 500 });
  }

  try {
    const { payload } = await jwtVerify(
      token,
      new TextEncoder().encode(secret)
    );

    const res = NextResponse.next();
    res.headers.set("x-user-id", String(payload.sub || ""));
    res.headers.set("x-user-email", String(payload.email || ""));
    res.headers.set("x-user-role", String(payload.role || ""));
    addCorsHeaders(res, req);
    addSecurityHeaders(res);
    return res;
  } catch {
    const res = NextResponse.json({ error: "Invalid or expired token" }, { status: 401 });
    addCorsHeaders(res, req);
    return res;
  }
}
