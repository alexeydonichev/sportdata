import { NextRequest, NextResponse } from "next/server";
import { getUserFromRequest } from "@/lib/auth";
import { usersRepo } from "@/lib/repositories";

export async function GET(req: NextRequest) {
  const actor = getUserFromRequest(req);
  if (!actor) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (actor.role_level > 3) return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  const users = await usersRepo.listUsers(actor.role_level);
  const roles = await usersRepo.listRoles();
  return NextResponse.json({ users, roles });
}
export async function POST(req: NextRequest) {
  const actor = getUserFromRequest(req);
  if (!actor) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  if (actor.role_level > 1) return NextResponse.json({ error: "Forbidden" }, { status: 403 });
  const { email, password, first_name, last_name, role_id } = await req.json();
  if (!email || !password || !first_name || !last_name || !role_id) return NextResponse.json({ error: "Missing fields" }, { status: 400 });
  if (await usersRepo.emailExists(email)) return NextResponse.json({ error: "Email exists" }, { status: 409 });
  const user = await usersRepo.createUser({ email, password, first_name, last_name, role_id });
  return NextResponse.json({ user }, { status: 201 });
}
