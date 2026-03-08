"use client";
import { mpColors } from "@/lib/utils";

const MARKETPLACES = [
  { slug: "all", label: "Все МП" },
  { slug: "wb", label: "Wildberries" },
  { slug: "ozon", label: "Ozon" },
  { slug: "yandex_market", label: "Яндекс Маркет" },
];

interface Props {
  value: string;
  onChange: (v: string) => void;
}

export default function MarketplaceFilter({ value, onChange }: Props) {
  return (
    <div className="flex items-center gap-1.5">
      {MARKETPLACES.map((mp) => {
        const active = value === mp.slug;
        const color = mpColors[mp.slug];
        return (
          <button
            key={mp.slug}
            onClick={() => onChange(mp.slug)}
            className={
              "flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium transition-all border " +
              (active
                ? "bg-text-primary text-surface-0 border-text-primary"
                : "bg-surface-1 text-text-secondary border-border-default hover:border-border-strong hover:text-text-primary")
            }
          >
            {color && (
              <span
                className="h-2 w-2 rounded-full shrink-0"
                style={{ backgroundColor: active ? "currentColor" : color }}
              />
            )}
            {mp.label}
          </button>
        );
      })}
    </div>
  );
}
