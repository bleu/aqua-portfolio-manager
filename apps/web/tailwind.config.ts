import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}", "./.storybook/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        surface: {
          // The brand guide's own Charcoal swatch (node 601:153, confirmed #1e2123) is
          // explicitly labeled "Surfaces and visual depth" -- it's the elevated-card tone, not
          // the page backdrop. No separate page-background swatch is documented, so DEFAULT
          // keeps the app's original near-black rather than using Charcoal for both.
          DEFAULT: "#0b0d12",
          raised: "#1e2123",
          card: "#1e2123",
        },
        border: {
          DEFAULT: "#262b36",
          subtle: "#1d212a",
        },
        accent: {
          // Trim brand guide's "Mint", the signature/primary-action color (node 601:153's
          // palette). `muted` has no brand-guide equivalent -- a darker mint step of my own
          // for the one place it's used (AllocationBar's gap-segment divider border).
          DEFAULT: "#94cad1",
          muted: "#5b98a3",
        },
        positive: "#22c55e",
        // Trim brand guide's text-color tiers (node 601:161 and siblings): primary for
        // headlines, secondary for body copy, muted for footer/low-emphasis text. `primary` is
        // the CSS variable's own bound value (--text-primary, confirmed directly on node
        // 601:151) -- #f5f7fa was a hardcoded literal on one specific hero-text instance
        // elsewhere in the file that's a hex step off the variable's real value.
        ink: {
          primary: "#f6f7f7",
          secondary: "#c9cbcc",
          muted: "#85898c",
        },
      },
      fontFamily: {
        // Brand guide: Unbounded is for the wordmark and short, expressive headlines only --
        // everything else stays on the default sans stack (SF Pro where available via
        // -apple-system, already first in Tailwind's own default sans stack).
        display: ["var(--font-unbounded)"],
      },
    },
  },
  plugins: [],
};

export default config;
