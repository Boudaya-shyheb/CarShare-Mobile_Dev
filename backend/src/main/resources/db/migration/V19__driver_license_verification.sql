ALTER TABLE app_users
    ADD COLUMN IF NOT EXISTS driver_license_expiry DATE,
    ADD COLUMN IF NOT EXISTS driver_license_status VARCHAR(20) NOT NULL DEFAULT 'NOT_SUBMITTED',
    ADD COLUMN IF NOT EXISTS driver_license_review_reason VARCHAR(500),
    ADD COLUMN IF NOT EXISTS driver_license_image BYTEA,
    ADD COLUMN IF NOT EXISTS driver_license_content_type VARCHAR(50);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'ck_app_users_driver_license_status'
          AND conrelid = 'app_users'::regclass
    ) THEN
        ALTER TABLE app_users
            ADD CONSTRAINT ck_app_users_driver_license_status
                CHECK (driver_license_status IN ('NOT_SUBMITTED', 'PENDING_REVIEW', 'APPROVED', 'REJECTED'));
    END IF;
END $$;
