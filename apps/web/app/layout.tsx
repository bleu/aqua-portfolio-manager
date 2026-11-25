import type { Metadata } from "next";
import { Geist_Mono, Inter } from "next/font/google";
import localFont from "next/font/local";
import type { ReactNode } from "react";
import { Providers } from "@/components/Providers";
import "./globals.css";

// Trim's wordmark/headline typeface -- only ever used via the `font-display` Tailwind token,
// never as the page default. 400 (Regular) for the header wordmark, 500 (Medium) for headlines,
// 600 (SemiBold) for the landing hero headline (Figma node 1196:13341).
// Self-hosted (not next/font/google) -- the Google fetch this performs at build time is a build-time
// network dependency, and it has flaked in CI (not Vercel) with build failures unrelated to any
// code change. The file in ./fonts is Unbounded's own variable font, OFL-licensed, vendored from
// Google's own fonts repo (see fonts/Unbounded-OFL.txt). Being a variable font, every weight in its
// 400-900 range -- including 600 -- is already available through this one `weight` range, with no
// separate entry needed per weight.
const unbounded = localFont({
  src: "./fonts/Unbounded-Variable.ttf",
  weight: "400 900",
  variable: "--font-unbounded",
});
// Landing page only: Inter for the preview cards' figures, Geist Mono for the FAQ numbering (both in the Figma frame).
const inter = Inter({ subsets: ["latin"], variable: "--font-inter" });
const geistMono = Geist_Mono({ subsets: ["latin"], weight: ["500"], variable: "--font-geist-mono" });

export const metadata: Metadata = {
  title: "Trim – Portfolio Manager for 1inch Aqua",
  description:
    "Set your target allocations and let trades routed through Aqua help keep your portfolio aligned, while you earn LP fees.",
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" className={`${unbounded.variable} ${inter.variable} ${geistMono.variable}`}>
      <body className="min-h-screen bg-surface font-sans antialiased">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
