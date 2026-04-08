import { NextRequest, NextResponse } from "next/server";
import { jwtVerify } from "jose";

const PUBLIC_PATHS = ["/api/v1/auth/login"];
const PROTECTED_PREFIX = "/api/v1/";
const MUTATION_METHODS = ["POST", "PUT", "DELETE", "PATCH"];

// === Rate Limiting ===
const rateLimits = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT = 100;       // requests per window
const RATE_WINDOW = 60_000;   // 1 minute

// Cleanup every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [key, val] of rateLimits) {
    if (now > val.resetAt) rateLimits.delete(key);
  }
}, 5 * 60_000);

function checkRateLimit(key: string): { allowed: boolean; remaining: number } {
  const now = Date.now();
  const entry = rateLimits.get(key);

  if (!entry || now > entry.resetAt) {
    rateLimits.set(key, { count: 1, resetAt: now + RATE_WINDOW });
    return { allowed: true, remaining: RATE_LIMIT - 1 };
  }

  entry.count++;
  const remaining = Math.max(0, RATE_LIMIT - entry.count);
  return { allowed: entry.count <= RATE_LIMIT, remaining };
}

// === CORS ===
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

// === CSRF Check ===
function checkCsrf(req: NextRequest): boolean {
  // Only check mutation methods
  if (!MUTATION_METHODS.includes(req.method)) return true;

  const origin = req.headers.get("origin");
  const host = req.headers.get("host");

  // If no origin header (e.g. same-origin non-CORS), allow
  if (!origin) return true;

  // Origin must match host
  try {
    const originUrl = new URL(origin);
    const expectedHost = host?.split(":")[0];
    if (originUrl.hostname === expectedHost) return true;
    if (originUrl.hostname === "localhost" && expectedHost === "localhost") return true;

    // Check against allowed CORS origins
    const allowed = getCorsOrigins();
    if (allowed.includes(origin)) return true;
  } catch {
    return false;
  }

  return false;
}

export default async function proxy(req: NextRequest) {
  const { pathname } = req.nextUrl;

  // Handle CORS preflight for API routes
  if (req.method === "OPTIONS" && pathname.startsWith(PROTECTED_PREFIX)) {
    const res = new NextResponse(null, { status: 204 });
    addCorsHeaders(res, req);
    return res;
  }

  // Non-API routes — just add security headers
  if (!pathname.startsWith(PROTECTED_PREFIX)) {
    const res = NextResponse.next();
    addSecurityHeaders(res);
    return res;
  }

  // === API Routes below ===

  // Rate limiting (by IP or forwarded IP)
  const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || req.headers.get("x-real-ip")
    || "unknown";
  const { allowed, remaining } = checkRateLimit(clientIp);

  if (!allowed) {
    const res = NextResponse.json(
      { error: "Too many requests. Try again later." },
      { status: 429 }
    );
    res.headers.set("Retry-After", "60");
    res.headers.set("X-RateLimit-Remaining", "0");
    addCorsHeaders(res, req);
    return res;
  }

  // CSRF check for mutations
  if (!checkCsrf(req)) {
    const res = NextResponse.json(
      { error: "CSRF validation failed" },
      { status: 403 }
    );
    addCorsHeaders(res, req);
    return res;
  }

  // Allow public paths
  if (PUBLIC_PATHS.some((p) => pathname === p)) {
    const res = NextResponse.next();
    res.headers.set("X-RateLimit-Remaining", String(remaining));
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
    res.headers.set("X-RateLimit-Remaining", String(remaining));
    addCorsHeaders(res, req);
    addSecurityHeaders(res);
    return res;
  } catch {
    const res = NextResponse.json({ error: "Invalid or expired token" }, { status: 401 });
    addCorsHeaders(res, req);
    return res;
  }
}


export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon\\.ico|icons/|manifest\\.json|sw\\.js|avatars/).*)",
  ],
};
