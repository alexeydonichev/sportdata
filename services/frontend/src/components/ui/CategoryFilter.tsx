"use client";
import { useEffect, useState, useRef } from "react";
import { api, Category } from "@/lib/api";
import { Tag, ChevronDown, Check } from "lucide-react";

interface Props {
  value: string;
  onChange: (v: string) => void;
}

export default function CategoryFilter({ value, onChange }: Props) {
  const [categories, setCategories] = useState<Category[]>([]);
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    api.categories().then(setCategories).catch(console.error);
  }, []);

  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const totalCount = categories.length > 0 
    ? categories.reduce((s, c) => s + c.products_count, 0) 
    : 0;

  const selected = value === "all" 
    ? null
    : categories.find(c => c.slug === value);

  const displayName = value === "all" 
    ? `Все (${totalCount})` 
    : (selected ? selected.name : "Категория");

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-2 px-3 py-1.5 rounded-lg text-xs font-medium transition-all border bg-surface-1 text-text-secondary border-border-default hover:border-border-strong hover:text-text-primary"
      >
        <Tag className="h-3 w-3" />
        <span className="max-w-[120px] truncate">{displayName}</span>
        <ChevronDown className={"h-3 w-3 transition-transform " + (open ? "rotate-180" : "")} />
      </button>

      {open && (
        <div className="absolute top-full right-0 mt-1 w-64 max-h-80 overflow-y-auto rounded-xl border border-border-default bg-surface-1 shadow-lg z-50">
          <div className="p-1">
            <button
              onClick={() => { onChange("all"); setOpen(false); }}
              className={"w-full flex items-center justify-between px-3 py-2 rounded-lg text-sm transition-colors " + 
                (value === "all" ? "bg-surface-2 text-text-primary" : "text-text-secondary hover:bg-surface-2 hover:text-text-primary")}
            >
              <span>Все категории</span>
              <div className="flex items-center gap-2">
                <span className="text-xs text-text-tertiary">{String(totalCount)}</span>
                {value === "all" && <Check className="h-3.5 w-3.5 text-accent-green" />}
              </div>
            </button>
            
            <div className="h-px bg-border-subtle my-1" />
            
            {categories.map((c) => (
              <button
                key={c.slug}
                onClick={() => { onChange(c.slug); setOpen(false); }}
                className={"w-full flex items-center justify-between px-3 py-2 rounded-lg text-sm transition-colors " + 
                  (value === c.slug ? "bg-surface-2 text-text-primary" : "text-text-secondary hover:bg-surface-2 hover:text-text-primary")}
              >
                <span className="truncate">{c.name}</span>
                <div className="flex items-center gap-2">
                  <span className="text-xs text-text-tertiary">{String(c.products_count)}</span>
                  {value === c.slug && <Check className="h-3.5 w-3.5 text-accent-green" />}
                </div>
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
