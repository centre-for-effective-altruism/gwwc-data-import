
BEGIN;
INSERT INTO pledges.reported_donation
SELECT
  donation.id AS id,
  map.person_id AS person_id,
  donation.currency AS currency_code,
  donation.amount AS amount,
  donation.created_at::DATE AS donation_date,
  match.external_organization_id AS organization_id
FROM gwwc_import.donations AS donation
JOIN gwwc_import.person_to_gwwc_entity AS map ON map.entity_id = donation.contact_id
JOIN gwwc_import.external_organization_matches AS match ON donation.target = match.donation_target
;

ROLLBACK;
