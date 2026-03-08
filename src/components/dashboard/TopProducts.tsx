"use client";

import { TopProduct } from "@/lib/api";
import { formatMoney, formatNumber } from "@/lib/utils";

export default function TopProducts({ data }: { data: TopProduct[] | null }) {
  return (
    <div className="rounded-xl border border-border-subtle bg-surface-1 p-5">
      <h3 className="text-sm font-medium text-text-primary mb-4">Топ товаров</h3>
      {!data || data.length === 0 ? (
        <div className="py-8 text-center text-sm text-text-tertiary">Нет данных за период</div>
      ) : (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider">
              <th className="pb-3 font-medium">Товар</th>
              <th className="pb-3 font-medium text-right">Кол-во</th>
              <th className="pb-3 font-medium text-right">Выручка</th>
              <th className="pb-3 font-medium text-right">Прибыль</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-border-subtle">
            {data.map((p, i) => (
              <tr key={p.product_id} className="hover:bg-surface-2/50 transition-colors">
                <td className="py-3 pr-4">
                  <div className="flex items-center gap-3">
                    <span className="text-xs text-text-tertiary tabular-nums w-4">{i + 1}</span>
                    <div>
                      <p className="text-text-primary font-medium truncate max-w-[240px]">{p.name}</p>
                      <p className="text-xs text-text-tertiary mt-0.5">{p.sku}</p>
                    </div>
                  </div>
                </td>
                <td className="py-3 text-right tabular-nums text-text-secondary">{formatNumber(p.quantity)}</td>
                <td className="py-3 text-right tabular-nums font-medium">{formatMoney(p.revenue)}</td>
                <td className="py-3 text-right tabular-nums text-accent-green font-medium">{formatMoney(p.profit)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
