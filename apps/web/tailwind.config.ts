import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}", "./.storybook/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        surface: {
          DEFAULT: "#0b0d12",
          raised: "#13161d",
          card: "#171a22",
        },
        border: {
          DEFAULT: "#262b36",
          subtle: "#1d212a",
        },
        accent: {
          DEFAULT: "#6366f1",
          muted: "#4f46e5",
        },
        positive: "#22c55e",
      },
    },
  },
  plugins: [],
};

export default config;
