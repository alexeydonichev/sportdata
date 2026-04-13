import { HTMLAttributes } from "react";

interface BadgeProps extends HTMLAttributes<HTMLSpanElement> {
  variant?: "default" | "secondary" | "destructive" | "outline";
}

function Badge({ className = "", variant = "default", ...props }: BadgeProps) {
  const base = "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium transition-colors";
  const variants: Record<string, string> = {
    default: "bg-accent-blue/15 text-accent-blue",
    secondary: "bg-surface-3 text-text-secondary",
    destructive: "bg-accent-red/15 text-accent-red",
    outline: "border border-border-default text-text-secondary",
  };
  return <span className={`${base} ${variants[variant] || variants.default} ${className}`} {...props} />;
}

export { Badge };
