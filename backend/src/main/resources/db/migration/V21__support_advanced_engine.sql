ALTER TABLE support_tickets
    ADD COLUMN IF NOT EXISTS priority_calculated_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS ticket_risk_signals (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    term VARCHAR(40) NOT NULL,
    excerpt VARCHAR(240) NOT NULL,
    negated BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_ticket_risk_signal UNIQUE (ticket_id, term, negated)
);

CREATE INDEX IF NOT EXISTS idx_ticket_risk_signals_ticket
    ON ticket_risk_signals(ticket_id);

CREATE TABLE IF NOT EXISTS ticket_escalation_events (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    event_key VARCHAR(180) NOT NULL UNIQUE,
    event_type VARCHAR(30) NOT NULL,
    message VARCHAR(500) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_ticket_escalations_ticket
    ON ticket_escalation_events(ticket_id);

CREATE TABLE IF NOT EXISTS support_agent_profiles (
    user_id UUID PRIMARY KEY REFERENCES app_users(id) ON DELETE CASCADE,
    available BOOLEAN NOT NULL DEFAULT TRUE,
    skills VARCHAR(500) NOT NULL DEFAULT 'GENERAL',
    capacity INTEGER NOT NULL DEFAULT 10 CHECK (capacity BETWEEN 1 AND 100),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO support_agent_profiles(user_id, available, skills, capacity)
SELECT id, TRUE, 'GENERAL', 10 FROM app_users WHERE role = 'ADMIN'
ON CONFLICT (user_id) DO NOTHING;

CREATE TABLE IF NOT EXISTS ticket_assignment_proposals (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    agent_id UUID NOT NULL REFERENCES app_users(id),
    algorithm VARCHAR(30) NOT NULL,
    score INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL,
    explanation VARCHAR(500) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    confirmed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_assignment_proposals_ticket
    ON ticket_assignment_proposals(ticket_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ticket_evidence_analyses (
    id UUID PRIMARY KEY,
    evidence_id UUID NOT NULL UNIQUE REFERENCES ticket_evidence(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    detected_type VARCHAR(120),
    sha256 VARCHAR(64) NOT NULL,
    duplicate_evidence_id UUID REFERENCES ticket_evidence(id) ON DELETE SET NULL,
    metadata TEXT,
    extracted_text TEXT,
    error_message VARCHAR(500),
    analyzed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_evidence_analysis_sha256
    ON ticket_evidence_analyses(sha256);

CREATE TABLE IF NOT EXISTS ticket_weather_contexts (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL UNIQUE REFERENCES support_tickets(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL,
    temperature_c DOUBLE PRECISION,
    precipitation_mm DOUBLE PRECISION,
    wind_speed_kmh DOUBLE PRECISION,
    weather_code INTEGER,
    source VARCHAR(100) NOT NULL,
    error_message VARCHAR(500),
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ticket_geo_investigations (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL UNIQUE REFERENCES support_tickets(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL,
    planned_lat DOUBLE PRECISION NOT NULL,
    planned_lng DOUBLE PRECISION NOT NULL,
    actual_lat DOUBLE PRECISION,
    actual_lng DOUBLE PRECISION,
    actual_recorded_at TIMESTAMPTZ,
    nearby_places TEXT,
    source VARCHAR(100) NOT NULL,
    error_message VARCHAR(500),
    fetched_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
