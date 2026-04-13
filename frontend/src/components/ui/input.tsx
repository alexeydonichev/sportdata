import { forwardRef, InputHTMLAttributes } from "react";

const Input = forwardRef<HTMLInputElement, InputHTMLAttributes<HTMLInputElement>>(
  ({ className = "", ...props }, ref) => (
    <input
      ref={ref}
      className={`flex h-10 w-full rounded-xl border border-border-default bg-surface-0 px-3 py-2 text-sm text-text-primary placeholder:text-text-tertiary focus:outline-none focus:ring-2 focus:ring-accent-blue/30 focus:border-accent-blue disabled:opacity-50 ${className}`}
      {...props}
    />
  )
);
Input.displayName = "Input";

export { Input };
