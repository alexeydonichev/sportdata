"use client";
import { useState, use, useEffect } from "react";
import AppLayout from "@/components/layout/AppLayout";
import Spinner from "@/components/ui/Spinner";
import ErrorState from "@/components/ui/ErrorState";
import { api } from "@/lib/api";
import { useApiQuery } from "@/hooks/useApiQuery";
import type { RNPItemsResponse, RNPItem, Manager, RNPDailyStat, RNPChecklistItem } from "@/types/models";
import { formatMoney, formatNumber, cn } from "@/lib/utils";
import { ArrowLeft, Search, TrendingUp, TrendingDown, Minus, Package, Star, X, CheckCircle2, Circle, AlertTriangle, AlertCircle } from "lucide-react";
import Link from "next/link";

const SEASONS: Record<string, string> = {
  winter: "Зима",
  summer: "Лето",
  demi_season: "Деми",
  all_season: "Всесезон",
  new: "Новинка",
  allseason: "Всесезон",
  season: "Сезон",
};

const STATUS_STYLES = {
  under: { bg: "bg-red-500/10", text: "text-red-500" },
  ok: { bg: "bg-yellow-500/10", text: "text-yellow-500" },
  over: { bg: "bg-green-500/10", text: "text-green-500" },
};

const ITEM_STATUS_CONFIG = {
  ok: { label: "OK", bg: "bg-green-500/10", text: "text-green-500", icon: CheckCircle2 },
  risk: { label: "Риск", bg: "bg-yellow-500/10", text: "text-yellow-500", icon: AlertTriangle },
  action: { label: "Действие", bg: "bg-red-500/10", text: "text-red-500", icon: AlertCircle },
};

export default function RNPDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<string>("all");
  const [seasonFilter, setSeasonFilter] = useState<string>("all");
  const [selectedItem, setSelectedItem] = useState<RNPItem | null>(null);
  const [managers, setManagers] = useState<Manager[]>([]);

  const { data, loading, error, refresh } = useApiQuery<RNPItemsResponse>(
    () => api.rnpItems(parseInt(id)),
    [id]
  );

  useEffect(() => {
    api.rnpManagers().then(res => setManagers(res.managers)).catch(() => {});
  }, []);

  const filteredItems = data?.items.filter((item) => {
    if (search) {
      const q = search.toLowerCase();
      if (!item.name.toLowerCase().includes(q) && !item.sku.toLowerCase().includes(q)) return false;
    }
    if (statusFilter !== "all" && item.completion_status !== statusFilter) return false;
    if (seasonFilter !== "all" && item.season !== seasonFilter) return false;
    return true;
  }) || [];

  const summary = filteredItems.reduce(
    (acc, item) => ({
      planQty: acc.planQty + Number(item.plan_orders_qty || 0),
      planRub: acc.planRub + Number(item.plan_orders_rub || 0),
      factQty: acc.factQty + Number(item.fact_orders_qty || 0),
      factRub: acc.factRub + Number(item.fact_orders_rub || 0),
      totalStock: acc.totalStock + Number(item.stock_fbo || 0) + Number(item.stock_fbs || 0),
    }),
    { planQty: 0, planRub: 0, factQty: 0, factRub: 0, totalStock: 0 }
  );

  const overallCompletion = summary.planQty > 0 && data?.template.days_passed
    ? (summary.factQty / (summary.planQty * data.template.days_passed / data.template.days_in_month)) * 100
    : 0;

  const handleManagerChange = async (itemId: number, managerId: number | null) => {
    try {
      await api.rnpUpdateItem(itemId, { manager_id: managerId });
      refresh();
    } catch (e) {
      console.error(e);
    }
  };

  const handleStatusChange = async (itemId: number, status: string) => {
    try {
      await api.rnpUpdateItem(itemId, { item_status: status });
      refresh();
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <AppLayout>
      <div className="flex items-center gap-4 mb-6">
        <Link href="/rnp" className="p-2 rounded-lg border border-border-default hover:bg-surface-2 transition-colors">
          <ArrowLeft className="h-4 w-4" />
        </Link>
        <div className="flex-1">
          <h1 className="text-xl font-semibold tracking-tight">РНП #{id}</h1>
          {data && (
            <p className="text-sm text-text-tertiary mt-0.5">
              {data.template.days_passed} из {data.template.days_in_month} дней · {data.count} товаров
            </p>
          )}
        </div>
      </div>

      {loading ? <Spinner /> : error ? <ErrorState message={error} onRetry={refresh} /> : data ? (
        <>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">План шт.</p>
              <p className="text-lg font-semibold">{formatNumber(summary.planQty)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">План ₽</p>
              <p className="text-lg font-semibold">{formatMoney(summary.planRub)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">Факт шт.</p>
              <p className="text-lg font-semibold">{formatNumber(summary.factQty)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">Факт ₽</p>
              <p className="text-lg font-semibold">{formatMoney(summary.factRub)}</p>
            </div>
            <div className="rounded-xl border border-border-subtle bg-surface-1 p-4">
              <p className="text-xs text-text-tertiary mb-1">Выполнение</p>
              <p className={cn("text-lg font-semibold", overallCompletion >= 100 ? "text-green-500" : overallCompletion >= 80 ? "text-yellow-500" : "text-red-500")}>
                {overallCompletion.toFixed(1)}%
              </p>
            </div>
          </div>

          <div className="flex flex-wrap items-center gap-3 mb-4">
            <div className="relative flex-1 min-w-[200px] max-w-md">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-text-tertiary" />
              <input
                type="text"
                placeholder="Поиск по названию или SKU..."
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                className="w-full pl-10 pr-4 py-2 rounded-lg border border-border-default bg-surface-1 text-sm placeholder:text-text-tertiary focus:outline-none focus:border-accent-white"
              />
            </div>
            <select value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)} className="px-3 py-2 rounded-lg border border-border-default bg-surface-1 text-sm">
              <option value="all">Все статусы</option>
              <option value="under">Отстаёт</option>
              <option value="ok">В норме</option>
              <option value="over">Опережает</option>
            </select>
            <select value={seasonFilter} onChange={(e) => setSeasonFilter(e.target.value)} className="px-3 py-2 rounded-lg border border-border-default bg-surface-1 text-sm">
              <option value="all">Все сезоны</option>
              <option value="winter">Зима</option>
              <option value="summer">Лето</option>
              <option value="demi_season">Деми</option>
              <option value="all_season">Всесезон</option>
            </select>
            <span className="text-sm text-text-tertiary ml-auto">{filteredItems.length} из {data.count}</span>
          </div>

          <div className="rounded-xl border border-border-subtle bg-surface-1 overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-left text-xs text-text-tertiary uppercase tracking-wider border-b border-border-subtle">
                    <th className="px-4 pb-3 pt-4 font-medium">Товар</th>
                    <th className="px-4 pb-3 pt-4 font-medium">Сезон</th>
                    <th className="px-4 pb-3 pt-4 font-medium">Менеджер</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">План</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Факт</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">%</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-center">Чеклист</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-center">Статус</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Остаток</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Оборот</th>
                    <th className="px-4 pb-3 pt-4 font-medium text-right">Рейтинг</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-border-subtle">
                  {filteredItems.map((item) => (
                    <ItemRow 
                      key={item.id} 
                      item={item} 
                      managers={managers}
                      onManagerChange={handleManagerChange}
                      onStatusChange={handleStatusChange}
                      onClick={() => setSelectedItem(item)}
                    />
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      ) : null}

      {selectedItem && (
        <ItemDetailModal
          item={selectedItem}
          managers={managers}
          onClose={() => setSelectedItem(null)}
          onUpdate={refresh}
        />
      )}
    </AppLayout>
  );
}

interface ItemRowProps {
  item: RNPItem;
  managers: Manager[];
  onManagerChange: (itemId: number, managerId: number | null) => void;
  onStatusChange: (itemId: number, status: string) => void;
  onClick: () => void;
}

function ItemRow({ item, managers, onManagerChange, onStatusChange, onClick }: ItemRowProps) {
  const status = STATUS_STYLES[item.completion_status] || STATUS_STYLES.under;
  const itemStatus = ITEM_STATUS_CONFIG[item.item_status as keyof typeof ITEM_STATUS_CONFIG] || ITEM_STATUS_CONFIG.ok;
  const totalStock = item.stock_fbo + item.stock_fbs;
  const StatusIcon = itemStatus.icon;

  return (
    <tr className="hover:bg-surface-2/50 transition-colors cursor-pointer" onClick={onClick}>
      <td className="px-4 py-3">
        <div className="flex items-center gap-3">
          {item.photo_url ? (
            <img src={item.photo_url} alt="" className="h-10 w-10 rounded-lg object-cover bg-surface-2" />
          ) : (
            <div className="h-10 w-10 rounded-lg bg-surface-2 flex items-center justify-center">
              <Package className="h-5 w-5 text-text-tertiary" />
            </div>
          )}
          <div className="min-w-0">
            <p className="font-medium text-text-primary truncate max-w-[200px]">{item.name}</p>
            <p className="text-xs text-text-tertiary">{item.sku}</p>
          </div>
        </div>
      </td>
      <td className="px-4 py-3"><span className="text-xs text-text-secondary">{SEASONS[item.season] || item.season}</span></td>
      <td className="px-4 py-3" onClick={(e) => e.stopPropagation()}>
        <select
          value={item.manager_id || ""}
          onChange={(e) => onManagerChange(item.id, e.target.value ? parseInt(e.target.value) : null)}
          className="px-2 py-1 rounded border border-border-default bg-surface-1 text-xs w-full max-w-[120px]"
        >
          <option value="">—</option>
          {managers.map(m => <option key={m.id} value={m.id}>{m.name}</option>)}
        </select>
      </td>
      <td className="px-4 py-3 text-right">
        <p className="tabular-nums">{formatNumber(item.plan_orders_qty)} шт</p>
        <p className="text-xs text-text-tertiary tabular-nums">{formatMoney(item.plan_orders_rub)}</p>
      </td>
      <td className="px-4 py-3 text-right">
        <p className="tabular-nums">{formatNumber(item.fact_orders_qty)} шт</p>
        <p className="text-xs text-text-tertiary tabular-nums">{formatMoney(item.fact_orders_rub)}</p>
      </td>
      <td className="px-4 py-3 text-right">
        <span className={cn("inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium", status.bg, status.text)}>
          {item.completion_status === "over" && <TrendingUp className="h-3 w-3" />}
          {item.completion_status === "under" && <TrendingDown className="h-3 w-3" />}
          {item.completion_status === "ok" && <Minus className="h-3 w-3" />}
          {Number(item.completion_pct_qty || 0).toFixed(0)}%
        </span>
      </td>
      <td className="px-4 py-3 text-center">
        <span className={cn(
          "inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium",
          item.checklist_total > 0 && item.checklist_done === item.checklist_total 
            ? "bg-green-500/10 text-green-500"
            : item.checklist_done > 0 
              ? "bg-yellow-500/10 text-yellow-500"
              : "bg-surface-2 text-text-tertiary"
        )}>
          {item.checklist_done}/{item.checklist_total}
        </span>
      </td>
      <td className="px-4 py-3 text-center" onClick={(e) => e.stopPropagation()}>
        <select
          value={item.item_status}
          onChange={(e) => onStatusChange(item.id, e.target.value)}
          className={cn("px-2 py-1 rounded text-xs font-medium border-0", itemStatus.bg, itemStatus.text)}
        >
          <option value="ok">OK</option>
          <option value="risk">Риск</option>
          <option value="action">Действие</option>
        </select>
      </td>
      <td className="px-4 py-3 text-right">
        <p className="tabular-nums">{formatNumber(totalStock)}</p>
        <p className="text-xs text-text-tertiary">FBO: {item.stock_fbo} · FBS: {item.stock_fbs}</p>
      </td>
      <td className="px-4 py-3 text-right">
        <p className={cn("tabular-nums", item.turnover_mtd < 7 ? "text-red-500" : item.turnover_mtd < 14 ? "text-yellow-500" : "text-text-primary")}>
          {item.turnover_mtd > 0 ? `${item.turnover_mtd.toFixed(0)} дн.` : "—"}
        </p>
      </td>
      <td className="px-4 py-3 text-right">
        {item.reviews_avg_rating > 0 ? (
          <span className="inline-flex items-center gap-1 text-sm"><Star className="h-3.5 w-3.5 text-yellow-500 fill-yellow-500" />{Number(item.reviews_avg_rating || 0).toFixed(1)}</span>
        ) : <span className="text-text-tertiary">—</span>}
      </td>
    </tr>
  );
}

interface ItemDetailModalProps {
  item: RNPItem;
  managers: Manager[];
  onClose: () => void;
  onUpdate: () => void;
}

function ItemDetailModal({ item, managers, onClose, onUpdate }: ItemDetailModalProps) {
  const [activeTab, setActiveTab] = useState<"daily" | "checklist">("daily");
  const [dailyStats, setDailyStats] = useState<RNPDailyStat[]>([]);
  const [checklist, setChecklist] = useState<RNPChecklistItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadData();
  }, [item.id, activeTab]);

  const loadData = async () => {
    setLoading(true);
    try {
      if (activeTab === "daily") {
        const res = await api.rnpItemDaily(item.id);
        setDailyStats(res.stats || []);
      } else {
        const res = await api.rnpItemChecklist(item.id);
        setChecklist(res.checklist || []);
      }
    } catch (e) {
      console.error(e);
    }
    setLoading(false);
  };

  const handleInitChecklist = async () => {
    try {
      await api.rnpInitChecklist(item.id);
      loadData();
      onUpdate();
    } catch (e) {
      console.error(e);
    }
  };

  const handleToggleChecklist = async (checklistItem: RNPChecklistItem) => {
    try {
      await api.rnpUpdateChecklist(checklistItem.id, { 
        is_done: !checklistItem.is_done,
        comment: checklistItem.comment 
      });
      loadData();
      onUpdate();
    } catch (e) {
      console.error(e);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onClose}>
      <div 
        className="bg-surface-1 rounded-xl border border-border-subtle w-full max-w-3xl max-h-[80vh] overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between p-4 border-b border-border-subtle">
          <div className="flex items-center gap-3">
            {item.photo_url ? (
              <img src={item.photo_url} alt="" className="h-12 w-12 rounded-lg object-cover" />
            ) : (
              <div className="h-12 w-12 rounded-lg bg-surface-2 flex items-center justify-center">
                <Package className="h-6 w-6 text-text-tertiary" />
              </div>
            )}
            <div>
              <h2 className="font-semibold">{item.name}</h2>
              <p className="text-sm text-text-tertiary">{item.sku}</p>
            </div>
          </div>
          <button onClick={onClose} className="p-2 hover:bg-surface-2 rounded-lg transition-colors">
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Tabs */}
        <div className="flex border-b border-border-subtle">
          <button
            onClick={() => setActiveTab("daily")}
            className={cn(
              "px-4 py-3 text-sm font-medium transition-colors",
              activeTab === "daily" ? "text-accent-white border-b-2 border-accent-white" : "text-text-tertiary hover:text-text-primary"
            )}
          >
            Ежедневная статистика
          </button>
          <button
            onClick={() => setActiveTab("checklist")}
            className={cn(
              "px-4 py-3 text-sm font-medium transition-colors",
              activeTab === "checklist" ? "text-accent-white border-b-2 border-accent-white" : "text-text-tertiary hover:text-text-primary"
            )}
          >
            Чеклист ({item.checklist_done}/{item.checklist_total})
          </button>
        </div>

        {/* Content */}
        <div className="p-4 overflow-y-auto max-h-[calc(80vh-140px)]">
          {loading ? (
            <div className="flex justify-center py-8"><Spinner /></div>
          ) : activeTab === "daily" ? (
            <DailyStatsTable stats={dailyStats} />
          ) : (
            <ChecklistView 
              checklist={checklist} 
              onInit={handleInitChecklist}
              onToggle={handleToggleChecklist}
            />
          )}
        </div>
      </div>
    </div>
  );
}

function DailyStatsTable({ stats }: { stats: RNPDailyStat[] }) {
  if (stats.length === 0) {
    return <p className="text-center text-text-tertiary py-8">Нет данных</p>;
  }

  return (
    <table className="w-full text-sm">
      <thead>
        <tr className="text-left text-xs text-text-tertiary uppercase border-b border-border-subtle">
          <th className="pb-2 font-medium">Дата</th>
          <th className="pb-2 font-medium text-right">План шт.</th>
          <th className="pb-2 font-medium text-right">Факт шт.</th>
          <th className="pb-2 font-medium text-right">Δ</th>
          <th className="pb-2 font-medium text-right">%</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-border-subtle">
        {stats.map((stat) => (
          <tr key={stat.id}>
            <td className="py-2">{new Date(stat.date).toLocaleDateString("ru-RU")}</td>
            <td className="py-2 text-right tabular-nums">{stat.plan_qty}</td>
            <td className="py-2 text-right tabular-nums">{stat.orders_qty}</td>
            <td className={cn("py-2 text-right tabular-nums", stat.delta_qty >= 0 ? "text-green-500" : "text-red-500")}>
              {stat.delta_qty >= 0 ? "+" : ""}{stat.delta_qty}
            </td>
            <td className={cn("py-2 text-right tabular-nums", stat.delta_pct >= 100 ? "text-green-500" : "text-red-500")}>
              {stat.delta_pct.toFixed(0)}%
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

interface ChecklistViewProps {
  checklist: RNPChecklistItem[];
  onInit: () => void;
  onToggle: (item: RNPChecklistItem) => void;
}

function ChecklistView({ checklist, onInit, onToggle }: ChecklistViewProps) {
  if (checklist.length === 0) {
    return (
      <div className="text-center py-8">
        <p className="text-text-tertiary mb-4">Чеклист ещё не создан</p>
        <button
          onClick={onInit}
          className="px-4 py-2 bg-accent-white text-black rounded-lg text-sm font-medium hover:bg-accent-white/90 transition-colors"
        >
          Создать чеклист
        </button>
      </div>
    );
  }

  return (
    <div className="space-y-2">
      {checklist.map((item) => (
        <div
          key={item.id}
          className={cn(
            "flex items-center gap-3 p-3 rounded-lg border transition-colors cursor-pointer",
            item.is_done ? "bg-green-500/5 border-green-500/20" : "bg-surface-2 border-border-subtle hover:border-border-default"
          )}
          onClick={() => onToggle(item)}
        >
          {item.is_done ? (
            <CheckCircle2 className="h-5 w-5 text-green-500 flex-shrink-0" />
          ) : (
            <Circle className="h-5 w-5 text-text-tertiary flex-shrink-0" />
          )}
          <div className="flex-1 min-w-0">
            <p className={cn("font-medium", item.is_done && "line-through text-text-tertiary")}>{item.name}</p>
            {item.is_done && item.done_by && (
              <p className="text-xs text-text-tertiary mt-0.5">
                {item.done_by} · {item.done_at && new Date(item.done_at).toLocaleDateString("ru-RU")}
              </p>
            )}
            {item.comment && (
              <p className="text-xs text-text-secondary mt-1">{item.comment}</p>
            )}
          </div>
        </div>
      ))}
    </div>
  );
}
