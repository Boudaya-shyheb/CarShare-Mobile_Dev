-- Driver licences can now expire: a daily job moves APPROVED licences past their date to EXPIRED.
ALTER TABLE app_users DROP CONSTRAINT IF EXISTS ck_app_users_driver_license_status;
ALTER TABLE app_users
    ADD CONSTRAINT ck_app_users_driver_license_status
        CHECK (driver_license_status IN ('NOT_SUBMITTED', 'PENDING_REVIEW', 'APPROVED', 'REJECTED', 'EXPIRED'));

-- Deleting an account anonymises it instead of removing the row, so trips, ratings, sanctions
-- and support history keep pointing at somebody ("Deleted user"). The timestamp marks those rows.
ALTER TABLE app_users ADD COLUMN IF NOT EXISTS anonymized_at TIMESTAMPTZ;

COMMENT ON COLUMN app_users.anonymized_at IS 'Set when the user deleted their account: personal data was replaced, history kept.';
