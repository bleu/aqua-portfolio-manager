import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}", "./.storybook/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        surface: {
          // Trim brand guide's confirmed charcoal (node 601:153). raised/card keep the same
          // relative lightening steps the old near-black base used -- the brand guide doesn't
          // define those two separately.
          DEFAULT: "#1e2123",
          raised: "#282c2f",
          card: "#2d3134",
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
        // headlines, secondary for body copy, muted for footer/low-emphasis text.
        ink: {
          primary: "#f5f7fa",
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
