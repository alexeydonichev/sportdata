"use client";

import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import Spinner from "@/components/ui/Spinner";
import { api } from "@/lib/api";
import { ArrowLeft } from "lucide-react";
import Link from "next/link";

interface Project { id: number; name: string; }
interface Manager { id: string; first_name: string; last_name: string; email: string; full_name: string; }
interface Marketplace { id: number; name: string; slug: string; is_active: boolean; }

const MONTHS = ["Январь","Февраль","Март","Апрель","Май","Июнь","Июль","Август","Сентябрь","Октябрь","Ноябрь","Декабрь"];

export default function NewRnpPage() {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [dataLoading, setDataLoading] = useState(true);
  const [projects, setProjects] = useState<Project[]>([]);
  const [managers, setManagers] = useState<Manager[]>([]);
  const [marketplaces, setMarketplaces] = useState<Marketplace[]>([]);
  const [error, setError] = useState<string | null>(null);
  const now = new Date();
  const [formData, setFormData] = useState({ project_id: "", manager_id: "", marketplace_id: "", year: now.getFullYear(), month: now.getMonth() + 1 });

  useEffect(() => {
    const loadData = async () => {
      try {
        setDataLoading(true);
        const [projectsRes, managersRes, marketplacesRes] = await Promise.all([
          api.request<{ projects: Project[] }>("/api/v1/projects"),
          api.request<{ managers: Manager[] }>("/api/v1/rnp/managers"),
          api.request<{ marketplaces: Marketplace[] }>("/api/v1/marketplaces"),
        ]);
        console.log("Projects:", projectsRes);
        console.log("Managers:", managersRes);
        console.log("Marketplaces:", marketplacesRes);
        setProjects(projectsRes.projects || []);
        setManagers(managersRes.managers || []);
        setMarketplaces((marketplacesRes.marketplaces || []).filter((m: Marketplace) => m.is_active !== false));
      } catch (err) { 
        console.error("Load error:", err);
        setError("Ошибка загрузки данных"); 
      }
      finally { setDataLoading(false); }
    };
    loadData();
  }, []);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formData.project_id || !formData.manager_id || !formData.marketplace_id) { setError("Заполните все поля"); return; }
    setLoading(true); setError(null);
    try {
      await api.request("/api/v1/rnp/templates", { method: "POST", body: JSON.stringify({ project_id: +formData.project_id, manager_id: formData.manager_id, marketplace_id: +formData.marketplace_id, year: formData.year, month: formData.month }) });
      router.push("/rnp");
    } catch (err: any) { setError(err.message || "Ошибка"); }
    finally { setLoading(false); }
  };

  return (
    <AppLayout>
      <div className="max-w-2xl mx-auto">
        <div className="flex items-center gap-4 mb-6">
          <Link href="/rnp" className="p-2 rounded-lg border border-border-default hover:bg-surface-2"><ArrowLeft className="h-4 w-4" /></Link>
          <div><h1 className="text-xl font-semibold">Новый шаблон РНП</h1><p className="text-sm text-text-tertiary">Создание плана продаж</p></div>
        </div>
        {dataLoading ? <div className="rounded-xl border border-border-subtle bg-surface-1 p-12"><Spinner /></div> : (
          <form onSubmit={handleSubmit} className="rounded-xl border border-border-subtle bg-surface-1 p-6 space-y-5">
            {error && <div className="p-3 rounded-lg bg-red-500/10 border border-red-500/20 text-red-400 text-sm">{error}</div>}
            <div>
              <label className="block text-sm font-medium text-text-secondary mb-2">Проект *</label>
              <select value={formData.project_id} onChange={e => setFormData({...formData, project_id: e.target.value})} className="w-full px-3 py-2.5 rounded-lg border border-border-default bg-surface-2 text-text-primary" required>
                <option value="">Выберите проект</option>
                {projects.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-text-secondary mb-2">Менеджер *</label>
              <select value={formData.manager_id} onChange={e => setFormData({...formData, manager_id: e.target.value})} className="w-full px-3 py-2.5 rounded-lg border border-border-default bg-surface-2 text-text-primary" required>
                <option value="">Выберите менеджера</option>
                {managers.map(m => <option key={m.id} value={m.id}>{m.full_name || `${m.first_name} ${m.last_name}` || m.email}</option>)}
              </select>
            </div>
            <div>
              <label className="block text-sm font-medium text-text-secondary mb-2">Маркетплейс *</label>
              <select value={formData.marketplace_id} onChange={e => setFormData({...formData, marketplace_id: e.target.value})} className="w-full px-3 py-2.5 rounded-lg border border-border-default bg-surface-2 text-text-primary" required>
                <option value="">Выберите маркетплейс</option>
                {marketplaces.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
              </select>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div><label className="block text-sm font-medium text-text-secondary mb-2">Год</label><input type="number" value={formData.year} onChange={e => setFormData({...formData, year: +e.target.value})} className="w-full px-3 py-2.5 rounded-lg border border-border-default bg-surface-2 text-text-primary" min={2024} max={2030} required /></div>
              <div><label className="block text-sm font-medium text-text-secondary mb-2">Месяц</label><select value={formData.month} onChange={e => setFormData({...formData, month: +e.target.value})} className="w-full px-3 py-2.5 rounded-lg border border-border-default bg-surface-2 text-text-primary" required>{MONTHS.map((m,i) => <option key={i+1} value={i+1}>{m}</option>)}</select></div>
            </div>
            <div className="flex gap-3 pt-4 border-t border-border-subtle">
              <button type="submit" disabled={loading} className="flex-1 px-4 py-2.5 rounded-lg text-sm font-medium bg-accent-white text-text-inverse hover:opacity-90 disabled:opacity-50">{loading ? "Создание..." : "Создать шаблон"}</button>
              <Link href="/rnp" className="px-4 py-2.5 rounded-lg text-sm font-medium border border-border-default hover:bg-surface-2">Отмена</Link>
            </div>
          </form>
        )}
      </div>
    </AppLayout>
  );
}
