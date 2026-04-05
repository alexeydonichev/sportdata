"use client";
import { useState } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import type { RNPTemplatesResponse } from "@/types/models";
import { mpColors } from "@/lib/utils";
import { Plus, Calendar, ChevronLeft, ChevronRight, Package, TrendingUp } from "lucide-react";
import Link from "next/link";

const MONTHS = [
  "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
  "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"
];

export default function RNPPage() {
  const now = new Date();
  const [year, setYear] = useState(now.getFullYear());
  const [month, setMonth] = useState(now.getMonth() + 1);

  const { data, loading, error, refresh } = useApiQuery<RNPTemplatesResponse>(
    () => api.rnpTemplates({ year, month }),
    [year, month]
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

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">РНП — Рука на пульсе</h1>
          <p className="text-sm text-text-tertiary mt-0.5">
            Планирование и контроль продаж по менеджерам
          </p>
        </div>
        <Link
          href="/rnp/new"
          className="flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-accent-white text-text-inverse hover:opacity-90 transition-opacity"
        >
          <Plus className="h-3.5 w-3.5" />
          Создать РНП
        </Link>
      </div>

      <div className="flex items-center gap-4 mb-6">
        <div className="flex items-center gap-1">
          <button
            onClick={prevMonth}
            className="p-2 rounded-lg border border-border-default hover:bg-surface-2 transition-colors"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          <div className="px-4 py-2 min-w-[160px] text-center">
            <span className="font-medium">{MONTHS[month - 1]}</span>
            <span className="text-text-tertiary ml-2">{year}</span>
          </div>
          <button
            onClick={nextMonth}
            className="p-2 rounded-lg border border-border-default hover:bg-surface-2 transition-colors"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>
        <button
          onClick={goToToday}
          className="flex items-center gap-2 px-3 py-2 rounded-lg text-xs font-medium border border-border-default hover:bg-surface-2 transition-colors"
        >
          <Calendar className="h-3.5 w-3.5" />
          Сегодня
        </button>
        {data && (
          <span className="text-sm text-text-tertiary ml-auto">
            {data.templates.length} шаблонов
          </span>
        )}
      </div>

      {loading ? (
        <Spinner />
      ) : error ? (
        <ErrorState message={error} onRetry={refresh} />
      ) : data && data.templates.length === 0 ? (
        <div className="rounded-xl border border-border-subtle bg-surface-1 p-12 text-center">
          <Package className="h-12 w-12 text-text-tertiary mx-auto mb-4" />
          <h3 className="text-lg font-medium mb-2">Нет РНП за этот месяц</h3>
          <p className="text-sm text-text-tertiary mb-6">
            Создайте первый план продаж для менеджера
          </p>
          <Link
            href="/rnp/new"
            className="inline-flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium bg-accent-white text-text-inverse hover:opacity-90 transition-opacity"
          >
            <Plus className="h-4 w-4" />
            Создать РНП
          </Link>
        </div>
      ) : data ? (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {data.templates.map((t) => {
            const mpColor = mpColors[t.marketplace.toLowerCase().replace(/\s/g, "")] || "#666";
            const progressPct = t.days_in_month > 0 ? (t.days_passed / t.days_in_month) * 100 : 0;

            return (
              <Link
                key={t.id}
                href={`/rnp/${t.id}`}
                className="rounded-xl border border-border-subtle bg-surface-1 p-5 hover:border-border-default hover:bg-surface-2/50 transition-all group"
              >
                <div className="flex items-start justify-between mb-4">
                  <div>
                    <h3 className="font-medium text-text-primary group-hover:text-accent-white transition-colors">
                      {t.manager_name}
                    </h3>
                    <p className="text-xs text-text-tertiary mt-0.5">{t.project_name}</p>
                  </div>
                  <span
                    className="inline-flex items-center gap-1.5 text-xs px-2 py-1 rounded-full"
                    style={{ backgroundColor: mpColor + "20", color: mpColor }}
                  >
                    <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: mpColor }} />
                    {t.marketplace}
                  </span>
                </div>

                <div className="mb-4">
                  <div className="flex items-center justify-between text-xs mb-1.5">
                    <span className="text-text-secondary">Прогресс месяца</span>
                    <span className="text-text-tertiary">
                      {t.days_passed} / {t.days_in_month} дн.
                    </span>
                  </div>
                  <div className="h-2 bg-surface-3 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-accent-white rounded-full transition-all"
                      style={{ width: `${progressPct}%` }}
                    />
                  </div>
                </div>

                <div className="flex items-center justify-between text-sm">
                  <div className="flex items-center gap-1.5 text-text-secondary">
                    <Package className="h-3.5 w-3.5" />
                    <span>{t.items_count} товаров</span>
                  </div>
                  <div className="flex items-center gap-1.5 text-text-tertiary">
                    <TrendingUp className="h-3.5 w-3.5" />
                    <span>{t.days_left} дн. осталось</span>
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      ) : null}
    </AppLayout>
  );
}
