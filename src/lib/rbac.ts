export type RoleSlug = "super_admin" | "owner" | "director" | "head" | "manager";
export const ROLE_LEVELS: Record<RoleSlug, number> = { super_admin: 0, owner: 1, director: 2, head: 3, manager: 4 };
export function canManageUser(actorRole: string, targetRole: string): boolean {
  const a = ROLE_LEVELS[actorRole as RoleSlug], b = ROLE_LEVELS[targetRole as RoleSlug];
  return a !== undefined && b !== undefined && a < b;
}
export function isAdmin(role: string): boolean { return role === "super_admin" || role === "owner"; }
