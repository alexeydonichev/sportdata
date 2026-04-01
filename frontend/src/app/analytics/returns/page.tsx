"use client";
import { useEffect, useState } from "react";
import AppLayout from "@/components/layout/AppLayout";
import PeriodSelector from "@/components/ui/PeriodSelector";
import CategoryFilter from "@/components/ui/CategoryFilter";
import ExportButton from "@/components/ui/ExportButton";
import { formatMoney, formatNumber, formatPercent, formatDate } from "@/lib/utils";
import { api } from "@/lib/api";
import type { ReturnsAnalytics } from "@/lib/api";
import { TrendingUp, TrendingDown, Minus } from "lucide-react";
import Link from "next/link";
import {
  AreaChart, Area, XAxis, YAxis, Tooltip,
  ResponsiveContainer, CartesianGrid,
} from "recharts";

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

function formatK(v: number) {
  if (Math.abs(v) >= 5000000) return (v / 5000000).toFixed(1) + "M";
  if (Math.abs(v) >= 5000) return (v / 5000).toFixed(0) + "K";
  return v.toString();
}

type SortField = "return_qty" | "return_rate" | "return_amount";
type SortDir = "asc" | "desc";

export default function ReturnsPage() {
  const [data, setData] = useState<ReturnsAnalytics | null>(null);
  const [period, setPeriod] = useState("30d");
  const [category, setCategory] = useState("");
  const [loading, setLoading] = useState(true);
  const [sortField, setSortField] = useState<SortField>("return_qty");
  const [sortDir, setSortDir] = useState<SortDir>("desc");

  useEffect(() => {
    setLoading(true);
    const params: { period: string; category?: string } = { period };
    if (category && category !== "all") params.category = category;
    api
      .returnsAnalytics(params)
      .then(setData)
      .catch(console.error)
      .finally(() => setLoading(false));
  }, [period, category]);

  const toggleSort = (field: SortField) => {
    if (sortField === field) {
      setSortDir(d => d === "desc" ? "asc" : "desc");
    } else {
      setSortField(field);
      setSortDir("desc");
    }
  };

  const sortedProducts = data?.by_product
    ? [...data.by_product].sort((a, b) => {
        const mul = sortDir === "desc" ? -1 : 1;
        return (a[sortField] - b[sortField]) * mul;
      })
    : [];

  const exportHeaders = ["Товар", "SKU", "Категория", "Продажи шт", "Возвраты шт", "% возвратов", "Сумма возвратов"];
  const getExportRows = () => {
    if (!data) return [];
    return data.by_product.map(p => [
      p.name, p.sku, p.category,
      String(p.sales_qty), String(p.return_qty),
      String(p.return_rate), String(p.return_amount),
    ]);
  };

  const rateColor = (rate: number) =>
    rate >= 20 ? "text-accent-red" : rate >= 10 ? "text-accent-amber" : "text-accent-green";

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Анализ возвратов</h1>
          <p className="text-sm text-text-tertiary mt-0.5">Товары, категории, склады</p>
        </div>
        <div className="flex items-center gap-3">
          <ExportButton filename="returns" headers={exportHeaders} getRows={getExportRows} />
          <PeriodSelector value={period} onChange={setPeriod} />
        </div>
      </div>

      <div className="flex items-center gap-4 mb-6 flex-wrap">
        <CategoryFilter value={category} onChange={setCategory} />
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
        </div>
      ) : data ? (
        <div className="space-y-6 animate-fade-in">
          {/* KPI cards */}
          <div className="grid grid-cols-4 gap-4">
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">Возвратов</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-accent-red">
                {formatNumber(data.summary.total_returns)}
              </p>
              <div className="mt-2">
                <Change value={data.changes.returns} invert />
              </div>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">% Возвратов</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-accent-amber">
                {formatPercent(data.summary.return_rate)}
              </p>
              <div className="mt-2">
                <Change value={data.changes.return_rate} invert />
              </div>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">Сумма возвратов</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums">
                {formatMoney(data.summary.return_amount)}
              </p>
              <div className="mt-2">
                <Change value={data.changes.return_amount} invert />
              </div>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">Упущ. прибыль</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-accent-red">
                {formatMoney(data.summary.lost_profit)}
              </p>
              <p className="mt-2 text-xs text-text-tertiary">Логистика: {formatMoney(data.summary.return_logistics)}</p>
            </div>
          </div>

          {/* Chart */}
          <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
            <h3 className="text-sm font-medium text-text-secondary mb-4">Динамика возвратов по дням</h3>
            <ResponsiveContainer width="100%" height={280}>
              <AreaChart data={data.daily.map(d => ({ ...d, label: formatDate(d.date) }))} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
                <defs>
                  <linearGradient id="gRetSales" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#6366F1" stopOpacity={0.15} />
                    <stop offset="100%" stopColor="#6366F1" stopOpacity={0} />
                  </linearGradient>
                  <linearGradient id="gRetReturns" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#EF4444" stopOpacity={0.15} />
                    <stop offset="100%" stopColor="#EF4444" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} interval="preserveStartEnd" />
                <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} tickFormatter={formatK} />
                <Tooltip contentStyle={{ backgroundColor: "var(--color-surface-2)", border: "1px solid var(--color-border-default)", borderRadius: "8px", fontSize: "12px" }} />
                <Area type="monotone" dataKey="sales" name="Продажи" stroke="#6366F1" strokeWidth={2} fill="url(#gRetSales)" dot={false} />
                <Area type="monotone" dataKey="returns" name="Возвраты" stroke="#EF4444" strokeWidth={2} fill="url(#gRetReturns)" dot={false} />
              </AreaChart>
            </ResponsiveContainer>
          </div>

          {/* Layout: sidebar + table */}
          <div className="grid grid-cols-3 gap-6">
            {/* Sidebar */}
            <div className="space-y-4">
              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-4">По категориям</h3>
                <div className="space-y-3">
                  {data.by_category.map((cat) => {
                    const maxRet = Math.max(...data.by_category.map(c => c.return_qty), 1);
                    const pct = (cat.return_qty / maxRet) * 100;
                    return (
                      <div key={cat.category}>
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-xs text-text-secondary truncate max-w-[140px]">{cat.category}</span>
                          <span className={"text-xs tabular-nums font-medium " + rateColor(cat.return_rate)}>{formatPercent(cat.return_rate)}</span>
                        </div>
                        <div className="h-1.5 rounded-full bg-surface-3 overflow-hidden">
                          <div className="h-full rounded-full bg-accent-red/60" style={{ width: pct + "%" }} />
                        </div>
                        <div className="flex justify-between mt-0.5">
                          <span className="text-[11px] text-text-tertiary">{formatNumber(cat.return_qty)} шт</span>
                          <span className="text-[11px] text-text-tertiary">{formatMoney(cat.return_amount)}</span>
                        </div>
                      </div>
                    );
                  })}
                  {data.by_category.length === 0 && <p className="text-sm text-text-tertiary">Нет данных</p>}
                </div>
              </div>

              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-4">По складам</h3>
                <div className="space-y-3">
                  {data.by_warehouse.map((wh) => {
                    const maxRet = Math.max(...data.by_warehouse.map(w => w.return_qty), 1);
                    const pct = (wh.return_qty / maxRet) * 100;
                    return (
                      <div key={wh.warehouse}>
                        <div className="flex items-center justify-between mb-1">
                          <span className="text-xs text-text-secondary truncate max-w-[140px]">{wh.warehouse}</span>
                          <span className="text-xs tabular-nums text-text-secondary">{formatNumber(wh.return_qty)}</span>
                        </div>
                        <div className="h-1.5 rounded-full bg-surface-3 overflow-hidden">
                          <div className="h-full rounded-full bg-accent-amber/60" style={{ width: pct + "%" }} />
                        </div>
                      </div>
                    );
                  })}
                  {data.by_warehouse.length === 0 && <p className="text-sm text-text-tertiary">Нет данных по складам</p>}
                </div>
              </div>
            </div>

            {/* Product table */}
            <div className="col-span-2 rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-medium text-text-secondary mb-4">
                Топ товаров по возвратам
                <span className="ml-2 text-text-tertiary font-normal">({sortedProducts.length})</span>
              </h3>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider">
                      <th className="pb-3 font-medium">Товар</th>
                      <th className="pb-3 font-medium text-right">Продажи</th>
                      <th className="pb-3 font-medium text-right cursor-pointer select-none" onClick={() => toggleSort("return_qty")}>
                        Возвраты {sortField === "return_qty" && (sortDir === "desc" ? "↓" : "↑")}
                      </th>
                      <th className="pb-3 font-medium text-right cursor-pointer select-none" onClick={() => toggleSort("return_rate")}>
                        % возвр. {sortField === "return_rate" && (sortDir === "desc" ? "↓" : "↑")}
                      </th>
                      <th className="pb-3 font-medium text-right cursor-pointer select-none" onClick={() => toggleSort("return_amount")}>
                        Сумма {sortField === "return_amount" && (sortDir === "desc" ? "↓" : "↑")}
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-subtle">
                    {sortedProducts.map((p) => (
                      <tr key={p.product_id} className="hover:bg-surface-2/50 transition-colors">
                        <td className="py-3">
                          <Link href={"/products/" + p.product_id} className="hover:text-accent-blue transition-colors">
                            <div className="font-medium truncate max-w-[240px]">{p.name}</div>
                            <div className="text-[11px] text-text-tertiary">{p.sku} · {p.category}</div>
                          </Link>
                        </td>
                        <td className="py-3 text-right tabular-nums text-text-secondary">{formatNumber(p.sales_qty)}</td>
                        <td className="py-3 text-right tabular-nums font-medium text-accent-red">{formatNumber(p.return_qty)}</td>
                        <td className="py-3 text-right tabular-nums">
                          <span className={rateColor(p.return_rate)}>{formatPercent(p.return_rate)}</span>
                        </td>
                        <td className="py-3 text-right tabular-nums text-text-secondary">{formatMoney(p.return_amount)}</td>
                      </tr>
                    ))}
                    {sortedProducts.length === 0 && (
                      <tr><td colSpan={5} className="py-12 text-center text-text-tertiary">Нет возвратов за выбранный период</td></tr>
                    )}
                  </tbody>
                </table>
              </div>
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
