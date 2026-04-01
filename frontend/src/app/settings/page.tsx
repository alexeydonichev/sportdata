"use client";

import { useEffect, useState, useMemo, useRef } from "react";
import AppLayout from "@/components/layout/AppLayout";
import { api, UserInfo } from "@/lib/api";
import { User, Lock, Bell, Save, Check, Loader2, Shield, Eye, EyeOff, Camera } from "lucide-react";
import Image from "next/image";

interface PasswordCheck {
  label: string;
  test: (p: string) => boolean;
}

const PASSWORD_CHECKS: PasswordCheck[] = [
  { label: "Минимум 10 символов", test: (p) => p.length >= 10 },
  { label: "Заглавная буква (A-Z)", test: (p) => /[A-Z]/.test(p) },
  { label: "Строчная буква (a-z)", test: (p) => /[a-z]/.test(p) },
  { label: "Цифра (0-9)", test: (p) => /[0-9]/.test(p) },
  { label: "Спецсимвол (!@#$%...)", test: (p) => /[^a-zA-Z0-9]/.test(p) },
];

function getStrength(password: string): { score: number; label: string; color: string } {
  const passed = PASSWORD_CHECKS.filter((c) => c.test(password)).length;
  if (password.length === 0) return { score: 0, label: "", color: "" };
  if (passed <= 1) return { score: 1, label: "Очень слабый", color: "bg-accent-red" };
  if (passed <= 2) return { score: 2, label: "Слабый", color: "bg-accent-red" };
  if (passed <= 3) return { score: 3, label: "Средний", color: "bg-accent-amber" };
  if (passed <= 4) return { score: 4, label: "Хороший", color: "bg-accent-green/70" };
  return { score: 5, label: "Надёжный", color: "bg-accent-green" };
}

export default function SettingsPage() {
  const [user, setUser] = useState<UserInfo | null>(null);
  const [activeTab, setActiveTab] = useState<"profile" | "security" | "notifications">("profile");

  const [firstName, setFirstName] = useState("");
  const [lastName, setLastName] = useState("");
  const [email, setEmail] = useState("");
  const [avatarUrl, setAvatarUrl] = useState<string | null>(null);
  const [avatarUploading, setAvatarUploading] = useState(false);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileSaved, setProfileSaved] = useState(false);

  const [currentPassword, setCurrentPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showCurrent, setShowCurrent] = useState(false);
  const [showNew, setShowNew] = useState(false);
  const [passwordSaving, setPasswordSaving] = useState(false);
  const [passwordError, setPasswordError] = useState("");
  const [passwordSaved, setPasswordSaved] = useState(false);

  const [emailNotifications, setEmailNotifications] = useState(true);
  const [syncAlerts, setSyncAlerts] = useState(true);
  const [stockAlerts, setStockAlerts] = useState(true);
  const [weeklyReport, setWeeklyReport] = useState(false);

  const strength = useMemo(() => getStrength(newPassword), [newPassword]);
  const allChecksPassed = useMemo(
    () => PASSWORD_CHECKS.every((c) => c.test(newPassword)),
    [newPassword]
  );
  const passwordsMatch = newPassword === confirmPassword && confirmPassword.length > 0;
  const canSubmitPassword = allChecksPassed && passwordsMatch && currentPassword.length > 0;

  useEffect(() => {
    const stored = localStorage.getItem("yf_user");
    if (stored) {
      const u = JSON.parse(stored) as UserInfo & { avatar_url?: string };
      setUser(u);
      setFirstName(u.first_name || "");
      setLastName(u.last_name || "");
      setEmail(u.email || "");
      if (u.avatar_url) setAvatarUrl(u.avatar_url);
    }
  }, []);

  const handleAvatarUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setAvatarUploading(true);
    try {
      const formData = new FormData();
      formData.append("avatar", file);

      const token = api.getToken();
      const res = await fetch("/api/v1/auth/avatar", {
        method: "POST",
        headers: { Authorization: `Bearer ${token}` },
        body: formData,
      });

      if (!res.ok) {
        const err = await res.json();
        alert(err.error || "Ошибка загрузки");
        return;
      }

      const data = await res.json();
      setAvatarUrl(data.avatar_url);

      const updated = { ...user!, avatar_url: data.avatar_url };
      localStorage.setItem("yf_user", JSON.stringify(updated));
      setUser(updated);
    } catch {
      alert("Ошибка загрузки файла");
    } finally {
      setAvatarUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  };

  const handleProfileSave = async () => {
    setProfileSaving(true);
    try {
      await api.request("/api/v1/auth/profile", {
        method: "PUT",
        body: JSON.stringify({ first_name: firstName, last_name: lastName }),
      });
      const updated = { ...user!, first_name: firstName, last_name: lastName };
      localStorage.setItem("yf_user", JSON.stringify(updated));
      setUser(updated);
      setProfileSaved(true);
      setTimeout(() => setProfileSaved(false), 2000);
    } catch {
      // silent
    } finally {
      setProfileSaving(false);
    }
  };

  const handlePasswordChange = async () => {
    setPasswordError("");
    if (!canSubmitPassword) return;
    setPasswordSaving(true);
    try {
      await api.request("/api/v1/auth/password", {
        method: "PUT",
        body: JSON.stringify({ current_password: currentPassword, new_password: newPassword }),
      });
      setCurrentPassword("");
      setNewPassword("");
      setConfirmPassword("");
      setPasswordSaved(true);
      setTimeout(() => setPasswordSaved(false), 3000);
    } catch (e) {
      setPasswordError(e instanceof Error ? e.message : "Ошибка смены пароля");
    } finally {
      setPasswordSaving(false);
    }
  };

  const tabs = [
    { id: "profile" as const, label: "Профиль", icon: User },
    { id: "security" as const, label: "Безопасность", icon: Lock },
    { id: "notifications" as const, label: "Уведомления", icon: Bell },
  ];

  return (
    <AppLayout>
      <div className="mb-6">
        <h1 className="text-xl font-semibold tracking-tight">Настройки</h1>
        <p className="text-sm text-text-secondary mt-1">Управление аккаунтом и параметрами</p>
      </div>

      <div className="flex flex-col sm:flex-row gap-6">
        <div className="w-full sm:w-48 shrink-0">
          <nav className="flex sm:flex-col gap-1">
            {tabs.map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={
                  "flex items-center gap-2.5 rounded-lg px-3 py-2 text-[13px] transition-colors " +
                  (activeTab === tab.id
                    ? "bg-surface-3 text-text-primary font-medium"
                    : "text-text-secondary hover:text-text-primary hover:bg-surface-2")
                }
              >
                <tab.icon className="h-4 w-4" strokeWidth={1.5} />
                {tab.label}
              </button>
            ))}
          </nav>
        </div>

        <div className="flex-1 max-w-xl">
          {/* ── Profile ── */}
          {activeTab === "profile" && (
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-6">
              <div className="flex items-center gap-3 mb-6">
                {/* Avatar with upload */}
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/jpeg,image/png,image/webp,image/gif"
                  className="hidden"
                  onChange={handleAvatarUpload}
                />
                <button
                  onClick={() => fileInputRef.current?.click()}
                  disabled={avatarUploading}
                  className="relative w-12 h-12 rounded-full bg-surface-3 flex items-center justify-center overflow-hidden group cursor-pointer"
                >
                  {avatarUrl ? (
                    <Image
                      src={avatarUrl}
                      alt="Avatar"
                      width={48}
                      height={48}
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <User className="h-5 w-5 text-text-secondary" />
                  )}
                  <div className="absolute inset-0 bg-black/50 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-opacity">
                    {avatarUploading ? (
                      <Loader2 className="h-4 w-4 text-white animate-spin" />
                    ) : (
                      <Camera className="h-4 w-4 text-white" />
                    )}
                  </div>
                </button>
                <div>
                  <p className="text-sm font-medium text-text-primary">{firstName} {lastName}</p>
                  <p className="text-xs text-text-tertiary">{email}</p>
                  {user?.role && (
                    <span className="inline-flex items-center gap-1 mt-1 px-2 py-0.5 rounded-full text-[10px] font-medium bg-accent-green/10 text-accent-green">
                      <Shield className="h-2.5 w-2.5" />
                      {user.role}
                    </span>
                  )}
                </div>
              </div>

              <div className="space-y-4">
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs font-medium text-text-secondary mb-1.5">Имя</label>
                    <input type="text" value={firstName} onChange={(e) => setFirstName(e.target.value)}
                      className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors" />
                  </div>
                  <div>
                    <label className="block text-xs font-medium text-text-secondary mb-1.5">Фамилия</label>
                    <input type="text" value={lastName} onChange={(e) => setLastName(e.target.value)}
                      className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors" />
                  </div>
                </div>
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Email</label>
                  <input type="email" value={email} disabled
                    className="w-full bg-surface-2 border border-border-subtle rounded-lg px-3 py-2 text-sm text-text-tertiary cursor-not-allowed" />
                  <p className="text-[11px] text-text-tertiary mt-1">Email нельзя изменить</p>
                </div>
                <div className="pt-2">
                  <button onClick={handleProfileSave} disabled={profileSaving}
                    className="flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-50 transition-colors">
                    {profileSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : profileSaved ? <Check className="h-3.5 w-3.5" /> : <Save className="h-3.5 w-3.5" />}
                    {profileSaved ? "Сохранено" : "Сохранить"}
                  </button>
                </div>
              </div>
            </div>
          )}

          {/* ── Security ── */}
          {activeTab === "security" && (
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-semibold text-text-primary mb-4">Смена пароля</h3>

              <div className="space-y-4">
                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Текущий пароль</label>
                  <div className="relative">
                    <input
                      type={showCurrent ? "text" : "password"}
                      value={currentPassword}
                      onChange={(e) => setCurrentPassword(e.target.value)}
                      className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors pr-10"
                    />
                    <button type="button" onClick={() => setShowCurrent(!showCurrent)}
                      className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-tertiary hover:text-text-secondary">
                      {showCurrent ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                    </button>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Новый пароль</label>
                  <div className="relative">
                    <input
                      type={showNew ? "text" : "password"}
                      value={newPassword}
                      onChange={(e) => { setNewPassword(e.target.value); setPasswordError(""); }}
                      placeholder="Минимум 10 символов"
                      className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-text-secondary transition-colors pr-10"
                    />
                    <button type="button" onClick={() => setShowNew(!showNew)}
                      className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-tertiary hover:text-text-secondary">
                      {showNew ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                    </button>
                  </div>

                  {newPassword.length > 0 && (
                    <div className="mt-3 space-y-2">
                      <div className="flex items-center gap-2">
                        <div className="flex-1 h-1.5 bg-surface-3 rounded-full overflow-hidden flex gap-0.5">
                          {[1, 2, 3, 4, 5].map((i) => (
                            <div
                              key={i}
                              className={"flex-1 rounded-full transition-colors " + (i <= strength.score ? strength.color : "bg-surface-3")}
                            />
                          ))}
                        </div>
                        <span className={"text-[11px] font-medium " + (
                          strength.score <= 2 ? "text-accent-red" : strength.score <= 3 ? "text-accent-amber" : "text-accent-green"
                        )}>
                          {strength.label}
                        </span>
                      </div>

                      <div className="grid grid-cols-1 gap-1">
                        {PASSWORD_CHECKS.map((check) => {
                          const passed = check.test(newPassword);
                          return (
                            <div key={check.label} className="flex items-center gap-2">
                              <div className={"w-3.5 h-3.5 rounded-full flex items-center justify-center " + (passed ? "bg-accent-green" : "bg-surface-3")}>
                                {passed && <Check className="h-2 w-2 text-white" strokeWidth={3} />}
                              </div>
                              <span className={"text-[11px] " + (passed ? "text-text-secondary" : "text-text-tertiary")}>
                                {check.label}
                              </span>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  )}
                </div>

                <div>
                  <label className="block text-xs font-medium text-text-secondary mb-1.5">Подтвердите пароль</label>
                  <input
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    className={"w-full bg-surface-0 border rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none transition-colors " + (
                      confirmPassword.length > 0
                        ? (passwordsMatch ? "border-accent-green" : "border-accent-red")
                        : "border-border-default focus:border-text-secondary"
                    )}
                  />
                  {confirmPassword.length > 0 && !passwordsMatch && (
                    <p className="text-[11px] text-accent-red mt-1">Пароли не совпадают</p>
                  )}
                  {passwordsMatch && (
                    <p className="text-[11px] text-accent-green mt-1 flex items-center gap-1">
                      <Check className="h-3 w-3" />
                      Пароли совпадают
                    </p>
                  )}
                </div>

                {passwordError && (
                  <div className="rounded-lg bg-accent-red/10 border border-accent-red/20 px-3 py-2">
                    <p className="text-xs text-accent-red">{passwordError}</p>
                  </div>
                )}

                <div className="pt-2">
                  <button
                    onClick={handlePasswordChange}
                    disabled={passwordSaving || !canSubmitPassword}
                    className="flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                  >
                    {passwordSaving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : passwordSaved ? <Check className="h-3.5 w-3.5" /> : <Lock className="h-3.5 w-3.5" />}
                    {passwordSaved ? "Пароль изменён" : "Изменить пароль"}
                  </button>
                </div>
              </div>

              <div className="mt-8 pt-6 border-t border-border-subtle">
                <h3 className="text-sm font-semibold text-text-primary mb-2">Сессии</h3>
                <p className="text-xs text-text-tertiary mb-3">Текущая активная сессия</p>
                <div className="flex items-center gap-3 p-3 rounded-lg bg-surface-0 border border-border-subtle">
                  <div className="w-2 h-2 rounded-full bg-accent-green"></div>
                  <div className="flex-1">
                    <p className="text-xs text-text-primary">Текущий браузер</p>
                    <p className="text-[11px] text-text-tertiary">Активна сейчас</p>
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* ── Notifications ── */}
          {activeTab === "notifications" && (
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-semibold text-text-primary mb-4">Уведомления</h3>
              <div className="space-y-4">
                {[
                  { label: "Email-уведомления", desc: "Получать уведомления на email", value: emailNotifications, setter: setEmailNotifications },
                  { label: "Ошибки синхронизации", desc: "Уведомлять при сбоях синхронизации", value: syncAlerts, setter: setSyncAlerts },
                  { label: "Заканчивающийся товар", desc: "Уведомлять когда остатки ниже минимума", value: stockAlerts, setter: setStockAlerts },
                  { label: "Еженедельный отчёт", desc: "Сводка продаж каждый понедельник", value: weeklyReport, setter: setWeeklyReport },
                ].map((item) => (
                  <div key={item.label} className="flex items-center justify-between py-2">
                    <div>
                      <p className="text-sm text-text-primary">{item.label}</p>
                      <p className="text-[11px] text-text-tertiary mt-0.5">{item.desc}</p>
                    </div>
                    <button
                      onClick={() => item.setter(!item.value)}
                      className={"relative inline-flex h-5 w-9 shrink-0 items-center rounded-full transition-colors " + (item.value ? "bg-accent-green" : "bg-surface-3")}
                    >
                      <span className={"inline-block h-3.5 w-3.5 rounded-full bg-white shadow-sm transition-transform " + (item.value ? "translate-x-[18px]" : "translate-x-[3px]")} />
                    </button>
                  </div>
                ))}
              </div>
              <div className="mt-6 pt-4 border-t border-border-subtle">
                <p className="text-[11px] text-text-tertiary">
                  Настройки уведомлений будут доступны после подключения SMTP-сервера
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </AppLayout>
  );
}
