import { NextRequest, NextResponse } from "next/server";
import { getUserFromRequest } from "@/lib/auth";
import { readFile, writeFile, mkdir } from "fs/promises";
import path from "path";

const DATA_DIR = path.join(process.cwd(), "data");
const PROFILE_FILE = path.join(DATA_DIR, "profile.json");

async function readProfile(): Promise<Record<string, unknown>> {
  try {
    const raw = await readFile(PROFILE_FILE, "utf-8");
    return JSON.parse(raw);
  } catch { return {}; }
}

async function saveProfile(data: Record<string, unknown>) {
  await mkdir(DATA_DIR, { recursive: true });
  await writeFile(PROFILE_FILE, JSON.stringify(data, null, 2));
}

export async function GET(req: NextRequest) {
  const user = getUserFromRequest(req);
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const profile = await readProfile();
  return NextResponse.json({
    email: user.email,
    first_name: profile.first_name || "",
    last_name: profile.last_name || "",
    company: profile.company || "",
    phone: profile.phone || "",
    avatar_url: profile.avatar_url || null,
  });
}

export async function PUT(req: NextRequest) {
  const user = getUserFromRequest(req);
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const body = await req.json();

    // Sanitize — only allow specific fields, max lengths
    const ALLOWED_FIELDS = ["first_name", "last_name", "company", "phone"];
    const MAX_LEN = 100;

    const profile = await readProfile();
    for (const field of ALLOWED_FIELDS) {
      if (body[field] !== undefined) {
        const val = String(body[field]).trim().slice(0, MAX_LEN);
        profile[field] = val;
      }
    }

    await saveProfile(profile);
    return NextResponse.json({ success: true });
  } catch (e) {
    console.error("Profile update error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
