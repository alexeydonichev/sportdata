"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import {
  BarChart3, Package, ShoppingCart, Warehouse, RefreshCw, LogOut, Settings, X,
  PieChart, Bell, FileText, Calculator, Users, RotateCcw, Globe, DollarSign, Target,
} from "lucide-react";
import { api } from "@/lib/api";
import { useEffect, useState } from "react";

const nav = [
  { name: "Дашборд", href: "/", icon: BarChart3 },
  { name: "Товары", href: "/products", icon: Package },
  { name: "Продажи", href: "/sales", icon: ShoppingCart },
  { name: "Остатки", href: "/inventory", icon: Warehouse },
  { name: "P&L Отчёт", href: "/analytics/pnl", icon: FileText },
  { name: "Юнит-экономика", href: "/analytics/unit-economics", icon: Calculator },
  { name: "ABC-анализ", href: "/analytics/abc", icon: PieChart },
  { name: "Возвраты", href: "/analytics/returns", icon: RotateCcw },
  { name: "Финансы", href: "/analytics/finance", icon: DollarSign },
  { name: "География", href: "/analytics/geography", icon: Globe },
  { name: "РНП", href: "/rnp", icon: Target },
  { name: "Синхронизация", href: "/sync", icon: RefreshCw },
  { name: "Уведомления", href: "/notifications", icon: Bell },
];

const ADMIN_ROLES = ["owner", "admin"];

export default function Sidebar({ onClose }: { onClose?: () => void }) {
  const pathname = usePathname();
  const user = typeof window !== "undefined" ? JSON.parse(localStorage.getItem("yf_user") || "{}") : {};
  const [alertCount, setAlertCount] = useState(0);
  const isAdmin = ADMIN_ROLES.includes(user.role);

  useEffect(() => {
    api.notifications().then(r => setAlertCount(r.summary.critical + r.summary.warning)).catch(() => {});
  }, []);

  return (
    <aside className="w-56 h-full border-r border-border-subtle bg-surface-0 flex flex-col">
      <div className="px-5 py-5 border-b border-border-subtle flex items-center justify-between">
        <Link href="/" onClick={onClose}>
          <h1 className="text-lg font-bold tracking-tight">Your<span className="font-light">Fit</span></h1>
          <p className="text-[11px] text-text-tertiary mt-0.5 tracking-wide uppercase">Analytics</p>
        </Link>
        {onClose && (
          <button onClick={onClose} className="lg:hidden p-1.5 rounded-lg text-text-tertiary hover:text-text-primary hover:bg-surface-2 transition-colors">
            <X className="h-4 w-4" />
          </button>
        )}
      </div>
      <nav className="flex-1 px-3 py-4 space-y-0.5 overflow-y-auto">
        {nav.map(item => {
          const active = pathname === item.href || (item.href !== "/" && pathname.startsWith(item.href));
          const showBadge = item.href === "/notifications" && alertCount > 0;
          return (
            <Link key={item.href} href={item.href} onClick={onClose} className={cn(
              "flex items-center gap-3 rounded-md px-2.5 py-2 text-[13px] transition-colors",
              active ? "bg-surface-3 text-text-primary" : "text-text-secondary hover:text-text-primary hover:bg-surface-2"
            )}>
              <item.icon className="h-4 w-4" strokeWidth={1.5} />
              <span className="flex-1">{item.name}</span>
              {showBadge && <span className="min-w-[18px] h-[18px] flex items-center justify-center rounded-full bg-accent-red text-white text-[10px] font-bold px-1">{alertCount > 99 ? "99+" : alertCount}</span>}
            </Link>
          );
        })}
      </nav>
      <div className="border-t border-border-subtle px-3 py-3 space-y-1">
        {isAdmin && (
          <Link href="/team" onClick={onClose} className={cn("flex items-center gap-3 rounded-md px-2.5 py-2 text-[13px] transition-colors",pathname==="/team"?"bg-surface-3 text-text-primary":"text-text-secondary hover:text-text-primary hover:bg-surface-2")}>
            <Users className="h-4 w-4" strokeWidth={1.5} /> Команда
          </Link>
        )}
        <Link href="/settings" onClick={onClose} className={cn("flex items-center gap-3 rounded-md px-2.5 py-2 text-[13px] transition-colors",pathname==="/settings"?"bg-surface-3 text-text-primary":"text-text-secondary hover:text-text-primary hover:bg-surface-2")}>
          <Settings className="h-4 w-4" strokeWidth={1.5} /> Настройки
        </Link>
        <button onClick={() => { api.clearToken(); window.location.href = "/login"; }} className="w-full flex items-center gap-3 rounded-md px-2.5 py-2 text-[13px] text-text-secondary hover:text-accent-red hover:bg-surface-2 transition-colors">
          <LogOut className="h-4 w-4" strokeWidth={1.5} /> Выйти
        </button>
        {user.email && (
          <div className="px-2.5 pt-2 border-t border-border-subtle mt-2">
            <p className="text-xs text-text-primary truncate">{user.first_name} {user.last_name}</p>
            <p className="text-[11px] text-text-tertiary truncate">{user.email}</p>
          </div>
        )}
      </div>
    </aside>
  );
}
