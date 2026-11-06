CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
    language VARCHAR(10) NOT NULL DEFAULT 'en' CHECK (language IN ('en', 'fr', 'ar')),
    home_place VARCHAR(180),
    work_place VARCHAR(180),
    campus_place VARCHAR(180),
    music_allowed BOOLEAN NOT NULL DEFAULT TRUE,
    smoking_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    pets_allowed BOOLEAN NOT NULL DEFAULT FALSE,
    luggage_preference VARCHAR(20) NOT NULL DEFAULT 'standard'
        CHECK (luggage_preference IN ('standard', 'small', 'large')),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_sanctions (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    points INTEGER NOT NULL CHECK (points BETWEEN 1 AND 12),
    reason VARCHAR(500) NOT NULL,
    issued_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX ix_user_sanctions_user_issued ON user_sanctions(user_id, issued_at DESC);
CREATE INDEX ix_user_sanctions_expires ON user_sanctions(expires_at);

CREATE TABLE user_emergency_contacts (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    phone VARCHAR(24) NOT NULL,
    relationship VARCHAR(40) NOT NULL
);

CREATE INDEX ix_user_emergency_contacts_user ON user_emergency_contacts(user_id, name);
