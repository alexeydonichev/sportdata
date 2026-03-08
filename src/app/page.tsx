"use client";
import { useEffect, useState } from "react";
import AppLayout from "@/components/layout/AppLayout";
import MetricCard from "@/components/ui/MetricCard";
import PeriodSelector from "@/components/ui/PeriodSelector";
import CategoryFilter from "@/components/ui/CategoryFilter";
import MarketplaceBreakdown from "@/components/dashboard/MarketplaceBreakdown";
import TopProducts from "@/components/dashboard/TopProducts";
import RevenueChart from "@/components/dashboard/RevenueChart";
import ThemeToggle from "@/components/ui/ThemeToggle";
import { api, DashboardData, ChartDataPoint } from "@/lib/api";
import { formatMoney, formatNumber, formatPercent } from "@/lib/utils";
import { RefreshCw } from "lucide-react";

export default function DashboardPage() {
  const [data, setData] = useState<DashboardData | null>(null);
  const [chartData, setChartData] = useState<ChartDataPoint[]>([]);
  const [period, setPeriod] = useState("7d");
  const [category, setCategory] = useState("");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  async function loadData(p: string, cat: string) {
    try {
      const qs = new URLSearchParams({ period: p });
      if (cat) qs.set("category", cat);
      const [d, chart] = await Promise.all([
        api.request<DashboardData>("/api/v1/dashboard?" + qs.toString()),
        api.request<ChartDataPoint[]>("/api/v1/dashboard/chart?" + qs.toString()),
      ]);
      setData(d);
      setChartData(chart);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useEffect(() => {
    setLoading(true);
    loadData(period, category);
  }, [period, category]);

  function handleRefresh() {
    setRefreshing(true);
    loadData(period, category);
  }

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
          <CategoryFilter value={category} onChange={setCategory} />
          <PeriodSelector value={period} onChange={setPeriod} />
          <ThemeToggle />
          <button onClick={handleRefresh} disabled={refreshing}
            className="rounded-lg border border-border-default bg-surface-1 p-2 text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors disabled:opacity-50">
            <RefreshCw className={"h-4 w-4 " + (refreshing ? "animate-spin" : "")} strokeWidth={1.5} />
          </button>
        </div>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
        </div>
      ) : data ? (
        <div className="space-y-6 animate-fade-in">
          <div className="grid grid-cols-4 gap-4">
            <MetricCard label="Выручка" value={formatMoney(data.total_revenue)} change={c?.revenue} subtitle={formatNumber(data.total_orders) + " заказов"} />
            <MetricCard label="Прибыль" value={formatMoney(data.total_profit)} change={c?.profit} subtitle={"Маржа " + formatPercent(data.profit_margin_pct)} />
            <MetricCard label="Продано" value={formatNumber(data.total_quantity)} change={c?.quantity} subtitle={formatNumber(data.total_sku) + " SKU"} />
            <MetricCard label="Средний чек" value={formatMoney(data.avg_order_value)} change={c?.avg_order} />
          </div>
          <RevenueChart data={chartData} />
          <div className="grid grid-cols-2 gap-4">
            <MetricCard label="Комиссии МП" value={formatMoney(data.total_commission)} change={c?.commission} invertColor />
            <MetricCard label="Логистика" value={formatMoney(data.total_logistics)} change={c?.logistics} invertColor />
          </div>
          <div className="grid grid-cols-2 gap-4">
            <MarketplaceBreakdown data={data.by_marketplace} totalRevenue={data.total_revenue} />
            <TopProducts data={data.top_products} />
          </div>
        </div>
      ) : (
        <div className="text-center py-20 text-text-tertiary">Не удалось загрузить данные</div>
      )}
    </AppLayout>
  );
}
