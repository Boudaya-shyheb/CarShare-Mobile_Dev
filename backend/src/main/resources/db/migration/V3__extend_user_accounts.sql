ALTER TABLE app_users
    ADD COLUMN account_status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE'
        CHECK (account_status IN ('ACTIVE', 'WARNING', 'SUSPENDED', 'BANNED')),
    ADD COLUMN status_until TIMESTAMPTZ,
    ADD COLUMN failed_sign_in_attempts INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN sign_in_locked_until TIMESTAMPTZ,
    ADD COLUMN profile_photo BYTEA,
    ADD COLUMN profile_photo_mime_type VARCHAR(50);

-- Existing accounts may already share a phone number. Preserve those records,
-- while enforcing uniqueness for every newly created or changed phone number.
-- The advisory lock makes the check safe when concurrent sign-ups use the
-- same normalized phone number.
CREATE FUNCTION enforce_unique_app_user_phone() RETURNS trigger AS $$
DECLARE
    normalized_phone TEXT;
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.phone IS NOT DISTINCT FROM OLD.phone THEN
        RETURN NEW;
    END IF;

    normalized_phone := regexp_replace(NEW.phone, '[[:space:]().-]', '', 'g');
    PERFORM pg_advisory_xact_lock(hashtextextended(normalized_phone, 0));

    IF EXISTS (
        SELECT 1
        FROM app_users existing
        WHERE existing.id <> NEW.id
          AND regexp_replace(existing.phone, '[[:space:]().-]', '', 'g') = normalized_phone
    ) THEN
        RAISE EXCEPTION 'An account already exists for this phone number.'
            USING ERRCODE = '23505', CONSTRAINT = 'uq_app_users_phone';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_app_users_unique_phone
    BEFORE INSERT OR UPDATE OF phone ON app_users
    FOR EACH ROW EXECUTE FUNCTION enforce_unique_app_user_phone();
