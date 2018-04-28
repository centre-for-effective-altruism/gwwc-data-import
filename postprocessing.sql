-- Add all the donation targets
INSERT INTO gwwc_import.external_organization_matches (donation_target)
(
  SELECT DISTINCT target::citext from gwwc_import.donations ORDER BY target
);

-- Copy external orgs so that we don't have to touch the main table yet
INSERT INTO gwwc_import.external_organization (SELECT * FROM organizations.external_organization);

-- Make sure that all 'skips' have a value
UPDATE gwwc_import.person_merge_candidates SET skip = false WHERE skip IS NULL;
ALTER TABLE gwwc_import.person_merge_candidates ALTER COLUMN skip SET NOT NULL;

-- People with no email address are useless to us, and they're all dups anyway...
-- Also test users are awful...
-- Also do_not_imports...
DELETE FROM gwwc_import.person WHERE email IS NULL;
DELETE FROM gwwc_import.person WHERE email IN (SELECT email FROM gwwc_import.do_not_import);
DELETE FROM gwwc_import.person
  WHERE
    first_name ilike '%test%' OR
    last_name ilike '%test%' OR
    email ilike '%test%'
;
ALTER TABLE gwwc_import.person ALTER COLUMN email SET NOT NULL;

-- Required for levenshtein()
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;

-- Some common words throw off our levenshtein matching accuracy (e.g. fund, foundation)
CREATE OR REPLACE FUNCTION gwwc_import.strip_common_words (str TEXT)
RETURNS TEXT AS $$
DECLARE
  _out TEXT;
  _match TEXT;
  matches TEXT[] = array['foundation', 'fund'];
BEGIN
  _out := str;
  FOREACH _match IN ARRAY matches LOOP
    _out := replace(LOWER(_out), LOWER(_match), '');
  END LOOP;
  RETURN _out;
END
$$ LANGUAGE plpgsql IMMUTABLE;

-- Remap donation targets
CREATE OR REPLACE FUNCTION gwwc_import.remap_donation_targets()
RETURNS SETOF gwwc_import.external_organization AS $$
  DECLARE
    _org gwwc_import.unmatched_external_orgs;
    _external_org gwwc_import.external_organization;
    _name TEXT;
    _keywords TEXT[];
    _new_keywords TEXT[];
  BEGIN
    RAISE NOTICE 'Remapping donation targets...';
    -- start by creating orgs that have keywords
    FOR _org IN (SELECT * FROM gwwc_import.unmatched_external_orgs WHERE keywords IS NOT NULL) LOOP
      _name := COALESCE(_org.remap_to, _org.donation_target);
      _keywords := string_to_array(_org.keywords, ',');
      -- See if the org exists
      SELECT * INTO _external_org FROM gwwc_import.external_organization
        WHERE LOWER(name) = LOWER(_name)
        ORDER BY created_at ASC LIMIT 1;
      IF _external_org.id IS NOT NULL THEN
        -- if we've got the org, just add any unique keywords
        _new_keywords:= ARRAY(SELECT DISTINCT UNNEST(array_cat(_external_org.keywords, _keywords)));
        UPDATE gwwc_import.external_organization
          SET keywords = _new_keywords
          WHERE id = _external_org.id
          RETURNING * INTO _external_org;
        RETURN NEXT _external_org;
      ELSE
        -- if we don't have the org, create it
        INSERT INTO gwwc_import.external_organization (name, keywords)
        VALUES (_name, _keywords)
        RETURNING * INTO _external_org;
        RETURN NEXT _external_org;
      END IF;
    END LOOP;

    -- OK, now we've got keywords covered, do the same thing with the names
    FOR _org IN (SELECT * FROM gwwc_import.unmatched_external_orgs WHERE remap_to IS NOT NULL) LOOP
      -- try to find a matching name
      SELECT * INTO _external_org FROM gwwc_import.external_organization
        WHERE LOWER(name) = LOWER(_org.remap_to);
      -- nope? try the keywords...
      IF _external_org.id IS NULL THEN
        SELECT * INTO _external_org FROM gwwc_import.external_organization
        WHERE id = (
          SELECT id FROM
          (
            SELECT id, UNNEST(keywords) as keyword FROM gwwc_import.external_organization
          ) a
          WHERE lower(keyword) = LOWER(_org.remap_to)
          ORDER BY id ASC
          LIMIT 1
        );
      END IF;
      -- OK, did we get an external_org?
      IF _external_org.id IS NOT NULL THEN
        -- If we got an external org, update the donation_target mapping to the right name
        UPDATE gwwc_import.external_organization_matches
          SET external_organization_id = _external_org.id
          WHERE donation_target = _org.donation_target;
        -- add the donation_target to the external_org's list of keywords
        _new_keywords:= ARRAY(SELECT DISTINCT LOWER(UNNEST(
          array_append(_external_org.keywords, _org.remap_to)
        )));
        -- in general we want to add the org name from the donation target, but
        -- sometimes these are just rambling sentences or innumerable lists
        IF LENGTH(_org.donation_target) < 20 THEN
          _new_keywords := array_append(_new_keywords, _org.donation_target);
        END IF;
        UPDATE gwwc_import.external_organization
          SET keywords = _new_keywords
          WHERE id = _external_org.id
          RETURNING * INTO _external_org;
        RETURN NEXT _external_org;
      ELSE
        -- If we don't have an external org, create one with our remapped name
        INSERT INTO gwwc_import.external_organization (name)
          VALUES (_org.remap_to) RETURNING * INTO _external_org;
        RETURN NEXT _external_org;
        UPDATE gwwc_import.external_organization_matches
          SET external_organization_id = _external_org.id
          WHERE donation_target = _org.donation_target;
      END IF;
    END LOOP;
  END
$$ LANGUAGE plpgsql VOLATILE;

SELECT gwwc_import.remap_donation_targets();

-- Store external orgs and keywords somewhere
INSERT INTO gwwc_import.external_organization_reference (
  SELECT id, LOWER(name) as reference FROM gwwc_import.external_organization
    UNION (SELECT id, LOWER(unnest(keywords)) as reference FROM gwwc_import.external_organization)
  ORDER BY id
);

-- Find donations that have targets that match external orgs closely, and store the mapping
WITH matches AS (
  SELECT target as donation_target, id as external_organization_id FROM (
    SELECT target_refs.*, levenshtein(LOWER(target_refs.target), LOWER(target_refs.reference)) as distance FROM (
      SELECT don.target, ref.* FROM gwwc_import.donations AS don
      JOIN gwwc_import.external_organization_reference ref ON ABS(LENGTH(don.target) - LENGTH(ref.reference)) < 3
      ORDER BY target
    ) target_refs
  ) distances
  WHERE (
    (distance = 0) OR
    (LENGTH(gwwc_import.strip_common_words(target)) > 4 AND distance <= 1) OR
    (LENGTH(gwwc_import.strip_common_words(target)) > 10 AND distance <= 2)
  )
)
UPDATE gwwc_import.external_organization_matches
SET (external_organization_id) = (matches.external_organization_id)
FROM matches
WHERE external_organization_matches.donation_target = matches.donation_target
;

-- Create new organizations from unmatched orgs
DO $func$
  DECLARE
    _external_org_match gwwc_import.external_organization_matches;
    _external_org gwwc_import.external_organization;
  BEGIN
    FOR _external_org_match IN (
      SELECT * FROM gwwc_import.external_organization_matches WHERE external_organization_id IS NULL
    ) LOOP
      -- Upsert a new org
      INSERT INTO gwwc_import.external_organization (name)
        VALUES (_external_org_match.donation_target)
        ON CONFLICT (name) DO UPDATE SET name = EXCLUDED.name
        RETURNING * INTO _external_org;
      -- Update the mapping with the returned org
      UPDATE gwwc_import.external_organization_matches
        SET (external_organization_id) = (_external_org.id)
        WHERE donation_target = _external_org_match.donation_target;
      PERFORM pg_sleep_for('2 milliseconds');
    END LOOP;
  END
$func$;
