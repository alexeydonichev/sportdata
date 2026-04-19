"use client";
import { useState } from "react";
import AppLayout from "@/components/layout/AppLayout";
import MetricCard from "@/components/ui/MetricCard";
import PeriodSelector from "@/components/ui/PeriodSelector";
import CategoryFilter from "@/components/ui/CategoryFilter";
import MarketplaceFilter from "@/components/ui/MarketplaceFilter";
import MarketplaceBreakdown from "@/components/dashboard/MarketplaceBreakdown";
import TopProducts from "@/components/dashboard/TopProducts";
import RevenueChart from "@/components/dashboard/RevenueChart";
import ThemeToggle from "@/components/ui/ThemeToggle";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import type { DashboardData, ChartDataPoint } from "@/types/models";
import { formatMoney, formatNumber, formatPercent } from "@/lib/utils";
import { RefreshCw } from "lucide-react";

export default function DashboardPage() {
  const [period, setPeriod] = useState("30d");
  const [category, setCategory] = useState("");
  const [marketplace, setMarketplace] = useState("all");

  const qs = new URLSearchParams({ period });
  if (category && category !== "all") qs.set("category", category);
  if (marketplace && marketplace !== "all") qs.set("marketplace", marketplace);
  const query = qs.toString();

  const { data, loading, error, refresh, refreshing } = useApiQuery<DashboardData>(
    () => api.request("/api/v1/dashboard?" + query), [query]
  );
  const { data: chartData } = useApiQuery<ChartDataPoint[]>(
    () => api.request("/api/v1/dashboard/chart?" + query), [query]
  );

  const c = data?.changes;

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Дашборд</h1>
          <p className="text-sm text-text-tertiary mt-0.5">
            {data ? data.date_from + " — " + data.date_to : "Загрузка..."}
          </p>
        </div>
        <div className="flex items-center gap-3">
          <PeriodSelector value={period} onChange={setPeriod} />
          <ThemeToggle />
          <button onClick={refresh} disabled={refreshing}
            className="rounded-lg border border-border-default bg-surface-1 p-2 text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors disabled:opacity-50">
            <RefreshCw className={"h-4 w-4 " + (refreshing ? "animate-spin" : "")} strokeWidth={1.5} />
          </button>
        </div>
      </div>

      <div className="flex items-center gap-4 mb-6 flex-wrap">
        <MarketplaceFilter value={marketplace} onChange={setMarketplace} />
        <CategoryFilter value={category} onChange={setCategory} />
      </div>

      {loading ? <Spinner /> : error ? <ErrorState message={error} onRetry={refresh} /> : data ? (
        <div className="space-y-6 animate-fade-in">
          <div className="grid grid-cols-4 gap-4">
            <MetricCard label="Выручка" value={formatMoney(data.total_revenue)} change={c?.revenue} subtitle={formatNumber(data.total_orders) + " заказов"} />
            <MetricCard label="Прибыль" value={formatMoney(data.total_profit)} change={c?.profit} subtitle={"Маржа " + formatPercent(data.profit_margin_pct)} />
            <MetricCard label="Продано" value={formatNumber(data.total_quantity)} change={c?.quantity} subtitle={formatNumber(data.total_sku) + " SKU"} />
            <MetricCard label="Средний чек" value={formatMoney(data.avg_order_value)} change={c?.avg_order} />
          </div>
          {chartData && <RevenueChart data={chartData} />}
          <div className="grid grid-cols-4 gap-4">
            <MetricCard label="Комиссии МП" value={formatMoney(data.total_commission)} change={c?.commission} invertColor />
            <MetricCard label="Логистика" value={formatMoney(data.total_logistics)} change={c?.logistics} invertColor />
            <MetricCard label="Штрафы" value={formatMoney(data.total_penalty || 0)} change={c?.penalty} invertColor />
            <MetricCard label="Возвраты" value={formatNumber(data.total_returns || 0)} change={c?.returns} invertColor subtitle={formatNumber(data.total_returns_quantity || 0) + " шт"} />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <MarketplaceBreakdown data={data.by_marketplace} totalRevenue={data.total_revenue} />
            <TopProducts data={data.top_products} />
          </div>
        </div>
      ) : null}
    </AppLayout>
  );
}
