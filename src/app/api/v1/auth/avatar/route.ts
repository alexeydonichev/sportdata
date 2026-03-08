import { NextRequest, NextResponse } from "next/server";
import jwt from "jsonwebtoken";
import { writeFile, mkdir } from "fs/promises";
import path from "path";
import crypto from "crypto";

function getUserFromToken(req: NextRequest) {
  const auth = req.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  try {
    return jwt.verify(auth.slice(7), process.env.JWT_SECRET!) as { sub: string; email: string };
  } catch {
    return null;
  }
}

const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"];
const ALLOWED_EXTENSIONS = ["jpg", "jpeg", "png", "webp", "gif"];
const MAX_SIZE = 2 * 1024 * 1024; // 2MB

export async function POST(req: NextRequest) {
  const user = getUserFromToken(req);
  if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  try {
    const formData = await req.formData();
    const file = formData.get("avatar") as File | null;

    if (!file) {
      return NextResponse.json({ error: "No file provided" }, { status: 400 });
    }

    if (!ALLOWED_TYPES.includes(file.type)) {
      return NextResponse.json({ error: "Допустимые форматы: JPG, PNG, WebP, GIF" }, { status: 400 });
    }

    if (file.size > MAX_SIZE) {
      return NextResponse.json({ error: "Максимальный размер файла: 2 МБ" }, { status: 400 });
    }

    // Safe extension: derive from MIME type, not from filename
    const extMap: Record<string, string> = {
      "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/gif": "gif"
    };
    const ext = extMap[file.type] || "jpg";

    // Validate file.name extension doesn't contain path separators
    const originalExt = (file.name.split(".").pop() || "").toLowerCase().replace(/[^a-z0-9]/g, "");
    if (originalExt && !ALLOWED_EXTENSIONS.includes(originalExt)) {
      return NextResponse.json({ error: "Недопустимое расширение файла" }, { status: 400 });
    }

    // Generate safe random filename (no user input in path)
    const randomId = crypto.randomBytes(16).toString("hex");
    const fileName = `avatar_${randomId}.${ext}`;
    const uploadDir = path.join(process.cwd(), "public", "uploads");

    await mkdir(uploadDir, { recursive: true });

    // Verify resolved path is within uploadDir
    const fullPath = path.resolve(uploadDir, fileName);
    if (!fullPath.startsWith(path.resolve(uploadDir))) {
      return NextResponse.json({ error: "Invalid file path" }, { status: 400 });
    }

    const bytes = new Uint8Array(await file.arrayBuffer());

    // Validate magic bytes
    if (!validateMagicBytes(bytes, file.type)) {
      return NextResponse.json({ error: "Файл не является изображением" }, { status: 400 });
    }

    await writeFile(fullPath, bytes);

    const avatarUrl = `/uploads/${fileName}`;
    return NextResponse.json({ success: true, avatar_url: avatarUrl });
  } catch (e: unknown) {
    console.error("Avatar upload error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

function validateMagicBytes(bytes: Uint8Array, mimeType: string): boolean {
  if (bytes.length < 4) return false;
  switch (mimeType) {
    case "image/jpeg":
      return bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF;
    case "image/png":
      return bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47;
    case "image/gif":
      return bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46;
    case "image/webp":
      return bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46;
    default:
      return false;
  }
}
