import type { Metadata } from "next";
import { Unbounded } from "next/font/google";
import type { ReactNode } from "react";
import { Providers } from "@/components/Providers";
import "./globals.css";

// Trim's wordmark/headline typeface (brand guide) -- only ever used via the `font-display`
// Tailwind token, never as the page default.
const unbounded = Unbounded({ subsets: ["latin"], weight: ["500"], variable: "--font-unbounded" });

export const metadata: Metadata = {
  title: "Aqua Portfolio Manager",
  description: "Set up and monitor Portfolio Manager strategies.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={unbounded.variable}>
      <body className="min-h-screen bg-surface font-sans antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
