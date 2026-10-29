-- A call whose provider reported no usable token counts used to be recorded with cost 0 (basis 'unknown'), so a spend
-- limit never saw it (D-07). It is now booked at its worst case, labelled 'conservative_estimate'.
-- Additive: the new value is allowed; every existing row stays valid.
ALTER TABLE ai_generations DROP CONSTRAINT ai_generations_cost_basis_check;
ALTER TABLE ai_generations
  ADD CONSTRAINT ai_generations_cost_basis_check
  CHECK (cost_basis IN ('provider_reported', 'model_price', 'provider_estimate', 'conservative_estimate', 'unknown'));
