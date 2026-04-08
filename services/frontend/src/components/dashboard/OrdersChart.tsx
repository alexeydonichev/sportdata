"use client";
import { BarChart, Bar, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";

interface DataPoint {
  date: string;
  orders: number;
  quantity: number;
}

interface Props {
  data: DataPoint[];
}

function CustomTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-lg border border-border-default bg-surface-2 px-3 py-2 shadow-lg">
      <p className="text-xs text-text-tertiary mb-1">{label}</p>
      {payload.map((p: any) => (
        <p key={p.dataKey} className="text-sm font-medium" style={{ color: p.color }}>
          {p.name}: {p.value}
        </p>
      ))}
    </div>
  );
}

export default function OrdersChart({ data }: Props) {
  if (!data?.length) {
    return (
      <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
        <h3 className="text-sm font-medium text-text-secondary mb-4">Заказы и продажи</h3>
        <div className="flex items-center justify-center h-[240px] text-text-tertiary text-sm">
          Нет данных за период
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-medium text-text-secondary">Заказы и продажи</h3>
        <div className="flex items-center gap-4 text-xs text-text-tertiary">
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-white" />Заказы
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-accent-amber" />Штуки
          </span>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={240}>
        <BarChart data={data} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
          <XAxis dataKey="date" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} dy={8} />
          <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} dx={-4} />
          <Tooltip content={<CustomTooltip />} />
          <Bar dataKey="orders" name="Заказы" fill="#FFFFFF" radius={[4, 4, 0, 0]} barSize={12} opacity={0.8} />
          <Bar dataKey="quantity" name="Штуки" fill="#F59E0B" radius={[4, 4, 0, 0]} barSize={12} opacity={0.8} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
