"use client";
import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import AppLayout from "@/components/layout/AppLayout";
import PeriodSelector from "@/components/ui/PeriodSelector";
import MetricCard from "@/components/ui/MetricCard";
import { api } from "@/lib/api";
import type { ProductDetail } from "@/types/models";
import { ArrowLeft, Pencil, Save, X, Image as ImageIcon, Box, Globe } from "lucide-react";
import { formatMoney, formatNumber, formatPercent, formatDate, mpColors } from "@/lib/utils";
import Link from "next/link";
import {
  AreaChart, Area, BarChart, Bar, LineChart, Line,
  XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from "recharts";

function formatK(v: number) {
  if (Math.abs(v) >= 1e6) return (v/1e6).toFixed(1)+"M";
  if (Math.abs(v) >= 1e3) return (v/1e3).toFixed(0)+"K";
  return v.toString();
}

function FinRow({label,value,pct,color}:{label:string;value:number;pct?:number;color?:string}) {
  return (
    <div className="flex items-center justify-between py-1.5">
      <span className="text-xs text-text-secondary">{label}</span>
      <div className="flex items-center gap-2">
        {pct !== undefined && <span className="text-[11px] text-text-tertiary tabular-nums">{pct.toFixed(1)}%</span>}
        <span className={"text-xs font-medium tabular-nums "+(color||"")}>{formatMoney(value)}</span>
      </div>
    </div>
  );
}

export default function ProductDetailPage() {
  const params = useParams();
  const id = params.id as string;
  const [data, setData] = useState<ProductDetail | null>(null);
  const [period, setPeriod] = useState("90d");
  const [loading, setLoading] = useState(true);
  const [chartMode, setChartMode] = useState<"revenue"|"quantity">("revenue");
  const [editingCost, setEditingCost] = useState(false);
  const [costValue, setCostValue] = useState("");
  const [costSaving, setCostSaving] = useState(false);

  const startEditCost = () => { setCostValue(String(data?.product.cost_price||0)); setEditingCost(true); };
  const saveCost = async () => {
    const val = parseFloat(costValue);
    if (isNaN(val)||val<0) return;
    setCostSaving(true);
    try { await api.updateProduct(id,{cost_price:val}); setData(await api.productDetail(id,period)); setEditingCost(false); }
    catch(e){console.error(e)} finally{setCostSaving(false)}
  };

  useEffect(() => {
    setLoading(true);
    api.productDetail(id,period).then(setData).catch(console.error).finally(()=>setLoading(false));
  }, [id, period]);

  return (
    <AppLayout>
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Link href="/products" className="p-2 rounded-lg hover:bg-surface-2 transition-colors text-text-secondary hover:text-text-primary">
            <ArrowLeft className="h-4 w-4" />
          </Link>
          <div className="flex items-center gap-4">
            {data?.product.image_url ? (
              <img src={data.product.image_url} alt="" className="h-12 w-12 rounded-xl object-cover border border-border-subtle" />
            ) : (
              <div className="h-12 w-12 rounded-xl bg-surface-2 border border-border-subtle flex items-center justify-center">
                <ImageIcon className="h-5 w-5 text-text-tertiary" />
              </div>
            )}
            <div>
              <h1 className="text-xl font-semibold tracking-tight">{data?.product.name||"Загрузка..."}</h1>
              <div className="flex items-center gap-2 mt-0.5">
                <span className="text-sm text-text-tertiary">{data?.product.sku}</span>
                {data?.product.brand && <span className="text-xs px-1.5 py-0.5 rounded bg-surface-2 text-text-secondary">{data.product.brand}</span>}
                {data?.product.category && <span className="text-xs text-text-tertiary">· {data.product.category}</span>}
                {data?.product.nm_id && <span className="text-[11px] text-text-tertiary">· nm {data.product.nm_id}</span>}
              </div>
            </div>
          </div>
        </div>
        <PeriodSelector value={period} onChange={setPeriod} />
      </div>

      {loading ? (
        <div className="flex items-center justify-center py-20">
          <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
        </div>
      ) : data ? (
        <div className="space-y-6 animate-fade-in">
          {(data.product.dimensions||data.product.weight_g) && (
            <div className="flex items-center gap-4 px-4 py-2.5 rounded-xl border border-border-subtle bg-surface-1">
              <Box className="h-4 w-4 text-text-tertiary" />
              {data.product.dimensions && <span className="text-xs text-text-secondary">{data.product.dimensions.length}×{data.product.dimensions.width}×{data.product.dimensions.height} мм</span>}
              {data.product.weight_g && <span className="text-xs text-text-secondary">{data.product.weight_g} г</span>}
              {data.product.retail_price>0 && <span className="text-xs text-text-tertiary">РРЦ: {formatMoney(data.product.retail_price)}</span>}
              {data.product.discount_price>0 && <span className="text-xs text-text-tertiary">Со скидкой: {formatMoney(data.product.discount_price)}</span>}
            </div>
          )}

          <div className="grid grid-cols-5 gap-4">
            <MetricCard label="Выручка" value={formatMoney(data.metrics.total_revenue)} change={data.changes.revenue} />
            <MetricCard label="Прибыль" value={formatMoney(data.metrics.total_profit)} change={data.changes.profit} subtitle={"Маржа "+formatPercent(data.metrics.margin_pct)} />
            <MetricCard label="Продано" value={formatNumber(data.metrics.total_sold)} change={data.changes.quantity} />
            <MetricCard label="Ср. цена" value={formatMoney(data.metrics.avg_price)} subtitle={
              editingCost ? (
                <span className="flex items-center gap-1 mt-0.5">
                  <input type="number" value={costValue} onChange={e=>setCostValue(e.target.value)}
                    onKeyDown={e=>{if(e.key==="Enter")saveCost();if(e.key==="Escape")setEditingCost(false)}}
                    className="w-20 bg-surface-0 border border-border-default rounded px-1.5 py-0.5 text-xs text-text-primary focus:outline-none focus:border-text-secondary tabular-nums"
                    autoFocus disabled={costSaving} />
                  <button onClick={saveCost} disabled={costSaving} className="p-0.5 rounded hover:bg-surface-3 text-accent-green"><Save className="h-3 w-3" /></button>
                  <button onClick={()=>setEditingCost(false)} className="p-0.5 rounded hover:bg-surface-3 text-text-tertiary"><X className="h-3 w-3" /></button>
                </span>
              ) : (
                <span className="inline-flex items-center gap-1 cursor-pointer group" onClick={startEditCost}>
                  {"Себест: "+formatMoney(data.product.cost_price)}
                  <Pencil className="h-2.5 w-2.5 text-text-tertiary opacity-0 group-hover:opacity-100 transition-opacity" />
                </span>
              )
            } />
            <MetricCard label="Возвраты" value={formatNumber(data.metrics.total_returns)} subtitle={formatPercent(data.metrics.return_pct)} />
          </div>

          <div className="grid grid-cols-3 gap-6">
            <div className="col-span-2 rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-medium text-text-secondary">Динамика продаж</h3>
                <div className="flex items-center rounded-lg border border-border-default bg-surface-1 p-0.5">
                  {(["revenue","quantity"] as const).map(mode=>(
                    <button key={mode} onClick={()=>setChartMode(mode)}
                      className={"px-3 py-1 text-xs font-medium rounded-md transition-colors "+(chartMode===mode?"bg-surface-3 text-text-primary":"text-text-tertiary hover:text-text-secondary")}>
                      {mode==="revenue"?"Выручка":"Количество"}
                    </button>
                  ))}
                </div>
              </div>
              <ResponsiveContainer width="100%" height={280}>
                {chartMode==="revenue" ? (
                  <AreaChart data={data.chart.map(d=>({...d,label:formatDate(d.date)}))} margin={{top:4,right:4,bottom:0,left:0}}>
                    <defs>
                      <linearGradient id="gPdRev" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#F97316" stopOpacity={0.2}/><stop offset="100%" stopColor="#F97316" stopOpacity={0}/></linearGradient>
                      <linearGradient id="gPdProf" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#22C55E" stopOpacity={0.15}/><stop offset="100%" stopColor="#22C55E" stopOpacity={0}/></linearGradient>
                    </defs>
                    <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                    <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{fontSize:11,fill:"var(--color-text-tertiary)"}} interval="preserveStartEnd" />
                    <YAxis axisLine={false} tickLine={false} tick={{fontSize:11,fill:"var(--color-text-tertiary)"}} tickFormatter={formatK} />
                    <Tooltip contentStyle={{backgroundColor:"var(--color-surface-2)",border:"1px solid var(--color-border-default)",borderRadius:"8px",fontSize:"12px"}} />
                    <Area type="monotone" dataKey="revenue" name="Выручка" stroke="#F97316" strokeWidth={2} fill="url(#gPdRev)" dot={false} />
                    <Area type="monotone" dataKey="profit" name="Прибыль" stroke="#22C55E" strokeWidth={2} fill="url(#gPdProf)" dot={false} />
                  </AreaChart>
                ) : (
                  <BarChart data={data.chart.map(d=>({...d,label:formatDate(d.date)}))} margin={{top:4,right:4,bottom:0,left:0}}>
                    <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                    <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{fontSize:11,fill:"var(--color-text-tertiary)"}} interval="preserveStartEnd" />
                    <YAxis axisLine={false} tickLine={false} tick={{fontSize:11,fill:"var(--color-text-tertiary)"}} />
                    <Tooltip contentStyle={{backgroundColor:"var(--color-surface-2)",border:"1px solid var(--color-border-default)",borderRadius:"8px",fontSize:"12px"}} />
                    <Bar dataKey="quantity" name="Продажи" fill="#6366F1" radius={[3,3,0,0]} />
                    <Bar dataKey="orders" name="Заказы" fill="#F59E0B" radius={[3,3,0,0]} opacity={0.6} />
                  </BarChart>
                )}
              </ResponsiveContainer>
            </div>

            <div className="space-y-4">
              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-3">Финансовая разбивка</h3>
                <div className="space-y-0.5">
                  <FinRow label="Выручка (розница)" value={data.finance.revenue} />
                  <FinRow label="К выплате (for_pay)" value={data.finance.for_pay} color="text-accent-blue" />
                  <div className="border-t border-border-subtle my-2" />
                  <FinRow label="Комиссия МП" value={data.finance.commission} pct={data.finance.avg_commission_pct} color="text-accent-amber" />
                  <FinRow label="СПП (скидка)" value={0} pct={data.finance.avg_spp_pct} color="text-text-tertiary" />
                  <FinRow label="Логистика" value={data.finance.logistics} color="text-accent-amber" />
                  <FinRow label="Эквайринг" value={data.finance.acquiring} color="text-accent-amber" />
                  <FinRow label="Хранение" value={data.finance.storage} color="text-accent-amber" />
                  {data.finance.penalty>0 && <FinRow label="Штрафы" value={data.finance.penalty} color="text-accent-red" />}
                  {data.finance.deduction>0 && <FinRow label="Удержания" value={data.finance.deduction} color="text-accent-red" />}
                  {data.finance.acceptance>0 && <FinRow label="Приёмка" value={data.finance.acceptance} color="text-accent-amber" />}
                  {data.finance.return_logistics>0 && <FinRow label="Обратная логистика" value={data.finance.return_logistics} color="text-accent-amber" />}
                  <div className="border-t border-border-subtle my-2" />
                  <FinRow label="Себестоимость" value={data.finance.cogs} color="text-text-secondary" />
                  <div className="border-t border-border-subtle my-2" />
                  <div className="flex items-center justify-between py-1.5">
                    <span className="text-xs font-medium">Чистая прибыль</span>
                    <span className={"text-sm font-bold tabular-nums "+(data.finance.net_profit>=0?"text-accent-green":"text-accent-red")}>{formatMoney(data.finance.net_profit)}</span>
                  </div>
                </div>
              </div>

              {data.abc && (
                <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                  <h3 className="text-sm font-medium text-text-secondary mb-3">ABC-грейд</h3>
                  <div className="flex items-center gap-4">
                    <span className={"text-4xl font-bold "+(data.abc.grade==="A"?"text-accent-green":data.abc.grade==="B"?"text-accent-amber":"text-accent-red")}>{data.abc.grade}</span>
                    <div>
                      <p className="text-sm text-text-secondary">{data.abc.grade==="A"?"Топ-товар":data.abc.grade==="B"?"Средний":"Аутсайдер"}</p>
                      <p className="text-xs text-text-tertiary">{formatPercent(data.abc.revenue_share)} от выручки</p>
                    </div>
                  </div>
                </div>
              )}

              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-3">Остатки</h3>
                <div className="space-y-3">
                  <div className="flex justify-between"><span className="text-sm text-text-secondary">Всего</span><span className="text-sm font-semibold tabular-nums">{formatNumber(data.inventory.total_stock)} шт</span></div>
                  <div className="flex justify-between"><span className="text-sm text-text-secondary">Продаж/день</span><span className="text-sm font-medium tabular-nums">{data.inventory.avg_daily_sales.toFixed(1)}</span></div>
                  <div className="flex justify-between">
                    <span className="text-sm text-text-secondary">Дней запаса</span>
                    <span className={"text-sm font-semibold tabular-nums "+(data.inventory.days_of_stock<7?"text-accent-red":data.inventory.days_of_stock<30?"text-accent-amber":"text-accent-green")}>
                      {data.inventory.days_of_stock>999?"999+":data.inventory.days_of_stock}
                    </span>
                  </div>
                  {data.inventory.items.length>0 && (
                    <div className="border-t border-border-subtle pt-3 space-y-2">
                      <p className="text-xs text-text-tertiary uppercase tracking-wider">По складам:</p>
                      {data.inventory.items.map((w,idx)=>(
                        <div key={`${w.warehouse}-${idx}`} className="flex justify-between text-xs">
                          <span className="text-text-secondary truncate max-w-[140px]">{w.warehouse}</span>
                          <span className="font-medium tabular-nums">{formatNumber(w.stock)}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>

          {data.price_history && data.price_history.length>1 && (
            <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
              <h3 className="text-sm font-medium text-text-secondary mb-4">История цен (по неделям)</h3>
              <ResponsiveContainer width="100%" height={200}>
                <LineChart data={data.price_history.map(d=>({...d,label:formatDate(d.week)}))} margin={{top:4,right:4,bottom:0,left:0}}>
                  <CartesianGrid strokeDasharray="3 3" stroke="var(--color-border-subtle)" vertical={false} />
                  <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{fontSize:11,fill:"var(--color-text-tertiary)"}} />
                  <YAxis axisLine={false} tickLine={false} tick={{fontSize:11,fill:"var(--color-text-tertiary)"}} tickFormatter={formatK} />
                  <Tooltip contentStyle={{backgroundColor:"var(--color-surface-2)",border:"1px solid var(--color-border-default)",borderRadius:"8px",fontSize:"12px"}} />
                  <Line type="monotone" dataKey="avg_price" name="Ср. цена" stroke="#F97316" strokeWidth={2} dot={false} />
                  <Line type="monotone" dataKey="avg_for_pay" name="К выплате" stroke="#22C55E" strokeWidth={2} dot={false} strokeDasharray="5 5" />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )}

          <div className="grid grid-cols-2 gap-6">
            {data.by_marketplace && data.by_marketplace.length>0 && (
              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-4">По маркетплейсам</h3>
                <div className="space-y-3">
                  {data.by_marketplace.map(mp=>(
                    <div key={mp.marketplace} className="rounded-xl border border-border-subtle bg-surface-2 p-4">
                      <div className="flex items-center gap-2 mb-2">
                        <span className="h-2.5 w-2.5 rounded-full" style={{backgroundColor:mpColors[mp.marketplace]||"#666"}} />
                        <p className="text-sm font-medium">{mp.name}</p>
                      </div>
                      <div className="space-y-1">
                        <div className="flex justify-between text-xs"><span className="text-text-secondary">Выручка</span><span className="font-medium tabular-nums">{formatMoney(mp.revenue)}</span></div>
                        <div className="flex justify-between text-xs"><span className="text-text-secondary">Прибыль</span><span className="font-medium tabular-nums text-accent-green">{formatMoney(mp.profit)}</span></div>
                        <div className="flex justify-between text-xs"><span className="text-text-secondary">Продажи</span><span className="font-medium tabular-nums">{formatNumber(mp.quantity)}</span></div>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}

            {data.geography && (data.geography.by_country.length>0||data.geography.by_warehouse.length>0) && (
              <div className="rounded-2xl border border-border-subtle bg-surface-1 p-6">
                <h3 className="text-sm font-medium text-text-secondary mb-4 flex items-center gap-2">
                  <Globe className="h-4 w-4" /> География продаж
                </h3>
                {data.geography.by_country.length>0 && (
                  <div className="mb-4">
                    <p className="text-xs text-text-tertiary uppercase tracking-wider mb-2">По странам</p>
                    <div className="space-y-2">
                      {data.geography.by_country.map(c=>(
                        <div key={c.country} className="flex items-center justify-between text-xs">
                          <span className="text-text-secondary">{c.country}</span>
                          <div className="flex items-center gap-3">
                            <span className="text-text-tertiary tabular-nums">{formatNumber(c.quantity)} шт</span>
                            <span className="font-medium tabular-nums">{formatMoney(c.revenue)}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
                {data.geography.by_warehouse.length>0 && (
                  <div>
                    <p className="text-xs text-text-tertiary uppercase tracking-wider mb-2">По складам</p>
                    <div className="space-y-2">
                      {data.geography.by_warehouse.map(w=>(
                        <div key={w.warehouse} className="flex items-center justify-between text-xs">
                          <span className="text-text-secondary truncate max-w-[160px]">{w.warehouse}</span>
                          <div className="flex items-center gap-3">
                            <span className="text-text-tertiary tabular-nums">{formatNumber(w.quantity)} шт</span>
                            <span className="font-medium tabular-nums">{formatMoney(w.revenue)}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      ) : (
        <div className="text-center py-20 text-text-tertiary">Товар не найден</div>
      )}
    </AppLayout>
  );
}
