"use client";
import { useState, useMemo } from "react";
import AppLayout from "@/components/layout/AppLayout";
import MarketplaceFilter from "@/components/ui/MarketplaceFilter";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import type { NotificationsResponse, NotificationAlert } from "@/types/models";
import {
  Bell, AlertTriangle, AlertCircle, TrendingUp, TrendingDown,
  RotateCcw, Package, RefreshCw,
} from "lucide-react";

const TYPE_CONFIG = {
  stock_critical: { icon: AlertCircle, color: "text-accent-red", bg: "bg-accent-red/10", border: "border-accent-red/20", label: "Критический остаток" },
  stock_low: { icon: AlertTriangle, color: "text-accent-amber", bg: "bg-accent-amber/10", border: "border-accent-amber/20", label: "Низкий остаток" },
  sales_spike: { icon: TrendingUp, color: "text-accent-green", bg: "bg-accent-green/10", border: "border-accent-green/20", label: "Всплеск продаж" },
  sales_drop: { icon: TrendingDown, color: "text-accent-red", bg: "bg-accent-red/10", border: "border-accent-red/20", label: "Падение продаж" },
  high_returns: { icon: RotateCcw, color: "text-accent-red", bg: "bg-accent-red/10", border: "border-accent-red/20", label: "Высокий возврат" },
} as const;

const SEVERITY_STYLES: Record<string, string> = {
  critical: "border-accent-red/30 bg-accent-red/5",
  warning: "border-accent-amber/20 bg-accent-amber/5",
  info: "border-border-subtle bg-surface-1",
};

type FilterType = "all" | "stock" | "sales" | "returns";
type SeverityFilter = "all" | "critical" | "warning";

export default function NotificationsPage() {
  const [filter, setFilter] = useState<FilterType>("all");
  const [severityFilter, setSeverityFilter] = useState<SeverityFilter>("all");
  const [marketplace, setMarketplace] = useState("all");

  const { data, loading, error, refresh, refreshing } = useApiQuery<NotificationsResponse>(
    () => {
      const qs = new URLSearchParams();
      if (marketplace && marketplace !== "all") qs.set("marketplace", marketplace);
      return api.request<NotificationsResponse>("/api/v1/notifications?" + qs.toString());
    },
    [marketplace]
  );

  const toggleSeverity = (s: SeverityFilter) => {
    setSeverityFilter((prev) => (prev === s ? "all" : s));
  };

  const filtered = useMemo(() => {
    if (!data) return [];
    return data.alerts.filter((a: NotificationAlert) => {
      if (filter === "stock" && a.type !== "stock_critical" && a.type !== "stock_low") return false;
      if (filter === "sales" && a.type !== "sales_spike" && a.type !== "sales_drop") return false;
      if (filter === "returns" && a.type !== "high_returns") return false;
      if (severityFilter !== "all" && a.severity !== severityFilter) return false;
      return true;
    });
  }, [data, filter, severityFilter]);

  const typeFilters: { key: FilterType; label: string; icon: typeof Bell; count: number }[] = [
    { key: "all", label: "Все", icon: Bell, count: data?.summary.total || 0 },
    { key: "stock", label: "Остатки", icon: Package, count: data?.alerts.filter((a: NotificationAlert) => a.type.startsWith("stock")).length || 0 },
    { key: "sales", label: "Продажи", icon: TrendingUp, count: data?.alerts.filter((a: NotificationAlert) => a.type.startsWith("sales")).length || 0 },
    { key: "returns", label: "Возвраты", icon: RotateCcw, count: data?.alerts.filter((a: NotificationAlert) => a.type === "high_returns").length || 0 },
  ];

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight flex items-center gap-2">
            <Bell className="h-5 w-5 text-text-secondary" />Уведомления
          </h1>
          <p className="text-sm text-text-tertiary mt-0.5">
            {data ? (
              <>{data.summary.total} алертов{data.summary.critical > 0 && <span className="text-accent-red ml-1">&middot; {data.summary.critical} критических</span>}</>
            ) : "Анализ данных..."}
          </p>
        </div>
        <button onClick={refresh} disabled={refreshing}
          className="rounded-lg border border-border-default bg-surface-1 p-2 text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors disabled:opacity-50">
          <RefreshCw className={"h-4 w-4 " + (refreshing ? "animate-spin" : "")} strokeWidth={1.5} />
        </button>
      </div>

      {data && (
        <div className="grid grid-cols-3 gap-4 mb-6">
          <button
            onClick={() => toggleSeverity("critical")}
            className={
              "rounded-xl border p-4 text-left transition-all cursor-pointer " +
              (severityFilter === "critical"
                ? "border-accent-red bg-accent-red/10 ring-2 ring-accent-red/30"
                : data.summary.critical > 0
                  ? "border-accent-red/30 bg-accent-red/5 hover:border-accent-red/50"
                  : "border-border-subtle bg-surface-1 hover:border-border-default")
            }
          >
            <div className="flex items-center gap-2 text-xs font-medium mb-1">
              <AlertCircle className={"h-3.5 w-3.5 " + (data.summary.critical > 0 ? "text-accent-red" : "text-text-tertiary")} />
              <span className={data.summary.critical > 0 ? "text-accent-red" : "text-text-secondary"}>Критические</span>
            </div>
            <p className={"text-2xl font-semibold tabular-nums " + (data.summary.critical > 0 ? "text-accent-red" : "text-text-primary")}>{data.summary.critical}</p>
          </button>
          <button
            onClick={() => toggleSeverity("warning")}
            className={
              "rounded-xl border p-4 text-left transition-all cursor-pointer " +
              (severityFilter === "warning"
                ? "border-accent-amber bg-accent-amber/10 ring-2 ring-accent-amber/30"
                : data.summary.warning > 0
                  ? "border-accent-amber/20 bg-accent-amber/5 hover:border-accent-amber/40"
                  : "border-border-subtle bg-surface-1 hover:border-border-default")
            }
          >
            <div className="flex items-center gap-2 text-xs font-medium mb-1">
              <AlertTriangle className={"h-3.5 w-3.5 " + (data.summary.warning > 0 ? "text-accent-amber" : "text-text-tertiary")} />
              <span className={data.summary.warning > 0 ? "text-accent-amber" : "text-text-secondary"}>Предупреждения</span>
            </div>
            <p className={"text-2xl font-semibold tabular-nums " + (data.summary.warning > 0 ? "text-accent-amber" : "text-text-primary")}>{data.summary.warning}</p>
          </button>
          <button
            onClick={() => setSeverityFilter("all")}
            className={
              "rounded-xl border p-4 text-left transition-all cursor-pointer " +
              (severityFilter === "all"
                ? "border-accent-green bg-accent-green/10 ring-2 ring-accent-green/30"
                : "border-accent-green/20 bg-accent-green/5 hover:border-accent-green/40")
            }
          >
            <div className="flex items-center gap-2 text-xs font-medium text-accent-green mb-1"><Bell className="h-3.5 w-3.5" />Всего алертов</div>
            <p className="text-2xl font-semibold tabular-nums text-text-primary">{data.summary.total}</p>
          </button>
        </div>
      )}

      <div className="flex flex-wrap items-center gap-3 mb-6">
        <MarketplaceFilter value={marketplace} onChange={setMarketplace} />
        <div className="h-6 w-px bg-border-subtle" />
        <div className="flex items-center gap-2">
          {typeFilters.map((f) => {
            const Icon = f.icon;
            return (
              <button key={f.key} onClick={() => setFilter(f.key)}
                className={"flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all border " +
                  (filter === f.key ? "bg-text-primary text-surface-0 border-text-primary" : "bg-surface-1 text-text-secondary border-border-default hover:border-border-strong hover:text-text-primary")}>
                <Icon className="h-3 w-3" />{f.label}
                {f.count > 0 && (
                  <span className={"ml-0.5 px-1.5 py-0.5 rounded-full text-[10px] font-bold " +
                    (filter === f.key ? "bg-white/20 text-surface-0" : "bg-surface-3 text-text-tertiary")}>{f.count}</span>
                )}
              </button>
            );
          })}
        </div>
        {severityFilter !== "all" && (
          <button
            onClick={() => setSeverityFilter("all")}
            className="text-xs text-text-tertiary hover:text-text-primary transition-colors underline underline-offset-2"
          >
            Сбросить фильтр
          </button>
        )}
      </div>

      {loading ? <Spinner /> : error ? <ErrorState message={error} onRetry={refresh} /> : filtered.length === 0 ? (
        <div className="text-center py-20">
          <Bell className="h-10 w-10 text-text-tertiary mx-auto mb-3 opacity-30" />
          <p className="text-text-tertiary text-sm">Нет уведомлений</p>
          <p className="text-text-tertiary text-xs mt-1">
            {severityFilter !== "all" || filter !== "all" ? "Попробуйте сбросить фильтры" : "Все в порядке!"}
          </p>
        </div>
      ) : (
        <div className="space-y-3 animate-fade-in">
          {filtered.map((alert: NotificationAlert) => {
            const config = TYPE_CONFIG[alert.type];
            const Icon = config.icon;
            return (
              <div key={alert.id} className={"rounded-xl border p-4 transition-colors hover:border-border-default " + SEVERITY_STYLES[alert.severity]}>
                <div className="flex items-start gap-3">
                  <div className={"rounded-lg p-2 " + config.bg}><Icon className={"h-4 w-4 " + config.color} /></div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <span className={"text-xs font-medium px-2 py-0.5 rounded-full " + config.bg + " " + config.color}>{config.label}</span>
                      <span className={"text-[10px] font-bold px-1.5 py-0.5 rounded uppercase " +
                        (alert.severity === "critical" ? "bg-accent-red/20 text-accent-red" : "bg-accent-amber/20 text-accent-amber")}>
                        {alert.severity === "critical" ? "КРИТ" : "ВНИМАНИЕ"}
                      </span>
                    </div>
                    <p className="text-sm text-text-primary font-medium">{alert.title}</p>
                    <p className="text-xs text-text-secondary mt-0.5">{alert.message}</p>
                    {alert.sku && <p className="text-[11px] text-text-tertiary mt-1">SKU: {alert.sku}</p>}
                  </div>
                  {alert.value !== undefined && (
                    <div className="text-right shrink-0">
                      <p className={"text-lg font-bold tabular-nums " + config.color}>
                        {alert.type.startsWith("sales") ? (alert.value > 0 ? "+" : "") + alert.value + "%" : alert.value}
                      </p>
                      <p className="text-[10px] text-text-tertiary">
                        {alert.type.startsWith("stock") ? "дней" : alert.type === "high_returns" ? "% возвратов" : "vs среднее"}
                      </p>
                    </div>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </AppLayout>
  );
}
