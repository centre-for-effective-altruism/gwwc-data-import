DROP SCHEMA IF EXISTS gwwc_import CASCADE;
CREATE SCHEMA gwwc_import;

CREATE TABLE gwwc_import.person (
  id INTEGER NOT NULL PRIMARY KEY,
  source TEXT,
  first_name citext,
  last_name citext,
  prefix_id TEXT,
  suffix_id TEXT,
  job_title TEXT,
  gender_id TEXT,
  birth_date DATE,
  email citext,
  street_address TEXT,
  supplemental_address_1 TEXT,
  supplemental_address_2 TEXT,
  supplemental_address_3 TEXT,
  city TEXT,
  postal_code TEXT,
  phone TEXT
);

CREATE TABLE gwwc_import.membershipstatus (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  giving_what_we_can_member BOOLEAN,
  trying_out_giving BOOLEAN,
  further_pledge TEXT,
  comments_on_signing_up TEXT,
  confirmed_will_only_enter_real_d TEXT,
  how_much_would_they_have_given_w TEXT,
  welcome_letter_sent_ TEXT,
  wishes_to_remain_anonymous TEXT,
  skype_phone_call_set_up_ TEXT,
  my_giving_user TEXT,
  where_they_are_planning_to_donat TEXT,
  has_gwwc_influenced_their_giving TEXT,
  has_gwwc_influenced_details_ TEXT,
  switched_to_new_pledge_if_joined TEXT,
  trying_giving_ending_email_sent_ TEXT
);

CREATE TABLE gwwc_import.pledgedamounts (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  pledge_percentage TEXT,
  baseline TEXT,
  expected_total_giving_amount TEXT,
  baseline_currency TEXT
);

CREATE TABLE gwwc_import.dates (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  joining_date TEXT,
  left_date_former_members_ TEXT,
  end_date_try_out_givers_ TEXT,
  start_date_trying_giving_ TEXT
);

CREATE TABLE gwwc_import.occupationandincome (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  employment_status TEXT,
  occupation TEXT,
  job_title TEXT,
  company TEXT,
  current_annual_income TEXT,
  expected_average_future_annual_i TEXT,
  currency TEXT,
  total_earning_period_years_ TEXT,
  expected_future_earnings TEXT,
  current_annual_income_currency TEXT
);

CREATE TABLE gwwc_import.volunteering (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  willing_to_volunteer TEXT,
  when_able_to_volunteer TEXT,
  what_are_their_skills TEXT,
  what_department_are_they_volunte TEXT,
  primary_contact TEXT
);

CREATE TABLE gwwc_import.mailinglists (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  loop TEXT,
  oxford_events TEXT,
  cea_office_announcements TEXT,
  cea_office_chat TEXT,
  non_members_newsletter TEXT
);

CREATE TABLE gwwc_import.chapters (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  chapter_they_are_part_of TEXT,
  former_chapter_membership TEXT,
  position_within_chapter TEXT,
  put_in_touch_with_nearest_chapte TEXT,
  put_in_touch_with_other_interest TEXT,
  chapter_they_would_like_to_join TEXT
);

CREATE TABLE gwwc_import.education (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  currently_studying_ TEXT,
  subject TEXT,
  school_university TEXT,
  graduation_year_expected_ TEXT
);

CREATE TABLE gwwc_import.givingreview (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  giving_review_data TEXT,
  market_research_contact TEXT,
  pledge_fulfilled_for_2011 TEXT,
  pledge_fulfilled_for_2012 TEXT
);

CREATE TABLE gwwc_import.donation_info (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  giving_id TEXT,
  donated_pledged_amount_for_2014 TEXT,
  donated_pledged_amount_for_2015 TEXT,
  records_donations_for TEXT,
  donations_recorded_by TEXT,
  donated_pledged_amount_for_2014_ TEXT,
  donated_pledged_amount_for_2015_ TEXT,
  defaultcurrency TEXT,
  yearstartdate TEXT,
  yearstartmonth TEXT,
  lastupdated TEXT,
  public TEXT
);

CREATE TABLE gwwc_import.outreach (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  responded TEXT,
  last_contacted_by TEXT,
  date_started TEXT,
  date_finished TEXT,
  channel TEXT,
  group_name TEXT,
  outcome TEXT,
  other_outcome TEXT,
  next_contact_date TEXT,
  do_not_contact TEXT
);

CREATE TABLE gwwc_import.gwwcinteraction (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  how_they_first_heard_of_gwwc TEXT,
  interaction_since TEXT,
  turning_point TEXT
);

CREATE TABLE gwwc_import.legacydata (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  date_old_pledge_form_submitted TEXT,
  physical_pledge_form_sent_ TEXT
);

CREATE TABLE gwwc_import.onlinecontact (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  facebook_name TEXT,
  twitter_name TEXT,
  skype_name TEXT,
  personal_web_page TEXT
);

CREATE TABLE gwwc_import.diversitymonitoring (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  other_gender_if_applicable_ TEXT
);


------ SPECIAL TABLES
CREATE TABLE gwwc_import.donations (
  id BIGINT PRIMARY KEY DEFAULT generate_id('pledges'),
  md5_hash TEXT UNIQUE,
  contact_id INTEGER NOT NULL REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  created_at TIMESTAMP WITH TIME ZONE,
  target citext,
  currency TEXT REFERENCES public.currency(code),
  amount NUMERIC
);

CREATE INDEX ON gwwc_import.donations (target);

CREATE TABLE gwwc_import.reported_income (
  id BIGINT PRIMARY KEY DEFAULT generate_id('pledges'),
  contact_id INTEGER NOT NULL REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  start_date DATE,
  end_date DATE,
  currency TEXT REFERENCES public.currency(code),
  amount NUMERIC,
  pledge_percentage TEXT
);

CREATE TABLE gwwc_import.recurring_donations (
  id BIGINT PRIMARY KEY DEFAULT generate_id('pledges'),
  contact_id INTEGER NOT NULL REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  start_timestamp TIMESTAMP WITH TIME ZONE,
  end_timestamp TIMESTAMP WITH TIME ZONE,
  frequency_unit TEXT,
  frequency INTEGER,
  target TEXT,
  currency TEXT,
  amount TEXT
);
CREATE INDEX ON gwwc_import.recurring_donations (target);

-- Map entities to person_ids, so that we can always reconstruct data if we only do a partial import
CREATE TABLE gwwc_import.person_to_gwwc_entity (
  entity_id INTEGER PRIMARY KEY REFERENCES gwwc_import.person(id) ON DELETE CASCADE,
  person_id BIGINT REFERENCES people.person(id),
  new_registration BOOLEAN NOT NULL
);

-- Table to hold external organizations and keywords
CREATE TABLE gwwc_import.external_organization_reference (
  id BIGINT,
  reference TEXT,
  PRIMARY KEY (id, reference)
);
CREATE INDEX external_organization_reference_idx ON gwwc_import.external_organization_reference USING btree(reference);


-- Staging for copy of organizations.external_organization
CREATE TABLE gwwc_import.external_organization (
  id BIGINT PRIMARY KEY DEFAULT generate_id('organizations'),
  name TEXT UNIQUE NOT NULL CHECK (char_length(name) > 0),
  keywords TEXT[],
  organization_slug TEXT UNIQUE REFERENCES organizations.organization(slug) ON DELETE CASCADE,
  url TEXT
);
SELECT utils.add_timestamps('gwwc_import.external_organization');
CREATE INDEX on gwwc_import.external_organization USING GIN (keywords);

-- Map donation targets to reported_donation_organizations
CREATE TABLE gwwc_import.external_organization_matches (
  donation_target TEXT PRIMARY KEY,
  external_organization_id BIGINT REFERENCES gwwc_import.external_organization(id)
);
CREATE INDEX external_organization_matches_idx ON gwwc_import.external_organization_matches USING btree(external_organization_id);

-- Tables for the data in the ./data folder
CREATE TABLE gwwc_import.do_not_import(
  email citext PRIMARY KEY CHECK(email = TRIM(email))
);

CREATE TABLE gwwc_import.person_merge_candidates (
  first_name citext CHECK(first_name = TRIM(first_name)),
  last_name citext CHECK(last_name = TRIM(last_name)),
  email citext CHECK(email = TRIM(email)),
  person_first_name citext CHECK(person_first_name = TRIM(person_first_name)),
  person_last_name citext CHECK(person_last_name = TRIM(person_last_name)),
  person_email citext CHECK(person_email = TRIM(person_email)),
  person_id BIGINT REFERENCES people.person(id),
  skip BOOLEAN,
  force_person_id BIGINT REFERENCES people.person(id)
);

CREATE TABLE gwwc_import.remap_emails (
  gwwc_email citext CHECK (gwwc_email = TRIM(gwwc_email)),
  ea_funds_email citext CHECK (ea_funds_email = TRIM(ea_funds_email))
);

CREATE TABLE gwwc_import.unmatched_external_orgs (
  donation_target TEXT PRIMARY KEY,
  remap_to TEXT CHECK (remap_to = TRIM(remap_to)),
  keywords TEXT CHECK (keywords = TRIM(keywords))
);
