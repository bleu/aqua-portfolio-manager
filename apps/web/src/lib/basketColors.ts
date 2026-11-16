/** The 5 basket accent colors, confirmed directly against Figma's own "Variants - Allocation"
 *  swatches (node 938:17680, frames Mint/Salmon/Purple/Green/White in that order) -- not an
 *  arbitrary palette. Mint is the same hex as the app's own `accent` Tailwind token. Used for
 *  allocation rings/legends (Targets, Dashboard) as flat swatches. */
export const BASKET_COLORS = ["#94cad1", "#d99d8e", "#aa9eb7", "#b3fd8b", "#f6f7f7"];

/** Two-stop vertical gradients for each basket's own token chips (Create-baskets step), by the
 *  same index as BASKET_COLORS. Mint and Salmon are copied verbatim from the Claude Artifact's
 *  "Baskets · filled" mockup (project/Step1_Baskets_Filled.dc.html, classes .t-teal/.t-sal) --
 *  the artifact never shows a 3rd/4th/5th basket, so Purple/Green/White are extrapolated with the
 *  same light-tint-to-base technique, not independently confirmed. Basket 5 (White) never renders
 *  in this app anyway -- MAX_BASKETS below is capped at 4 by PortfolioManagerArgsCodec.MAX_GROUPS. */
export const BASKET_CHIP_GRADIENTS: { from: string; to: string }[] = [
  { from: "#d9eff1", to: "#8fc9d0" }, // Mint -- confirmed (.t-teal)
  { from: "#f3dcd5", to: "#d4968a" }, // Salmon -- confirmed (.t-sal)
  { from: "#ddd8e2", to: "#aa9eb7" }, // Purple -- extrapolated
  { from: "#e1fed1", to: "#b3fd8b" }, // Green -- extrapolated
  { from: "#ffffff", to: "#f6f7f7" }, // White -- extrapolated, unused (basket 5 never renders)
];
