"use client";

const PERIODS = [
  { key: "today", label: "Сегодня" },
  { key: "7d", label: "7 дней" },
  { key: "30d", label: "30 дней" },
  { key: "90d", label: "90 дней" },
  { key: "180d", label: "180 дней" },
  { key: "365d", label: "365 дней" },
];

interface Props {
  value: string;
  onChange: (v: string) => void;
}

export default function PeriodSelector({ value, onChange }: Props) {
  return (
    <div className="flex items-center rounded-lg border border-border-default bg-surface-1 p-0.5">
      {PERIODS.map((p) => (
        <button
          key={p.key}
          onClick={() => onChange(p.key)}
          className={
            "px-3 py-1.5 text-xs font-medium rounded-md transition-colors " +
            (value === p.key
              ? "bg-surface-3 text-text-primary"
              : "text-text-tertiary hover:text-text-secondary")
          }
        >
          {p.label}
        </button>
      ))}
    </div>
  );
}
