import type { Metadata, Viewport } from "next";
import "./globals.css";
import ServiceWorkerRegistration from "@/components/ui/ServiceWorkerRegistration";

export const metadata: Metadata = {
  title: "YourFit — Аналитика",
  description: "Платформа аналитики маркетплейсов",
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: "YourFit",
  },
  icons: {
    icon: "/icons/icon-192.svg",
    apple: "/icons/icon-192.svg",
  },
};

export const viewport: Viewport = {
  themeColor: "#0A0A0A",
  width: "device-width",
  initialScale: 1,
  maximumScale: 1,
  userScalable: false,
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ru" suppressHydrationWarning>
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: "try{const t=localStorage.getItem('yf_theme');if(t==='light')document.documentElement.classList.add('light')}catch(e){}",
          }}
        />
      </head>
      <body suppressHydrationWarning>
        {children}
        <ServiceWorkerRegistration />
      </body>
    </html>
  );
}
