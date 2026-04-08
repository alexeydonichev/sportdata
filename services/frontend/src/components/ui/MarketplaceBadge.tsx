import { mpColors, mpNames } from "@/lib/utils";

export default function MarketplaceBadge({ marketplace }: { marketplace: string }) {
  const color = mpColors[marketplace] || "#666";
  const name = mpNames[marketplace] || marketplace;
  return (
    <span className="inline-flex items-center gap-1.5 rounded-md border border-border-subtle px-2 py-0.5 text-[11px] font-medium">
      <span className="h-2 w-2 rounded-full" style={{ backgroundColor: color }} />
      {name}
    </span>
  );
}
