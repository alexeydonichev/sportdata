import { forwardRef, ButtonHTMLAttributes } from "react";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "default" | "outline" | "ghost" | "destructive";
  size?: "default" | "sm" | "lg" | "icon";
}

const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className = "", variant = "default", size = "default", ...props }, ref) => {
    const base = "inline-flex items-center justify-center rounded-xl font-medium transition-colors focus:outline-none disabled:opacity-50 disabled:pointer-events-none";
    const variants: Record<string, string> = {
      default: "bg-accent-blue text-white hover:bg-accent-blue/90",
      outline: "border border-border-default bg-transparent hover:bg-surface-2 text-text-primary",
      ghost: "hover:bg-surface-2 text-text-secondary",
      destructive: "bg-accent-red text-white hover:bg-accent-red/90",
    };
    const sizes: Record<string, string> = {
      default: "h-10 px-4 py-2 text-sm",
      sm: "h-8 px-3 text-xs",
      lg: "h-12 px-6 text-base",
      icon: "h-10 w-10",
    };
    return (
      <button ref={ref} className={`${base} ${variants[variant] || ""} ${sizes[size] || ""} ${className}`} {...props} />
    );
  }
);
Button.displayName = "Button";

export { Button };
