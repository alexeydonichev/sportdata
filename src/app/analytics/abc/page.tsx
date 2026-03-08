"use client";

import { useEffect, useState, useMemo } from "react";
import AppLayout from "@/components/layout/AppLayout";
import { api } from "@/lib/api";
import {
  BarChart3,
  Download,
  Search,
  ArrowUpDown,
  ArrowUp,
  ArrowDown,
  Package,
  TrendingUp,
  Filter,
} from "lucide-react";

interface Product {
  id: string;
  name: string;
  sku?: string;
  revenue: number;
  profit: number;
  quantity: number;
  orders: number;
  category?: string;
}

interface ABCProduct extends Product {
  grade: "A" | "B" | "C";
  revenueShare: number;
  cumulativeShare: number;
}

function classifyABC(products: Product[]): ABCProduct[] {
  const sorted = [...products].sort((a, b) => b.revenue - a.revenue);
  const totalRevenue = sorted.reduce((s, p) => s + p.revenue, 0);
  if (totalRevenue === 0) return sorted.map((p) => ({ ...p, grade: "C" as const, revenueShare: 0, cumulativeShare: 0 }));

  let cumulative = 0;
  return sorted.map((p) => {
    const share = p.revenue / totalRevenue;
    cumulative += share;
    let grade: "A" | "B" | "C" = "C";
    if (cumulative - share < 0.8) grade = "A";
    else if (cumulative - share < 0.95) grade = "B";
    return { ...p, grade, revenueShare: share, cumulativeShare: cumulative };
  });
}

const GRADE_STYLES = {
  A: { bg: "bg-accent-green/10", text: "text-accent-green", bar: "bg-accent-green", label: "A — Лидеры" },
  B: { bg: "bg-accent-amber/10", text: "text-accent-amber", bar: "bg-accent-amber", label: "B — Средние" },
  C: { bg: "bg-accent-red/10", text: "text-accent-red", bar: "bg-accent-red", label: "C — Аутсайдеры" },
};

const PERIODS = [
  { value: "7", label: "7 дней" },
  { value: "14", label: "14 дней" },
  { value: "30", label: "30 дней" },
  { value: "90", label: "90 дней" },
];

type SortKey = "revenue" | "profit" | "quantity" | "orders" | "revenueShare" | "name";
type SortDir = "asc" | "desc";

export default function ABCAnalysisPage() {
  const [products, setProducts] = useState<ABCProduct[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [search, setSearch] = useState("");
  const [filterGrade, setFilterGrade] = useState<"all" | "A" | "B" | "C">("all");
  const [period, setPeriod] = useState("90");
  const [sortKey, setSortKey] = useState<SortKey>("revenue");
  const [sortDir, setSortDir] = useState<SortDir>("desc");

  useEffect(() => {
    loadProducts();
  }, [period]);

  async function loadProducts() {
    setLoading(true);
    setError("");
    try {
      const res = await api.request<{ products: Product[] }>(`/api/v1/analytics/abc?period=${period}`);
      setProducts(classifyABC(res.products || []));
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ошибка загрузки");
    } finally {
      setLoading(false);
    }
  }

  const filtered = useMemo(() => {
    let result = [...products];
    if (filterGrade !== "all") result = result.filter((p) => p.grade === filterGrade);
    if (search) {
      const q = search.toLowerCase();
      result = result.filter(
        (p) => p.name.toLowerCase().includes(q) || p.sku?.toLowerCase().includes(q) || p.category?.toLowerCase().includes(q)
      );
    }
    result.sort((a, b) => {
      const mul = sortDir === "asc" ? 1 : -1;
      if (sortKey === "name") return mul * a.name.localeCompare(b.name);
      return mul * ((a[sortKey] as number) - (b[sortKey] as number));
    });
    return result;
  }, [products, filterGrade, search, sortKey, sortDir]);

  const stats = useMemo(() => {
    const gradeA = products.filter((p) => p.grade === "A");
    const gradeB = products.filter((p) => p.grade === "B");
    const gradeC = products.filter((p) => p.grade === "C");
    const total = products.reduce((s, p) => s + p.revenue, 0);
    return {
      A: { count: gradeA.length, revenue: gradeA.reduce((s, p) => s + p.revenue, 0), pct: total ? gradeA.reduce((s, p) => s + p.revenue, 0) / total : 0 },
      B: { count: gradeB.length, revenue: gradeB.reduce((s, p) => s + p.revenue, 0), pct: total ? gradeB.reduce((s, p) => s + p.revenue, 0) / total : 0 },
      C: { count: gradeC.length, revenue: gradeC.reduce((s, p) => s + p.revenue, 0), pct: total ? gradeC.reduce((s, p) => s + p.revenue, 0) / total : 0 },
      total,
      totalCount: products.length,
    };
  }, [products]);

  function handleSort(key: SortKey) {
    if (sortKey === key) setSortDir(sortDir === "asc" ? "desc" : "asc");
    else { setSortKey(key); setSortDir("desc"); }
  }

  function SortIcon({ col }: { col: SortKey }) {
    if (sortKey !== col) return <ArrowUpDown className="h-3 w-3 opacity-30" />;
    return sortDir === "desc" ? <ArrowDown className="h-3 w-3" /> : <ArrowUp className="h-3 w-3" />;
  }

  function exportCSV() {
    const header = "Название,SKU,Категория,Класс,Выручка,Прибыль,Доля %,Количество,Заказы\n";
    const rows = filtered.map((p) =>
      `"${p.name}","${p.sku || ""}","${p.category || ""}",${p.grade},${p.revenue},${p.profit},${(p.revenueShare * 100).toFixed(1)},${p.quantity},${p.orders}`
    ).join("\n");
    const blob = new Blob(["\uFEFF" + header + rows], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `abc-analysis-${period}d-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  const fmt = (n: number) => n.toLocaleString("ru-RU");
  const fmtCurrency = (n: number) => `${fmt(Math.round(n))} ₽`;

  return (
    <AppLayout>
      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div>
          <h1 className="text-xl font-semibold tracking-tight flex items-center gap-2">
            <BarChart3 className="h-5 w-5 text-text-secondary" />
            ABC-анализ
          </h1>
          <p className="text-sm text-text-secondary mt-1">
            Классификация товаров по вкладу в выручку
          </p>
        </div>
        <div className="flex items-center gap-2">
          <div className="flex bg-surface-1 border border-border-default rounded-lg p-0.5">
            {PERIODS.map((p) => (
              <button
                key={p.value}
                onClick={() => setPeriod(p.value)}
                className={
                  "px-3 py-1.5 rounded-md text-xs font-medium transition-colors " +
                  (period === p.value ? "bg-text-primary text-surface-0" : "text-text-secondary hover:text-text-primary")
                }
              >
                {p.label}
              </button>
            ))}
          </div>
          <button
            onClick={exportCSV}
            className="flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-surface-1 border border-border-default text-text-primary hover:bg-surface-2 transition-colors"
          >
            <Download className="h-3.5 w-3.5" />
            CSV
          </button>
        </div>
      </div>

      {error && (
        <div className="mb-6 rounded-xl bg-accent-red/10 border border-accent-red/20 p-4">
          <p className="text-sm text-accent-red">{error}</p>
        </div>
      )}

      {/* Summary cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-6">
        {(["A", "B", "C"] as const).map((grade) => {
          const s = GRADE_STYLES[grade];
          const data = stats[grade];
          return (
            <button
              key={grade}
              onClick={() => setFilterGrade(filterGrade === grade ? "all" : grade)}
              className={
                "rounded-xl border p-4 text-left transition-all " +
                (filterGrade === grade
                  ? `${s.bg} border-2 shadow-sm`
                  : "bg-surface-1 border-border-subtle hover:border-border-default")
              }
            >
              <div className="flex items-center justify-between mb-3">
                <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-bold ${s.bg} ${s.text}`}>
                  {grade}
                </span>
                <span className="text-[11px] text-text-tertiary">{s.label}</span>
              </div>
              <p className="text-lg font-semibold text-text-primary">
                {data.count} <span className="text-xs font-normal text-text-tertiary">из {stats.totalCount}</span>
              </p>
              <div className="flex items-center justify-between mt-2">
                <p className="text-xs text-text-secondary">{fmtCurrency(data.revenue)}</p>
                <p className={`text-xs font-medium ${s.text}`}>{(data.pct * 100).toFixed(1)}%</p>
              </div>
              <div className="mt-2 h-1.5 bg-surface-3 rounded-full overflow-hidden">
                <div className={`h-full rounded-full ${s.bar}`} style={{ width: `${data.pct * 100}%` }} />
              </div>
            </button>
          );
        })}
      </div>

      {/* Pareto bar */}
      <div className="rounded-xl border border-border-subtle bg-surface-1 p-4 mb-6">
        <div className="flex items-center justify-between mb-3">
          <p className="text-xs font-medium text-text-secondary flex items-center gap-1.5">
            <TrendingUp className="h-3.5 w-3.5" />
            Распределение выручки (Парето)
          </p>
          <p className="text-[11px] text-text-tertiary">{stats.totalCount} товаров · {fmtCurrency(stats.total)}</p>
        </div>
        <div className="h-8 rounded-lg overflow-hidden flex">
          {(["A", "B", "C"] as const).map((grade) => {
            const pct = stats[grade].pct;
            if (pct === 0) return null;
            const s = GRADE_STYLES[grade];
            return (
              <div key={grade} className={`${s.bar} flex items-center justify-center transition-all`} style={{ width: `${pct * 100}%` }}>
                <span className="text-[10px] font-bold text-white">{grade} {(pct * 100).toFixed(0)}%</span>
              </div>
            );
          })}
        </div>
      </div>

      {/* Table */}
      <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
        <div className="p-4 border-b border-border-subtle flex flex-col sm:flex-row gap-3">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-3.5 w-3.5 text-text-tertiary" />
            <input
              type="text"
              placeholder="Поиск по названию, SKU или категории..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="w-full bg-surface-0 border border-border-default rounded-lg pl-9 pr-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:border-text-secondary transition-colors"
            />
          </div>
          <div className="flex gap-1.5">
            {(["all", "A", "B", "C"] as const).map((g) => (
              <button
                key={g}
                onClick={() => setFilterGrade(g)}
                className={
                  "px-3 py-1.5 rounded-lg text-xs font-medium transition-colors " +
                  (filterGrade === g
                    ? "bg-text-primary text-surface-0"
                    : "bg-surface-0 text-text-secondary hover:bg-surface-2 border border-border-default")
                }
              >
                {g === "all" ? (
                  <span className="flex items-center gap-1"><Filter className="h-3 w-3" />Все</span>
                ) : g}
              </button>
            ))}
          </div>
        </div>

        {loading ? (
          <div className="p-12 text-center">
            <div className="w-6 h-6 border-2 border-text-tertiary border-t-transparent rounded-full animate-spin mx-auto mb-3" />
            <p className="text-sm text-text-tertiary">Загрузка данных...</p>
          </div>
        ) : filtered.length === 0 ? (
          <div className="p-12 text-center">
            <Package className="h-8 w-8 text-text-tertiary mx-auto mb-3" />
            <p className="text-sm text-text-tertiary">Нет товаров</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border-subtle bg-surface-0">
                  <th className="text-left px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider w-10">#</th>
                  <th className="text-left px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">
                    <button onClick={() => handleSort("name")} className="flex items-center gap-1 hover:text-text-secondary">
                      Товар <SortIcon col="name" />
                    </button>
                  </th>
                  <th className="text-center px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider w-16">Класс</th>
                  <th className="text-right px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">
                    <button onClick={() => handleSort("revenue")} className="flex items-center gap-1 justify-end hover:text-text-secondary ml-auto">
                      Выручка <SortIcon col="revenue" />
                    </button>
                  </th>
                  <th className="text-right px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">
                    <button onClick={() => handleSort("profit")} className="flex items-center gap-1 justify-end hover:text-text-secondary ml-auto">
                      Прибыль <SortIcon col="profit" />
                    </button>
                  </th>
                  <th className="text-right px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">
                    <button onClick={() => handleSort("revenueShare")} className="flex items-center gap-1 justify-end hover:text-text-secondary ml-auto">
                      Доля <SortIcon col="revenueShare" />
                    </button>
                  </th>
                  <th className="text-right px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">
                    <button onClick={() => handleSort("quantity")} className="flex items-center gap-1 justify-end hover:text-text-secondary ml-auto">
                      Продано <SortIcon col="quantity" />
                    </button>
                  </th>
                  <th className="text-right px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider">
                    <button onClick={() => handleSort("orders")} className="flex items-center gap-1 justify-end hover:text-text-secondary ml-auto">
                      Заказы <SortIcon col="orders" />
                    </button>
                  </th>
                  <th className="text-right px-4 py-3 text-[11px] font-medium text-text-tertiary uppercase tracking-wider w-16">Накоп.</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((p, i) => {
                  const s = GRADE_STYLES[p.grade];
                  return (
                    <tr key={p.id} className="border-b border-border-subtle/50 hover:bg-surface-0/50 transition-colors">
                      <td className="px-4 py-3 text-text-tertiary text-xs">{i + 1}</td>
                      <td className="px-4 py-3">
                        <p className="text-text-primary font-medium text-[13px]">{p.name}</p>
                        <div className="flex items-center gap-2 mt-0.5">
                          {p.sku && <span className="text-[11px] text-text-tertiary">{p.sku}</span>}
                          {p.category && (
                            <span className="inline-block px-1.5 py-0.5 rounded text-[10px] bg-surface-2 text-text-tertiary">{p.category}</span>
                          )}
                        </div>
                      </td>
                      <td className="px-4 py-3 text-center">
                        <span className={`inline-flex w-7 h-7 items-center justify-center rounded-lg text-xs font-bold ${s.bg} ${s.text}`}>
                          {p.grade}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-right font-medium text-text-primary">{fmtCurrency(p.revenue)}</td>
                      <td className={`px-4 py-3 text-right font-medium ${p.profit >= 0 ? "text-accent-green" : "text-accent-red"}`}>
                        {fmtCurrency(p.profit)}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex items-center justify-end gap-2">
                          <div className="w-12 h-1.5 bg-surface-3 rounded-full overflow-hidden">
                            <div className={`h-full rounded-full ${s.bar}`} style={{ width: `${Math.min(p.revenueShare * 100 * 5, 100)}%` }} />
                          </div>
                          <span className="text-xs text-text-secondary w-10 text-right">{(p.revenueShare * 100).toFixed(1)}%</span>
                        </div>
                      </td>
                      <td className="px-4 py-3 text-right text-text-secondary">{fmt(p.quantity)}</td>
                      <td className="px-4 py-3 text-right text-text-secondary">{fmt(p.orders)}</td>
                      <td className="px-4 py-3 text-right text-[11px] text-text-tertiary">{(p.cumulativeShare * 100).toFixed(1)}%</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}

        <div className="px-4 py-3 border-t border-border-subtle flex items-center justify-between text-[11px] text-text-tertiary">
          <span>Показано {filtered.length} из {products.length} товаров</span>
          <span>Общая выручка за {period} дн.: {fmtCurrency(stats.total)}</span>
        </div>
      </div>
    </AppLayout>
  );
}
