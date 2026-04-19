"use client";
import { useState, useMemo } from "react";
import AppLayout from "@/components/layout/AppLayout";
import CategoryFilter from "@/components/ui/CategoryFilter";
import MarketplaceFilter from "@/components/ui/MarketplaceFilter";
import PeriodSelector from "@/components/ui/PeriodSelector";
import ExportButton from "@/components/ui/ExportButton";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import type { InventoryResponse, InventoryItem } from "@/types/models";
import { formatNumber } from "@/lib/utils";
import { AlertTriangle, CheckCircle, Clock } from "lucide-react";

type StockStatus = "all" | "critical" | "low" | "ok";

function stockBadge(days: number) {
  if (days <= 7)
    return { color: "text-accent-red bg-accent-red/10", icon: AlertTriangle, label: "Критично" };
  if (days <= 21)
    return { color: "text-accent-amber bg-accent-amber/10", icon: Clock, label: "Мало" };
  return { color: "text-accent-green bg-accent-green/10", icon: CheckCircle, label: "Норма" };
}

function getStockStatus(days: number): StockStatus {
  if (days <= 7) return "critical";
  if (days <= 21) return "low";
  return "ok";
}

export default function InventoryPage() {
  const [category, setCategory] = useState("all");
  const [marketplace, setMarketplace] = useState("all");
  const [stockFilter, setStockFilter] = useState<StockStatus>("all");
  const [period, setPeriod] = useState("30d");

  const { data, loading, error, refresh } = useApiQuery<InventoryResponse>(
    () => api.inventory({ category, marketplace, period }),
    [category, marketplace, period]
  );

  const counts = useMemo(() => {
    const items = data?.items || [];
    return {
      critical: items.filter((i: InventoryItem) => i.days_of_stock <= 7).length,
      low: items.filter((i: InventoryItem) => i.days_of_stock > 7 && i.days_of_stock <= 21).length,
      ok: items.filter((i: InventoryItem) => i.days_of_stock > 21).length,
    };
  }, [data]);

  const filteredItems = useMemo(() => {
    const items = data?.items || [];
    if (stockFilter === "all") return items;
    return items.filter((i: InventoryItem) => getStockStatus(i.days_of_stock) === stockFilter);
  }, [data, stockFilter]);

  const toggleFilter = (status: StockStatus) => {
    setStockFilter((prev) => (prev === status ? "all" : status));
  };

  const exportHeaders = [
    "Товар", "SKU", "Категория", "Склад", "Остаток",
    "Продажи/день", "Хватит на (дней)", "Статус",
  ];
  const getExportRows = () =>
    filteredItems.map((item: InventoryItem) => [
      item.name, item.sku, item.category, item.warehouse,
      String(item.stock), String(item.avg_daily_sales.toFixed(1)),
      String(item.days_of_stock >= 999 ? "999+" : item.days_of_stock),
      item.days_of_stock <= 7 ? "Критично" : item.days_of_stock <= 21 ? "Мало" : "Норма",
    ]);

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Остатки на складах</h1>
          <p className="text-sm text-text-tertiary mt-0.5">
            {data
              ? data.summary.products_in_stock + " товаров · " +
                data.summary.warehouses + " складов · " +
                formatNumber(data.summary.total_stock) + " шт"
              : "Загрузка..."}
          </p>
        </div>
        <div className="flex items-center gap-3">
          <ExportButton filename="inventory" headers={exportHeaders} getRows={getExportRows} />
          <PeriodSelector value={period} onChange={setPeriod} />
        </div>
      </div>

      <div className="grid grid-cols-3 gap-4 mb-6">
        <button
          onClick={() => toggleFilter("critical")}
          className={
            "rounded-xl border p-4 text-left transition-all " +
            (stockFilter === "critical"
              ? "border-accent-red bg-accent-red/10 ring-2 ring-accent-red/30"
              : "border-accent-red/20 bg-accent-red/5 hover:border-accent-red/40")
          }
        >
          <div className="flex items-center gap-2 text-accent-red text-xs font-medium mb-1">
            <AlertTriangle className="h-3.5 w-3.5" />
            {"Критично (≤ 7 дней)"}
          </div>
          <p className="text-2xl font-semibold tabular-nums text-accent-red">{counts.critical}</p>
        </button>
        <button
          onClick={() => toggleFilter("low")}
          className={
            "rounded-xl border p-4 text-left transition-all " +
            (stockFilter === "low"
              ? "border-accent-amber bg-accent-amber/10 ring-2 ring-accent-amber/30"
              : "border-accent-amber/20 bg-accent-amber/5 hover:border-accent-amber/40")
          }
        >
          <div className="flex items-center gap-2 text-accent-amber text-xs font-medium mb-1">
            <Clock className="h-3.5 w-3.5" />
            {"Мало (8–21 день)"}
          </div>
          <p className="text-2xl font-semibold tabular-nums text-accent-amber">{counts.low}</p>
        </button>
        <button
          onClick={() => toggleFilter("ok")}
          className={
            "rounded-xl border p-4 text-left transition-all " +
            (stockFilter === "ok"
              ? "border-accent-green bg-accent-green/10 ring-2 ring-accent-green/30"
              : "border-accent-green/20 bg-accent-green/5 hover:border-accent-green/40")
          }
        >
          <div className="flex items-center gap-2 text-accent-green text-xs font-medium mb-1">
            <CheckCircle className="h-3.5 w-3.5" />
            {"Норма (22+ дней)"}
          </div>
          <p className="text-2xl font-semibold tabular-nums text-accent-green">{counts.ok}</p>
        </button>
      </div>

      <div className="flex items-center gap-4 mb-6 flex-wrap">
        <CategoryFilter value={category} onChange={setCategory} />
        <MarketplaceFilter value={marketplace} onChange={setMarketplace} />
        {stockFilter !== "all" && (
          <button
            onClick={() => setStockFilter("all")}
            className="text-xs text-text-tertiary hover:text-text-primary transition-colors underline underline-offset-2"
          >
            Сбросить фильтр статуса
          </button>
        )}
      </div>

      {loading ? (
        <Spinner />
      ) : error ? (
        <ErrorState message={error} onRetry={refresh} />
      ) : data ? (
        <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider border-b border-border-subtle">
                  <th className="px-4 pb-3 pt-4 font-medium">Товар</th>
                  <th className="px-4 pb-3 pt-4 font-medium">Категория</th>
                  <th className="px-4 pb-3 pt-4 font-medium">Склад</th>
                  <th className="px-4 pb-3 pt-4 font-medium text-right">Остаток</th>
                  <th className="px-4 pb-3 pt-4 font-medium text-right">Продажи/день</th>
                  <th className="px-4 pb-3 pt-4 font-medium text-right">Хватит на</th>
                  <th className="px-4 pb-3 pt-4 font-medium text-center">Статус</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {filteredItems.map((item: InventoryItem, i: number) => {
                  const badge = stockBadge(item.days_of_stock);
                  const Icon = badge.icon;
                  return (
                    <tr key={item.product_id + "-" + item.warehouse + "-" + i}
                      className="hover:bg-surface-2/50 transition-colors">
                      <td className="px-4 py-3">
                        <p className="font-medium text-text-primary truncate max-w-[250px]">{item.name}</p>
                        <p className="text-xs text-text-tertiary mt-0.5">{item.sku}</p>
                      </td>
                      <td className="px-4 py-3 text-text-secondary text-xs">{item.category}</td>
                      <td className="px-4 py-3 text-text-secondary text-xs">{item.warehouse}</td>
                      <td className="px-4 py-3 text-right tabular-nums font-medium">{formatNumber(item.stock)}</td>
                      <td className="px-4 py-3 text-right tabular-nums text-text-secondary">
                        {item.avg_daily_sales > 0 ? item.avg_daily_sales.toFixed(1) : "—"}
                      </td>
                      <td className="px-4 py-3 text-right tabular-nums font-medium">
                        {item.days_of_stock >= 999 ? "∞" : item.days_of_stock + " дн"}
                      </td>
                      <td className="px-4 py-3 text-center">
                        <span className={"inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs font-medium " + badge.color}>
                          <Icon className="h-3 w-3" />{badge.label}
                        </span>
                      </td>
                    </tr>
                  );
                })}
                {filteredItems.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-4 py-12 text-center text-text-tertiary text-sm">
                      Нет товаров с выбранным статусом
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}
    </AppLayout>
  );
}
