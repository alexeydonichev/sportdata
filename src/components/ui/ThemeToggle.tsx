"use client";

import { useEffect, useState } from "react";
import { Sun, Moon } from "lucide-react";

export default function ThemeToggle() {
  const [theme, setTheme] = useState<"dark" | "light">("dark");

  useEffect(() => {
    const saved = localStorage.getItem("yf_theme") as "dark" | "light" | null;
    if (saved) {
      setTheme(saved);
      document.documentElement.classList.toggle("light", saved === "light");
    }
  }, []);

  function toggle() {
    const next = theme === "dark" ? "light" : "dark";
    setTheme(next);
    localStorage.setItem("yf_theme", next);
    document.documentElement.classList.toggle("light", next === "light");
  }

  return (
    <button
      onClick={toggle}
      className="rounded-lg border border-border-default bg-surface-1 p-2 text-text-secondary hover:text-text-primary hover:border-border-strong transition-colors"
      title={theme === "dark" ? "Светлая тема" : "Тёмная тема"}
    >
      {theme === "dark" ? <Sun className="h-4 w-4" strokeWidth={1.5} /> : <Moon className="h-4 w-4" strokeWidth={1.5} />}
    </button>
  );
}
