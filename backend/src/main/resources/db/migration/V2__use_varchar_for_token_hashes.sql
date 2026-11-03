ALTER TABLE auth_sessions
    ALTER COLUMN token_hash TYPE VARCHAR(64);

ALTER TABLE password_reset_tokens
    ALTER COLUMN token_hash TYPE VARCHAR(64);
