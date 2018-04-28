-- Create people with remapped email addresses
CREATE FUNCTION gwwc_import.remap_email_addresses ()
RETURNS SETOF gwwc_import.person_to_gwwc_entity AS $$
  DECLARE
    new_registration BOOLEAN;
    _mapping gwwc_import.remap_emails;
    _person people.person;
    _gwwc_person gwwc_import.person;
  BEGIN
    -- loop through all our remappings
    FOR _mapping IN (SELECT * FROM gwwc_import.remap_emails) LOOP
      -- Get the person's details
      SELECT * INTO _gwwc_person FROM gwwc_import.person
        WHERE email IN (TRIM(_mapping.gwwc_email), TRIM(_mapping.ea_funds_email));
      IF NOT FOUND THEN
        RAISE EXCEPTION 'Cannot remap % -> %, email addresses not found', _mapping.gwwc_email, _mapping.ea_funds_email;
      END IF;
      -- check if either of the remap candidate emails exist
      SELECT * INTO _person FROM people.person WHERE id IN (
        SELECT person_id FROM people.email_address
        WHERE email IN (_mapping.ea_funds_email, _mapping.gwwc_email)
      );
      -- FOUND
      IF FOUND THEN
        new_registration = FALSE;
        -- check that both email addresses are in the db
        INSERT INTO people.email_address (person_id, email) VALUES
          (_person.id, _mapping.gwwc_email),
          (_person.id, _mapping.ea_funds_email)
        ON CONFLICT DO NOTHING;
        -- make sure we're using their remap preference as their primary email
        UPDATE people.person SET email = _mapping.ea_funds_email WHERE id = _person.id;
      -- NOT FOUND
      ELSE
        new_registration = TRUE;
        -- Create the person
        _person := people.register_person_shadow(
          _mapping.ea_funds_email,
          _gwwc_person.first_name,
          _gwwc_person.last_name,
          'import'
        );
        -- Make sure the GWWC address is on file
        INSERT INTO people.email_address (person_id, email) VALUES
          (_person.id, _mapping.gwwc_email)
        ON CONFLICT DO NOTHING;
      END IF; -- end 'IF FOUND'
      -- Save the mapping
      RETURN QUERY INSERT INTO gwwc_import.person_to_gwwc_entity (person_id, entity_id, new_registration) VALUES
        (_person.id, _gwwc_person.id, new_registration) RETURNING *;
    END LOOP;
  END
$$ LANGUAGE plpgsql VOLATILE;

-- Import all merge candidates
CREATE FUNCTION gwwc_import.merge_person_merge_candidates()
RETURNS SETOF gwwc_import.person_to_gwwc_entity AS $func$
  DECLARE
    _candidate gwwc_import.person_merge_candidates;
    _gwwc_person gwwc_import.person;
  BEGIN
    FOR _candidate IN (SELECT * FROM gwwc_import.person_merge_candidates WHERE NOT skip) LOOP
      -- Find the person entry
      SELECT * INTO _gwwc_person FROM gwwc_import.person
        WHERE email = _candidate.email;
      -- Some of these candidates may have already been deleted on import (e.g. test users)
      IF NOT FOUND THEN
        CONTINUE;
      END IF;
      -- Make sure the candidate's email is on file
      INSERT INTO people.email_address (person_id, email) VALUES
        (_candidate.person_id, _candidate.email)
        ON CONFLICT DO NOTHING;
      -- Store the mapping
      RETURN QUERY INSERT INTO gwwc_import.person_to_gwwc_entity (person_id, entity_id, new_registration) VALUES
        (_candidate.person_id, _gwwc_person.id, FALSE)
      ON CONFLICT (entity_id) DO NOTHING
      RETURNING *;
    END LOOP;
  END
$func$ LANGUAGE plpgsql VOLATILE;

-- Import the rest of the people
CREATE FUNCTION gwwc_import.migrate_people()
RETURNS SETOF gwwc_import.person_to_gwwc_entity AS $func$
  DECLARE
    c INTEGER = 0;
    t INTEGER;
    _gwwc_person gwwc_import.person;
    _result people.find_or_register_person_shadow_result;
  BEGIN
    -- Figure out how many rows we need to migrate
    SELECT count(*) INTO t FROM gwwc_import.person WHERE email IS NOT NULL AND id NOT IN (
      SELECT entity_id FROM gwwc_import.person_to_gwwc_entity
    );
    FOR _gwwc_person IN (
      SELECT * FROM gwwc_import.person WHERE email IS NOT NULL AND id NOT IN (
        SELECT entity_id FROM gwwc_import.person_to_gwwc_entity
      )
    ) LOOP
      _result = people.find_or_register_person_shadow(
        _gwwc_person.email,
        _gwwc_person.first_name,
        _gwwc_person.last_name
      );
      RETURN QUERY INSERT INTO gwwc_import.person_to_gwwc_entity (person_id, entity_id, new_registration) VALUES
        (_result.person_id, _gwwc_person.id, _result.new_registration) RETURNING *;
      c := c + 1;
      -- Print a notice so we know how far in we are
      IF c % 500 = 0 THEN
        RAISE NOTICE 'Migrated %/% people', c, t;
      END IF;
    END LOOP;
  END
$func$ LANGUAGE plpgsql VOLATILE;

-- Verify the data
CREATE FUNCTION gwwc_import.validate_people_migration()
RETURNS VOID AS $func$
DECLARE
  count INTEGER;
BEGIN
  -- From https://dba.stackexchange.com/a/72656/139843
  SELECT count(*) INTO count FROM (
    SELECT * FROM (SELECT id AS entity_id FROM gwwc_import.person WHERE email IS NOT NULL) AS a
    FULL OUTER JOIN (SELECT entity_id FROM gwwc_import.person_to_gwwc_entity) b
    USING(entity_id)
    WHERE a.entity_id IS NULL
       OR b.entity_id IS NULL
  ) s;
  IF count <> 0 THEN
    RAISE EXCEPTION 'Person migration failed, % rows are different', count;
  ELSE
    RAISE NOTICE 'All people successfully migrated!';
  END IF;
END
$func$ LANGUAGE plpgsql STABLE;

-- Use a DO with PERFORM to suppress row outputs
DO $$ BEGIN
  RAISE NOTICE 'Remapping emails';
  PERFORM gwwc_import.remap_email_addresses();
  RAISE NOTICE 'Merging merge candidates';
  PERFORM gwwc_import.merge_person_merge_candidates();
  RAISE NOTICE 'Migrating everyone else';
  PERFORM gwwc_import.migrate_people();
  RAISE NOTICE 'Validating the migration';
  PERFORM gwwc_import.validate_people_migration();
END $$;

DO $$ BEGIN
  RAISE NOTICE 'Copying birth dates';
  WITH person_birthdates AS (
    SELECT gwwc_person.birth_date, mapping.person_id
    FROM gwwc_import.person_to_gwwc_entity AS mapping
    JOIN gwwc_import.person gwwc_person ON mapping.entity_id = gwwc_person.id
  )
  UPDATE people.person
    SET (birth_date) = (person_birthdates.birth_date)
    FROM person_birthdates
    WHERE id = person_birthdates.person_id;
END $$;

DROP FUNCTION gwwc_import.remap_email_addresses();
DROP FUNCTION gwwc_import.merge_person_merge_candidates();
DROP FUNCTION gwwc_import.migrate_people();
DROP FUNCTION gwwc_import.validate_people_migration();
