"use client";
import { useEffect, useState } from "react";
import AppLayout from "@/components/layout/AppLayout";
import PeriodSelector from "@/components/ui/PeriodSelector";
import CategoryFilter from "@/components/ui/CategoryFilter";
import { formatMoney, formatNumber, formatPercent } from "@/lib/utils";
import { api } from "@/lib/api";
import { ArrowUpDown, ChevronDown, ChevronUp } from "lucide-react";
import Link from "next/link";

interface UEItem {
  id: number; name: string; sku: string; category: string; category_slug: string;
  cost_price: number; avg_price: number; revenue: number; returns_amount: number;
  commission: number; logistics: number; profit: number;
  units_sold: number; units_returned: number;
  margin_pct: number; profit_per_unit: number; roi: number; return_rate: number;
}

interface UEData {
  period: string;
  items: UEItem[];
  summary: {
    total_revenue: number; total_profit: number; total_commission: number;
    total_logistics: number; total_cogs: number; total_units: number;
    total_returns: number; avg_margin: number; avg_roi: number; products_count: number;
  };
}

function SortHeader({ label, field, current, order, onSort }: {
  label: string; field: string; current: string; order: string; onSort: (f: string) => void;
}) {
  const active = current === field;
  return (
    <th className="pb-3 font-medium text-right cursor-pointer select-none hover:text-text-primary transition-colors" onClick={() => onSort(field)}>
      <span className="inline-flex items-center gap-1">
        {label}
        {active ? (order === "desc" ? <ChevronDown className="h-3 w-3" /> : <ChevronUp className="h-3 w-3" />) : <ArrowUpDown className="h-3 w-3 opacity-30" />}
      </span>
    </th>
  );
}
export default function UnitEconomicsPage() {
  const [data, setData] = useState<UEData | null>(null);
  const [period, setPeriod] = useState("30d");
  const [category, setCategory] = useState("");
  const [sort, setSort] = useState("revenue");
  const [order, setOrder] = useState("desc");
  const [loading, setLoading] = useState(true);

  function handleSort(field: string) {
    if (sort === field) { setOrder(order === "desc" ? "asc" : "desc"); }
    else { setSort(field); setOrder("desc"); }
  }

  useEffect(() => {
    setLoading(true);
    const qs = new URLSearchParams({ period, sort, order });
    if (category) qs.set("category", category);
    api.request<UEData>("/api/v1/analytics/unit-economics?" + qs.toString())
      .then(setData).catch(console.error).finally(() => setLoading(false));
  }, [period, category, sort, order]);

  const s = data?.summary;

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Юнит-экономика</h1>
          <p className="text-sm text-text-tertiary mt-0.5">Детальный расчёт по каждому товару</p>
        </div>
        <div className="flex items-center gap-3">
          <CategoryFilter value={category} onChange={setCategory} />
          <PeriodSelector value={period} onChange={setPeriod} />
        </div>
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
        </div>
      ) : data && s ? (
        <div className="space-y-6 animate-fade-in">
          <div className="grid grid-cols-5 gap-4">
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">Выручка</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums">{formatMoney(s.total_revenue)}</p>
              <p className="text-xs text-text-tertiary mt-1">{formatNumber(s.products_count)} товаров</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">Прибыль</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums text-accent-green">{formatMoney(s.total_profit)}</p>
              <p className="text-xs text-text-tertiary mt-1">{formatNumber(s.total_units)} единиц</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">Ср. маржа</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums">{formatPercent(s.avg_margin)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">ROI</p>
              <p className="mt-2 text-2xl font-semibold tabular-nums">{formatPercent(s.avg_roi)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
              <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">Расходы</p>
              <div className="mt-2 space-y-0.5">
                <p className="text-xs text-text-secondary">COGS: <span className="font-medium">{formatMoney(s.total_cogs)}</span></p>
                <p className="text-xs text-text-secondary">Комиссия: <span className="font-medium">{formatMoney(s.total_commission)}</span></p>
                <p className="text-xs text-text-secondary">Логистика: <span className="font-medium">{formatMoney(s.total_logistics)}</span></p>
              </div>
            </div>
          </div>
          <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider">
                    <th className="pb-3 font-medium">Товар</th>
                    <SortHeader label="Продано" field="quantity" current={sort} order={order} onSort={handleSort} />
                    <SortHeader label="Себест." field="revenue" current={sort} order={order} onSort={handleSort} />
                    <SortHeader label="Выручка" field="revenue" current={sort} order={order} onSort={handleSort} />
                    <SortHeader label="Прибыль" field="profit" current={sort} order={order} onSort={handleSort} />
                    <SortHeader label="Маржа" field="margin" current={sort} order={order} onSort={handleSort} />
                    <SortHeader label="На ед." field="profit" current={sort} order={order} onSort={handleSort} />
                    <SortHeader label="ROI" field="roi" current={sort} order={order} onSort={handleSort} />
                    <th className="pb-3 font-medium text-right">Возвр.</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {data.items.map((item) => (
                    <tr key={item.id} className="hover:bg-surface-2/50 transition-colors group">
                      <td className="py-3 pr-4">
                        <Link href={"/products/" + item.id} className="group-hover:underline">
                          <p className="text-text-primary font-medium truncate max-w-[250px]">{item.name}</p>
                        </Link>
                        <p className="text-xs text-text-tertiary mt-0.5">{item.sku} · {item.category}</p>
                      </td>
                      <td className="py-3 text-right tabular-nums text-text-secondary">{formatNumber(item.units_sold)}</td>
                      <td className="py-3 text-right tabular-nums text-text-secondary">{formatMoney(item.cost_price)}</td>
                      <td className="py-3 text-right tabular-nums font-medium">{formatMoney(item.revenue)}</td>
                      <td className="py-3 text-right tabular-nums font-medium text-accent-green">{formatMoney(item.profit)}</td>
                      <td className="py-3 text-right tabular-nums">
                        <span className={item.margin_pct >= 50 ? "text-accent-green" : item.margin_pct >= 20 ? "text-accent-amber" : "text-accent-red"}>
                          {formatPercent(item.margin_pct)}
                        </span>
                      </td>
                      <td className="py-3 text-right tabular-nums text-accent-green">{formatMoney(item.profit_per_unit)}</td>
                      <td className="py-3 text-right tabular-nums">
                        <span className={item.roi >= 100 ? "text-accent-green" : item.roi >= 50 ? "text-accent-amber" : "text-accent-red"}>
                          {formatPercent(item.roi)}
                        </span>
                      </td>
                      <td className="py-3 text-right tabular-nums">
                        {item.units_returned > 0 ? (
                          <span className={item.return_rate > 10 ? "text-accent-red" : "text-accent-amber"}>
                            {item.units_returned} ({formatPercent(item.return_rate)})
                          </span>
                        ) : (
                          <span className="text-text-tertiary">—</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      ) : (
        <div className="text-center py-20 text-text-tertiary">Не удалось загрузить данные</div>
      )}
    </AppLayout>
  );
}