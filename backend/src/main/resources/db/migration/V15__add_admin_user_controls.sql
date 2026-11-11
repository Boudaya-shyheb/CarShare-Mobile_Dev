ALTER TABLE app_users
    ADD COLUMN status_reason VARCHAR(500),
    ADD COLUMN status_manually_set BOOLEAN NOT NULL DEFAULT FALSE;
