"use client";
import { AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid } from "recharts";
import { formatDate } from "@/lib/utils";

interface DataPoint {
  date: string;
  revenue: number;
  profit: number;
}

interface Props {
  data: DataPoint[];
}

function formatK(v: number) {
  if (v >= 1000000) return (v / 1000000).toFixed(1) + "М";
  if (v >= 1000) return (v / 1000).toFixed(0) + "К";
  return v.toString();
}

function CustomTooltip({ active, payload, label }: any) {
  if (!active || !payload?.length) return null;
  return (
    <div className="rounded-lg border border-border-default bg-surface-2 px-3 py-2 shadow-lg">
      <p className="text-xs text-text-tertiary mb-1">{formatDate(label)}</p>
      {payload.map((p: any) => (
        <p key={p.dataKey} className="text-sm font-medium" style={{ color: p.color }}>
          {p.name}: {formatK(p.value)} ₽
        </p>
      ))}
    </div>
  );
}

export default function RevenueChart({ data }: Props) {
  if (!data?.length) {
    return (
      <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
        <h3 className="text-sm font-medium text-text-secondary mb-4">Выручка и прибыль</h3>
        <div className="flex items-center justify-center h-[240px] text-text-tertiary text-sm">
          Нет данных за период
        </div>
      </div>
    );
  }

  const formatted = data.map(d => ({
    ...d,
    label: formatDate(d.date),
  }));

  return (
    <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-medium text-text-secondary">Выручка и прибыль</h3>
        <div className="flex items-center gap-4 text-xs text-text-tertiary">
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: "#F97316" }} />Выручка
          </span>
          <span className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-accent-green" />Прибыль
          </span>
        </div>
      </div>
      <ResponsiveContainer width="100%" height={240}>
        <AreaChart data={formatted} margin={{ top: 4, right: 4, bottom: 0, left: 0 }}>
          <defs>
            <linearGradient id="gRevenue" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#F97316" stopOpacity={0.2} />
              <stop offset="100%" stopColor="#F97316" stopOpacity={0} />
            </linearGradient>
            <linearGradient id="gProfit" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#22C55E" stopOpacity={0.15} />
              <stop offset="100%" stopColor="#22C55E" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
          <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} dy={8} interval="preserveStartEnd" />
          <YAxis axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--color-text-tertiary)" }} tickFormatter={formatK} dx={-4} />
          <Tooltip content={<CustomTooltip />} />
          <Area type="monotone" dataKey="revenue" name="Выручка" stroke="#F97316" strokeWidth={2} fill="url(#gRevenue)" dot={false} activeDot={{ r: 4, fill: "#F97316" }} />
          <Area type="monotone" dataKey="profit" name="Прибыль" stroke="#22C55E" strokeWidth={2} fill="url(#gProfit)" dot={false} activeDot={{ r: 4, fill: "#22C55E" }} />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
