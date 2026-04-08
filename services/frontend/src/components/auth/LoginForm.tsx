"use client";
import { useState } from "react";
import { api } from "@/lib/api";
import { ArrowRight, AlertCircle } from "lucide-react";
import ThemeToggle from "@/components/ui/ThemeToggle";

export default function LoginForm() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      await api.login(email, password);
      window.location.href = "/";
    } catch (err) {
      setError(err instanceof Error ? err.message : "Ошибка авторизации");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface-0 px-4 relative">
      <div className="absolute top-4 right-4"><ThemeToggle /></div>
      <div className="w-full max-w-[360px] animate-fade-in">
        <div className="mb-10 text-center">
          <h1 className="text-2xl font-bold tracking-tight text-text-primary">
            Your<span className="font-light">Fit</span>
          </h1>
          <p className="mt-2 text-sm text-text-tertiary">Аналитика маркетплейсов</p>
        </div>
        <form onSubmit={handleSubmit} className="space-y-4">
          {error && (
            <div className="flex items-center gap-2 rounded-lg border border-accent-red/20 bg-accent-red/5 px-3 py-2.5 text-sm text-accent-red">
              <AlertCircle className="h-4 w-4 shrink-0" />{error}
            </div>
          )}
          <div>
            <label className="block text-xs font-medium text-text-secondary mb-1.5">Email</label>
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-lg border border-border-default bg-surface-1 px-3 py-2.5 text-sm text-text-primary placeholder:text-text-tertiary transition-colors focus:border-border-strong focus:bg-surface-2"
              placeholder="name@company.ru" required autoFocus />
          </div>
          <div>
            <label className="block text-xs font-medium text-text-secondary mb-1.5">Пароль</label>
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-lg border border-border-default bg-surface-1 px-3 py-2.5 text-sm text-text-primary placeholder:text-text-tertiary transition-colors focus:border-border-strong focus:bg-surface-2"
              placeholder="••••••••" required />
          </div>
          <button type="submit" disabled={loading}
            className="w-full flex items-center justify-center gap-2 rounded-lg bg-accent-white text-text-inverse py-2.5 text-sm font-medium transition-all hover:opacity-90 active:scale-[0.98] disabled:opacity-50">
            {loading ? (
              <div className="h-4 w-4 border-2 border-text-inverse/30 border-t-text-inverse rounded-full animate-spin" />
            ) : (<>Войти<ArrowRight className="h-4 w-4" /></>)}
          </button>
        </form>
        <p className="mt-8 text-center text-xs text-text-tertiary">Доступ выдаёт администратор</p>
      </div>
    </div>
  );
}
