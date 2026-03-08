import { NextRequest } from "next/server";

export interface AuthUser {
  id: string;
  email: string;
  role: string;
}

/**
 * Extract user from request headers set by proxy.ts
 * This is the primary method — proxy already verified JWT.
 */
export function getUserFromRequest(req: NextRequest): AuthUser | null {
  const id = req.headers.get("x-user-id");
  const email = req.headers.get("x-user-email");

  if (!id || !email) return null;

  return {
    id,
    email,
    role: req.headers.get("x-user-role") || "user",
  };
}
