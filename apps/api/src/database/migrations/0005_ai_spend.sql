-- 1. xAI reports the exact charge of every call: a cost that is neither a flat estimate nor an operator price.
ALTER TABLE ai_generations DROP CONSTRAINT ai_generations_cost_basis_check;
ALTER TABLE ai_generations
  ADD CONSTRAINT ai_generations_cost_basis_check
  CHECK (cost_basis IN ('provider_reported', 'model_price', 'provider_estimate', 'unknown'));

-- 2. Daily spend per provider: what the budget limits (AI_BUDGET_*) are checked against. It holds no user id on
-- purpose: summing ai_generations would shrink whenever a user erases their data (DELETE /me/cloud-data, account
-- deletion) or the retention job purges old rows, and a budget that can be reset that way is no budget. A few
-- rows a day, no personal data, so nothing here needs a retention rule.
CREATE TABLE ai_spend_daily (
  day      date          NOT NULL,
  provider text          NOT NULL,
  requests integer       NOT NULL DEFAULT 0 CHECK (requests >= 0),
  cost_usd numeric(14, 6) NOT NULL DEFAULT 0 CHECK (cost_usd >= 0),
  PRIMARY KEY (day, provider)
);

-- The history that already exists counts towards this month.
INSERT INTO ai_spend_daily (day, provider, requests, cost_usd)
SELECT (created_at AT TIME ZONE 'UTC')::date, provider, count(*), sum(estimated_cost_usd)
FROM ai_generations
GROUP BY 1, 2;
