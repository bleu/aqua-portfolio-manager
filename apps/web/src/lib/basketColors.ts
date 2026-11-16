/** The 4 basket accent colors. Source: the "Fix the Trim setup flow" prompt's own literal
 *  palette (teal/salmon/lavender/sand), chosen over an earlier Figma-swatch reading of the same
 *  palette because the Claude Artifact's own rendered CSS (project/Step1_Baskets_Filled.dc.html,
 *  .nav .on, .t-teal) uses this exact teal (#8fc9d0), not the Figma swatch's #94cad1. Only 4
 *  colors: MAX_BASKETS is capped at 4 by PortfolioManagerArgsCodec.MAX_GROUPS, so a 5th is never
 *  needed. */
export const BASKET_COLORS = ["#8fc9d0", "#d9998a", "#b9a8dc", "#d9c48f"];

/** Two-stop vertical gradients for each basket's own token chips (Create-baskets step), by the
 *  same index as BASKET_COLORS. Mint/teal and salmon are copied verbatim from the Claude
 *  Artifact's own CSS (project/Step1_Baskets_Filled.dc.html, .t-teal/.t-sal) -- note the
 *  artifact's confirmed salmon gradient bottom-stop (#d4968a) is a slightly different hex than
 *  this file's flat BASKET_COLORS[1] (#d9998a, the prompt's own literal value); the gradient uses
 *  the artifact's more precise confirmed value, the flat swatch keeps the prompt's literal one.
 *  Lavender and sand have no basket in the artifact to confirm against -- extrapolated with the
 *  same light-tint-to-base technique as before. */
export const BASKET_CHIP_GRADIENTS: { from: string; to: string }[] = [
  { from: "#d9eff1", to: "#8fc9d0" }, // Teal -- confirmed (.t-teal)
  { from: "#f3dcd5", to: "#d4968a" }, // Salmon -- confirmed (.t-sal)
  { from: "#e5dcf1", to: "#b9a8dc" }, // Lavender -- extrapolated
  { from: "#f3ead2", to: "#d9c48f" }, // Sand -- extrapolated
];
