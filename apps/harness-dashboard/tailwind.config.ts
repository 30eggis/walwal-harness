import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./app/**/*.{ts,tsx}",
    "./components/**/*.{ts,tsx}",
    "./hooks/**/*.{ts,tsx}",
    "./lib/**/*.{ts,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        "brick-bg": "#0b1020",
        "brick-floor": "#1a2236",
        "brick-wall": "#2a3450",
        "aura-idle": "#4b5563",
        "aura-typing": "#22d3ee",
        "aura-talking": "#fbbf24",
        "aura-alert": "#ef4444",
      },
      fontFamily: {
        mono: ["ui-monospace", "Menlo", "monospace"],
      },
      keyframes: {
        "aura-pulse": {
          "0%, 100%": { opacity: "0.6" },
          "50%": { opacity: "1" },
        },
        "aura-blink": {
          "0%, 100%": { opacity: "0.4" },
          "50%": { opacity: "1" },
        },
        "alert-shake": {
          "0%, 100%": { transform: "translateX(0)" },
          "25%": { transform: "translateX(-1px)" },
          "75%": { transform: "translateX(1px)" },
        },
      },
      animation: {
        "aura-pulse": "aura-pulse 1.4s ease-in-out infinite",
        "aura-blink": "aura-blink 0.8s ease-in-out infinite",
        "alert-shake": "alert-shake 0.3s ease-in-out infinite",
      },
    },
  },
  plugins: [],
};

export default config;
