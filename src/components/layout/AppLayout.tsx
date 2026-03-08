"use client";

import { useEffect, useState } from "react";
import { useRouter, usePathname } from "next/navigation";
import Sidebar from "./Sidebar";
import { Menu, X } from "lucide-react";

export default function AppLayout({ children }: { children: React.ReactNode }) {
  const router = useRouter();
  const pathname = usePathname();
  const [ready, setReady] = useState(false);
  const [mobileOpen, setMobileOpen] = useState(false);

  useEffect(() => {
    const token = localStorage.getItem("yf_token");
    if (!token) {
      router.push("/login");
    } else {
      setReady(true);
    }
  }, [router]);

  // Close mobile menu on route change
  useEffect(() => {
    setMobileOpen(false);
  }, [pathname]);

  if (!ready) {
    return (
      <div className="min-h-screen bg-surface-0 flex items-center justify-center">
        <div className="h-5 w-5 border-2 border-border-default border-t-text-primary rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-surface-0">
      {/* Mobile header */}
      <header className="lg:hidden fixed top-0 left-0 right-0 h-14 bg-surface-0 border-b border-border-subtle flex items-center px-4 z-50">
        <button
          onClick={() => setMobileOpen(true)}
          className="p-2 -ml-2 rounded-lg text-text-secondary hover:text-text-primary hover:bg-surface-2 transition-colors"
        >
          <Menu className="h-5 w-5" />
        </button>
        <div className="ml-3">
          <span className="text-base font-bold tracking-tight">Your</span>
          <span className="text-base font-light tracking-tight">Fit</span>
        </div>
      </header>

      {/* Mobile overlay */}
      {mobileOpen && (
        <div
          className="lg:hidden fixed inset-0 bg-black/40 z-50 backdrop-blur-sm"
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Sidebar */}
      <div
        className={
          "fixed top-0 bottom-0 left-0 z-50 transition-transform duration-200 " +
          "lg:translate-x-0 " +
          (mobileOpen ? "translate-x-0" : "-translate-x-full")
        }
      >
        <Sidebar onClose={() => setMobileOpen(false)} />
      </div>

      {/* Main content */}
      <main className="lg:ml-56 min-h-screen pt-14 lg:pt-0">
        <div className="px-4 sm:px-6 lg:px-8 py-6 max-w-[1400px]">{children}</div>
      </main>
    </div>
  );
}
