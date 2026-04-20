"use client";
import { useEffect, useState } from "react";
import AppLayout from "@/components/layout/AppLayout";
import PeriodSelector from "@/components/ui/PeriodSelector";
import ThemeToggle from "@/components/ui/ThemeToggle";
import CategoryFilter from "@/components/ui/CategoryFilter";
import MarketplaceFilter from "@/components/ui/MarketplaceFilter";
import MetricCard from "@/components/ui/MetricCard";
import { formatMoney, formatNumber, formatPercent } from "@/lib/utils";
import { api } from "@/lib/api";
import { Globe, MapPin, Store } from "lucide-react";

interface GeoResponse {
  period: string;
  by_country: { country: string; revenue: number; quantity: number; orders: number; returns: number; return_rate: number }[];
  by_warehouse: { warehouse: string; revenue: number; quantity: number; orders: number; returns: number }[];
  by_pvz: { pvz: string; revenue: number; quantity: number }[];
  summary: { countries: number; warehouses: number; total_revenue: number; top_country: string; top_warehouse: string };
}

function ProgressBar({ value, max, color }: { value: number; max: number; color: string }) {
  const pct = max > 0 ? (value / max) * 100 : 0;
  return (
    <div className="h-1.5 rounded-full bg-surface-3 overflow-hidden">
      <div className={"h-full rounded-full " + color} style={{ width: pct + "%" }} />
    </div>
  );
}

export default function GeographyPage() {
  const [data, setData] = useState<GeoResponse | null>(null);
  const [period, setPeriod] = useState("30d");
  const [category, setCategory] = useState("all");
  const [marketplace, setMarketplace] = useState("all");
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<"country" | "warehouse" | "pvz">("country");

  useEffect(() => {
    setLoading(true);
    const p = new URLSearchParams({ period, category, marketplace });
    api.request<GeoResponse>("/api/v1/analytics/geography?" + p)
      .then(setData).catch(console.error).finally(() => setLoading(false));
  }, [period, category, marketplace]);

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">География продаж</h1>
          <p className="text-sm text-text-tertiary mt-0.5">Продажи по странам, складам и ПВЗ</p>
        </div>
        <div className="flex items-center gap-3">
          <PeriodSelector value={period} onChange={setPeriod} />
          <ThemeToggle />
        </div>
      </div>

      <div className="flex items-center gap-4 mb-6 flex-wrap">
        <MarketplaceFilter value={marketplace} onChange={setMarketplace} />
        <CategoryFilter value={category} onChange={setCategory} />
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
        </div>
      ) : data ? (
        <div className="space-y-6 animate-fade-in">
          <div className="grid grid-cols-4 gap-4">
            <MetricCard label="Общая выручка" value={formatMoney(data.summary.total_revenue)} />
            <MetricCard label="Стран" value={String(data.summary.countries)} subtitle={data.summary.top_country} />
            <MetricCard label="Складов" value={String(data.summary.warehouses)} subtitle={data.summary.top_warehouse} />
            <MetricCard label="ПВЗ" value={String(data.by_pvz.length)} />
          </div>

          <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
            <div className="flex items-center gap-1 mb-6 rounded-lg border border-border-default bg-surface-1 p-0.5 w-fit">
              {([["country", "Страны", Globe], ["warehouse", "Склады", MapPin], ["pvz", "ПВЗ", Store]] as const).map(([key, label, Icon]) => (
                <button key={key} onClick={() => setTab(key as typeof tab)}
                  className={"flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-md transition-colors " +
                    (tab === key ? "bg-surface-3 text-text-primary" : "text-text-tertiary hover:text-text-secondary")}>
                  <Icon className="h-3.5 w-3.5" /> {label}
                </button>
              ))}
            </div>

            {tab === "country" && (
              <div className="space-y-3">
                {data.by_country.map((c, i) => {
                  const maxRev = data.by_country[0]?.revenue || 1;
                  return (
                    <div key={c.country} className="rounded-xl border border-border-subtle bg-surface-2 p-4">
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-text-tertiary w-5">{i + 1}</span>
                          <span className="text-sm font-medium">{c.country}</span>
                        </div>
                        <span className="text-sm font-semibold tabular-nums">{formatMoney(c.revenue)}</span>
                      </div>
                      <ProgressBar value={c.revenue} max={maxRev} color="bg-accent-blue" />
                      <div className="flex items-center gap-4 mt-2 text-xs text-text-tertiary">
                        <span>{formatNumber(c.quantity)} шт</span>
                        <span>{formatNumber(c.orders)} заказов</span>
                        <span>{formatNumber(c.returns)} возвратов</span>
                        {c.return_rate > 0 && <span className="text-accent-amber">{formatPercent(c.return_rate)} возврат</span>}
                      </div>
                    </div>
                  );
                })}
                {data.by_country.length === 0 && <p className="text-sm text-text-tertiary text-center py-8">Нет данных по странам. Запустите синхронизацию reportDetail.</p>}
              </div>
            )}

            {tab === "warehouse" && (
              <div className="space-y-3">
                {data.by_warehouse.map((w, i) => {
                  const maxRev = data.by_warehouse[0]?.revenue || 1;
                  return (
                    <div key={w.warehouse} className="rounded-xl border border-border-subtle bg-surface-2 p-4">
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-text-tertiary w-5">{i + 1}</span>
                          <span className="text-sm font-medium truncate max-w-[300px]">{w.warehouse}</span>
                        </div>
                        <span className="text-sm font-semibold tabular-nums">{formatMoney(w.revenue)}</span>
                      </div>
                      <ProgressBar value={w.revenue} max={maxRev} color="bg-accent-green" />
                      <div className="flex items-center gap-4 mt-2 text-xs text-text-tertiary">
                        <span>{formatNumber(w.quantity)} шт</span>
                        <span>{formatNumber(w.orders)} заказов</span>
                      </div>
                    </div>
                  );
                })}
                {data.by_warehouse.length === 0 && <p className="text-sm text-text-tertiary text-center py-8">Нет данных. Запустите синхронизацию reportDetail.</p>}
              </div>
            )}

            {tab === "pvz" && (
              <div className="space-y-3">
                {data.by_pvz.map((p, i) => {
                  const maxRev = data.by_pvz[0]?.revenue || 1;
                  return (
                    <div key={p.pvz} className="rounded-xl border border-border-subtle bg-surface-2 p-4">
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <span className="text-xs text-text-tertiary w-5">{i + 1}</span>
                          <span className="text-sm font-medium truncate max-w-[300px]">{p.pvz}</span>
                        </div>
                        <span className="text-sm font-semibold tabular-nums">{formatMoney(p.revenue)}</span>
                      </div>
                      <ProgressBar value={p.revenue} max={maxRev} color="bg-accent-purple" />
                      <div className="flex items-center gap-4 mt-2 text-xs text-text-tertiary">
                        <span>{formatNumber(p.quantity)} шт</span>
                      </div>
                    </div>
                  );
                })}
                {data.by_pvz.length === 0 && <p className="text-sm text-text-tertiary text-center py-8">Нет данных по ПВЗ. Запустите синхронизацию reportDetail.</p>}
              </div>
            )}
          </div>
        </div>
      ) : null}
    </AppLayout>
  );
}
