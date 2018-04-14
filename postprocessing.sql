-- Add all the donation targets
INSERT INTO gwwc_import.donation_target_to_external_organization (donation_target)
(
  SELECT DISTINCT target::citext from gwwc_import.donations ORDER BY target
);

-- Required for levenshtein()
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

-- build a window function using the lowest confidence
-- to guess the name of the new org
WITH external_orgs AS (
  SELECT id, LOWER(name) as reference FROM organizations.external_organization
    UNION (SELECT id, LOWER(unnest(keywords)) as reference FROM organizations.external_organization)
  ORDER BY id
)
  SELECT
    donation_target,
    reference, id as external_organization_id,
    levenshtein(donation_target, reference) as confidence
  FROM gwwc_import.donation_target_to_external_organization
    JOIN external_orgs ON TRUE
  ORDER BY donation_target, confidence
;
