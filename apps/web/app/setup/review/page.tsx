"use client";

import dynamic from "next/dynamic";

/** See apps/web/app/dashboard/page.tsx's own doc comment for why this indirection exists --
 *  `ssr: false` is the part that actually matters: it stops Next from ever importing
 *  ReviewPageClient's module graph during the build, not just from prerendering its output. */
const ReviewPageClient = dynamic(() => import("./ReviewPageClient"), { ssr: false });

export default function Page() {
  return <ReviewPageClient />;
}
