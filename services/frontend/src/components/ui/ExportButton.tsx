"use client";
import { useState } from "react";
import { Download, ChevronDown } from "lucide-react";
import { exportCSV, exportExcel } from "@/lib/export";

interface ExportButtonProps {
  filename: string;
  headers: string[];
  getRows: () => string[][];
}

export default function ExportButton({ filename, headers, getRows }: ExportButtonProps) {
  const [open, setOpen] = useState(false);

  function handleExport(format: "csv" | "excel") {
    const rows = getRows();
    const date = new Date().toISOString().slice(0, 10);
    const fullName = `${filename}-${date}`;
    if (format === "csv") exportCSV(fullName, headers, rows);
    else exportExcel(fullName, headers, rows);
    setOpen(false);
  }

  return (
    <div className="relative">
      <button
        onClick={() => setOpen(!open)}
        className="flex items-center gap-2 px-4 py-2 rounded-lg text-xs font-medium bg-surface-1 border border-border-default text-text-primary hover:bg-surface-2 transition-colors"
      >
        <Download className="h-3.5 w-3.5" />
        Экспорт
        <ChevronDown className={"h-3 w-3 transition-transform " + (open ? "rotate-180" : "")} />
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-10" onClick={() => setOpen(false)} />
          <div className="absolute right-0 top-full mt-1 z-20 bg-surface-1 border border-border-default rounded-lg shadow-lg overflow-hidden min-w-[140px]">
            <button
              onClick={() => handleExport("csv")}
              className="w-full px-4 py-2.5 text-left text-xs text-text-primary hover:bg-surface-2 transition-colors flex items-center gap-2"
            >
              <span className="text-[10px] font-mono bg-surface-3 px-1.5 py-0.5 rounded">CSV</span>
              Скачать CSV
            </button>
            <button
              onClick={() => handleExport("excel")}
              className="w-full px-4 py-2.5 text-left text-xs text-text-primary hover:bg-surface-2 transition-colors flex items-center gap-2 border-t border-border-subtle"
            >
              <span className="text-[10px] font-mono bg-accent-green/10 text-accent-green px-1.5 py-0.5 rounded">XLS</span>
              Скачать Excel
            </button>
          </div>
        </>
      )}
    </div>
  );
}
