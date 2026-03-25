"use client";
import { useState, useEffect } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Spinner from "@/components/ui/Spinner";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import type { SyncCredential, SyncHistoryItem } from "@/types/models";
import { formatDate } from "@/lib/utils";
import {
  RefreshCw, Link2, Unlink, Plus, Eye, EyeOff,
  CheckCircle, XCircle, Clock, Loader2, AlertTriangle,
  ChevronDown, ChevronUp, Zap, History, Settings,
} from "lucide-react";

const MP_META: Record<string, { color: string; icon: string }> = {
  wb: { color: "#A855F6", icon: "WB" },
  ozon: { color: "#2563EB", icon: "OZ" },
  yandex_market: { color: "#FC3F1D", icon: "YM" },
};

const STATUS_STYLES: Record<string, { icon: typeof CheckCircle; color: string; bg: string; label: string }> = {
  completed: { icon: CheckCircle, color: "text-accent-green", bg: "bg-accent-green/10", label: "Завершено" },
  running:   { icon: Loader2,     color: "text-accent-amber", bg: "bg-accent-amber/10", label: "В процессе" },
  pending:   { icon: Clock,       color: "text-text-tertiary", bg: "bg-surface-3",       label: "В очереди" },
  failed:    { icon: XCircle,     color: "text-accent-red",   bg: "bg-accent-red/10",   label: "Ошибка" },
};

export default function SyncPage() {
  const [syncing, setSyncing] = useState<string | null>(null);
  const [showForm, setShowForm] = useState(false);
  const [formData, setFormData] = useState({ marketplace_id: 0, name: "", api_key: "", client_id: "" });
  const [showKey, setShowKey] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [tab, setTab] = useState<"connections" | "history">("connections");
  const [expandedJob, setExpandedJob] = useState<number | null>(null);

  const { data: credentials, loading: loadingCreds, refresh: refreshCreds } = useApiQuery<SyncCredential[]>(
    () => api.syncCredentials(), []
  );
  const { data: history, loading: loadingHist, refresh: refreshHist } = useApiQuery<SyncHistoryItem[]>(
    () => api.syncHistory(), []
  );

  const creds = credentials || [];
  const hist = history || [];
  const loading = loadingCreds || loadingHist;

  // Auto-refresh while any job is running
  const hasRunning = hist.some(j => j.status === "running" || j.status === "pending") || syncing !== null;

  useEffect(() => {
    if (!hasRunning) return;
    const iv = setInterval(() => {
      refreshCreds();
      refreshHist();
    }, 5000);
    return () => clearInterval(iv);
  }, [hasRunning]);

  function reloadAll() { refreshCreds(); refreshHist(); }

  async function handleSync(slug?: string) {
    setSyncing(slug || "all");
    setError("");
    try {
      await api.triggerSync(slug);
      setTimeout(reloadAll, 1500);
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setTimeout(() => setSyncing(null), 2000);
    }
  }

  async function handleSave() {
    setSaving(true); setError("");
    try {
      await api.saveSyncCredential(formData);
      setShowForm(false);
      setFormData({ marketplace_id: 0, name: "", api_key: "", client_id: "" });
      reloadAll();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "Ошибка");
    } finally { setSaving(false); }
  }

  async function handleDisconnect(mpId: number) {
    if (!confirm("Отключить маркетплейс?")) return;
    try { await api.disconnectMarketplace(mpId); reloadAll(); }
    catch (e: unknown) { setError(e instanceof Error ? e.message : "Ошибка"); }
  }

  function fmtDur(sec: number | null) {
    if (!sec) return "-";
    return sec < 60 ? sec + " сек" : Math.floor(sec / 60) + " мин " + (sec % 60) + " сек";
  }

  if (loading) return <AppLayout><Spinner /></AppLayout>;

  const connected = creds.filter((c) => c.status === "connected");
  const available = creds.filter((c) => c.status !== "connected");

  return (
    <AppLayout>
      <div className="animate-fade-in">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">Синхронизация</h1>
            <p className="text-sm text-text-tertiary mt-0.5">{connected.length} из {creds.length} подключено</p>
          </div>
          <button onClick={() => handleSync()} disabled={syncing !== null || connected.length === 0}
            className="flex items-center gap-2 px-4 py-2 rounded-lg bg-white text-black text-sm font-medium hover:bg-white/90 transition-colors disabled:opacity-50">
            <RefreshCw className={"h-4 w-4 " + (syncing === "all" ? "animate-spin" : "")} />
            Синхронизировать всё
          </button>
        </div>

        {error && (
          <div className="mb-4 p-3 rounded-lg bg-accent-red/10 border border-accent-red/20 text-accent-red text-sm flex items-center gap-2">
            <AlertTriangle className="h-4 w-4 flex-shrink-0" />{error}
          </div>
        )}

        <div className="flex gap-1 mb-6 p-1 rounded-lg bg-surface-2 w-fit">
          {([["connections", Settings, "Подключения"], ["history", History, "История"]] as const).map(([key, Icon, label]) => (
            <button key={key} onClick={() => setTab(key)}
              className={"px-4 py-2 rounded-md text-sm font-medium transition-colors flex items-center gap-2 " +
                (tab === key ? "bg-surface-1 text-text-primary shadow-sm" : "text-text-tertiary hover:text-text-secondary")}>
              <Icon className="h-4 w-4" />{label}
            </button>
          ))}
        </div>

        {tab === "connections" && (
          <div className="space-y-4">
            {connected.map(mp => {
              const meta = MP_META[mp.slug] || { color: "#666", icon: mp.slug.toUpperCase().slice(0, 2) };
              const ls = mp.last_sync;
              const ss = ls ? STATUS_STYLES[ls.status] || STATUS_STYLES.pending : null;
              return (
                <div key={mp.id} className="rounded-xl border border-border-subtle bg-surface-1 p-5">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-4">
                      <div className="h-11 w-11 rounded-xl flex items-center justify-center text-white text-sm font-bold" style={{ backgroundColor: meta.color }}>{meta.icon}</div>
                      <div>
                        <div className="flex items-center gap-2">
                          <h3 className="font-medium">{mp.name}</h3>
                          <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium bg-accent-green/10 text-accent-green">
                            <Link2 className="h-3 w-3" />Подключен
                          </span>
                        </div>
                        {mp.credential_name && <p className="text-xs text-text-tertiary mt-0.5">{mp.credential_name}</p>}
                      </div>
                    </div>
                    <div className="flex items-center gap-2">
                      <button onClick={() => handleSync(mp.slug)} disabled={syncing !== null}
                        className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-border-default text-sm text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors disabled:opacity-50">
                        <Zap className={"h-3.5 w-3.5 " + (syncing === mp.slug ? "animate-spin" : "")} />Синхр.
                      </button>
                      <button onClick={() => handleDisconnect(mp.id)} className="p-1.5 rounded-lg text-text-tertiary hover:text-accent-red hover:bg-accent-red/10 transition-colors" title="Отключить">
                        <Unlink className="h-4 w-4" />
                      </button>
                    </div>
                  </div>
                  {ls && ss && (
                    <div className="mt-3 pt-3 border-t border-border-subtle flex items-center justify-between text-sm">
                      <div className="flex items-center gap-4 text-text-tertiary">
                        <span className={"inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs " + ss.bg + " " + ss.color}>
                          <ss.icon className={"h-3 w-3 " + (ls.status === "running" ? "animate-spin" : "")} />{ss.label}
                        </span>
                        <span>{ls.job_type}</span>
                        {ls.records_processed > 0 && <span>{ls.records_processed} записей</span>}
                      </div>
                      <span className="text-xs text-text-tertiary">{ls.completed_at ? formatDate(ls.completed_at) : ls.started_at ? "В процессе..." : ""}</span>
                    </div>
                  )}
                </div>
              );
            })}

            {available.length > 0 && (
              <>
                <h3 className="text-sm font-medium text-text-secondary mt-6 mb-2">Доступные маркетплейсы</h3>
                {available.map(mp => {
                  const meta = MP_META[mp.slug] || { color: "#666", icon: mp.slug.toUpperCase().slice(0, 2) };
                  return (
                    <div key={mp.id} className="rounded-xl border border-border-subtle border-dashed bg-surface-1/50 p-5">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-4">
                          <div className="h-11 w-11 rounded-xl flex items-center justify-center text-white/60 text-sm font-bold border border-border-default" style={{ backgroundColor: meta.color + "33" }}>{meta.icon}</div>
                          <div><h3 className="font-medium text-text-secondary">{mp.name}</h3><p className="text-xs text-text-tertiary">Не подключен</p></div>
                        </div>
                        <button onClick={() => { setFormData({ ...formData, marketplace_id: mp.id, name: "" }); setShowForm(true); }}
                          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg border border-border-default text-sm text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors">
                          <Plus className="h-3.5 w-3.5" />Подключить
                        </button>
                      </div>
                    </div>
                  );
                })}
              </>
            )}

            {showForm && (
              <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" onClick={() => setShowForm(false)}>
                <div className="rounded-2xl border border-border-default bg-surface-1 p-6 w-full max-w-md shadow-2xl" onClick={e => e.stopPropagation()}>
                  <h3 className="text-lg font-semibold mb-4">Подключить маркетплейс</h3>
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm text-text-secondary mb-1.5">Название</label>
                      <input value={formData.name} onChange={e => setFormData({ ...formData, name: e.target.value })} placeholder="Основной аккаунт"
                        className="w-full rounded-lg border border-border-default bg-surface-2 px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-border-strong" />
                    </div>
                    <div>
                      <label className="block text-sm text-text-secondary mb-1.5">API Ключ</label>
                      <div className="relative">
                        <input type={showKey ? "text" : "password"} value={formData.api_key} onChange={e => setFormData({ ...formData, api_key: e.target.value })} placeholder="Вставьте API ключ"
                          className="w-full rounded-lg border border-border-default bg-surface-2 px-3 py-2 pr-10 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-border-strong font-mono" />
                        <button onClick={() => setShowKey(!showKey)} className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-text-tertiary hover:text-text-secondary">
                          {showKey ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                        </button>
                      </div>
                    </div>
                    {creds.find(c => c.id === formData.marketplace_id)?.slug === "ozon" && (
                      <div>
                        <label className="block text-sm text-text-secondary mb-1.5">Client ID</label>
                        <input value={formData.client_id} onChange={e => setFormData({ ...formData, client_id: e.target.value })} placeholder="123456"
                          className="w-full rounded-lg border border-border-default bg-surface-2 px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-border-strong font-mono" />
                      </div>
                    )}
                  </div>
                  <div className="flex gap-3 mt-6">
                    <button onClick={() => setShowForm(false)} className="flex-1 px-4 py-2 rounded-lg border border-border-default text-sm text-text-secondary hover:text-text-primary transition-colors">Отмена</button>
                    <button onClick={handleSave} disabled={saving || !formData.api_key || !formData.name}
                      className="flex-1 px-4 py-2 rounded-lg bg-white text-black text-sm font-medium hover:bg-white/90 transition-colors disabled:opacity-50">
                      {saving ? "Сохраняю..." : "Подключить"}
                    </button>
                  </div>
                </div>
              </div>
            )}
          </div>
        )}

        {tab === "history" && (
          <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
            {hist.length === 0 ? (
              <div className="text-center py-16 text-text-tertiary">
                <History className="h-8 w-8 mx-auto mb-3 opacity-50" /><p>История пуста</p>
              </div>
            ) : (
              <div className="divide-y divide-border-subtle">
                {hist.map(job => {
                  const ss = STATUS_STYLES[job.status] || STATUS_STYLES.pending;
                  const StatusIcon = ss.icon;
                  const isExp = expandedJob === job.id;
                  const meta = MP_META[job.marketplace] || { color: "#666", icon: "??" };
                  return (
                    <div key={job.id}>
                      <div className="flex items-center justify-between px-5 py-3.5 hover:bg-surface-2/50 transition-colors cursor-pointer"
                        onClick={() => setExpandedJob(isExp ? null : job.id)}>
                        <div className="flex items-center gap-3">
                          <div className="h-8 w-8 rounded-lg flex items-center justify-center text-white text-xs font-bold" style={{ backgroundColor: meta.color }}>{meta.icon}</div>
                          <div>
                            <div className="flex items-center gap-2">
                              <span className="text-sm font-medium">{job.marketplace_name}</span>
                              <span className="text-xs text-text-tertiary px-1.5 py-0.5 rounded bg-surface-3">{job.job_type}</span>
                            </div>
                            <p className="text-xs text-text-tertiary">{formatDate(job.created_at)}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-3">
                          <span className={"inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-xs " + ss.bg + " " + ss.color}>
                            <StatusIcon className={"h-3 w-3 " + (job.status === "running" ? "animate-spin" : "")} />{ss.label}
                          </span>
                          {job.records_processed > 0 && <span className="text-xs text-text-secondary tabular-nums">{job.records_processed} зап.</span>}
                          {isExp ? <ChevronUp className="h-4 w-4 text-text-tertiary" /> : <ChevronDown className="h-4 w-4 text-text-tertiary" />}
                        </div>
                      </div>
                      {isExp && (
                        <div className="px-5 pb-4 pt-0">
                          <div className="rounded-lg bg-surface-2 p-4 grid grid-cols-4 gap-4 text-sm">
                            <div><p className="text-xs text-text-tertiary mb-1">Начало</p><p className="font-medium">{job.started_at ? formatDate(job.started_at) : "-"}</p></div>
                            <div><p className="text-xs text-text-tertiary mb-1">Завершение</p><p className="font-medium">{job.completed_at ? formatDate(job.completed_at) : "-"}</p></div>
                            <div><p className="text-xs text-text-tertiary mb-1">Длительность</p><p className="font-medium">{fmtDur(job.duration_sec)}</p></div>
                            <div><p className="text-xs text-text-tertiary mb-1">Обработано</p><p className="font-medium tabular-nums">{job.records_processed} записей</p></div>
                            {job.error_message && (
                              <div className="col-span-4">
                                <p className="text-xs text-text-tertiary mb-1">Ошибка</p>
                                <p className="text-sm text-accent-red bg-accent-red/5 rounded p-2 font-mono">{job.error_message}</p>
                              </div>
                            )}
                          </div>
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}
      </div>
    </AppLayout>
  );
}
