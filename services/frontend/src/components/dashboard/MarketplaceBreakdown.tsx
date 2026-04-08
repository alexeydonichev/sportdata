"use client";

import { MarketplaceStats } from "@/lib/api";
import { formatMoney, mpColors, mpNames, formatPercent } from "@/lib/utils";

interface Props {
  data: MarketplaceStats[];
  totalRevenue: number;
}

export default function MarketplaceBreakdown({ data, totalRevenue }: Props) {
  const sorted = [...data].sort((a, b) => b.revenue - a.revenue);
  return (
    <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
      <h3 className="text-sm font-medium text-text-primary mb-4">По маркетплейсам</h3>
      {totalRevenue === 0 ? (
        <div className="py-8 text-center text-sm text-text-tertiary">Нет данных за период</div>
      ) : (
        <div className="space-y-4">
          {sorted.map((mp) => {
            const color = mpColors[mp.marketplace] || "#666";
            const pct = totalRevenue > 0 ? (mp.revenue / totalRevenue) * 100 : 0;
            return (
              <div key={mp.marketplace}>
                <div className="flex items-center justify-between mb-1.5">
                  <div className="flex items-center gap-2">
                    <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: color }} />
                    <span className="text-sm text-text-primary">{mpNames[mp.marketplace] || mp.marketplace}</span>
                  </div>
                  <div className="flex items-center gap-3">
                    <span className="text-sm font-medium tabular-nums">{formatMoney(mp.revenue)}</span>
                    <span className="text-xs text-text-tertiary tabular-nums w-12 text-right">{formatPercent(pct)}</span>
                  </div>
                </div>
                <div className="h-1 rounded-full bg-surface-3 overflow-hidden">
                  <div className="h-full rounded-full transition-all duration-500" style={{ width: pct + "%", backgroundColor: color }} />
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
