import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}", "./.storybook/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        surface: {
          DEFAULT: "#0b0d12",
          raised: "#1e2123",
          // The actual landing-page frame (node 680:20946, found via the Figma Plugin API after
          // text-searching the whole document -- get_metadata's page dumps never surfaced it,
          // apparently collapsed inside a component instance) gives the "Portfolio preview"
          // card's real fill directly: var(--surface-primary, #121518). An earlier pass used the
          // brand guide's generic Charcoal swatch (#1e2123) here instead, which read visibly too
          // light against the real page.
          card: "#121518",
        },
        border: {
          DEFAULT: "#262b36",
          subtle: "#1d212a",
        },
        accent: {
          DEFAULT: "#94cad1",
          // Confirmed directly on the real allocation bar's gradient/border (node 680:20972 and
          // siblings): var(--highlight-mint-strong, #6b939a). Replaces an earlier guessed value.
          muted: "#6b939a",
        },
        // The allocation bar's "Gap to target" segment (node 680:20959/680:20973 etc.) is a
        // distinct brand color, var(--color-purple-400, #bfb6c9) -- not a tint of accent.
        difference: "#bfb6c9",
        positive: "#22c55e",
        // Text-color tiers, confirmed on the real landing-page frame itself (var(--text-primary),
        // var(--text-secondary), var(--text-muted)), not just the brand guide's documentation
        // swatches. The hero headline hardcodes a one-step-darker literal (#f5f7fa) directly on
        // its own node rather than binding to the variable -- that one instance keeps its literal
        // value inline rather than through this token.
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
