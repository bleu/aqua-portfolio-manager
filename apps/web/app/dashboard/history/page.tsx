"use client";

import dynamic from "next/dynamic";

/** See apps/web/app/dashboard/page.tsx's own doc comment for why this indirection exists --
 *  `ssr: false` is the part that actually matters: it stops Next from ever importing
 *  HistoryPageClient's module graph during the build, not just from prerendering its output. */
const HistoryPageClient = dynamic(() => import("./HistoryPageClient"), { ssr: false });

export default function Page() {
  return <HistoryPageClient />;
}
