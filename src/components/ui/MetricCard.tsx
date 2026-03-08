import { cn } from "@/lib/utils";
import { TrendingUp, TrendingDown, Minus } from "lucide-react";

interface MetricCardProps {
  label: string;
  value: string;
  change?: number | null;
  subtitle?: string;
  className?: string;
  /** For costs: growth is bad (red), decrease is good (green) */
  invertColor?: boolean;
}

export default function MetricCard({ label, value, change, subtitle, className, invertColor }: MetricCardProps) {
  const hasChange = change !== undefined && change !== null;

  function changeColor(val: number) {
    if (val === 0) return "text-text-tertiary";
    const positive = invertColor ? val < 0 : val > 0;
    return positive ? "text-accent-green" : "text-accent-red";
  }

  return (
    <div className={cn("rounded-xl border border-border-subtle bg-surface-1 p-5 transition-colors hover:border-border-default", className)}>
      <p className="text-xs font-medium text-text-secondary uppercase tracking-wider">{label}</p>
      <p className="mt-2 text-2xl font-semibold tabular-nums tracking-tight">{value}</p>
      <div className="mt-2 flex items-center gap-2">
        {hasChange && (
          <span className={cn("inline-flex items-center gap-0.5 text-xs font-medium tabular-nums", changeColor(change))}>
            {change > 0 && <TrendingUp className="h-3 w-3" />}
            {change < 0 && <TrendingDown className="h-3 w-3" />}
            {change === 0 && <Minus className="h-3 w-3" />}
            {change > 0 ? "+" : ""}{change.toFixed(1)}%
          </span>
        )}
        {subtitle && <span className="text-xs text-text-tertiary">{subtitle}</span>}
      </div>
    </div>
  );
}
