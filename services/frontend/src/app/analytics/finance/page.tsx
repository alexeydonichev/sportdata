"use client";
import { useEffect, useState } from "react";
import AppLayout from "@/components/layout/AppLayout";
import PeriodSelector from "@/components/ui/PeriodSelector";
import CategoryFilter from "@/components/ui/CategoryFilter";
import MarketplaceFilter from "@/components/ui/MarketplaceFilter";
import MetricCard from "@/components/ui/MetricCard";
import { formatMoney, formatPercent, formatDate } from "@/lib/utils";
import { api } from "@/lib/api";
import { TrendingUp, TrendingDown, AlertTriangle } from "lucide-react";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid, Legend } from "recharts";

interface FinanceResponse {
  period: string;
  pnl: {
    gross_revenue: number; returns_amount: number; net_revenue: number; for_pay: number;
    commission: number; logistics: number; acquiring: number; storage: number;
    penalty: number; deduction: number; acceptance: number; return_logistics: number;
    additional_payment: number; cogs: number; net_profit: number;
  };
  margins: { gross_margin: number; net_margin: number; commission_pct: number; logistics_pct: number; return_rate: number };
  changes: Record<string, number>;
  weekly: { week: string; revenue: number; for_pay: number; commission: number; logistics: number; storage: number; penalty: number; net_profit: number }[];
  by_category: { category: string; slug: string; revenue: number; commission: number; logistics: number; storage: number; penalty: number; cogs: number; net_profit: number; units: number }[];
  warnings: string[];
}

function Row({ label, value, pct, bold, color, indent }: { label: string; value: number; pct?: number; bold?: boolean; color?: string; indent?: boolean }) {
  return (
    <div className={"flex items-center justify-between py-2 " + (indent ? "pl-4" : "")}>
      <span className={"text-sm " + (bold ? "font-medium text-text-primary" : "text-text-secondary")}>{label}</span>
      <div className="flex items-center gap-3">
        {pct !== undefined && <span className="text-xs text-text-tertiary tabular-nums">{pct.toFixed(1)}%</span>}
        <span className={"text-sm tabular-nums " + (bold ? "font-semibold " : "font-medium ") + (color || "")}>{formatMoney(value)}</span>
      </div>
    </div>
  );
}

function formatK(v: number) { if (Math.abs(v) >= 1e6) return (v / 1e6).toFixed(1) + "M"; if (Math.abs(v) >= 1e3) return (v / 1e3).toFixed(0) + "K"; return v.toString(); }

export default function FinancePage() {
  const [data, setData] = useState<FinanceResponse | null>(null);
  const [period, setPeriod] = useState("30d");
  const [category, setCategory] = useState("all");
  const [marketplace, setMarketplace] = useState("all");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    const params = new URLSearchParams({ period, category, marketplace });
    api.request<FinanceResponse>("/api/v1/analytics/finance?" + params)
      .then(setData).catch(console.error).finally(() => setLoading(false));
  }, [period, category, marketplace]);

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Финансы</h1>
          <p className="text-sm text-text-tertiary mt-0.5">Детальная финансовая разбивка</p>
        </div>
        <div className="flex items-center gap-3">
          <MarketplaceFilter value={marketplace} onChange={setMarketplace} />
          <CategoryFilter value={category} onChange={setCategory} />
          <PeriodSelector value={period} onChange={setPeriod} />
        </div>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
        </div>
      ) : data ? (
        <div className="space-y-6 animate-fade-in">
          {data.warnings.length > 0 && (
            <div className="space-y-2">
              {data.warnings.map((w, i) => (
                <div key={i} className="flex items-start gap-2 px-4 py-3 rounded-xl border border-accent-amber/30 bg-accent-amber/5">
                  <AlertTriangle className="h-4 w-4 text-accent-amber mt-0.5 shrink-0" />
                  <p className="text-sm text-text-secondary">{w}</p>
                </div>
              ))}
            </div>
          )}

          <div className="grid grid-cols-5 gap-4">
            <MetricCard label="Выручка" value={formatMoney(data.pnl.gross_revenue)} change={data.changes.gross_revenue} />
            <MetricCard label="К выплате" value={formatMoney(data.pnl.for_pay)} subtitle={formatPercent(data.margins.gross_margin) + " маржа"} />
            <MetricCard label="Комиссия" value={formatMoney(data.pnl.commission)} change={data.changes.commission} invertColor subtitle={formatPercent(data.margins.commission_pct)} />
            <MetricCard label="Логистика" value={formatMoney(data.pnl.logistics)} change={data.changes.logistics} invertColor subtitle={formatPercent(data.margins.logistics_pct)} />
            <MetricCard label="Чистая прибыль" value={formatMoney(data.pnl.net_profit)} change={data.changes.net_profit} subtitle={formatPercent(data.margins.net_margin) + " маржа"} />
          </div>

          <div className="grid grid-cols-3 gap-6">
            <div className="col-span-2 rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-medium text-text-secondary mb-4">Финансы по неделям</h3>
              <ResponsiveContainer width="100%" height={300}>
                <BarChart data={data.weekly.map(d => ({ ...d, label: formatDate(d.week) }))} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
                  <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} />
                  <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} tickFormatter={formatK} />
                  <Tooltip contentStyle={{ backgroundColor: "var(--color-surface-2)", border: "1px solid var(--color-border-default)", borderRadius: "8px", fontSize: "12px" }} />
                  <Legend wrapperStyle={{ fontSize: "11px" }} />
                  <Bar dataKey="revenue" name="Выручка" fill="#F97316" radius={[3, 3, 0, 0]} />
                  <Bar dataKey="net_profit" name="Прибыль" fill="#22C55E" radius={[3, 3, 0, 0]} />
                  <Bar dataKey="commission" name="Комиссия" fill="#F59E0B" radius={[3, 3, 0, 0]} />
                  <Bar dataKey="logistics" name="Логистика" fill="#6366F1" radius={[3, 3, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>

            <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-medium text-text-secondary mb-4">P&L Разбивка</h3>
              <div className="divide-y divide-border-subtle">
                <Row label="Выручка (розница)" value={data.pnl.gross_revenue} bold />
                <Row label="Возвраты" value={-data.pnl.returns_amount} color="text-accent-red" />
                <Row label="Чистая выручка" value={data.pnl.net_revenue} bold />
                <Row label="К выплате от МП" value={data.pnl.for_pay} color="text-accent-blue" />
                <Row label="Комиссия МП" value={data.pnl.commission} pct={data.margins.commission_pct} indent color="text-accent-amber" />
                <Row label="Логистика" value={data.pnl.logistics} pct={data.margins.logistics_pct} indent color="text-accent-amber" />
                <Row label="Эквайринг" value={data.pnl.acquiring} indent color="text-accent-amber" />
                <Row label="Хранение" value={data.pnl.storage} indent color="text-accent-amber" />
                {data.pnl.penalty > 0 && <Row label="Штрафы" value={data.pnl.penalty} indent color="text-accent-red" />}
                {data.pnl.deduction > 0 && <Row label="Удержания" value={data.pnl.deduction} indent color="text-accent-red" />}
                {data.pnl.acceptance > 0 && <Row label="Приёмка" value={data.pnl.acceptance} indent color="text-accent-amber" />}
                {data.pnl.return_logistics > 0 && <Row label="Обратная логистика" value={data.pnl.return_logistics} indent color="text-accent-amber" />}
                <Row label="Себестоимость (COGS)" value={data.pnl.cogs} color="text-text-secondary" />
                <Row label="Чистая прибыль" value={data.pnl.net_profit} bold color={data.pnl.net_profit >= 0 ? "text-accent-green" : "text-accent-red"} />
              </div>
            </div>
          </div>

          {data.by_category.length > 0 && (
            <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-medium text-text-secondary mb-4">По категориям</h3>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border-subtle text-text-tertiary text-xs uppercase tracking-wider">
                      <th className="text-left py-3 font-medium">Категория</th>
                      <th className="text-right py-3 font-medium">Выручка</th>
                      <th className="text-right py-3 font-medium">Комиссия</th>
                      <th className="text-right py-3 font-medium">Логистика</th>
                      <th className="text-right py-3 font-medium">Хранение</th>
                      <th className="text-right py-3 font-medium">Себест.</th>
                      <th className="text-right py-3 font-medium">Прибыль</th>
                      <th className="text-right py-3 font-medium">Шт</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-border-subtle">
                    {data.by_category.map(c => (
                      <tr key={c.slug} className="hover:bg-surface-2 transition-colors">
                        <td className="py-3 font-medium">{c.category}</td>
                        <td className="py-3 text-right tabular-nums">{formatMoney(c.revenue)}</td>
                        <td className="py-3 text-right tabular-nums text-accent-amber">{formatMoney(c.commission)}</td>
                        <td className="py-3 text-right tabular-nums text-accent-amber">{formatMoney(c.logistics)}</td>
                        <td className="py-3 text-right tabular-nums text-accent-amber">{formatMoney(c.storage)}</td>
                        <td className="py-3 text-right tabular-nums">{formatMoney(c.cogs)}</td>
                        <td className={"py-3 text-right tabular-nums font-medium " + (c.net_profit >= 0 ? "text-accent-green" : "text-accent-red")}>{formatMoney(c.net_profit)}</td>
                        <td className="py-3 text-right tabular-nums text-text-tertiary">{c.units}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      ) : null}
    </AppLayout>
  );
}
