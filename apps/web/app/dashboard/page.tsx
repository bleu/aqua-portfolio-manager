"use client";

import dynamic from "next/dynamic";

/** This route needs a live wallet connection and reads contract addresses from env vars at
 *  module-load time (apps/web/src/lib/contracts.ts's own doc comment explains why those throw
 *  eagerly rather than lazily) -- `ssr: false` stops Next from ever importing/evaluating
 *  DashboardPageClient's module graph during the build or on the server at all, not just from
 *  statically prerendering its output. A plain `export const dynamic = "force-dynamic"` on the
 *  page itself was NOT enough: Next still executes a page's module graph once during
 *  "Generating static pages" to produce the client reference manifest, regardless of that flag,
 *  which is exactly what threw "Missing required env var" in CI/Vercel builds without every
 *  NEXT_PUBLIC_PM_* var set for the Preview environment. */
const DashboardPageClient = dynamic(() => import("./DashboardPageClient"), { ssr: false });

export default function Page() {
  return <DashboardPageClient />;
}
