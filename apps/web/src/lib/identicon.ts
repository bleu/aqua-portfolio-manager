/** Deterministic per-address identicon, no external dependency (the prompt's own engineering
 *  constraint: don't add a dependency without asking). The Safe Apps SDK's own `getInfo()`
 *  response (safeAddress/chainId/threshold/owners/network) has no avatar or logo field -- Safe's
 *  own UI doesn't fetch a "real" per-Safe image either, it generates a blockie client-side from
 *  the address. This is that same approach: a symmetric 5x5 grid + a hue, both derived from the
 *  address so the same Safe always renders the same icon. */

function hashString(value: string): number {
  let hash = 0;
  for (let i = 0; i < value.length; i++) {
    hash = (hash << 5) - hash + value.charCodeAt(i);
    hash |= 0;
  }
  return Math.abs(hash);
}

export type IdenticonSpec = {
  /** 5x5 symmetric grid, true = filled with `foreground`. */
  cells: boolean[][];
  background: string;
  foreground: string;
};

export function identiconFor(address: string): IdenticonSpec {
  const seed = address.toLowerCase();
  const hue = hashString(seed) % 360;
  const background = `hsl(${hue}, 35%, 16%)`;
  const foreground = `hsl(${hue}, 55%, 62%)`;

  // Only the left half (+ center column) is derived from the address; the right half mirrors it,
  // the same symmetric construction classic "blockies" use.
  const cells: boolean[][] = [];
  for (let row = 0; row < 5; row++) {
    const rowCells: boolean[] = [];
    for (let col = 0; col < 3; col++) {
      const bit = hashString(`${seed}:${row}:${col}`) % 2 === 0;
      rowCells.push(bit);
    }
    cells.push([...rowCells, rowCells[1]!, rowCells[0]!]);
  }
  return { cells, background, foreground };
}
