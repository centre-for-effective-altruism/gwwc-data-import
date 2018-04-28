-- Copy from the external_organization table, updating keywords as necessary
INSERT INTO organizations.external_organization
(SELECT * FROM gwwc_import.external_organization)
ON CONFLICT (id) DO UPDATE SET keywords=EXCLUDED.keywords
;
