import { clsx, type ClassValue } from "clsx";

export function cn(...inputs: ClassValue[]) {
  return clsx(inputs);
}

export function formatMoney(value: number): string {
  if (value === 0) return "0 ₽";
  if (Math.abs(value) >= 1000000) {
    return (value / 1000000).toFixed(1).replace(".", ",") + " млн ₽";
  }
  if (Math.abs(value) >= 1000) {
    return (value / 1000).toFixed(1).replace(".", ",") + " тыс ₽";
  }
  return value.toLocaleString("ru-RU") + " ₽";
}

export function formatNumber(value: number): string {
  return value.toLocaleString("ru-RU");
}

export function formatPercent(value: number): string {
  return value.toFixed(1).replace(".", ",") + "%";
}

export function formatDate(date: string): string {
  return new Date(date).toLocaleDateString("ru-RU", { day: "numeric", month: "short" });
}

export function formatDateTime(date: string): string {
  return new Date(date).toLocaleString("ru-RU", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

export const mpColors: Record<string, string> = {
  wb: "#CB11AB",
  wildberries: "#CB11AB",
  ozon: "#005BFF",
  yandex_market: "#FFCC00",
  avito: "#00AAFF",
};

export const mpNames: Record<string, string> = {
  wb: "Wildberries",
  wildberries: "Wildberries",
  ozon: "Ozon",
  yandex_market: "Яндекс Маркет",
  avito: "Авито",
};
