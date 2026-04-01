"use client";

import { useState, useEffect, Suspense } from "react";
import { useSearchParams, useRouter } from "next/navigation";
import { api } from "@/lib/api";
import { Loader2, UserPlus, AlertTriangle } from "lucide-react";

function RegisterForm() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const token = searchParams.get("token") || "";

  const [name, setName] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!token) setError("Отсутствует токен приглашения");
  }, [token]);

  const canSubmit = name.trim().length > 0 && password.length >= 8 && password === confirm && token.length > 0;

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!canSubmit) return;
    setSaving(true);
    setError("");
    try {
      const data = await api.register({ token, password, name: name.trim() });
      api.setToken(data.token);
      localStorage.setItem("yf_user", JSON.stringify(data.user));
      router.push("/");
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ошибка регистрации");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="min-h-screen bg-surface-0 flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-6">
          <h1 className="text-lg font-bold tracking-tight">Your<span className="font-light">Fit</span></h1>
          <p className="text-sm text-text-secondary mt-1">Регистрация по приглашению</p>
        </div>

        <form onSubmit={handleSubmit} className="rounded-xl border border-border-subtle bg-surface-1 p-6 space-y-4">
          <div>
            <label className="block text-xs font-medium text-text-secondary mb-1.5">Имя</label>
            <input type="text" value={name} onChange={(e) => setName(e.target.value)}
              className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none focus:border-text-secondary transition-colors" />
          </div>
          <div>
            <label className="block text-xs font-medium text-text-secondary mb-1.5">Пароль</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="Минимум 8 символов"
              className="w-full bg-surface-0 border border-border-default rounded-lg px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-text-secondary transition-colors" />
          </div>
          <div>
            <label className="block text-xs font-medium text-text-secondary mb-1.5">Подтвердите пароль</label>
            <input type="password" value={confirm} onChange={(e) => setConfirm(e.target.value)}
              className={"w-full bg-surface-0 border rounded-lg px-3 py-2 text-sm text-text-primary focus:outline-none transition-colors " +
                (confirm.length > 0 ? (password === confirm ? "border-accent-green" : "border-accent-red") : "border-border-default focus:border-text-secondary")} />
            {confirm.length > 0 && password !== confirm && (
              <p className="text-[11px] text-accent-red mt-1">Пароли не совпадают</p>
            )}
          </div>

          {error && (
            <div className="rounded-lg bg-accent-red/10 border border-accent-red/20 px-3 py-2 flex items-center gap-2">
              <AlertTriangle className="h-3.5 w-3.5 text-accent-red shrink-0" />
              <p className="text-xs text-accent-red">{error}</p>
            </div>
          )}

          <button type="submit" disabled={saving || !canSubmit}
            className="w-full flex items-center justify-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-text-primary text-surface-0 hover:bg-text-secondary disabled:opacity-40 disabled:cursor-not-allowed transition-colors">
            {saving ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <UserPlus className="h-3.5 w-3.5" />}
            Создать аккаунт
          </button>
        </form>
      </div>
    </div>
  );
}

export default function RegisterPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen bg-surface-0 flex items-center justify-center">
        <Loader2 className="h-5 w-5 animate-spin text-text-tertiary" />
      </div>
    }>
      <RegisterForm />
    </Suspense>
  );
}
