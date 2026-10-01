CREATE TABLE "candidates" (
	"id" text PRIMARY KEY NOT NULL,
	"strategy_id" text NOT NULL,
	"token_in" text NOT NULL,
	"token_out" text NOT NULL,
	"amount_in" bigint NOT NULL,
	"quoted_out" bigint NOT NULL,
	"fair_out" bigint NOT NULL,
	"profit_usd_wad" bigint NOT NULL,
	"profit_headroom" bigint NOT NULL,
	"fynd_target" text NOT NULL,
	"fynd_spender" text NOT NULL,
	"fynd_calldata" text NOT NULL,
	"min_curve_amount_out" bigint NOT NULL,
	"deadline" bigint NOT NULL,
	"state_version" text NOT NULL,
	"retry_count" integer DEFAULT 0 NOT NULL,
	"status" text DEFAULT 'eligible' NOT NULL,
	"rejection_reason" text,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "execution_attempts" (
	"id" text PRIMARY KEY NOT NULL,
	"candidate_id" text NOT NULL,
	"executor_address" text NOT NULL,
	"executor_version" text NOT NULL,
	"tx_hash" text,
	"status" text NOT NULL,
	"failure_reason" text,
	"submitted_at" timestamp,
	"confirmed_at" timestamp,
	"finalized_at" timestamp,
	"created_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "feed_prices" (
	"feed_proxy" text PRIMARY KEY NOT NULL,
	"price_wad" bigint NOT NULL,
	"updated_at" bigint NOT NULL,
	"block_timestamp" bigint NOT NULL
);
--> statement-breakpoint
CREATE TABLE "strategies" (
	"id" text PRIMARY KEY NOT NULL,
	"maker" text NOT NULL,
	"app" text NOT NULL,
	"strategy_hash" text NOT NULL,
	"tokens" jsonb NOT NULL,
	"is_active" boolean NOT NULL,
	"encoded_order" text NOT NULL,
	"resolver_kyc_token" text,
	"ineligibility_reason" text,
	"shipped_at" bigint NOT NULL,
	"docked_at" bigint,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "strategy_wallet_balances" (
	"wallet" text NOT NULL,
	"token" text NOT NULL,
	"balance" bigint NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "strategy_wallet_balances_wallet_token_pk" PRIMARY KEY("wallet","token")
);
--> statement-breakpoint
CREATE TABLE "sync_cursors" (
	"entity" text PRIMARY KEY NOT NULL,
	"cursor" text NOT NULL,
	"updated_at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "candidates" ADD CONSTRAINT "candidates_strategy_id_strategies_id_fk" FOREIGN KEY ("strategy_id") REFERENCES "public"."strategies"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "execution_attempts" ADD CONSTRAINT "execution_attempts_candidate_id_candidates_id_fk" FOREIGN KEY ("candidate_id") REFERENCES "public"."candidates"("id") ON DELETE no action ON UPDATE no action;