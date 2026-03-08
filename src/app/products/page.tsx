"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import CategoryFilter from "@/components/ui/CategoryFilter";
import MarketplaceFilter from "@/components/ui/MarketplaceFilter";
import ExportButton from "@/components/ui/ExportButton";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import { useDebouncedValue } from "@/hooks/useDebouncedValue";
import type { Product } from "@/types/models";
import { formatMoney, formatNumber, formatPercent } from "@/lib/utils";
import { Search, ArrowUpDown, Package, TrendingUp, AlertTriangle } from "lucide-react";

type SortKey = "revenue" | "profit" | "quantity" | "name" | "price" | "margin" | "stock";

export default function ProductsPage() {
  const router = useRouter();
  const [category, setCategory] = useState("all");
  const [marketplace, setMarketplace] = useState("all");
  const [searchInput, setSearchInput] = useState("");
  const [sort, setSort] = useState<SortKey>("revenue");
  const [order, setOrder] = useState<"desc" | "asc">("desc");

  const search = useDebouncedValue(searchInput, 300);

  const { data: products = [], loading, error, refresh } = useApiQuery<Product[]>(
    () => api.products({ category, marketplace, search, sort, order }),
    [category, marketplace, search, sort, order]
  );

  const list = products || [];

  function toggleSort(key: SortKey) {
    if (sort === key) setOrder(order === "desc" ? "asc" : "desc");
    else { setSort(key); setOrder("desc"); }
  }

  const SortHeader = ({ label, sortKey, className = "" }: {
    label: string; sortKey: SortKey; className?: string;
  }) => (
    <th
      className={"pb-3 font-medium cursor-pointer select-none group " + className}
      onClick={() => toggleSort(sortKey)}
    >
      <span className="inline-flex items-center gap-1">
        {label}
        <ArrowUpDown
          className={"h-3 w-3 transition-colors " +
            (sort === sortKey ? "text-text-primary" : "text-transparent group-hover:text-text-tertiary")}
        />
      </span>
    </th>
  );

  const totalRevenue = list.reduce((s, p) => s + p.revenue, 0);
  const totalProfit = list.reduce((s, p) => s + p.profit, 0);
  const totalQty = list.reduce((s, p) => s + p.quantity, 0);

  const exportHeaders = [
    "Название", "SKU", "Категория", "Цена", "Продано",
    "Выручка", "Прибыль", "Маржа %", "Остаток", "Возвраты", "Возврат %",
  ];
  const getExportRows = () =>
    list.map((p) => [
      p.name, p.sku, p.category, String(p.avg_price), String(p.quantity),
      String(p.revenue), String(p.profit), String(p.margin_pct),
      String(p.stock), String(p.returns), String(p.return_pct),
    ]);

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Товары</h1>
          <p className="text-sm text-text-tertiary mt-0.5">
            {list.length} товаров · Данные за 90 дней
          </p>
        </div>
        <ExportButton filename="products" headers={exportHeaders} getRows={getExportRows} />
      </div>

      <div className="grid grid-cols-4 gap-4 mb-6">
        <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
          <div className="flex items-center gap-2 text-xs text-text-secondary mb-1">
            <Package className="h-3.5 w-3.5" />Товаров
          </div>
          <p className="text-2xl font-semibold tabular-nums">{list.length}</p>
        </div>
        <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
          <div className="flex items-center gap-2 text-xs text-text-secondary mb-1">
            <TrendingUp className="h-3.5 w-3.5" />Выручка
          </div>
          <p className="text-2xl font-semibold tabular-nums">{formatMoney(totalRevenue)}</p>
        </div>
        <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
          <div className="flex items-center gap-2 text-xs text-text-secondary mb-1">
            <TrendingUp className="h-3.5 w-3.5" />Прибыль
          </div>
          <p className="text-2xl font-semibold tabular-nums text-accent-green">
            {formatMoney(totalProfit)}
          </p>
        </div>
        <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
          <div className="flex items-center gap-2 text-xs text-text-secondary mb-1">
            <Package className="h-3.5 w-3.5" />Продано
          </div>
          <p className="text-2xl font-semibold tabular-nums">{formatNumber(totalQty)} шт</p>
        </div>
      </div>

      <div className="space-y-3 mb-6">
        <div className="relative max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-text-tertiary" />
          <input
            type="text"
            placeholder="Поиск по названию или SKU..."
            value={searchInput}
            onChange={(e) => setSearchInput(e.target.value)}
            className="w-full pl-10 pr-4 py-2 rounded-lg border border-border-default bg-surface-1 text-sm text-text-primary placeholder:text-text-tertiary focus:border-border-strong transition-colors"
          />
        </div>
        <MarketplaceFilter value={marketplace} onChange={setMarketplace} />
        <CategoryFilter value={category} onChange={setCategory} />
      </div>

      {loading ? (
        <Spinner />
      ) : error ? (
        <ErrorState message={error} onRetry={refresh} />
      ) : (
        <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider border-b border-border-subtle">
                  <th className="px-4 pb-3 pt-4 font-medium w-8">#</th>
                  <SortHeader label="Товар" sortKey="name" className="px-4 pt-4" />
                  <SortHeader label="Цена" sortKey="price" className="px-4 pt-4 text-right" />
                  <SortHeader label="Продано" sortKey="quantity" className="px-4 pt-4 text-right" />
                  <SortHeader label="Выручка" sortKey="revenue" className="px-4 pt-4 text-right" />
                  <SortHeader label="Прибыль" sortKey="profit" className="px-4 pt-4 text-right" />
                  <SortHeader label="Маржа" sortKey="margin" className="px-4 pt-4 text-right" />
                  <SortHeader label="Остаток" sortKey="stock" className="px-4 pt-4 text-right" />
                  <th className="px-4 pb-3 pt-4 font-medium text-right">Возврат</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border-subtle">
                {list.map((p, i) => (
                  <tr
                    key={p.id}
                    onClick={() => router.push("/products/" + p.id)}
                    className="hover:bg-surface-2/50 transition-colors cursor-pointer"
                  >
                    <td className="px-4 py-3 text-text-tertiary tabular-nums">{i + 1}</td>
                    <td className="px-4 py-3">
                      <p className="font-medium text-text-primary truncate max-w-[300px]">
                        {p.name}
                      </p>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-xs text-text-tertiary">{p.sku}</span>
                        <span className="text-xs text-text-tertiary">·</span>
                        <span className="text-xs text-text-tertiary">{p.category}</span>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      {formatMoney(p.avg_price)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      {formatNumber(p.quantity)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums font-medium">
                      {formatMoney(p.revenue)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums font-medium text-accent-green">
                      {formatMoney(p.profit)}
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      <span
                        className={
                          p.margin_pct >= 50
                            ? "text-accent-green"
                            : p.margin_pct >= 30
                            ? "text-accent-amber"
                            : "text-accent-red"
                        }
                      >
                        {formatPercent(p.margin_pct)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      <span
                        className={
                          "inline-flex items-center gap-1 " +
                          (p.stock <= 5
                            ? "text-accent-red"
                            : p.stock <= 20
                            ? "text-accent-amber"
                            : "text-text-secondary")
                        }
                      >
                        {p.stock <= 5 && <AlertTriangle className="h-3 w-3" />}
                        {formatNumber(p.stock)}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-right tabular-nums">
                      <span
                        className={p.return_pct > 10 ? "text-accent-red" : "text-text-tertiary"}
                      >
                        {p.returns > 0
                          ? p.returns + " (" + formatPercent(p.return_pct) + ")"
                          : "—"}
                      </span>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </AppLayout>
  );
}
