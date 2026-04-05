"use client";
import { useState, use } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import type { RNPItemsResponse, RNPItem } from "@/types/models";
import { formatMoney, formatNumber, cn } from "@/lib/utils";
import { ArrowLeft, Search, TrendingUp, TrendingDown, Minus, Package, Star } from "lucide-react";
import Link from "next/link";

const SEASONS: Record<string, string> = {
  winter: "Зима",
  summer: "Лето",
  demi_season: "Деми",
  all_season: "Всесезон",
};

const STATUS_STYLES = {
  under: { bg: "bg-red-500/10", text: "text-red-500" },
  ok: { bg: "bg-yellow-500/10", text: "text-yellow-500" },
  over: { bg: "bg-green-500/10", text: "text-green-500" },
};

export default function RNPDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [seasonFilter, setSeasonFilter] = useState<string>("all");

  const { data, loading, error, refresh } = useApiQuery<RNPItemsResponse>(
    () => api.rnpItems(parseInt(id)),
    [id]
  );

  const filteredItems = data?.items.filter((item) => {
    if (search) {
      const q = search.toLowerCase();
      if (!item.name.toLowerCase().includes(q) && !item.sku.toLowerCase().includes(q)) return false;
    }
    if (statusFilter !== "all" && item.completion_status !== statusFilter) return false;
    if (seasonFilter !== "all" && item.season !== seasonFilter) return false;
    return true;
  }) || [];

  const summary = filteredItems.reduce(
    (acc, item) => ({
      planQty: acc.planQty + item.plan_orders_qty,
      planRub: acc.planRub + item.plan_orders_rub,
      factQty: acc.factQty + item.fact_orders_qty,
      factRub: acc.factRub + item.fact_orders_rub,
      totalStock: acc.totalStock + item.stock_fbo + item.stock_fbs,
    }),
    { planQty: 0, planRub: 0, factQty: 0, factRub: 0, totalStock: 0 }
  );

  const overallCompletion = summary.planQty > 0 && data?.template.days_passed
    ? (summary.factQty / (summary.planQty * data.template.days_passed / data.template.days_in_month)) * 100
    : 0;

  return (
    <AppLayout>
      <div className="flex items-center gap-4 mb-6">
        <Link href="/rnp" className="p-2 rounded-lg border border-border-default hover:bg-surface-2 transition-colors">
          <ArrowLeft className="h-4 w-4" />
        </Link>
        <div className="flex-1">
          <h1 className="text-xl font-semibold tracking-tight">РНП #{id}</h1>
          {data && (
            <p className="text-sm text-text-tertiary mt-0.5">
              {data.template.days_passed} из {data.template.days_in_month} дней · {data.count} товаров
            </p>
          )}
        </div>
      </div>

      {loading ? <Spinner /> : error ? <ErrorState message={error} onRetry={refresh} /> : data ? (
        <>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">План шт.</p>
              <p className="text-lg font-semibold">{formatNumber(summary.planQty)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">План ₽</p>
              <p className="text-lg font-semibold">{formatMoney(summary.planRub)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">Факт шт.</p>
              <p className="text-lg font-semibold">{formatNumber(summary.factQty)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">Факт ₽</p>
              <p className="text-lg font-semibold">{formatMoney(summary.factRub)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">Выполнение</p>
              <p className={cn("text-lg font-semibold", overallCompletion >= 100 ? "text-green-500" : overallCompletion >= 80 ? "text-yellow-500" : "text-red-500")}>
                {overallCompletion.toFixed(1)}%
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3 mb-4">
            <div className="relative flex-1 min-w-[200px] max-w-md">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-text-tertiary" />
              <input
                type="text"
                placeholder="Поиск по названию или SKU..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-border-default bg-surface-1 text-sm placeholder:text-text-tertiary focus:outline-none focus:border-accent-white"
              />
            </div>
            <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="px-3 py-2 rounded-lg border border-border-default bg-surface-1 text-sm">
              <option value="all">Все статусы</option>
              <option value="under">Отстаёт</option>
              <option value="ok">В норме</option>
              <option value="over">Опережает</option>
            </select>
            <select value={seasonFilter} onChange={(e) => setSeasonFilter(e.target.value)} className="px-3 py-2 rounded-lg border border-border-default bg-surface-1 text-sm">
              <option value="all">Все сезоны</option>
              <option value="winter">Зима</option>
              <option value="summer">Лето</option>
              <option value="demi_season">Деми</option>
              <option value="all_season">Всесезон</option>
            </select>
            <span className="text-sm text-text-tertiary ml-auto">{filteredItems.length} из {data.count}</span>
          </div>

          <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider border-b border-border-subtle">
                    <th className="px-4 pb-3 pt-4 font-medium">Товар</th>
                    <th className="px-4 pb-3 pt-4 font-medium">Сезон</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">План</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Факт</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">%</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Остаток</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Оборот</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Рейтинг</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {filteredItems.map((item) => <ItemRow key={item.id} item={item} />)}
                </tbody>
              </table>
            </div>
          </div>
        </>
      ) : null}
    </AppLayout>
  );
}

function ItemRow({ item }: { item: RNPItem }) {
  const status = STATUS_STYLES[item.completion_status] || STATUS_STYLES.under;
  const totalStock = item.stock_fbo + item.stock_fbs;

  return (
    <tr className="hover:bg-surface-2/50 transition-colors">
      <td className="px-4 py-3">
        <div className="flex items-center gap-3">
          {item.photo_url ? (
            <img src={item.photo_url} alt="" className="h-10 w-10 rounded-lg object-cover bg-surface-2" />
          ) : (
            <div className="h-10 w-10 rounded-lg bg-surface-2 flex items-center justify-center">
              <Package className="h-5 w-5 text-text-tertiary" />
            </div>
          )}
          <div className="min-w-0">
            <p className="font-medium text-text-primary truncate max-w-[250px]">{item.name}</p>
            <p className="text-xs text-text-tertiary">{item.sku}{item.size && item.size !== "0" && <span className="ml-2">· Размер {item.size}</span>}</p>
          </div>
        </div>
      </td>
      <td className="px-4 py-3"><span className="text-xs text-text-secondary">{SEASONS[item.season] || item.season}</span></td>
      <td className="px-4 py-3 text-right">
        <p className="tabular-nums">{formatNumber(item.plan_orders_qty)} шт</p>
        <p className="text-xs text-text-tertiary tabular-nums">{formatMoney(item.plan_orders_rub)}</p>
      </td>
      <td className="px-4 py-3 text-right">
        <p className="tabular-nums">{formatNumber(item.fact_orders_qty)} шт</p>
        <p className="text-xs text-text-tertiary tabular-nums">{formatMoney(item.fact_orders_rub)}</p>
      </td>
      <td className="px-4 py-3 text-right">
        <span className={cn("inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium", status.bg, status.text)}>
          {item.completion_status === "over" && <TrendingUp className="h-3 w-3" />}
          {item.completion_status === "under" && <TrendingDown className="h-3 w-3" />}
          {item.completion_status === "ok" && <Minus className="h-3 w-3" />}
          {item.completion_pct_qty.toFixed(0)}%
        </span>
      </td>
      <td className="px-4 py-3 text-right">
        <p className="tabular-nums">{formatNumber(totalStock)}</p>
        <p className="text-xs text-text-tertiary">FBO: {item.stock_fbo} · FBS: {item.stock_fbs}</p>
      </td>
      <td className="px-4 py-3 text-right">
        <p className={cn("tabular-nums", item.turnover_mtd < 7 ? "text-red-500" : item.turnover_mtd < 14 ? "text-yellow-500" : "text-text-primary")}>
          {item.turnover_mtd > 0 ? `${item.turnover_mtd.toFixed(0)} дн.` : "—"}
        </p>
      </td>
      <td className="px-4 py-3 text-right">
        {item.reviews_avg_rating > 0 ? (
          <span className="inline-flex items-center gap-1 text-sm"><Star className="h-3.5 w-3.5 text-yellow-500 fill-yellow-500" />{item.reviews_avg_rating.toFixed(1)}</span>
        ) : <span className="text-text-tertiary">—</span>}
      </td>
    </tr>
  );
}
