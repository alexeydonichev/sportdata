"use client";
import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import PeriodSelector from "@/components/ui/PeriodSelector";
import MetricCard from "@/components/ui/MetricCard";
import { api, ProductDetail } from "@/lib/api";
import { formatMoney, formatNumber, formatPercent, formatDate, mpColors, mpNames } from "@/lib/utils";
import { ArrowLeft } from "lucide-react";
import Link from "next/link";
import { AreaChart, Area, BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";

function formatK(v: number) {
  if (Math.abs(v) >= 1000000) return (v / 1000000).toFixed(1) + "M";
  if (Math.abs(v) >= 1000) return (v / 1000).toFixed(0) + "K";
  return v.toString();
}
export default function ProductDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const [data, setData] = useState<ProductDetail | null>(null);
  const [period, setPeriod] = useState("90d");
  const [loading, setLoading] = useState(true);
  const [chartMode, setChartMode] = useState<"revenue" | "quantity">("revenue");

  useEffect(() => {
    setLoading(true);
    api.productDetail(id, period)
      .then(setData).catch(console.error).finally(() => setLoading(false));
  }, [id, period]);

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Link href="/products" className="p-2 rounded-lg hover:bg-surface-2 transition-colors text-text-secondary hover:text-text-primary">
            <ArrowLeft className="h-4 w-4" />
          </Link>
          <div>
            <h1 className="text-xl font-semibold tracking-tight">{data?.product.name || "Загрузка..."}</h1>
            <p className="text-sm text-text-tertiary mt-0.5">{data ? data.product.sku + " · " + data.product.category : ""}</p>
          </div>
        </div>
        <PeriodSelector value={period} onChange={setPeriod} />
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
        </div>
      ) : data ? (
        <div className="space-y-6 animate-fade-in">
          <div className="grid grid-cols-5 gap-4">
            <MetricCard label="Выручка" value={formatMoney(data.metrics.total_revenue)} change={data.changes.revenue} />
            <MetricCard label="Прибыль" value={formatMoney(data.metrics.total_profit)} change={data.changes.profit} subtitle={"Маржа " + formatPercent(data.metrics.margin_pct)} />
            <MetricCard label="Продано" value={formatNumber(data.metrics.total_sold)} change={data.changes.quantity} />
            <MetricCard label="Ср. цена" value={formatMoney(data.metrics.avg_price)} subtitle={"Себест: " + formatMoney(data.product.cost_price)} />
            <MetricCard label="Возвраты" value={formatNumber(data.metrics.total_returns)} subtitle={formatPercent(data.metrics.return_pct)} />
          </div>
          <div className="grid grid-cols-3 gap-6">
            <div className="col-span-2 rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-medium text-text-secondary">Динамика продаж</h3>
                <div className="flex items-center rounded-lg border border-border-default bg-surface-1 p-0.5">
                  <button onClick={() => setChartMode("revenue")}
                    className={"px-3 py-1 text-xs font-medium rounded-md transition-colors " + (chartMode === "revenue" ? "bg-surface-3 text-text-primary" : "text-text-tertiary hover:text-text-secondary")}>
                    Выручка
                  </button>
                  <button onClick={() => setChartMode("quantity")}
                    className={"px-3 py-1 text-xs font-medium rounded-md transition-colors " + (chartMode === "quantity" ? "bg-surface-3 text-text-primary" : "text-text-tertiary hover:text-text-secondary")}>
                    Количество
                  </button>
                </div>
              </div>
              <ResponsiveContainer width="100%" height={280}>
                {chartMode === "revenue" ? (
                  <AreaChart data={data.chart.map(d => ({ ...d, label: formatDate(d.date) }))} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
                    <defs>
                      <linearGradient id="gPdRev" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#F97316" stopOpacity={0.2} /><stop offset="100%" stopColor="#F97316" stopOpacity={0} /></linearGradient>
                      <linearGradient id="gPdProf" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#22C55E" stopOpacity={0.15} /><stop offset="100%" stopColor="#22C55E" stopOpacity={0} /></linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                    <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} interval="preserveStartEnd" />
                    <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} tickFormatter={formatK} />
                    <Tooltip contentStyle={{ backgroundColor: "var(--color-surface-2)", border: "1px solid var(--color-border-default)", borderRadius: "8px", fontSize: "12px" }} />
                    <Area type="monotone" dataKey="revenue" name="Выручка" stroke="#F97316" strokeWidth={2} fill="url(#gPdRev)" dot={false} />
                    <Area type="monotone" dataKey="profit" name="Прибыль" stroke="#22C55E" strokeWidth={2} fill="url(#gPdProf)" dot={false} />
                  </AreaChart>
                ) : (
                  <BarChart data={data.chart.map(d => ({ ...d, label: formatDate(d.date) }))} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
                    <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                    <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} interval="preserveStartEnd" />
                    <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} />
                    <Tooltip contentStyle={{ backgroundColor: "var(--color-surface-2)", border: "1px solid var(--color-border-default)", borderRadius: "8px", fontSize: "12px" }} />
                    <Bar dataKey="quantity" name="Продажи" fill="#6366F1" radius={[3, 3, 0, 0]} />
                    <Bar dataKey="orders" name="Заказы" fill="#F59E0B" radius={[3, 3, 0, 0]} opacity={0.6} />
                  </BarChart>
                )}
              </ResponsiveContainer>
            </div>
            <div className="space-y-4">
              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-4">Юнит-экономика</h3>
                <div className="space-y-3">
                  {(() => {
                    const m = data.metrics;
                    const cp = data.product.cost_price;
                    const commPerUnit = m.total_sold > 0 ? m.total_commission / m.total_sold : 0;
                    const logPerUnit = m.total_sold > 0 ? m.total_logistics / m.total_sold : 0;
                    const profitPerUnit = m.total_sold > 0 ? m.total_profit / m.total_sold : 0;
                    const roi = cp > 0 ? (profitPerUnit / cp * 100) : 0;
                    const commPct = m.total_revenue > 0 ? (m.total_commission / m.total_revenue * 100) : 0;
                    const logPct = m.total_revenue > 0 ? (m.total_logistics / m.total_revenue * 100) : 0;
                    return (
                      <>
                        <div className="flex justify-between"><span className="text-xs text-text-secondary">Ср. цена продажи</span><span className="text-xs font-medium tabular-nums">{formatMoney(m.avg_price)}</span></div>
                        <div className="flex justify-between"><span className="text-xs text-text-secondary">Себестоимость</span><span className="text-xs font-medium tabular-nums">{formatMoney(cp)}</span></div>
                        <div className="flex justify-between"><span className="text-xs text-text-secondary">Комиссия МП</span><span className="text-xs font-medium tabular-nums text-accent-amber">{formatMoney(commPerUnit)} ({commPct.toFixed(1)}%)</span></div>
                        <div className="flex justify-between"><span className="text-xs text-text-secondary">Логистика</span><span className="text-xs font-medium tabular-nums text-accent-amber">{formatMoney(logPerUnit)} ({logPct.toFixed(1)}%)</span></div>
                        <div className="border-t border-border-subtle pt-3 flex justify-between"><span className="text-xs font-medium">Прибыль/шт</span><span className="text-xs font-bold tabular-nums text-accent-green">{formatMoney(profitPerUnit)}</span></div>
                        <div className="flex justify-between"><span className="text-xs font-medium">ROI</span><span className={"text-xs font-bold tabular-nums " + (roi >= 100 ? "text-accent-green" : roi >= 50 ? "text-accent-amber" : "text-accent-red")}>{formatPercent(roi)}</span></div>
                      </>
                    );
                  })()}
                </div>
              </div>

              {data.abc && (
                <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                  <h3 className="text-sm font-medium text-text-secondary mb-3">ABC-грейд</h3>
                  <div className="flex items-center gap-4">
                    <span className={"text-4xl font-bold " + (data.abc.grade === "A" ? "text-accent-green" : data.abc.grade === "B" ? "text-accent-amber" : "text-accent-red")}>{data.abc.grade}</span>
                    <div>
                      <p className="text-sm text-text-secondary">{data.abc.grade === "A" ? "Топ-товар" : data.abc.grade === "B" ? "Средний" : "Аутсайдер"}</p>
                      <p className="text-xs text-text-tertiary">{formatPercent(data.abc.revenue_share)} от выручки</p>
                    </div>
                  </div>
                </div>
              )}
              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-3">Остатки</h3>
                <div className="space-y-3">
                  <div className="flex justify-between"><span className="text-sm text-text-secondary">Всего</span><span className="text-sm font-semibold tabular-nums">{formatNumber(data.inventory.total_stock)} шт</span></div>
                  <div className="flex justify-between"><span className="text-sm text-text-secondary">Продаж/день</span><span className="text-sm font-medium tabular-nums">{data.inventory.avg_daily_sales.toFixed(1)}</span></div>
                  <div className="flex justify-between">
                    <span className="text-sm text-text-secondary">Дней запаса</span>
                    <span className={"text-sm font-semibold tabular-nums " + (data.inventory.days_of_stock < 7 ? "text-accent-red" : data.inventory.days_of_stock < 30 ? "text-accent-amber" : "text-accent-green")}>
                      {data.inventory.days_of_stock > 999 ? "999+" : data.inventory.days_of_stock}
                    </span>
                  </div>
                  {data.inventory.items.length > 0 && (
                    <div className="border-t border-border-subtle pt-3 space-y-2">
                      <p className="text-xs text-text-tertiary uppercase tracking-wider">По складам:</p>
                      {data.inventory.items.map((w) => (
                        <div key={w.warehouse} className="flex justify-between text-xs">
                          <span className="text-text-secondary truncate max-w-[140px]">{w.warehouse}</span>
                          <span className="font-medium tabular-nums">{formatNumber(w.stock)}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>

          {data.by_marketplace && data.by_marketplace.length > 0 && (
            <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-medium text-text-secondary mb-4">По маркетплейсам</h3>
              <div className="grid grid-cols-3 gap-4">
                {data.by_marketplace.map((mp) => (
                  <div key={mp.marketplace} className="rounded-xl border border-border-subtle bg-surface-2 p-4">
                    <div className="flex items-center gap-2 mb-2">
                      <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: mpColors[mp.marketplace] || "#666" }} />
                      <p className="text-sm font-medium">{mp.name}</p>
                    </div>
                    <div className="space-y-1">
                      <div className="flex justify-between text-xs"><span className="text-text-secondary">Выручка</span><span className="font-medium tabular-nums">{formatMoney(mp.revenue)}</span></div>
                      <div className="flex justify-between text-xs"><span className="text-text-secondary">Прибыль</span><span className="font-medium tabular-nums text-accent-green">{formatMoney(mp.profit)}</span></div>
                      <div className="flex justify-between text-xs"><span className="text-text-secondary">Продажи</span><span className="font-medium tabular-nums">{formatNumber(mp.quantity)}</span></div>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      ) : (
        <div className="text-center py-20 text-text-tertiary">Товар не найден</div>
      )}
    </AppLayout>
  );
}