"use client";
import { useEffect, useState } from "react";
import AppLayout from "@/components/layout/AppLayout";
import PeriodSelector from "@/components/ui/PeriodSelector";
import CategoryFilter from "@/components/ui/CategoryFilter";
import MarketplaceFilter from "@/components/ui/MarketplaceFilter";
import ExportButton from "@/components/ui/ExportButton";
import { formatMoney, formatNumber, formatPercent, formatDate } from "@/lib/utils";
import { api } from "@/lib/api";
import { TrendingUp, TrendingDown, Minus } from "lucide-react";
import {
  AreaChart, Area, XAxis, YAxis, Tooltip,
  ResponsiveContainer, CartesianGrid,
} from "recharts";

interface PnlData {
  period: string;
  pnl: {
    gross_revenue: number; returns_amount: number; net_revenue: number;
    cogs: number; gross_profit: number; commission: number; logistics: number;
    operating_expenses: number; operating_profit: number; advertising: number;
    for_pay: number;
    net_profit: number;
  };
  margins: {
    gross_margin: number; operating_margin: number;
    net_margin: number; return_rate: number;
  };
  metrics: {
    units_sold: number; units_returned: number; active_skus: number;
    avg_check: number; avg_profit_per_unit: number;
  };
  warnings: string[];
  changes: Record<string, number>;
  daily: {
    date: string; revenue: number; returns: number;
    commission: number; logistics: number; profit: number;
  }[];
  by_category: {
    category: string; slug: string; revenue: number;
    commission: number; logistics: number; cogs: number;
    profit: number; units: number;
  }[];
}

function Change({ value, invert }: { value?: number; invert?: boolean }) {
  if (value === undefined || value === null) return null;
  const positive = invert ? value < 0 : value > 0;
  const color =
    value === 0
      ? "text-text-tertiary"
      : positive
      ? "text-accent-green"
      : "text-accent-red";
  return (
    <span
      className={
        "inline-flex items-center gap-0.5 text-xs font-medium tabular-nums " + color
      }
    >
      {value > 0 ? (
        <TrendingUp className="h-3 w-3" />
      ) : value < 0 ? (
        <TrendingDown className="h-3 w-3" />
      ) : (
        <Minus className="h-3 w-3" />
      )}
      {value > 0 ? "+" : ""}
      {value.toFixed(1)}%
    </span>
  );
}

function PnlRow({
  label, value, change, indent, bold, invert, border,
}: {
  label: string; value: number; change?: number;
  indent?: boolean; bold?: boolean; invert?: boolean; border?: boolean;
}) {
  return (
    <div
      className={
        "flex items-center justify-between py-3 " +
        (border
          ? "border-t border-border-default"
          : "border-t border-border-subtle") +
        (indent ? " pl-6" : "")
      }
    >
      <span
        className={
          "text-sm " +
          (bold ? "font-semibold text-text-primary" : "text-text-secondary")
        }
      >
        {label}
      </span>
      <div className="flex items-center gap-4">
        <Change value={change} invert={invert} />
        <span
          className={
            "tabular-nums text-sm min-w-[100px] text-right " +
            (bold ? "font-semibold" : "font-medium") +
            (value < 0 ? " text-accent-red" : "")
          }
        >
          {formatMoney(value)}
        </span>
      </div>
    </div>
  );
}

function formatK(v: number) {
  if (Math.abs(v) >= 1000000) return (v / 1000000).toFixed(1) + "M";
  if (Math.abs(v) >= 1000) return (v / 1000).toFixed(0) + "K";
  return v.toString();
}

export default function PnlPage() {
  const [data, setData] = useState<PnlData | null>(null);
  const [period, setPeriod] = useState("30d");
  const [category, setCategory] = useState("");
  const [marketplace, setMarketplace] = useState("all");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    const qs = new URLSearchParams({ period });
    if (category && category !== "all") qs.set("category", category);
    if (marketplace && marketplace !== "all") qs.set("marketplace", marketplace);
    api
      .request<PnlData>("/api/v1/analytics/pnl?" + qs.toString())
      .then(setData)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [period, category, marketplace]);

  const exportHeaders = [
    "Показатель", "Значение", "Изменение %",
  ];
  const getExportRows = () => {
    if (!data) return [];
    const p = data.pnl;
    const c = data.changes;
    return [
      ["Валовая выручка", String(p.gross_revenue), String(c.gross_revenue ?? "")],
      ["Возвраты", String(-p.returns_amount), ""],
      ["Чистая выручка", String(p.net_revenue), String(c.net_revenue ?? "")],
      ["Себестоимость", String(-p.cogs), String(c.cogs ?? "")],
      ["Валовая прибыль", String(p.gross_profit), String(c.gross_profit ?? "")],
      ["Комиссия МП", String(-p.commission), String(c.commission ?? "")],
      ["Логистика", String(-p.logistics), String(c.logistics ?? "")],
      ["Операционная прибыль", String(p.operating_profit), String(c.operating_profit ?? "")],
      ["Чистая прибыль", String(p.net_profit), String(c.net_profit ?? "")],
    ];
  };

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">P&L Отчёт</h1>
          <p className="text-sm text-text-tertiary mt-0.5">Прибыли и убытки</p>
        </div>
        <div className="flex items-center gap-3">
          <ExportButton filename="pnl" headers={exportHeaders} getRows={getExportRows} />
          <PeriodSelector value={period} onChange={setPeriod} />
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
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                Валовая маржа
              </p>
              <p className="mt-2 text-2xl font-semibold tabular-nums">
                {formatPercent(data.margins.gross_margin)}
              </p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                Операц. маржа
              </p>
              <p className="mt-2 text-2xl font-semibold tabular-nums">
                {formatPercent(data.margins.operating_margin)}
              </p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                Чистая маржа
              </p>
              <p className="mt-2 text-2xl font-semibold tabular-nums">
                {formatPercent(data.margins.net_margin)}
              </p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">
                % Возвратов
              </p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-accent-amber">
                {formatPercent(data.margins.return_rate)}
              </p>
            </div>
          </div>

          {data.warnings && data.warnings.length > 0 && (
            <div className="space-y-2">
              {data.warnings.map((w, i) => (
                <div key={i} className="flex items-start gap-3 rounded-xl border border-accent-amber/30 bg-accent-amber/5 px-4 py-3">
                  <svg className="h-5 w-5 text-accent-amber shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" d="M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z" />
                  </svg>
                  <p className="text-sm text-text-secondary">{w}</p>
                </div>
              ))}
            </div>
          )}

          <div className="grid grid-cols-3 gap-6">
            <div className="col-span-2 rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-medium text-text-secondary mb-2">
                Отчёт о прибылях и убытках
              </h3>
              <div>
                <PnlRow label="Валовая выручка" value={data.pnl.gross_revenue} change={data.changes.gross_revenue} bold />
                <PnlRow label="Возвраты" value={-data.pnl.returns_amount} indent />
                <PnlRow label="Чистая выручка" value={data.pnl.net_revenue} change={data.changes.net_revenue} bold border />
                <PnlRow label="Себестоимость (COGS)" value={-data.pnl.cogs} change={data.changes.cogs} invert indent />
                <PnlRow label="Валовая прибыль" value={data.pnl.gross_profit} change={data.changes.gross_profit} bold border />
                <PnlRow label="Комиссия маркетплейса" value={-data.pnl.commission} change={data.changes.commission} invert indent />
                <PnlRow label="Логистика" value={-data.pnl.logistics} change={data.changes.logistics} invert indent />
                <PnlRow label="Операционная прибыль" value={data.pnl.operating_profit} change={data.changes.operating_profit} bold border />
                <PnlRow label="К выплате от МП" value={data.pnl.for_pay || 0} indent />
                <div className="mt-2 pt-3 border-t-2 border-border-strong">
                  <PnlRow label="ЧИСТАЯ ПРИБЫЛЬ" value={data.pnl.net_profit} change={data.changes.net_profit} bold />
                </div>
              </div>
            </div>

            <div className="space-y-4">
              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-4">Ключевые метрики</h3>
                <div className="space-y-4">
                  <div className="flex justify-between"><span className="text-sm text-text-secondary">Продано единиц</span><span className="text-sm font-medium tabular-nums">{formatNumber(data.metrics.units_sold)}</span></div>
                  <div className="flex justify-between"><span className="text-sm text-text-secondary">Возвращено</span><span className="text-sm font-medium tabular-nums text-accent-amber">{formatNumber(data.metrics.units_returned)}</span></div>
                  <div className="flex justify-between"><span className="text-sm text-text-secondary">Активных SKU</span><span className="text-sm font-medium tabular-nums">{formatNumber(data.metrics.active_skus)}</span></div>
                  <div className="flex justify-between border-t border-border-subtle pt-3"><span className="text-sm text-text-secondary">Средний чек</span><span className="text-sm font-medium tabular-nums">{formatMoney(data.metrics.avg_check)}</span></div>
                  <div className="flex justify-between"><span className="text-sm text-text-secondary">Прибыль/единицу</span><span className="text-sm font-medium tabular-nums text-accent-green">{formatMoney(data.metrics.avg_profit_per_unit)}</span></div>
                </div>
              </div>

              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-4">Структура расходов</h3>
                {(() => {
                  const total = data.pnl.cogs + data.pnl.commission + data.pnl.logistics;
                  if (total === 0) return <p className="text-sm text-text-tertiary">Нет данных</p>;
                  const items = [
                    { label: "Себестоимость", value: data.pnl.cogs, color: "#6366F1" },
                    { label: "Комиссия МП", value: data.pnl.commission, color: "#F59E0B" },
                    { label: "Логистика", value: data.pnl.logistics, color: "#EF4444" },
                  ];
                  return (
                    <div className="space-y-3">
                      {items.map((it) => {
                        const pct = (it.value / total) * 100;
                        return (
                          <div key={it.label}>
                            <div className="flex items-center justify-between mb-1">
                              <div className="flex items-center gap-2">
                                <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: it.color }} />
                                <span className="text-xs text-text-secondary">{it.label}</span>
                              </div>
                              <span className="text-xs tabular-nums text-text-secondary">{pct.toFixed(0)}%</span>
                            </div>
                            <div className="h-1.5 rounded-full bg-surface-3 overflow-hidden">
                              <div className="h-full rounded-full" style={{ width: pct + "%", backgroundColor: it.color }} />
                            </div>
                          </div>
                        );
                      })}
                    </div>
                  );
                })()}
              </div>
            </div>
          </div>

          <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
            <h3 className="text-sm font-medium text-text-secondary mb-4">Динамика P&L по дням</h3>
            <ResponsiveContainer width="100%" height={280}>
              <AreaChart data={data.daily.map((d) => ({ ...d, label: formatDate(d.date) }))} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
                <defs>
                  <linearGradient id="gPnlRev" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#F97316" stopOpacity={0.15} /><stop offset="100%" stopColor="#F97316" stopOpacity={0} /></linearGradient>
                  <linearGradient id="gPnlProf" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#22C55E" stopOpacity={0.15} /><stop offset="100%" stopColor="#22C55E" stopOpacity={0} /></linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} interval="preserveStartEnd" />
                <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} tickFormatter={formatK} />
                <Tooltip contentStyle={{ backgroundColor: "var(--color-surface-2)", border: "1px solid var(--color-border-default)", borderRadius: "8px", fontSize: "12px" }} />
                <Area type="monotone" dataKey="revenue" name="Выручка" stroke="#F97316" strokeWidth={2} fill="url(#gPnlRev)" dot={false} />
                <Area type="monotone" dataKey="profit" name="Прибыль" stroke="#22C55E" strokeWidth={2} fill="url(#gPnlProf)" dot={false} />
              </AreaChart>
            </ResponsiveContainer>
          </div>

          <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
            <h3 className="text-sm font-medium text-text-secondary mb-4">P&L по категориям</h3>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider">
                    <th className="pb-3 font-medium">Категория</th>
                    <th className="pb-3 font-medium text-right">Продано</th>
                    <th className="pb-3 font-medium text-right">Выручка</th>
                    <th className="pb-3 font-medium text-right">Себестоимость</th>
                    <th className="pb-3 font-medium text-right">Комиссия</th>
                    <th className="pb-3 font-medium text-right">Логистика</th>
                    <th className="pb-3 font-medium text-right">Прибыль</th>
                    <th className="pb-3 font-medium text-right">Маржа</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {data.by_category.map((cat) => {
                    const margin = cat.revenue > 0 ? (cat.profit / cat.revenue) * 100 : 0;
                    return (
                      <tr key={cat.slug} className="hover:bg-surface-2/50 transition-colors">
                        <td className="py-3 font-medium">{cat.category}</td>
                        <td className="py-3 text-right tabular-nums text-text-secondary">{formatNumber(cat.units)}</td>
                        <td className="py-3 text-right tabular-nums font-medium">{formatMoney(cat.revenue)}</td>
                        <td className="py-3 text-right tabular-nums text-text-secondary">{formatMoney(cat.cogs)}</td>
                        <td className="py-3 text-right tabular-nums text-text-secondary">{formatMoney(cat.commission)}</td>
                        <td className="py-3 text-right tabular-nums text-text-secondary">{formatMoney(cat.logistics)}</td>
                        <td className="py-3 text-right tabular-nums font-medium text-accent-green">{formatMoney(cat.profit)}</td>
                        <td className="py-3 text-right tabular-nums">
                          <span className={margin >= 50 ? "text-accent-green" : margin >= 20 ? "text-accent-amber" : "text-accent-red"}>
                            {formatPercent(margin)}
                          </span>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      ) : (
        <div className="text-center py-20 text-text-tertiary">
          Не удалось загрузить данные
        </div>
      )}
    </AppLayout>
  );
}
