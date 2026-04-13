"use client";

import { useEffect, useState, useCallback } from "react";
import AppLayout from "@/components/layout/AppLayout";
import { api } from "@/lib/api";
import {
  UserPlus, Shield, Loader2, Check, Trash2,
  MoreVertical, X, Key, AlertTriangle, Building2,
  ShoppingBag, Search, Edit,
} from "lucide-react";

interface Role { id: number; slug: string; name: string; level: number; }
interface Department { id: number; name: string; slug: string; }
interface MarketplaceAccess { id: number; name: string; slug: string; }
interface User {
  id: string; email: string; first_name: string; last_name: string;
  role: string; role_level?: number; role_name?: string; is_active: boolean;
  departments?: Department[] | null; marketplace_access?: MarketplaceAccess[] | null;
}

const roleColors: Record<string, string> = {
  owner: "border-accent-orange bg-accent-orange/10 text-accent-orange",
  director: "border-accent-purple bg-accent-purple/10 text-accent-purple",
  head: "border-accent-blue bg-accent-blue/10 text-accent-blue",
  manager: "border-accent-green bg-accent-green/10 text-accent-green",
};

export default function TeamPage() {
  const [users, setUsers] = useState<User[]>([]);
  const [roles, setRoles] = useState<Role[]>([]);
  const [departments, setDepartments] = useState<Department[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState("");
  const [filterRole, setFilterRole] = useState("");
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [showResetModal, setShowResetModal] = useState<string | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState<string | null>(null);
  const [activeMenu, setActiveMenu] = useState<string | null>(null);
  const [editingUser, setEditingUser] = useState<User | null>(null);
  const [currentUser, setCurrentUser] = useState<{ id: string; role: string } | null>(null);
  const [formData, setFormData] = useState({
    email: "", password: "", first_name: "", last_name: "",
    role: "manager", department_ids: [] as number[], marketplace_ids: [] as number[],
  });
  const [formError, setFormError] = useState("");
  const [formSaving, setFormSaving] = useState(false);
  const [resetPassword, setResetPassword] = useState("");
  const [resetSaving, setResetSaving] = useState(false);

  const loadData = useCallback(async () => {
    try {
      const [usersRes, rolesRes, deptsRes] = await Promise.all([
        api.get("/api/v1/users"), api.get("/api/v1/roles"), api.get("/api/v1/departments"),
      ]);
      setUsers(usersRes.data.data || usersRes.data.users || []);
      setRoles(rolesRes.data.data || rolesRes.data.roles || []);
      setDepartments(deptsRes.data.data || deptsRes.data.departments || []);
    } catch (e) { console.error(e); } finally { setLoading(false); }
  }, []);

  useEffect(() => {
    loadData();
    const stored = localStorage.getItem("yf_user");
    if (stored) setCurrentUser(JSON.parse(stored));
  }, [loadData]);

  const filtered = users.filter((u) => {
    const matchSearch = !search || u.email.toLowerCase().includes(search.toLowerCase()) ||
      `${u.first_name} ${u.last_name}`.toLowerCase().includes(search.toLowerCase());
    return matchSearch && (!filterRole || u.role === filterRole);
  });

  const resetForm = () => {
    setFormData({ email: "", password: "", first_name: "", last_name: "", role: "manager", department_ids: [], marketplace_ids: [] });
    setFormError("");
  };

  const handleCreate = async () => {
    if (!formData.email || !formData.password || !formData.first_name) { setFormError("Заполните обязательные поля"); return; }
    if (formData.password.length < 8) { setFormError("Пароль минимум 8 символов"); return; }
    setFormSaving(true); setFormError("");
    try {
      await api.post("/api/v1/users", formData);
      setShowCreateModal(false); resetForm(); loadData();
    } catch (e: any) { setFormError(e.response?.data?.error || e.message || "Ошибка"); } finally { setFormSaving(false); }
  };

  const openEdit = (u: User) => {
    setEditingUser(u);
    setFormData({
      email: u.email, password: "", first_name: u.first_name, last_name: u.last_name || "", role: u.role,
      department_ids: u.departments?.map((d) => d.id) || [],
      marketplace_ids: u.marketplace_access?.map((m) => m.id) || [],
    });
    setFormError(""); setShowEditModal(true); setActiveMenu(null);
  };

  const handleUpdate = async () => {
    if (!editingUser) return;
    setFormSaving(true); setFormError("");
    try {
      await api.patch(`/api/v1/users/${editingUser.id}`, {
        first_name: formData.first_name, last_name: formData.last_name, role: formData.role,
        department_ids: formData.department_ids, marketplace_ids: formData.marketplace_ids,
      });
      setShowEditModal(false); setEditingUser(null); resetForm(); loadData();
    } catch (e: any) { setFormError(e.response?.data?.error || e.message || "Ошибка"); } finally { setFormSaving(false); }
  };

  const handleResetPwd = async () => {
    if (!showResetModal || resetPassword.length < 8) return;
    setResetSaving(true);
    try {
      await api.post(`/api/v1/users/${showResetModal}/reset-password`, { password: resetPassword });
      setShowResetModal(null); setResetPassword("");
    } catch (e) { console.error(e); } finally { setResetSaving(false); }
  };

  const handleDelete = async (id: string) => {
    try { await api.delete(`/api/v1/users/${id}`); setShowDeleteConfirm(null); loadData(); } catch (e) { console.error(e); }
  };

  const toggleDept = (id: number) => setFormData((p) => ({
    ...p, department_ids: p.department_ids.includes(id) ? p.department_ids.filter((d) => d !== id) : [...p.department_ids, id]
  }));
  const toggleMp = (id: number) => setFormData((p) => ({
    ...p, marketplace_ids: p.marketplace_ids.includes(id) ? p.marketplace_ids.filter((m) => m !== id) : [...p.marketplace_ids, id]
  }));

  const canManageUser = (u: User) => {
    if (currentUser?.id === u.id) return false;
    if (currentUser?.role === "owner" || currentUser?.role === "super_admin") return true;
    if (currentUser?.role === "director" && u.role !== "owner" && u.role !== "director") return true;
    return false;
  };

  const mpSlugs = ['wildberries', 'ozon', 'yandex_market', 'avito', 'detmir'];
  const marketplaces = departments.filter(d => mpSlugs.includes(d.slug));

  return (
    <AppLayout>
      <div className="p-6 max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-lg font-semibold text-text-primary">Команда</h1>
            <p className="text-xs text-text-tertiary mt-0.5">{users.length} пользователей</p>
          </div>
          <button onClick={() => { resetForm(); setShowCreateModal(true); }}
            className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary">
            <UserPlus className="h-3.5 w-3.5" /> Добавить
          </button>
        </div>

        <div className="flex gap-3 mb-4">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-text-tertiary" />
            <input type="text" placeholder="Поиск..." value={search} onChange={(e) => setSearch(e.target.value)}
              className="w-full pl-9 pr-3 py-2 bg-surface-1 border border-border-default rounded-lg text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-text-secondary" />
          </div>
          <select value={filterRole} onChange={(e) => setFilterRole(e.target.value)}
            className="px-3 py-2 bg-surface-1 border border-border-default rounded-lg text-sm text-text-primary focus:outline-none">
            <option value="">Все роли</option>
            {roles.map((r) => <option key={r.slug} value={r.slug}>{r.name}</option>)}
          </select>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-12"><Loader2 className="h-6 w-6 animate-spin text-text-tertiary" /></div>
        ) : (
          <div className="rounded-xl border border-border-subtle bg-surface-1">
            <table className="w-full">
              <thead>
                <tr className="border-b border-border-subtle bg-surface-0">
                  <th className="px-4 py-3 text-left text-[11px] font-medium text-text-tertiary uppercase">Пользователь</th>
                  <th className="px-4 py-3 text-left text-[11px] font-medium text-text-tertiary uppercase">Роль</th>
                  <th className="px-4 py-3 text-left text-[11px] font-medium text-text-tertiary uppercase">Отделы</th>
                  <th className="px-4 py-3 text-left text-[11px] font-medium text-text-tertiary uppercase">Маркетплейсы</th>
                  <th className="px-4 py-3 text-left text-[11px] font-medium text-text-tertiary uppercase">Статус</th>
                  <th className="px-4 py-3 w-10"></th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {filtered.map((u) => (
                  <tr key={u.id} className="hover:bg-surface-0/50">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className="w-8 h-8 rounded-full bg-surface-2 flex items-center justify-center">
                          <span className="text-xs font-medium text-text-secondary">{u.first_name[0]}{u.last_name?.[0] || ""}</span>
                        </div>
                        <div>
                          <p className="text-sm font-medium text-text-primary">{u.first_name} {u.last_name}</p>
                          <p className="text-[11px] text-text-tertiary">{u.email}</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[11px] font-medium border ${roleColors[u.role] || "border-text-tertiary bg-surface-2 text-text-secondary"}`}>
                        <Shield className="h-3 w-3" />{u.role_name || u.role}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      {u.departments && u.departments.length > 0 ? (
                        <div className="flex flex-wrap gap-1">
                          {u.departments.map((d) => <span key={d.id} className="px-1.5 py-0.5 rounded text-[10px] bg-surface-2 text-text-secondary">{d.name}</span>)}
                        </div>
                      ) : <span className="text-[11px] text-text-tertiary">Все</span>}
                    </td>
                    <td className="px-4 py-3">
                      {u.marketplace_access && u.marketplace_access.length > 0 ? (
                        <div className="flex flex-wrap gap-1">
                          {u.marketplace_access.map((m) => <span key={m.id} className="px-1.5 py-0.5 rounded text-[10px] bg-surface-2 text-text-secondary">{m.name}</span>)}
                        </div>
                      ) : <span className="text-[11px] text-text-tertiary">Все</span>}
                    </td>
                    <td className="px-4 py-3">
                      <span className={`inline-flex items-center gap-1 text-[11px] ${u.is_active ? "text-accent-green" : "text-text-tertiary"}`}>
                        <span className={`w-1.5 h-1.5 rounded-full ${u.is_active ? "bg-accent-green" : "bg-text-tertiary"}`} />
                        {u.is_active ? "Активен" : "Неактивен"}
                      </span>
                    </td>
                    <td className="px-4 py-3">
                      {canManageUser(u) && (
                        <div className="relative">
                          <button onClick={() => setActiveMenu(activeMenu === u.id ? null : u.id)}
                            className="p-1.5 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-2">
                            <MoreVertical className="h-4 w-4" />
                          </button>
                          {activeMenu === u.id && (
                            <div className="absolute right-0 top-full mt-1 w-40 rounded-lg border border-border-subtle bg-surface-1 shadow-lg z-50">
                              <button onClick={() => openEdit(u)} className="w-full flex items-center gap-2 px-3 py-2 text-xs text-text-primary hover:bg-surface-2 rounded-t-lg">
                                <Edit className="h-3.5 w-3.5" /> Редактировать
                              </button>
                              <button onClick={() => { setShowResetModal(u.id); setActiveMenu(null); }} className="w-full flex items-center gap-2 px-3 py-2 text-xs text-text-primary hover:bg-surface-2">
                                <Key className="h-3.5 w-3.5" /> Сбросить пароль
                              </button>
                              <button onClick={() => { setShowDeleteConfirm(u.id); setActiveMenu(null); }} className="w-full flex items-center gap-2 px-3 py-2 text-xs text-accent-red hover:bg-surface-2 rounded-b-lg">
                                <Trash2 className="h-3.5 w-3.5" /> Удалить
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
        )}
      </div>

      {showCreateModal && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setShowCreateModal(false)}>
          <div className="w-full max-w-lg rounded-xl border border-border-subtle bg-surface-1 p-6 max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-text-primary">Добавить пользователя</h3>
              <button onClick={() => setShowCreateModal(false)} className="p-1 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-2"><X className="h-4 w-4" /></button>
            </div>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-3">
                <div><label className="block text-xs font-medium text-text-secondary mb-1.5">Имя *</label>
                  <input type="text" value={formData.first_name} onChange={(e) => setFormData({ ...formData, first_name: e.target.value })}
                    className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary" /></div>
                <div><label className="block text-xs font-medium text-text-secondary mb-1.5">Фамилия</label>
                  <input type="text" value={formData.last_name} onChange={(e) => setFormData({ ...formData, last_name: e.target.value })}
                    className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary" /></div>
              </div>
              <div><label className="block text-xs font-medium text-text-secondary mb-1.5">Email *</label>
                <input type="email" value={formData.email} onChange={(e) => setFormData({ ...formData, email: e.target.value })}
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary" /></div>
              <div><label className="block text-xs font-medium text-text-secondary mb-1.5">Пароль *</label>
                <input type="password" value={formData.password} onChange={(e) => setFormData({ ...formData, password: e.target.value })} placeholder="Минимум 8 символов"
                  className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary" /></div>
              <div><label className="block text-xs font-medium text-text-secondary mb-2">Роль *</label>
                <div className="grid grid-cols-2 gap-2">
                  {roles.map((r) => (
                    <button key={r.slug} type="button" onClick={() => setFormData({ ...formData, role: r.slug })}
                      className={`px-3 py-2 rounded-lg text-xs font-medium border text-left ${formData.role === r.slug ? "border-accent-blue bg-accent-blue/10 text-accent-blue" : "border-border-default text-text-secondary hover:border-text-tertiary"}`}>
                      <Shield className="h-3 w-3 inline mr-1.5" />{r.name}
                    </button>
                  ))}
                </div></div>
              <div><label className="block text-xs font-medium text-text-secondary mb-2">Отделы</label>
                <div className="flex flex-wrap gap-2">
                  {departments.map((d) => (
                    <button key={d.id} type="button" onClick={() => toggleDept(d.id)}
                      className={`px-2.5 py-1.5 rounded-lg text-xs font-medium border ${formData.department_ids.includes(d.id) ? "border-accent-green bg-accent-green/10 text-accent-green" : "border-border-default text-text-secondary hover:border-text-tertiary"}`}>
                      <Building2 className="h-3 w-3 inline mr-1" />{d.name}
                    </button>
                  ))}
                </div>
                <p className="text-[11px] text-text-tertiary mt-1">Пусто = все отделы</p></div>
              <div><label className="block text-xs font-medium text-text-secondary mb-2">Маркетплейсы</label>
                <div className="flex flex-wrap gap-2">
                  {marketplaces.map((m) => (
                    <button key={m.id} type="button" onClick={() => toggleMp(m.id)}
                      className={`px-2.5 py-1.5 rounded-lg text-xs font-medium border ${formData.marketplace_ids.includes(m.id) ? "border-accent-purple bg-accent-purple/10 text-accent-purple" : "border-border-default text-text-secondary hover:border-text-tertiary"}`}>
                      <ShoppingBag className="h-3 w-3 inline mr-1" />{m.name}
                    </button>
                  ))}
                </div>
                <p className="text-[11px] text-text-tertiary mt-1">Пусто = все маркетплейсы</p></div>
              {formError && <div className="rounded-lg bg-accent-red/10 border border-accent-red/20 px-3 py-2"><p className="text-xs text-accent-red">{formError}</p></div>}
              <button onClick={handleCreate} disabled={formSaving}
                className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-50">
                {formSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <UserPlus className="h-3.5 w-3.5" />} Создать
              </button>
            </div>
          </div>
        </div>
      )}

      {showEditModal && editingUser && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setShowEditModal(false)}>
          <div className="w-full max-w-lg rounded-xl border border-border-subtle bg-surface-1 p-6 max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold text-text-primary">Редактировать: {editingUser.first_name}</h3>
              <button onClick={() => setShowEditModal(false)} className="p-1 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-2"><X className="h-4 w-4" /></button>
            </div>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-3">
                <div><label className="block text-xs font-medium text-text-secondary mb-1.5">Имя</label>
                  <input type="text" value={formData.first_name} onChange={(e) => setFormData({ ...formData, first_name: e.target.value })}
                    className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary" /></div>
                <div><label className="block text-xs font-medium text-text-secondary mb-1.5">Фамилия</label>
                  <input type="text" value={formData.last_name} onChange={(e) => setFormData({ ...formData, last_name: e.target.value })}
                    className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary" /></div>
              </div>
              <div><label className="block text-xs font-medium text-text-secondary mb-2">Роль</label>
                <div className="grid grid-cols-2 gap-2">
                  {roles.map((r) => (
                    <button key={r.slug} type="button" onClick={() => setFormData({ ...formData, role: r.slug })}
                      className={`px-3 py-2 rounded-lg text-xs font-medium border text-left ${formData.role === r.slug ? "border-accent-blue bg-accent-blue/10 text-accent-blue" : "border-border-default text-text-secondary"}`}>
                      <Shield className="h-3 w-3 inline mr-1.5" />{r.name}
                    </button>
                  ))}
                </div></div>
              <div><label className="block text-xs font-medium text-text-secondary mb-2">Отделы</label>
                <div className="flex flex-wrap gap-2">
                  {departments.map((d) => (
                    <button key={d.id} type="button" onClick={() => toggleDept(d.id)}
                      className={`px-2.5 py-1.5 rounded-lg text-xs font-medium border ${formData.department_ids.includes(d.id) ? "border-accent-green bg-accent-green/10 text-accent-green" : "border-border-default text-text-secondary"}`}>
                      <Building2 className="h-3 w-3 inline mr-1" />{d.name}
                    </button>
                  ))}
                </div></div>
              <div><label className="block text-xs font-medium text-text-secondary mb-2">Маркетплейсы</label>
                <div className="flex flex-wrap gap-2">
                  {marketplaces.map((m) => (
                    <button key={m.id} type="button" onClick={() => toggleMp(m.id)}
                      className={`px-2.5 py-1.5 rounded-lg text-xs font-medium border ${formData.marketplace_ids.includes(m.id) ? "border-accent-purple bg-accent-purple/10 text-accent-purple" : "border-border-default text-text-secondary"}`}>
                      <ShoppingBag className="h-3 w-3 inline mr-1" />{m.name}
                    </button>
                  ))}
                </div></div>
              {formError && <div className="rounded-lg bg-accent-red/10 border border-accent-red/20 px-3 py-2"><p className="text-xs text-accent-red">{formError}</p></div>}
              <button onClick={handleUpdate} disabled={formSaving}
                className="w-full flex items-center justify-center gap-2 px-4 py-2.5 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-50">
                {formSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />} Сохранить
              </button>
            </div>
          </div>
        </div>
      )}

      {showResetModal && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setShowResetModal(null)}>
          <div className="w-full max-w-sm rounded-xl border border-border-subtle bg-surface-1 p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-accent-orange/10 flex items-center justify-center"><Key className="h-5 w-5 text-accent-orange" /></div>
              <h3 className="text-sm font-semibold text-text-primary">Сброс пароля</h3>
            </div>
            <div className="space-y-4">
              <input type="password" value={resetPassword} onChange={(e) => setResetPassword(e.target.value)} placeholder="Новый пароль (мин. 8 символов)"
                className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary" />
              <div className="flex gap-2">
                <button onClick={() => setShowResetModal(null)} className="flex-1 px-4 py-2 rounded-lg text-xs font-medium border border-border-default text-text-secondary hover:bg-surface-2">Отмена</button>
                <button onClick={handleResetPwd} disabled={resetSaving || resetPassword.length < 8}
                  className="flex-1 px-4 py-2 rounded-lg text-xs font-medium bg-accent-orange text-white hover:bg-accent-orange/90 disabled:opacity-50">
                  {resetSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin mx-auto" /> : "Сбросить"}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {showDeleteConfirm && (
        <div className="fixed inset-0 bg-black/40 backdrop-blur-sm z-50 flex items-center justify-center p-4" onClick={() => setShowDeleteConfirm(null)}>
          <div className="w-full max-w-sm rounded-xl border border-border-subtle bg-surface-1 p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center gap-3 mb-4">
              <div className="w-10 h-10 rounded-full bg-accent-red/10 flex items-center justify-center"><AlertTriangle className="h-5 w-5 text-accent-red" /></div>
              <div><h3 className="text-sm font-semibold text-text-primary">Удалить пользователя?</h3>
                <p className="text-xs text-text-tertiary">Действие необратимо</p></div>
            </div>
            <div className="flex gap-2">
              <button onClick={() => setShowDeleteConfirm(null)} className="flex-1 px-4 py-2 rounded-lg text-xs font-medium border border-border-default text-text-secondary hover:bg-surface-2">Отмена</button>
              <button onClick={() => handleDelete(showDeleteConfirm)} className="flex-1 px-4 py-2 rounded-lg text-xs font-medium bg-accent-red text-white hover:bg-accent-red/90">Удалить</button>
            </div>
          </div>
        </div>
      )}
    </AppLayout>
  );
}
