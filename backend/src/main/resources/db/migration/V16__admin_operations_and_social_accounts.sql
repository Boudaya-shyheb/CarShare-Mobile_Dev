ALTER TABLE vehicles
    ADD COLUMN review_status VARCHAR(16) NOT NULL DEFAULT 'APPROVED',
    ADD COLUMN review_reason VARCHAR(500);

CREATE TABLE support_tickets (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    trip_id UUID REFERENCES trips(id) ON DELETE SET NULL,
    category VARCHAR(60) NOT NULL,
    title VARCHAR(120) NOT NULL,
    description VARCHAR(1500) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    resolution VARCHAR(1000),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX ix_support_tickets_status_created ON support_tickets(status, created_at DESC);
CREATE INDEX ix_support_tickets_user_created ON support_tickets(user_id, created_at DESC);

CREATE TABLE user_auth_identities (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    provider VARCHAR(16) NOT NULL,
    provider_subject VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_user_auth_provider_subject UNIQUE(provider, provider_subject),
    CONSTRAINT uq_user_auth_provider_user UNIQUE(provider, user_id)
);
