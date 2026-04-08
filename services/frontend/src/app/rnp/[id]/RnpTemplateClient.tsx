"use client";

import { useState, useEffect } from "react";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ArrowLeft, Download, Calendar } from "lucide-react";
import Link from "next/link";

interface RnpItem {
  id: number;
  product_name: string;
  sku: string;
  plan_orders_rub: number;
  plan_quantity: number;
  fact_day_qty: number;
  fact_day_rub: number;
  fact_week_qty: number;
  fact_week_rub: number;
  fact_month_qty: number;
  fact_month_rub: number;
  stock_fbo: number;
  stock_fbs: number;
  stock_in_transit: number;
  stock_1c: number;
  days_of_stock: number;
  completion_pct_qty: number;
  completion_pct_rub: number;
}

interface Template {
  id: number;
  project_name: string;
  manager_name: string;
  marketplace: string;
  year: number;
  month: number;
  status: string;
  days_in_month: number;
  selected_date: string;
}

const months = [
  "Январь", "Февраль", "Март", "Апрель", "Май", "Июнь",
  "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"
];

function formatMoney(value: number): string {
  if (value >= 1000000) {
    return (value / 1000000).toFixed(1) + 'М';
  }
  if (value >= 1000) {
    return (value / 1000).toFixed(1) + 'К';
  }
  return value.toFixed(0);
}

function getStatusColor(pct: number): string {
  if (pct >= 100) return "text-green-600";
  if (pct >= 80) return "text-yellow-600";
  return "text-red-600";
}

function getStatusBg(pct: number): string {
  if (pct >= 100) return "bg-green-100";
  if (pct >= 80) return "bg-yellow-100";
  return "bg-red-100";
}

export default function RnpTemplateClient({ id }: { id: string }) {
  const [template, setTemplate] = useState<Template | null>(null);
  const [items, setItems] = useState<RnpItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedDate, setSelectedDate] = useState<string>(
    new Date().toISOString().split('T')[0]
  );

  useEffect(() => {
    fetchData();
  }, [id, selectedDate]);

  const fetchData = async () => {
    try {
      const res = await fetch(`/api/v1/rnp/templates/${id}?date=${selectedDate}`);
      if (!res.ok) throw new Error("Ошибка загрузки");
      const data = await res.json();
      setTemplate(data.template);
      setItems(data.items);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Ошибка");
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return <div className="p-8 text-center">Загрузка...</div>;
  }

  if (error || !template) {
    return <div className="p-8 text-center text-red-500">{error || "Шаблон не найден"}</div>;
  }

  // Итоги
  const totals = {
    plan_qty: items.reduce((sum, i) => sum + Number(i.plan_quantity), 0),
    plan_rub: items.reduce((sum, i) => sum + Number(i.plan_orders_rub), 0),
    fact_day_qty: items.reduce((sum, i) => sum + Number(i.fact_day_qty), 0),
    fact_day_rub: items.reduce((sum, i) => sum + Number(i.fact_day_rub), 0),
    fact_week_qty: items.reduce((sum, i) => sum + Number(i.fact_week_qty), 0),
    fact_week_rub: items.reduce((sum, i) => sum + Number(i.fact_week_rub), 0),
    fact_month_qty: items.reduce((sum, i) => sum + Number(i.fact_month_qty), 0),
    fact_month_rub: items.reduce((sum, i) => sum + Number(i.fact_month_rub), 0),
    stock_fbo: items.reduce((sum, i) => sum + Number(i.stock_fbo), 0),
    stock_fbs: items.reduce((sum, i) => sum + Number(i.stock_fbs), 0),
  };

  const totalCompletionPct = totals.plan_qty > 0 
    ? Math.round((totals.fact_month_qty / totals.plan_qty) * 100) 
    : 0;

  return (
    <div className="space-y-4">
      {/* Шапка */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <Link href="/rnp">
            <Button variant="ghost" size="sm">
              <ArrowLeft className="h-4 w-4 mr-2" />
              Назад
            </Button>
          </Link>
          <div>
            <h1 className="text-2xl font-bold">
              {template.project_name} — {template.marketplace}
            </h1>
            <p className="text-gray-500">
              {months[template.month - 1]} {template.year} • {template.manager_name}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <Calendar className="h-4 w-4 text-gray-400" />
            <Input
              type="date"
              value={selectedDate}
              onChange={(e) => setSelectedDate(e.target.value)}
              className="w-40"
            />
          </div>
          <Badge variant={template.status === 'active' ? 'default' : 'secondary'}>
            {template.status === 'active' ? 'Активный' : template.status}
          </Badge>
          <Button variant="outline" size="sm">
            <Download className="h-4 w-4 mr-2" />
            Excel
          </Button>
        </div>
      </div>

      {/* Сводка */}
      <div className="grid grid-cols-5 gap-4">
        <Card>
          <CardContent className="p-4">
            <div className="text-sm text-gray-500">План (шт)</div>
            <div className="text-2xl font-bold">{totals.plan_qty.toLocaleString()}</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="text-sm text-gray-500">Факт за день</div>
            <div className="text-2xl font-bold">{totals.fact_day_qty.toLocaleString()}</div>
            <div className="text-sm text-gray-400">{formatMoney(totals.fact_day_rub)} ₽</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="text-sm text-gray-500">Факт за неделю</div>
            <div className="text-2xl font-bold">{totals.fact_week_qty.toLocaleString()}</div>
            <div className="text-sm text-gray-400">{formatMoney(totals.fact_week_rub)} ₽</div>
          </CardContent>
        </Card>
        <Card>
          <CardContent className="p-4">
            <div className="text-sm text-gray-500">Факт за месяц</div>
            <div className="text-2xl font-bold">{totals.fact_month_qty.toLocaleString()}</div>
            <div className="text-sm text-gray-400">{formatMoney(totals.fact_month_rub)} ₽</div>
          </CardContent>
        </Card>
        <Card className={getStatusBg(totalCompletionPct)}>
          <CardContent className="p-4">
            <div className="text-sm text-gray-500">Выполнение</div>
            <div className={`text-2xl font-bold ${getStatusColor(totalCompletionPct)}`}>
              {totalCompletionPct}%
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Таблица */}
      <Card>
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b">
                <tr>
                  <th className="text-left p-3 font-medium">Товар</th>
                  <th className="text-left p-3 font-medium">SKU</th>
                  <th className="text-right p-3 font-medium">План шт</th>
                  <th className="text-right p-3 font-medium">План ₽</th>
                  <th className="text-right p-3 font-medium bg-blue-50">День шт</th>
                  <th className="text-right p-3 font-medium bg-blue-50">День ₽</th>
                  <th className="text-right p-3 font-medium bg-green-50">Нед шт</th>
                  <th className="text-right p-3 font-medium bg-green-50">Нед ₽</th>
                  <th className="text-right p-3 font-medium bg-yellow-50">Мес шт</th>
                  <th className="text-right p-3 font-medium bg-yellow-50">Мес ₽</th>
                  <th className="text-right p-3 font-medium">FBO</th>
                  <th className="text-right p-3 font-medium">FBS</th>
                  <th className="text-right p-3 font-medium">%</th>
                </tr>
              </thead>
              <tbody>
                {items.map((item) => (
                  <tr key={item.id} className="border-b hover:bg-gray-50">
                    <td className="p-3 max-w-[200px] truncate" title={item.product_name}>
                      {item.product_name}
                    </td>
                    <td className="p-3 text-gray-500">{item.sku}</td>
                    <td className="p-3 text-right">{item.plan_quantity}</td>
                    <td className="p-3 text-right">{formatMoney(item.plan_orders_rub)}</td>
                    <td className="p-3 text-right bg-blue-50">{item.fact_day_qty}</td>
                    <td className="p-3 text-right bg-blue-50">{formatMoney(item.fact_day_rub)}</td>
                    <td className="p-3 text-right bg-green-50">{item.fact_week_qty}</td>
                    <td className="p-3 text-right bg-green-50">{formatMoney(item.fact_week_rub)}</td>
                    <td className="p-3 text-right bg-yellow-50">{item.fact_month_qty}</td>
                    <td className="p-3 text-right bg-yellow-50">{formatMoney(item.fact_month_rub)}</td>
                    <td className="p-3 text-right">{item.stock_fbo}</td>
                    <td className="p-3 text-right">{item.stock_fbs}</td>
                    <td className={`p-3 text-right font-medium ${getStatusColor(item.completion_pct_qty)}`}>
                      {item.completion_pct_qty}%
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot className="bg-gray-100 font-medium">
                <tr>
                  <td className="p-3">ИТОГО</td>
                  <td className="p-3"></td>
                  <td className="p-3 text-right">{totals.plan_qty}</td>
                  <td className="p-3 text-right">{formatMoney(totals.plan_rub)}</td>
                  <td className="p-3 text-right bg-blue-100">{totals.fact_day_qty}</td>
                  <td className="p-3 text-right bg-blue-100">{formatMoney(totals.fact_day_rub)}</td>
                  <td className="p-3 text-right bg-green-100">{totals.fact_week_qty}</td>
                  <td className="p-3 text-right bg-green-100">{formatMoney(totals.fact_week_rub)}</td>
                  <td className="p-3 text-right bg-yellow-100">{totals.fact_month_qty}</td>
                  <td className="p-3 text-right bg-yellow-100">{formatMoney(totals.fact_month_rub)}</td>
                  <td className="p-3 text-right">{totals.stock_fbo}</td>
                  <td className="p-3 text-right">{totals.stock_fbs}</td>
                  <td className={`p-3 text-right ${getStatusColor(totalCompletionPct)}`}>
                    {totalCompletionPct}%
                  </td>
                </tr>
              </tfoot>
            </table>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
