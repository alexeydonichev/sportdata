import { NextRequest } from "next/server";
import jwt from "jsonwebtoken";

export interface AuthUser {
  id: string;
  email: string;
  role: string;
  role_level: number;
}

export function getUserFromRequest(req: NextRequest): AuthUser | null {
  const header = req.headers.get("authorization");
  if (!header?.startsWith("Bearer ")) return null;
  try {
    const payload = jwt.verify(header.slice(7), process.env.JWT_SECRET!) as any;
    return { id: payload.sub, email: payload.email, role: payload.role, role_level: payload.role_level ?? 99 };
  } catch { return null; }
}
