"use client";
import { useEffect, useState } from "react";
import { api, Category } from "@/lib/api";
import { formatMoney } from "@/lib/utils";
import { Tag } from "lucide-react";

interface Props {
  value: string;
  onChange: (v: string) => void;
}

export default function CategoryFilter({ value, onChange }: Props) {
  const [categories, setCategories] = useState<Category[]>([]);

  useEffect(() => {
    api.categories().then(setCategories).catch(console.error);
  }, []);

  return (
    <div className="flex items-center gap-2 flex-wrap">
      <button
        onClick={() => onChange("all")}
        className={
          "flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all border " +
          (value === "all"
            ? "bg-accent-white text-text-inverse border-accent-white"
            : "bg-surface-1 text-text-secondary border-border-default hover:border-border-strong hover:text-text-primary")
        }
      >
        <Tag className="h-3 w-3" />
        Все ({categories.reduce((s, c) => s + c.product_count, 0)})
      </button>
      {categories.map((c) => (
        <button
          key={c.slug}
          onClick={() => onChange(c.slug)}
          className={
            "px-3 py-1.5 rounded-lg text-xs font-medium transition-all border " +
            (value === c.slug
              ? "bg-accent-white text-text-inverse border-accent-white"
              : "bg-surface-1 text-text-secondary border-border-default hover:border-border-strong hover:text-text-primary")
          }
        >
          {c.name} ({c.product_count})
        </button>
      ))}
    </div>
  );
}
