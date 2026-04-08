"use client";
import { useState, useMemo } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { useApiQuery } from "@/hooks/useApiQuery";
import { api } from "@/lib/api";
import { formatMoney } from "@/lib/utils";
import { Calendar, ChevronLeft, ChevronRight, Download, TrendingDown } from "lucide-react";

interface RnpRecord {
  id: string;
  marketplace: string;
  marketplace_name: string;
  operation_date: string;
  category: string;
  category_name: string;
  subcategory: string | null;
  description: string | null;
  amount: string;
  document_id: string | null;
}

interface RnpSummary {
  category: string;
  category_name: string;
  total: string;
  count: number;
}

const MONTHS = [
  "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
  "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"
];

const MP_COLORS: Record<string, string> = {
  wildberries: "#CB11AB",
  ozon: "#005BFF",
  yandex_market: "#FFCC00",
  avito: "#00AAFF",
};

const CATEGORY_COLORS: Record<string, string> = {
  logistics: "#3B82F6",
  storage: "#8B5CF6",
  commission: "#F59E0B",
  advertising: "#10B981",
  fines: "#EF4444",
  other: "#6B7280",
};

export default function ExpensesPage() {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);
  const [marketplace, setMarketplace] = useState<string>("");
  const [category, setCategory] = useState<string>("");

  const startDate = `${year}-${String(month).padStart(2, "0")}-01`;
  const endDate = new Date(year, month, 0).toISOString().slice(0, 10);

  const { data: recordsData, loading: loadingRecords, error: errorRecords, refresh } = useApiQuery<{
    records: RnpRecord[];
    total: number;
  }>(
    async () => {
      const params = new URLSearchParams({ 
        view: "details",
        startDate, 
        endDate, 
        limit: "200" 
      });
      if (marketplace) params.set("marketplace", marketplace);
      if (category) params.set("category", category);
      return api.request(`/api/v1/analytics/rnp?${params}`);
    },
    [startDate, endDate, marketplace, category]
  );

  const { data: summaryData, loading: loadingSummary } = useApiQuery<{ summary: RnpSummary[] }>(
    async () => {
      const params = new URLSearchParams({ 
        view: "summary",
        startDate, 
        endDate 
      });
      if (marketplace) params.set("marketplace", marketplace);
      return api.request(`/api/v1/analytics/rnp?${params}`);
    },
    [startDate, endDate, marketplace]
  );

  const prevMonth = () => {
    if (month === 1) { setMonth(12); setYear(year - 1); }
    else setMonth(month - 1);
  };

  const nextMonth = () => {
    if (month === 12) { setMonth(1); setYear(year + 1); }
    else setMonth(month + 1);
  };

  const goToToday = () => {
    setYear(now.getFullYear());
    setMonth(now.getMonth() + 1);
  };

  // Агрегация
  const totals = useMemo(() => {
    if (!summaryData?.summary) return { total: 0, byCategory: [] };
    
    const total = summaryData.summary.reduce((sum, s) => sum + parseFloat(s.total), 0);
    
    const byCategory = summaryData.summary.map(s => ({
      category: s.category,
      name: s.category_name,
      color: CATEGORY_COLORS[s.category] || "#6B7280",
      amount: parseFloat(s.total),
      count: s.count,
    })).sort((a, b) => a.amount - b.amount);

    return { total, byCategory };
  }, [summaryData]);

  // Группировка по маркетплейсам
  const byMarketplace = useMemo(() => {
    if (!recordsData?.records) return [];
    
    const grouped = recordsData.records.reduce((acc, r) => {
      if (!acc[r.marketplace]) {
        acc[r.marketplace] = { 
          marketplace: r.marketplace, 
          name: r.marketplace_name, 
          amount: 0 
        };
      }
      acc[r.marketplace].amount += parseFloat(r.amount);
      return acc;
    }, {} as Record<string, { marketplace: string; name: string; amount: number }>);

    return Object.values(grouped).sort((a, b) => a.amount - b.amount);
  }, [recordsData]);

  const loading = loadingRecords || loadingSummary;

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Расходы на продажу (РНП)</h1>
          <p className="text-sm text-text-tertiary mt-0.5">
            Учёт расходов по маркетплейсам: логистика, хранение, комиссии, реклама
          </p>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={goToToday}
            className="px-3 py-1.5 text-xs font-medium bg-surface-2 hover:bg-surface-3 rounded-md transition"
          >
            <Calendar className="w-3.5 h-3.5 inline mr-1" />
            Сегодня
          </button>
          <button className="px-3 py-1.5 text-xs font-medium bg-surface-2 hover:bg-surface-3 rounded-md transition">
            <Download className="w-3.5 h-3.5 inline mr-1" />
            Экспорт
          </button>
        </div>
      </div>

      {/* Month selector */}
      <div className="flex items-center gap-4 mb-6">
        <div className="flex items-center gap-2 bg-surface-2 rounded-lg p-1">
          <button
            onClick={prevMonth}
            className="p-1.5 hover:bg-surface-3 rounded-md transition"
          >
            <ChevronLeft className="w-4 h-4" />
          </button>
          <span className="px-3 py-1 text-sm font-medium min-w-[140px] text-center">
            {MONTHS[month - 1]} {year}
          </span>
          <button
            onClick={nextMonth}
            className="p-1.5 hover:bg-surface-3 rounded-md transition"
          >
            <ChevronRight className="w-4 h-4" />
          </button>
        </div>

        {/* Filters */}
        <select
          value={marketplace}
          onChange={(e) => setMarketplace(e.target.value)}
          className="px-3 py-1.5 text-sm bg-surface-2 border border-border-default rounded-md"
        >
          <option value="">Все маркетплейсы</option>
          <option value="wildberries">Wildberries</option>
          <option value="ozon">Ozon</option>
          <option value="yandex_market">Яндекс Маркет</option>
          <option value="avito">Avito</option>
        </select>

        <select
          value={category}
          onChange={(e) => setCategory(e.target.value)}
          className="px-3 py-1.5 text-sm bg-surface-2 border border-border-default rounded-md"
        >
          <option value="">Все категории</option>
          <option value="logistics">Логистика</option>
          <option value="storage">Хранение</option>
          <option value="commission">Комиссия</option>
          <option value="advertising">Реклама</option>
          <option value="fines">Штрафы</option>
          <option value="other">Прочее</option>
        </select>
      </div>

      {loading && <Spinner />}
      {errorRecords && <ErrorState message="Ошибка загрузки данных" onRetry={refresh} />}

      {!loading && !errorRecords && (
        <>
          {/* Summary cards */}
          <div className="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
            <div className="bg-surface-1 border border-border-subtle rounded-lg p-4">
              <div className="flex items-center gap-2 text-text-tertiary text-xs mb-2">
                <TrendingDown className="w-4 h-4" />
                Итого расходов
              </div>
              <div className="text-2xl font-semibold text-red-500">
                {formatMoney(totals.total)}
              </div>
            </div>

            {byMarketplace.slice(0, 3).map((mp) => (
              <div key={mp.marketplace} className="bg-surface-1 border border-border-subtle rounded-lg p-4">
                <div className="flex items-center gap-2 text-text-tertiary text-xs mb-2">
                  <div
                    className="w-2 h-2 rounded-full"
                    style={{ backgroundColor: MP_COLORS[mp.marketplace] || "#6B7280" }}
                  />
                  {mp.name}
                </div>
                <div className="text-xl font-semibold text-red-500">
                  {formatMoney(mp.amount)}
                </div>
              </div>
            ))}
          </div>

          {/* By category breakdown */}
          <div className="bg-surface-1 border border-border-subtle rounded-lg p-4 mb-6">
            <h3 className="text-sm font-medium mb-4">Расходы по категориям</h3>
            <div className="space-y-3">
              {totals.byCategory.map((cat) => {
                const pct = totals.total !== 0 ? Math.abs((cat.amount / totals.total) * 100) : 0;
                return (
                  <div key={cat.category} className="flex items-center gap-3">
                    <div
                      className="w-3 h-3 rounded"
                      style={{ backgroundColor: cat.color }}
                    />
                    <div className="flex-1 min-w-0">
                      <div className="flex justify-between text-sm mb-1">
                        <span className="truncate">{cat.name}</span>
                        <span className="text-red-500 font-medium">{formatMoney(cat.amount)}</span>
                      </div>
                      <div className="h-2 bg-surface-3 rounded-full overflow-hidden">
                        <div
                          className="h-full rounded-full transition-all"
                          style={{ width: `${pct}%`, backgroundColor: cat.color }}
                        />
                      </div>
                    </div>
                    <span className="text-xs text-text-tertiary w-12 text-right">{pct.toFixed(1)}%</span>
                  </div>
                );
              })}
              {totals.byCategory.length === 0 && (
                <p className="text-sm text-text-tertiary text-center py-4">Нет данных за выбранный период</p>
              )}
            </div>
          </div>

          {/* Records table */}
          <div className="bg-surface-1 border border-border-subtle rounded-lg overflow-hidden">
            <div className="px-4 py-3 border-b border-border-subtle flex items-center justify-between">
              <h3 className="text-sm font-medium">Детализация операций</h3>
              <span className="text-xs text-text-tertiary">{recordsData?.total || 0} записей</span>
            </div>
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-surface-2">
                  <tr>
                    <th className="text-left px-4 py-2 font-medium text-text-secondary">Дата</th>
                    <th className="text-left px-4 py-2 font-medium text-text-secondary">Маркетплейс</th>
                    <th className="text-left px-4 py-2 font-medium text-text-secondary">Категория</th>
                    <th className="text-left px-4 py-2 font-medium text-text-secondary">Описание</th>
                    <th className="text-right px-4 py-2 font-medium text-text-secondary">Сумма</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {recordsData?.records?.map((r) => (
                    <tr key={r.id} className="hover:bg-surface-2/50">
                      <td className="px-4 py-2 text-text-secondary">
                        {new Date(r.operation_date).toLocaleDateString("ru-RU")}
                      </td>
                      <td className="px-4 py-2">
                        <span
                          className="inline-flex items-center gap-1.5 px-2 py-0.5 text-xs rounded-full"
                          style={{
                            backgroundColor: `${MP_COLORS[r.marketplace] || "#6B7280"}20`,
                            color: MP_COLORS[r.marketplace] || "#6B7280",
                          }}
                        >
                          {r.marketplace_name}
                        </span>
                      </td>
                      <td className="px-4 py-2">{r.category_name}</td>
                      <td className="px-4 py-2 text-text-tertiary truncate max-w-[200px]">
                        {r.description || r.subcategory || "—"}
                      </td>
                      <td className="px-4 py-2 text-right font-medium text-red-500">
                        {formatMoney(parseFloat(r.amount))}
                      </td>
                    </tr>
                  ))}
                  {(!recordsData?.records || recordsData.records.length === 0) && (
                    <tr>
                      <td colSpan={5} className="px-4 py-8 text-center text-text-tertiary">
                        Нет данных за выбранный период
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </AppLayout>
  );
}
