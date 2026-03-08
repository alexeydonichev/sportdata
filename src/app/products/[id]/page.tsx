"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import MetricCard from "@/components/ui/MetricCard";
import PeriodSelector from "@/components/ui/PeriodSelector";
import { api, ProductDetail } from "@/lib/api";
import { formatMoney, formatNumber, formatPercent, mpColors, mpNames, formatDate } from "@/lib/utils";
import {
  ArrowLeft, Package, TrendingUp, BarChart3, Warehouse,
  AlertTriangle, CheckCircle, Clock, RefreshCw,
} from "lucide-react";
import {
  AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer,
  CartesianGrid, BarChart, Bar,
} from "recharts";

const GRADE_STYLES = {
  A: { bg: "bg-accent-green/10", text: "text-accent-green", label: "Лидер" },
  B: { bg: "bg-accent-amber/10", text: "text-accent-amber", label: "Средний" },
  C: { bg: "bg-accent-red/10", text: "text-accent-red", label: "Аутсайдер" },
};

function formatK(v: number) {
  if (v >= 1000000) return (v / 1000000).toFixed(1) + "М";
  if (v >= 1000) return (v / 1000).toFixed(0) + "К";
  return v.toString();
}

function ChartTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-lg border border-border-default bg-surface-2 px-3 py-2 shadow-lg">
      <p className="text-xs text-text-tertiary mb-1">{formatDate(label)}</p>
      {payload.map((p: any) => (
        <p key={p.dataKey} className="text-sm font-medium" style={{ color: p.color }}>
          {p.name}: {p.dataKey === "quantity" || p.dataKey === "orders" ? p.value : formatK(p.value) + " ₽"}
        </p>
      ))}
    </div>
  );
}

export default function ProductDetailPage() {
  const params = useParams();
  const router = useRouter();
  const id = params.id as string;

  const [data, setData] = useState<ProductDetail | null>(null);
  const [period, setPeriod] = useState("90d");
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  async function load(p: string) {
    try {
      const res = await api.productDetail(id, p);
      setData(res);
    } catch (e) {
      console.error(e);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }

  useEffect(() => {
    setLoading(true);
    load(period);
  }, [id, period]);

  function handleRefresh() {
    setRefreshing(true);
    load(period);
  }

  function stockBadge(days: number) {
    if (days <= 7) return { color: "text-accent-red", bg: "bg-accent-red/10", icon: AlertTriangle, label: "Критично" };
    if (days <= 21) return { color: "text-accent-amber", bg: "bg-accent-amber/10", icon: Clock, label: "Мало" };
    return { color: "text-accent-green", bg: "bg-accent-green/10", icon: CheckCircle, label: "Норма" };
  }

  if (loading) {
    return (
      <AppLayout>
        <div className="flex items-center justify-center py-20">
          <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
        </div>
      </AppLayout>
    );
  }

  if (!data) {
    return (
      <AppLayout>
        <div className="text-center py-20">
          <Package className="h-10 w-10 text-text-tertiary mx-auto mb-3" />
          <p className="text-text-tertiary">Товар не найден</p>
          <button onClick={() => router.push("/products")} className="mt-4 text-sm text-text-secondary hover:text-text-primary transition-colors">
            ← К списку товаров
          </button>
        </div>
      </AppLayout>
    );
  }

  const { product, metrics, changes, chart, inventory, abc, by_marketplace } = data;
  const gradeStyle = GRADE_STYLES[abc.grade];
  const stockStatus = stockBadge(inventory.days_of_stock);
  const StockIcon = stockStatus.icon;
  const chartFormatted = chart.map(d => ({ ...d, label: formatDate(d.date) }));

  return (
    <AppLayout>
      <div className="animate-fade-in">
        <div className="flex items-start justify-between mb-6">
          <div className="flex items-start gap-4">
            <button onClick={() => router.push("/products")}
              className="mt-1 p-2 rounded-lg border border-border-default bg-surface-1 text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors">
              <ArrowLeft className="h-4 w-4" />
            </button>
            <div>
              <div className="flex items-center gap-3 mb-1">
                <h1 className="text-xl font-semibold tracking-tight">{product.name}</h1>
                <span className={"inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-xs font-bold " + gradeStyle.bg + " " + gradeStyle.text}>
                  {abc.grade}<span className="font-normal ml-0.5">{gradeStyle.label}</span>
                </span>
              </div>
              <div className="flex items-center gap-3 text-sm text-text-tertiary">
                <span>SKU: {product.sku}</span>
                {product.barcode && <span>· Баркод: {product.barcode}</span>}
                <span>· {product.category}</span>
                <span>· Доля выручки: {abc.revenue_share}%</span>
              </div>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <PeriodSelector value={period} onChange={setPeriod} />
            <button onClick={handleRefresh} disabled={refreshing}
              className="rounded-lg border border-border-default bg-surface-1 p-2 text-text-secondary hover:text-text-primary transition-colors disabled:opacity-50">
              <RefreshCw className={"h-4 w-4 " + (refreshing ? "animate-spin" : "")} strokeWidth={1.5} />
            </button>
          </div>
        </div>

        <div className="grid grid-cols-4 gap-4 mb-6">
          <MetricCard label="Выручка" value={formatMoney(metrics.total_revenue)} change={changes.revenue} />
          <MetricCard label="Прибыль" value={formatMoney(metrics.total_profit)} change={changes.profit} subtitle={"Маржа " + formatPercent(metrics.margin_pct)} />
          <MetricCard label="Продано" value={formatNumber(metrics.total_sold) + " шт"} change={changes.quantity} subtitle={formatNumber(metrics.total_orders) + " заказов"} />
          <MetricCard label="Средняя цена" value={formatMoney(metrics.avg_price)} />
        </div>

        <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6 mb-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-sm font-medium text-text-secondary flex items-center gap-2"><TrendingUp className="h-4 w-4" />Выручка и прибыль</h3>
            <div className="flex items-center gap-4 text-xs text-text-tertiary">
              <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: "#F97316" }} />Выручка</span>
              <span className="flex items-center gap-1.5"><span className="w-2.5 h-2.5 rounded-full bg-accent-green" />Прибыль</span>
            </div>
          </div>
          {chart.length > 0 ? (
            <ResponsiveContainer width="100%" height={240}>
              <AreaChart data={chartFormatted} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
                <defs>
                  <linearGradient id="gRevProd" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#F97316" stopOpacity={0.2} /><stop offset="100%" stopColor="#F97316" stopOpacity={0} /></linearGradient>
                  <linearGradient id="gProfProd" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#22C55E" stopOpacity={0.15} /><stop offset="100%" stopColor="#22C55E" stopOpacity={0} /></linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} dy={8} interval="preserveStartEnd" />
                <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} tickFormatter={formatK} dx={-4} />
                <Tooltip content={<ChartTooltip />} />
                <Area type="monotone" dataKey="revenue" name="Выручка" stroke="#F97316" strokeWidth={2} fill="url(#gRevProd)" dot={false} activeDot={{ r: 4, fill: "#F97316" }} />
                <Area type="monotone" dataKey="profit" name="Прибыль" stroke="#22C55E" strokeWidth={2} fill="url(#gProfProd)" dot={false} activeDot={{ r: 4, fill: "#22C55E" }} />
              </AreaChart>
            </ResponsiveContainer>
          ) : (
            <div className="flex items-center justify-center h-[240px] text-text-tertiary text-sm">Нет данных за период</div>
          )}
        </div>

        <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6 mb-6">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-sm font-medium text-text-secondary flex items-center gap-2"><BarChart3 className="h-4 w-4" />Продажи по дням</h3>
          </div>
          {chart.length > 0 ? (
            <ResponsiveContainer width="100%" height={180}>
              <BarChart data={chartFormatted} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} dy={8} interval="preserveStartEnd" />
                <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} dx={-4} />
                <Tooltip content={<ChartTooltip />} />
                <Bar dataKey="quantity" name="Штуки" fill="#FFFFFF" radius={[4, 4, 0, 0]} barSize={16} opacity={0.8} />
              </BarChart>
            </ResponsiveContainer>
          ) : (
            <div className="flex items-center justify-center h-[180px] text-text-tertiary text-sm">Нет данных</div>
          )}
        </div>

        <div className="grid grid-cols-2 gap-6 mb-6">
          <div className="grid grid-cols-2 gap-4">
            <MetricCard label="Комиссии МП" value={formatMoney(metrics.total_commission)} invertColor />
            <MetricCard label="Логистика" value={formatMoney(metrics.total_logistics)} invertColor />
            <MetricCard label="Возвраты" value={formatNumber(metrics.total_returns) + " шт"} subtitle={formatPercent(metrics.return_pct)} className={metrics.return_pct > 10 ? "border-accent-red/30" : ""} />
            <MetricCard label="Себестоимость" value={formatMoney(product.cost_price)} subtitle={"Цена " + formatMoney(product.price)} />
          </div>
          <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-medium text-text-primary flex items-center gap-2"><Warehouse className="h-4 w-4 text-text-secondary" />Остатки на складах</h3>
              <span className={"inline-flex items-center gap-1 px-2 py-1 rounded-md text-xs font-medium " + stockStatus.bg + " " + stockStatus.color}>
                <StockIcon className="h-3 w-3" />{inventory.days_of_stock >= 999 ? "∞" : inventory.days_of_stock + " дн"} · {stockStatus.label}
              </span>
            </div>
            <div className="grid grid-cols-3 gap-3 mb-4">
              <div className="rounded-lg bg-surface-2 p-3 text-center">
                <p className="text-xs text-text-tertiary mb-1">Всего</p>
                <p className="text-lg font-semibold tabular-nums">{formatNumber(inventory.total_stock)}</p>
              </div>
              <div className="rounded-lg bg-surface-2 p-3 text-center">
                <p className="text-xs text-text-tertiary mb-1">Продажи/день</p>
                <p className="text-lg font-semibold tabular-nums">{inventory.avg_daily_sales}</p>
              </div>
              <div className="rounded-lg bg-surface-2 p-3 text-center">
                <p className="text-xs text-text-tertiary mb-1">Хватит на</p>
                <p className={"text-lg font-semibold tabular-nums " + stockStatus.color}>{inventory.days_of_stock >= 999 ? "∞" : inventory.days_of_stock + " дн"}</p>
              </div>
            </div>
            {inventory.items.length > 0 ? (
              <div className="space-y-2">
                {inventory.items.map((item, i) => (
                  <div key={i} className="flex items-center justify-between py-2 border-t border-border-subtle first:border-0">
                    <span className="text-sm text-text-secondary">{item.warehouse}</span>
                    <span className="text-sm font-medium tabular-nums">{formatNumber(item.stock)} шт</span>
                  </div>
                ))}
              </div>
            ) : (
              <p className="text-sm text-text-tertiary text-center py-4">Нет остатков</p>
            )}
          </div>
        </div>

        {by_marketplace.length > 0 && (
          <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
            <h3 className="text-sm font-medium text-text-primary mb-4">Продажи по маркетплейсам</h3>
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider border-b border-border-subtle">
                  <th className="pb-3 font-medium">Маркетплейс</th>
                  <th className="pb-3 font-medium text-right">Выручка</th>
                  <th className="pb-3 font-medium text-right">Прибыль</th>
                  <th className="pb-3 font-medium text-right">Кол-во</th>
                  <th className="pb-3 font-medium text-right">Доля</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {by_marketplace.map((mp) => {
                  const total = by_marketplace.reduce((s, m) => s + m.revenue, 0);
                  const pct = total > 0 ? (mp.revenue / total) * 100 : 0;
                  return (
                    <tr key={mp.marketplace} className="hover:bg-surface-2/50 transition-colors">
                      <td className="py-3"><div className="flex items-center gap-2"><span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: mpColors[mp.marketplace] || "#666" }} /><span className="font-medium">{mpNames[mp.marketplace] || mp.name}</span></div></td>
                      <td className="py-3 text-right tabular-nums font-medium">{formatMoney(mp.revenue)}</td>
                      <td className="py-3 text-right tabular-nums text-accent-green font-medium">{formatMoney(mp.profit)}</td>
                      <td className="py-3 text-right tabular-nums text-text-secondary">{formatNumber(mp.quantity)}</td>
                      <td className="py-3 text-right"><div className="flex items-center justify-end gap-2"><div className="w-16 h-1.5 bg-surface-3 rounded-full overflow-hidden"><div className="h-full rounded-full" style={{ width: pct + "%", backgroundColor: mpColors[mp.marketplace] || "#666" }} /></div><span className="text-xs text-text-secondary tabular-nums w-10 text-right">{formatPercent(pct)}</span></div></td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </AppLayout>
  );
}
