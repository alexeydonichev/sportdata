import { NextRequest, NextResponse } from "next/server";
import { getUserFromRequest } from "@/lib/auth";
import { writeFile, mkdir, readFile } from "fs/promises";
import path from "path";
import crypto from "crypto";

const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"];
const MAX_SIZE = 2 * 1024 * 1024; // 2MB

const DATA_DIR = path.join(process.cwd(), "data");
const PROFILE_FILE = path.join(DATA_DIR, "profile.json");
const AVATARS_DIR = path.join(process.cwd(), "public", "avatars");

export async function POST(req: NextRequest) {
  const user = getUserFromRequest(req);
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const formData = await req.formData();
    const file = formData.get("avatar") as File | null;
    if (!file) return NextResponse.json({ error: "No file provided" }, { status: 400 });

    // Validate type
    if (!ALLOWED_TYPES.includes(file.type)) {
      return NextResponse.json({ error: "Допустимы: JPEG, PNG, WebP, GIF" }, { status: 400 });
    }

    // Validate size
    if (file.size > MAX_SIZE) {
      return NextResponse.json({ error: "Максимум 2MB" }, { status: 400 });
    }

    // Read and validate it's actually an image (check magic bytes)
    const buffer = Buffer.from(await file.arrayBuffer());
    if (!isValidImage(buffer)) {
      return NextResponse.json({ error: "Файл не является изображением" }, { status: 400 });
    }

    // Generate safe filename
    const ext = file.type.split("/")[1] === "jpeg" ? "jpg" : file.type.split("/")[1];
    const filename = crypto.randomBytes(16).toString("hex") + "." + ext;

    await mkdir(AVATARS_DIR, { recursive: true });
    await writeFile(path.join(AVATARS_DIR, filename), buffer);

    // Update profile
    const avatarUrl = "/avatars/" + filename;
    const profile = await readProfileSafe();
    profile.avatar_url = avatarUrl;
    await mkdir(DATA_DIR, { recursive: true });
    await writeFile(PROFILE_FILE, JSON.stringify(profile, null, 2));

    return NextResponse.json({ avatar_url: avatarUrl });
  } catch (e) {
    console.error("Avatar upload error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

function isValidImage(buffer: Buffer): boolean {
  if (buffer.length < 4) return false;
  // JPEG: FF D8 FF
  if (buffer[0] === 0xFF && buffer[1] === 0xD8 && buffer[2] === 0xFF) return true;
  // PNG: 89 50 4E 47
  if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4E && buffer[3] === 0x47) return true;
  // GIF: 47 49 46
  if (buffer[0] === 0x47 && buffer[1] === 0x49 && buffer[2] === 0x46) return true;
  // WebP: RIFF....WEBP
  if (buffer.length >= 12 && buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WEBP") return true;
  return false;
}

async function readProfileSafe(): Promise<Record<string, unknown>> {
  try {
    const raw = await readFile(PROFILE_FILE, "utf-8");
    return JSON.parse(raw);
  } catch { return {}; }
}
