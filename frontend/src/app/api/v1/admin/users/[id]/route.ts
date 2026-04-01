import { NextRequest, NextResponse } from "next/server";
import { getUserFromRequest } from "@/lib/auth";
import { usersRepo } from "@/lib/repositories";
import { canManageUser, ROLE_LEVELS, type RoleSlug } from "@/lib/rbac";
import { logAudit } from "@/lib/audit";

interface Params {
  params: Promise<{ id: string }>;
}

/**
 * GET /api/v1/admin/users/[id]
 */
export async function GET(req: NextRequest, { params }: Params) {
  const actor = getUserFromRequest(req);
  if (!actor) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { id } = await params;
  const userId = id;
  if (!userId || !userId.trim()) return NextResponse.json({ error: "Invalid ID" }, { status: 400 });

  try {
    const user = await usersRepo.getUserById(userId);
    if (!user) return NextResponse.json({ error: "User not found" }, { status: 404 });

    if (user.role_level < actor.role_level && actor.role_level !== 0) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    return NextResponse.json({ user });
  } catch (e) {
    console.error("Get user error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

/**
 * PUT /api/v1/admin/users/[id] — update user
 */
export async function PUT(req: NextRequest, { params }: Params) {
  const actor = getUserFromRequest(req);
  if (!actor) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { id } = await params;
  const userId = id;
  if (!userId || !userId.trim()) return NextResponse.json({ error: "Invalid ID" }, { status: 400 });

  try {
    const existing = await usersRepo.getUserById(userId);
    if (!existing) return NextResponse.json({ error: "User not found" }, { status: 404 });

    if (!canManageUser(actor.role, existing.role_slug)) {
      return NextResponse.json(
        { error: "Недостаточно прав для редактирования этого пользователя" },
        { status: 403 }
      );
    }

    const body = await req.json();
    const updates: Record<string, any> = {};

    if (body.first_name !== undefined) updates.first_name = String(body.first_name).trim();
    if (body.last_name !== undefined) updates.last_name = String(body.last_name).trim();
    if (body.is_active !== undefined) updates.is_active = Boolean(body.is_active);

    if (body.role_id !== undefined) {
      updates.role_id = Number(body.role_id);
    }

    const updated = await usersRepo.updateUser(userId, updates);

    await logAudit({
      userId: actor.id,
      userEmail: actor.email,
      action: "user.updated",
      details: { target_id: userId, changes: updates },
    });

    return NextResponse.json({ user: updated });
  } catch (e) {
    console.error("Update user error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

/**
 * DELETE /api/v1/admin/users/[id]
 */
export async function DELETE(req: NextRequest, { params }: Params) {
  const actor = getUserFromRequest(req);
  if (!actor) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { id } = await params;
  const userId = id;
  if (!userId || !userId.trim()) return NextResponse.json({ error: "Invalid ID" }, { status: 400 });

  try {
    const existing = await usersRepo.getUserById(userId);
    if (!existing) return NextResponse.json({ error: "User not found" }, { status: 404 });

    if (!canManageUser(actor.role, existing.role_slug)) {
      return NextResponse.json({ error: "Недостаточно прав" }, { status: 403 });
    }

    if (existing.role_level === 0) {
      return NextResponse.json({ error: "Нельзя удалить владельца" }, { status: 403 });
    }

    await usersRepo.deleteUser(userId);

    await logAudit({
      userId: actor.id,
      userEmail: actor.email,
      action: "user.deleted",
      details: { target_id: userId, target_email: existing.email },
    });

    return NextResponse.json({ success: true });
  } catch (e) {
    console.error("Delete user error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}

/**
 * PATCH /api/v1/admin/users/[id] — reset password
 */
export async function PATCH(req: NextRequest, { params }: Params) {
  const actor = getUserFromRequest(req);
  if (!actor) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

  const { id } = await params;
  const userId = id;
  if (!userId || !userId.trim()) return NextResponse.json({ error: "Invalid ID" }, { status: 400 });

  try {
    const existing = await usersRepo.getUserById(userId);
    if (!existing) return NextResponse.json({ error: "User not found" }, { status: 404 });

    if (!canManageUser(actor.role, existing.role_slug)) {
      return NextResponse.json({ error: "Недостаточно прав" }, { status: 403 });
    }

    const body = await req.json();
    if (!body.password || body.password.length < 8) {
      return NextResponse.json({ error: "Пароль минимум 8 символов" }, { status: 400 });
    }

    await usersRepo.resetPassword(userId, body.password);

    await logAudit({
      userId: actor.id,
      userEmail: actor.email,
      action: "user.password_reset",
      details: { target_id: userId, target_email: existing.email },
    });

    return NextResponse.json({ success: true });
  } catch (e) {
    console.error("Reset password error:", e);
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
}
