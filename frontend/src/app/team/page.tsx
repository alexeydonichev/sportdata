"use client";

import { useEffect, useState, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import { api, AdminUser, AdminInvite } from "@/lib/api";
import {
  Users, UserPlus, Mail, Shield, Loader2, Check, Trash2,
  MoreVertical, X, Key, AlertTriangle, Copy,
} from "lucide-react";

const ROLES = [
  { slug: "co_owner", label: "Совладелец", level: 1 },
  { slug: "director", label: "Директор / Гл. аналитик", level: 2 },
  { slug: "manager", label: "Руководитель", level: 3 },
  { slug: "shop_manager", label: "Менеджер магазина", level: 4 },
  { slug: "support", label: "Поддержка", level: 5 },
];

function roleBadgeClass(role: string) {
  switch (role) {
    case "owner": return "bg-accent-amber/10 text-accent-amber";
    case "co_owner": return "bg-purple-500/10 text-purple-500";
    case "director": return "bg-accent-blue/10 text-accent-blue";
    case "manager": return "bg-accent-green/10 text-accent-green";
    case "shop_manager": return "bg-teal-500/10 text-teal-500";
    default: return "bg-surface-3 text-text-secondary";
  }
}

function roleLabel(role: string) {
  if (role === "owner") return "Владелец";
  const found = ROLES.find((r) => r.slug === role);
  return found?.label || role;
}

function timeAgo(dateStr: string | null) {
  if (!dateStr) return "Никогда";
  const diff = Date.now() - new Date(dateStr).getTime();
  const mins = Math.floor(diff / 60000);
  if (mins < 1) return "Только что";
  if (mins < 60) return `${mins} мин назад`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours} ч назад`;
  const days = Math.floor(hours / 24);
  if (days < 30) return `${days} дн назад`;
  return new Date(dateStr).toLocaleDateString("ru-RU");
}

export default function TeamPage() {
  const [activeTab, setActiveTab] = useState<"users" | "invites">("users");
  const [users, setUsers] = useState<AdminUser[]>([]);
  const [invites, setInvites] = useState<AdminInvite[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");

  // Modal states
  const [showInviteModal, setShowInviteModal] = useState(false);
  const [showUserModal, setShowUserModal] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState<number | null>(null);
  const [showResetModal, setShowResetModal] = useState<number | null>(null);
  const [openMenu, setOpenMenu] = useState<number | null>(null);

  // Form
  const [formEmail, setFormEmail] = useState("");
  const [formName, setFormName] = useState("");
  const [formPassword, setFormPassword] = useState("");
  const [formRole, setFormRole] = useState("manager");
  const [formSaving, setFormSaving] = useState(false);
  const [formError, setFormError] = useState("");

  const [resetPassword, setResetPassword] = useState("");
  const [resetSaving, setResetSaving] = useState(false);

  // Edit user
  const [editUser, setEditUser] = useState<AdminUser | null>(null);
  const [editRole, setEditRole] = useState("");
  const [editActive, setEditActive] = useState(true);

  const currentUser = typeof window !== "undefined" ? JSON.parse(localStorage.getItem("yf_user") || "{}") : {};

  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const [u, i] = await Promise.all([api.adminUsers(), api.adminInvites()]);
      setUsers(u.users);
      setInvites(i.invites);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ошибка загрузки");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { load(); }, [load]);

  // Close menus on click outside
  useEffect(() => {
    const handler = () => setOpenMenu(null);
    document.addEventListener("click", handler);
    return () => document.removeEventListener("click", handler);
  }, []);

  const handleCreateUser = async () => {
    setFormError("");
    if (!formEmail || !formPassword || !formName) { setFormError("Заполните все поля"); return; }
    if (formPassword.length < 8) { setFormError("Пароль минимум 8 символов"); return; }
    setFormSaving(true);
    try {
      await api.adminCreateUser({ email: formEmail, password: formPassword, name: formName, role: formRole });
      setShowUserModal(false);
      resetForm();
      load();
    } catch (e) {
      setFormError(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setFormSaving(false);
    }
  };

  const handleInvite = async () => {
    setFormError("");
    if (!formEmail) { setFormError("Укажите email"); return; }
    setFormSaving(true);
    try {
      const res = await api.adminCreateInvite({ email: formEmail, role: formRole });
      setShowInviteModal(false);
      resetForm();
      load();
      // Copy link
      const link = window.location.origin + "/register?token=" + res.invite.token;
      await navigator.clipboard.writeText(link).catch(() => {});
    } catch (e) {
      setFormError(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setFormSaving(false);
    }
  };

  const handleUpdateUser = async () => {
    if (!editUser) return;
    setFormSaving(true);
    setFormError("");
    try {
      await api.adminUpdateUser(editUser.id, { role: editRole, is_active: editActive });
      setEditUser(null);
      load();
    } catch (e) {
      setFormError(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setFormSaving(false);
    }
  };

  const handleDelete = async (id: number) => {
    try {
      await api.adminDeleteUser(id);
      setShowDeleteConfirm(null);
      load();
    } catch (e) {
      alert(e instanceof Error ? e.message : "Ошибка");
    }
  };

  const handleResetPassword = async () => {
    if (!showResetModal || resetPassword.length < 8) return;
    setResetSaving(true);
    try {
      await api.adminResetPassword(showResetModal, resetPassword);
      setShowResetModal(null);
      setResetPassword("");
    } catch (e) {
      alert(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setResetSaving(false);
    }
  };

  const handleDeleteInvite = async (id: number) => {
    try {
      await api.adminDeleteInvite(id);
      load();
    } catch (e) {
      alert(e instanceof Error ? e.message : "Ошибка");
    }
  };

  const copyInviteLink = (token: string) => {
    const link = window.location.origin + "/register?token=" + token;
    navigator.clipboard.writeText(link).catch(() => {});
  };

  function resetForm() {
    setFormEmail(""); setFormName(""); setFormPassword(""); setFormRole("manager"); setFormError("");
  }

  function openEdit(u: AdminUser) {
    setEditUser(u);
    setEditRole(u.role);
    setEditActive(u.is_active);
    setFormError("");
    setOpenMenu(null);
  }

  if (loading) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center py-20">
          <Loader2 className="h-5 w-5 animate-spin text-text-tertiary" />
        </div>
      </AppLayout>
    );
  }

  if (error) {
    return (
      <AppLayout>
        <div className="flex flex-col items-center justify-center py-20 gap-3">
          <AlertTriangle className="h-6 w-6 text-accent-red" />
          <p className="text-sm text-text-secondary">{error}</p>
          <button onClick={load} className="text-xs text-text-secondary hover:text-text-primary underline">Повторить</button>
        </div>
      </AppLayout>
    );
  }

  const pendingInvites = invites.filter((i) => !i.used_at && new Date(i.expires_at) > new Date());

  return (
    <AppLayout>
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Команда</h1>
          <p className="text-sm text-text-secondary mt-1">{users.length} пользовател{users.length === 1 ? "ь" : "ей"}</p>
        </div>
        <div className="flex gap-2">
          <button onClick={() => { resetForm(); setShowInviteModal(true); }}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium border border-border-default text-text-secondary hover:text-text-primary hover:bg-surface-2 transition-colors">
            <Mail className="h-3.5 w-3.5" />
            Пригласить
          </button>
          <button onClick={() => { resetForm(); setShowUserModal(true); }}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary transition-colors">
            <UserPlus className="h-3.5 w-3.5" />
            Создать
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 mb-4">
        <button onClick={() => setActiveTab("users")}
          className={"px-3 py-1.5 rounded-lg text-xs font-medium transition-colors " + (activeTab === "users" ? "bg-surface-3 text-text-primary" : "text-text-secondary hover:text-text-primary hover:bg-surface-2")}>
          <Users className="h-3.5 w-3.5 inline mr-1.5" />Пользователи
        </button>
        <button onClick={() => setActiveTab("invites")}
          className={"px-3 py-1.5 rounded-lg text-xs font-medium transition-colors " + (activeTab === "invites" ? "bg-surface-3 text-text-primary" : "text-text-secondary hover:text-text-primary hover:bg-surface-2")}>
          <Mail className="h-3.5 w-3.5 inline mr-1.5" />Приглашения
          {pendingInvites.length > 0 && (
            <span className="ml-1.5 min-w-[18px] h-[18px] inline-flex items-center justify-center rounded-full bg-accent-amber/15 text-accent-amber text-[10px] font-bold px-1">
              {pendingInvites.length}
            </span>
          )}
        </button>
      </div>

      {/* Users table */}
      {activeTab === "users" && (
        <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-left">
              <thead>
                <tr className="border-b border-border-subtle">
                  <th className="px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">Пользователь</th>
                  <th className="px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">Роль</th>
                  <th className="px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider hidden sm:table-cell">Статус</th>
                  <th className="px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider hidden md:table-cell">Последний вход</th>
                  <th className="px-4 py-3 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <tr key={u.id} className="border-b border-border-subtle last:border-0 hover:bg-surface-2/50 transition-colors">
                    <td className="px-4 py-3">
                      <p className="text-sm text-text-primary">{u.name || "—"}</p>
                      <p className="text-[11px] text-text-tertiary">{u.email}</p>
                    </td>
                    <td className="px-4 py-3">
                      <span className={"inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-medium " + roleBadgeClass(u.role)}>
                        <Shield className="h-2.5 w-2.5" />
                        {roleLabel(u.role)}
                      </span>
                    </td>
                    <td className="px-4 py-3 hidden sm:table-cell">
                      <span className={"inline-flex items-center gap-1.5 text-xs " + (u.is_active ? "text-accent-green" : "text-text-tertiary")}>
                        <span className={"w-1.5 h-1.5 rounded-full " + (u.is_active ? "bg-accent-green" : "bg-text-tertiary")} />
                        {u.is_active ? "Активен" : "Заблокирован"}
                      </span>
                    </td>
                    <td className="px-4 py-3 hidden md:table-cell">
                      <span className="text-xs text-text-tertiary">{timeAgo(u.last_login_at)}</span>
                    </td>
                    <td className="px-4 py-3">
                      {u.role !== "owner" && u.id !== currentUser.id && (
                        <div className="relative">
                          <button
                            onClick={(e) => { e.stopPropagation(); setOpenMenu(openMenu === u.id ? null : u.id); }}
                            className="p-1 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-3 transition-colors"
                          >
                            <MoreVertical className="h-4 w-4" />
                          </button>
                          {openMenu === u.id && (
                            <div className="absolute right-0 top-8 w-44 rounded-lg border border-border-subtle bg-surface-1 shadow-lg z-20 py-1">
                              <button onClick={() => openEdit(u)}
                                className="w-full flex items-center gap-2 px-3 py-2 text-xs text-text-secondary hover:text-text-primary hover:bg-surface-2 transition-colors">
                                <Shield className="h-3.5 w-3.5" />Изменить роль
                              </button>
                              <button onClick={() => { setShowResetModal(u.id); setResetPassword(""); setOpenMenu(null); }}
                                className="w-full flex items-center gap-2 px-3 py-2 text-xs text-text-secondary hover:text-text-primary hover:bg-surface-2 transition-colors">
                                <Key className="h-3.5 w-3.5" />Сбросить пароль
                              </button>
                              <div className="border-t border-border-subtle my-1" />
                              <button onClick={() => { setShowDeleteConfirm(u.id); setOpenMenu(null); }}
                                className="w-full flex items-center gap-2 px-3 py-2 text-xs text-accent-red hover:bg-surface-2 transition-colors">
                                <Trash2 className="h-3.5 w-3.5" />Удалить
                              </button>
                            </div>
                          )}
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Invites */}
      {activeTab === "invites" && (
        <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
          {pendingInvites.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 gap-2">
              <Mail className="h-6 w-6 text-text-tertiary" />
              <p className="text-sm text-text-tertiary">Нет активных приглашений</p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left">
                <thead>
                  <tr className="border-b border-border-subtle">
                    <th className="px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">Email</th>
                    <th className="px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">Роль</th>
                    <th className="px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider hidden sm:table-cell">Истекает</th>
                    <th className="px-4 py-3 w-20"></th>
                  </tr>
                </thead>
                <tbody>
                  {pendingInvites.map((inv) => (
                    <tr key={inv.id} className="border-b border-border-subtle last:border-0 hover:bg-surface-2/50 transition-colors">
                      <td className="px-4 py-3">
                        <p className="text-sm text-text-primary">{inv.email}</p>
                        <p className="text-[11px] text-text-tertiary">от {inv.creator_email}</p>
                      </td>
                      <td className="px-4 py-3">
                        <span className={"inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-medium " + roleBadgeClass(inv.role_name)}>
                          <Shield className="h-2.5 w-2.5" />
                          {roleLabel(inv.role_name)}
                        </span>
                      </td>
                      <td className="px-4 py-3 hidden sm:table-cell">
                        <span className="text-xs text-text-tertiary">{timeAgo(inv.expires_at)}</span>
                      </td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-1">
                          <button onClick={() => copyInviteLink(inv.token)}
                            className="p-1.5 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-3 transition-colors" title="Копировать ссылку">
                            <Copy className="h-3.5 w-3.5" />
                          </button>
                          <button onClick={() => handleDeleteInvite(inv.id)}
                            className="p-1.5 rounded-lg text-text-tertiary hover:text-accent-red hover:bg-surface-3 transition-colors" title="Отозвать">
                            <Trash2 className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* ── Create User Modal ── */}
      {showUserModal && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setShowUserModal(false)}>
          <div className="w-full max-w-md rounded-xl border border-border-subtle bg-surface-1 p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-text-primary">Создать пользователя</h3>
              <button onClick={() => setShowUserModal(false)} className="p-1 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-2">
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-text-secondary mb-1.5">Имя</label>
                <input type="text" value={formName} onChange={(e) => setFormName(e.target.value)}
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors" />
              </div>
              <div>
                <label className="block text-xs font-medium text-text-secondary mb-1.5">Email</label>
                <input type="email" value={formEmail} onChange={(e) => setFormEmail(e.target.value)}
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors" />
              </div>
              <div>
                <label className="block text-xs font-medium text-text-secondary mb-1.5">Пароль</label>
                <input type="password" value={formPassword} onChange={(e) => setFormPassword(e.target.value)} placeholder="Минимум 8 символов"
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-text-secondary transition-colors" />
              </div>
              <div>
                <label className="block text-xs font-medium text-text-secondary mb-1.5">Роль</label>
                <select value={formRole} onChange={(e) => setFormRole(e.target.value)}
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors">
                  {ROLES.map((r) => <option key={r.slug} value={r.slug}>{r.label}</option>)}
                </select>
              </div>
              {formError && (
                <div className="rounded-lg bg-accent-red/10 border border-accent-red/20 px-3 py-2">
                  <p className="text-xs text-accent-red">{formError}</p>
                </div>
              )}
              <button onClick={handleCreateUser} disabled={formSaving}
                className="w-full flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-50 transition-colors">
                {formSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <UserPlus className="h-3.5 w-3.5" />}
                Создать
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Invite Modal ── */}
      {showInviteModal && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setShowInviteModal(false)}>
          <div className="w-full max-w-md rounded-xl border border-border-subtle bg-surface-1 p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-text-primary">Пригласить в команду</h3>
              <button onClick={() => setShowInviteModal(false)} className="p-1 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-2">
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-text-secondary mb-1.5">Email</label>
                <input type="email" value={formEmail} onChange={(e) => setFormEmail(e.target.value)}
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors" />
              </div>
              <div>
                <label className="block text-xs font-medium text-text-secondary mb-1.5">Роль</label>
                <select value={formRole} onChange={(e) => setFormRole(e.target.value)}
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors">
                  {ROLES.map((r) => <option key={r.slug} value={r.slug}>{r.label}</option>)}
                </select>
              </div>
              {formError && (
                <div className="rounded-lg bg-accent-red/10 border border-accent-red/20 px-3 py-2">
                  <p className="text-xs text-accent-red">{formError}</p>
                </div>
              )}
              <button onClick={handleInvite} disabled={formSaving}
                className="w-full flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-50 transition-colors">
                {formSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Mail className="h-3.5 w-3.5" />}
                Отправить приглашение
              </button>
              <p className="text-[11px] text-text-tertiary text-center">Ссылка будет скопирована в буфер обмена</p>
            </div>
          </div>
        </div>
      )}

      {/* ── Edit Role Modal ── */}
      {editUser && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setEditUser(null)}>
          <div className="w-full max-w-md rounded-xl border border-border-subtle bg-surface-1 p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-text-primary">Редактировать: {editUser.email}</h3>
              <button onClick={() => setEditUser(null)} className="p-1 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-2">
                <X className="h-4 w-4" />
              </button>
            </div>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-text-secondary mb-1.5">Роль</label>
                <select value={editRole} onChange={(e) => setEditRole(e.target.value)}
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors">
                  {ROLES.map((r) => <option key={r.slug} value={r.slug}>{r.label}</option>)}
                </select>
              </div>
              <div className="flex items-center justify-between py-2">
                <div>
                  <p className="text-sm text-text-primary">Активен</p>
                  <p className="text-[11px] text-text-tertiary mt-0.5">Заблокированный пользователь не сможет войти</p>
                </div>
                <button onClick={() => setEditActive(!editActive)}
                  className={"relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors " + (editActive ? "bg-accent-green" : "bg-surface-3")}>
                  <span className={"inline-block h-3.5 w-3.5 rounded-full bg-white shadow-sm transition-transform " + (editActive ? "translate-x-[18px]" : "translate-x-[3px]")} />
                </button>
              </div>
              {formError && (
                <div className="rounded-lg bg-accent-red/10 border border-accent-red/20 px-3 py-2">
                  <p className="text-xs text-accent-red">{formError}</p>
                </div>
              )}
              <button onClick={handleUpdateUser} disabled={formSaving}
                className="w-full flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-50 transition-colors">
                {formSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
                Сохранить
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Reset Password Modal ── */}
      {showResetModal && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setShowResetModal(null)}>
          <div className="w-full max-w-sm rounded-xl border border-border-subtle bg-surface-1 p-6" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-sm font-semibold text-text-primary mb-4">Сбросить пароль</h3>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-text-secondary mb-1.5">Новый пароль</label>
                <input type="password" value={resetPassword} onChange={(e) => setResetPassword(e.target.value)} placeholder="Минимум 8 символов"
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-text-secondary transition-colors" />
              </div>
              <button onClick={handleResetPassword} disabled={resetSaving || resetPassword.length < 8}
                className="w-full flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-50 transition-colors">
                {resetSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Key className="h-3.5 w-3.5" />}
                Сбросить
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Delete Confirm Modal ── */}
      {showDeleteConfirm && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setShowDeleteConfirm(null)}>
          <div className="w-full max-w-sm rounded-xl border border-border-subtle bg-surface-1 p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-accent-red/10 flex items-center justify-center">
                <AlertTriangle className="h-5 w-5 text-accent-red" />
              </div>
              <div>
                <h3 className="text-sm font-semibold text-text-primary">Удалить пользователя?</h3>
                <p className="text-[11px] text-text-tertiary mt-0.5">Это действие нельзя отменить</p>
              </div>
            </div>
            <div className="flex gap-2">
              <button onClick={() => setShowDeleteConfirm(null)}
                className="flex-1 px-4 py-2 rounded-lg text-xs font-medium border border-border-default text-text-secondary hover:text-text-primary hover:bg-surface-2 transition-colors">
                Отмена
              </button>
              <button onClick={() => handleDelete(showDeleteConfirm)}
                className="flex-1 px-4 py-2 rounded-lg text-xs font-medium bg-accent-red text-white hover:bg-accent-red/90 transition-colors">
                Удалить
              </button>
            </div>
          </div>
        </div>
      )}
    </AppLayout>
  );
}
