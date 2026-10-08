export type Token = {
  symbol: string;
  address: string;
  iconUrl?: string;
};

export type GroupSummary = {
  id: string;
  name: string;
  color: string;
  tokens: Token[];
  /** Either a target share (0-1) or a USD value, picked by the consumer via `trailing`. */
  trailing: { kind: "percentage"; value: number } | { kind: "amount"; value: number };
  selected?: boolean;
};
