"use client";
import { useState, useEffect } from "react";
import AppLayout from "@/components/layout/AppLayout";
import PeriodSelector from "@/components/ui/PeriodSelector";
import CategoryFilter from "@/components/ui/CategoryFilter";
import MarketplaceFilter from "@/components/ui/MarketplaceFilter";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import type { SalesResponse } from "@/types/models";
import { formatMoney, formatDate, mpColors } from "@/lib/utils";
import { ChevronLeft, ChevronRight, Download } from "lucide-react";

export default function SalesPage() {
  const [period, setPeriod] = useState("30d");
  const [category, setCategory] = useState("all");
  const [marketplace, setMarketplace] = useState("all");
  const [page, setPage] = useState(1);
  const [exporting, setExporting] = useState(false);

  useEffect(() => { setPage(1); }, [period, category, marketplace]);

  const { data, loading, error, refresh } = useApiQuery<SalesResponse>(
    () => api.sales({ period, category, marketplace, page }), [period, category, marketplace, page]
  );

  async function handleExport() {
    if (exporting) return;
    setExporting(true);
    try {
      const qs = new URLSearchParams({ period });
      if (category && category !== "all") qs.set("category", category);
      if (marketplace && marketplace !== "all") qs.set("marketplace", marketplace);
      
      const token = localStorage.getItem("yf_token");
      const response = await fetch("/api/v1/sales/export?" + qs.toString(), {
        headers: token ? { Authorization: "Bearer " + token } : {},
        credentials: "include"
      });
      
      if (!response.ok) {
        throw new Error("Ошибка экспорта");
      }
      
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `sales-${period}-${new Date().toISOString().slice(0, 10)}.csv`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (e) {
      console.error("Export error:", e);
      alert("Ошибка при экспорте");
    } finally {
      setExporting(false);
    }
  }

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Продажи</h1>
          <p className="text-sm text-text-tertiary mt-0.5">{data ? data.total + " записей" : "Загрузка..."}</p>
        </div>
        <div className="flex items-center gap-3">
          <button onClick={handleExport} disabled={exporting}
            className="flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-surface-1 border border-border-default text-text-primary hover:bg-surface-2 disabled:opacity-50 transition-colors">
            <Download className={"h-3.5 w-3.5 " + (exporting ? "animate-pulse" : "")} />
            {exporting ? "Экспорт..." : "Экспорт CSV"}
          </button>
          <PeriodSelector value={period} onChange={setPeriod} />
        </div>
      </div>

      <div className="space-y-3 mb-6">
        <MarketplaceFilter value={marketplace} onChange={setMarketplace} />
        <CategoryFilter value={category} onChange={setCategory} />
      </div>

      {loading ? <Spinner /> : error ? <ErrorState message={error} onRetry={refresh} /> : data ? (
        <>
          <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider border-b border-border-subtle">
                    <th className="px-4 pb-3 pt-4 font-medium">Дата</th>
                    <th className="px-4 pb-3 pt-4 font-medium">Товар</th>
                    <th className="px-4 pb-3 pt-4 font-medium">Категория</th>
                    <th className="px-4 pb-3 pt-4 font-medium">Маркетплейс</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Кол-во</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Выручка</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Прибыль</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Комиссия</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Логистика</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {data.items.map((s) => {
                    const mpSlug = (s as any).marketplace_slug || "";
                    const color = mpColors[mpSlug] || mpColors[s.marketplace.toLowerCase().replace(/\s/g, "")] || "#666";
                    return (
                      <tr key={s.id} className="hover:bg-surface-2/50 transition-colors">
                        <td className="px-4 py-3 text-text-secondary tabular-nums whitespace-nowrap">{formatDate(s.date)}</td>
                        <td className="px-4 py-3">
                          <p className="font-medium text-text-primary truncate max-w-[250px]">{s.product_name}</p>
                          <p className="text-xs text-text-tertiary mt-0.5">{s.sku}</p>
                        </td>
                        <td className="px-4 py-3 text-text-secondary text-xs">{s.category}</td>
                        <td className="px-4 py-3">
                          <span className="inline-flex items-center gap-1.5 text-xs text-text-secondary">
                            <span className="h-2 w-2 rounded-full shrink-0" style={{ backgroundColor: color }} />
                            {s.marketplace}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-right tabular-nums">{s.quantity}</td>
                        <td className="px-4 py-3 text-right tabular-nums font-medium">{formatMoney(s.revenue)}</td>
                        <td className="px-4 py-3 text-right tabular-nums font-medium text-accent-green">{formatMoney(s.profit)}</td>
                        <td className="px-4 py-3 text-right tabular-nums text-text-tertiary">{formatMoney(s.commission)}</td>
                        <td className="px-4 py-3 text-right tabular-nums text-text-tertiary">{formatMoney(s.logistics)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>

          {data.pages > 1 && (
            <div className="flex items-center justify-between mt-4 text-sm">
              <span className="text-text-tertiary">Стр. {data.page} из {data.pages} · {data.total} записей</span>
              <div className="flex items-center gap-1">
                <button onClick={() => setPage(Math.max(1, page - 1))} disabled={page === 1}
                  className="p-2 rounded-lg border border-border-default hover:bg-surface-2 disabled:opacity-30 transition-colors">
                  <ChevronLeft className="h-4 w-4" />
                </button>
                {Array.from({ length: Math.min(5, data.pages) }, (_, i) => {
                  const p = page <= 3 ? i + 1 : page + i - 2;
                  if (p < 1 || p > data.pages) return null;
                  return (
                    <button key={p} onClick={() => setPage(p)}
                      className={"px-3 py-1.5 rounded-lg text-xs font-medium transition-colors " +
                        (p === page ? "bg-accent-white text-text-inverse" : "hover:bg-surface-2 text-text-secondary")}>
                      {p}
                    </button>
                  );
                })}
                <button onClick={() => setPage(Math.min(data.pages, page + 1))} disabled={page === data.pages}
                  className="p-2 rounded-lg border border-border-default hover:bg-surface-2 disabled:opacity-30 transition-colors">
                  <ChevronRight className="h-4 w-4" />
                </button>
              </div>
            </div>
          )}
        </>
      ) : null}
    </AppLayout>
  );
}
