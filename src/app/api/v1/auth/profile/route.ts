import { NextRequest, NextResponse } from "next/server";
import jwt from "jsonwebtoken";
import { readFile, writeFile, mkdir } from "fs/promises";
import path from "path";

function getUserFromToken(req: NextRequest) {
  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  try {
    return jwt.verify(auth.slice(7), process.env.JWT_SECRET!) as { sub: string; email: string };
  } catch {
    return null;
  }
}

const DATA_DIR = path.join(process.cwd(), "data");
const PROFILE_FILE = path.join(DATA_DIR, "profile.json");

async function readProfile(): Promise<Record<string, unknown>> {
  try {
    const raw = await readFile(PROFILE_FILE, "utf-8");
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

async function saveProfile(data: Record<string, unknown>) {
  await mkdir(DATA_DIR, { recursive: true });
  await writeFile(PROFILE_FILE, JSON.stringify(data, null, 2));
}

export async function PUT(req: NextRequest) {
  const user = getUserFromToken(req);
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const { first_name, last_name } = await req.json();
    const profile = await readProfile();
    profile[user.sub] = {
      ...(profile[user.sub] as Record<string, unknown> || {}),
      first_name,
      last_name,
      updated_at: new Date().toISOString(),
    };
    await saveProfile(profile);
    return NextResponse.json({ success: true });
  } catch (e: unknown) {
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
