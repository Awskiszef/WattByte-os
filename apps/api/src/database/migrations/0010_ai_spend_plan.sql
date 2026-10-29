-- Daily AI spend per plan (free / premium): lets the free plan, whose accounts cost nothing to create, be held to a
-- share of the budget (AI_BUDGET_FREE_DAILY_USD) so that mass-created accounts can neither exhaust the whole budget
-- nor starve paying users (A-01, D-05). Like ai_spend_daily it holds no user id and no personal data.
-- Additive: a new table.
CREATE TABLE ai_spend_plan_daily (
  day      date           NOT NULL,
  plan     text           NOT NULL CHECK (plan IN ('free', 'premium')),
  cost_usd numeric(14, 6) NOT NULL DEFAULT 0 CHECK (cost_usd >= 0),
  PRIMARY KEY (day, plan)
);
