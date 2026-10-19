-- A call whose provider reported no token usage used to be stored as 0 tokens and $0, indistinguishable from a
-- free call. cost_basis says how estimated_cost_usd was derived; usage_reported says whether the token counts
-- are real. Existing rows were written when every cost was an estimate from reported tokens.
ALTER TABLE ai_generations
  ADD COLUMN cost_basis     text    NOT NULL DEFAULT 'provider_estimate'
    CHECK (cost_basis IN ('model_price', 'provider_estimate', 'unknown')),
  ADD COLUMN usage_reported boolean NOT NULL DEFAULT true;
