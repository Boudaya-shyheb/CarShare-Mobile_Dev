CREATE TABLE ticket_categories (
    id UUID PRIMARY KEY,
    name VARCHAR(60) NOT NULL UNIQUE,
    severity SMALLINT NOT NULL,
    priority VARCHAR(12) NOT NULL,
    response_delay_hours INTEGER NOT NULL,
    verification_type VARCHAR(16) NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_ticket_categories_severity CHECK (severity BETWEEN 1 AND 5),
    CONSTRAINT ck_ticket_categories_priority CHECK (priority IN ('NORMAL', 'HIGH')),
    CONSTRAINT ck_ticket_categories_response_delay CHECK (response_delay_hours > 0),
    CONSTRAINT ck_ticket_categories_verification CHECK (
        verification_type IN ('AUTOMATIC', 'MANUAL', 'HYBRID')
    )
);

INSERT INTO ticket_categories
    (id, name, severity, priority, response_delay_hours, verification_type)
VALUES
    ('00000000-0000-0000-0000-000000000501', 'Driver was late', 2, 'HIGH', 24, 'AUTOMATIC'),
    ('00000000-0000-0000-0000-000000000502', 'Driver didn''t show up', 3, 'HIGH', 24, 'AUTOMATIC'),
    ('00000000-0000-0000-0000-000000000503', 'Passenger didn''t show up', 3, 'HIGH', 24, 'AUTOMATIC'),
    ('00000000-0000-0000-0000-000000000504', 'Wrong route taken', 2, 'NORMAL', 72, 'AUTOMATIC'),
    ('00000000-0000-0000-0000-000000000505', 'Behaviour issue', 4, 'HIGH', 24, 'MANUAL'),
    ('00000000-0000-0000-0000-000000000506', 'Vehicle condition', 4, 'HIGH', 24, 'MANUAL'),
    ('00000000-0000-0000-0000-000000000507', 'Other', 1, 'NORMAL', 72, 'MANUAL');

-- Keep every legacy category instead of rewriting old ticket data to "Other".
INSERT INTO ticket_categories
    (id, name, severity, priority, response_delay_hours, verification_type)
SELECT md5('carshare-support-category:' || lower(trim(t.category)))::UUID,
       trim(t.category), 1, 'NORMAL', 72, 'MANUAL'
FROM (SELECT DISTINCT category FROM support_tickets) t
WHERE NOT EXISTS (
    SELECT 1 FROM ticket_categories c WHERE lower(c.name) = lower(trim(t.category))
);

ALTER TABLE support_tickets
    ADD COLUMN reference VARCHAR(24),
    ADD COLUMN reservation_id UUID REFERENCES reservations(id) ON DELETE SET NULL,
    ADD COLUMN reported_user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
    ADD COLUMN category_id UUID REFERENCES ticket_categories(id) ON DELETE RESTRICT,
    ADD COLUMN priority_score NUMERIC(10, 2) NOT NULL DEFAULT 0,
    ADD COLUMN deadline TIMESTAMPTZ,
    ADD COLUMN grouped_case_id UUID REFERENCES support_tickets(id) ON DELETE SET NULL,
    ADD COLUMN assigned_agent_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
    ADD COLUMN withdrawn_at TIMESTAMPTZ;

UPDATE support_tickets t
SET reference = 'DSP-' || to_char(t.created_at, 'YYYY') || '-'
        || upper(substr(replace(t.id::TEXT, '-', ''), 1, 8)),
    category_id = c.id,
    deadline = t.created_at + INTERVAL '72 hours'
FROM ticket_categories c
WHERE lower(c.name) = lower(trim(t.category));

ALTER TABLE support_tickets
    ALTER COLUMN reference SET NOT NULL,
    ALTER COLUMN category_id SET NOT NULL,
    ALTER COLUMN deadline SET NOT NULL,
    ADD CONSTRAINT uq_support_tickets_reference UNIQUE (reference),
    ADD CONSTRAINT ck_support_tickets_status CHECK (
        status IN ('OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW', 'RESOLVED',
                   'CLOSED', 'WITHDRAWN', 'CONTESTED')
    ),
    ADD CONSTRAINT ck_support_tickets_priority_score CHECK (priority_score >= 0);

-- A deleted account is anonymised in Support instead of deleting its ticket history.
ALTER TABLE support_tickets DROP CONSTRAINT support_tickets_user_id_fkey;
ALTER TABLE support_tickets ALTER COLUMN user_id DROP NOT NULL;
ALTER TABLE support_tickets
    ADD CONSTRAINT support_tickets_user_id_fkey
    FOREIGN KEY (user_id) REFERENCES app_users(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX uq_support_ticket_reservation_category
    ON support_tickets(reservation_id, category_id)
    WHERE reservation_id IS NOT NULL;
CREATE INDEX ix_support_tickets_category ON support_tickets(category_id);
CREATE INDEX ix_support_tickets_reservation ON support_tickets(reservation_id);
CREATE INDEX ix_support_tickets_reported_user ON support_tickets(reported_user_id);
CREATE INDEX ix_support_tickets_agent_status ON support_tickets(assigned_agent_id, status);
CREATE INDEX ix_support_tickets_status_deadline ON support_tickets(status, deadline);
CREATE INDEX ix_support_tickets_grouped_case ON support_tickets(grouped_case_id);

CREATE TABLE ticket_evidence (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    type VARCHAR(16) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    original_file_name VARCHAR(255) NOT NULL,
    content_type VARCHAR(100) NOT NULL,
    file_size BIGINT NOT NULL,
    uploaded_by_user_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_ticket_evidence_type CHECK (type IN ('PHOTO', 'DOCUMENT', 'TRIP_DATA')),
    CONSTRAINT ck_ticket_evidence_size CHECK (file_size >= 0 AND file_size <= 5242880)
);
CREATE INDEX ix_ticket_evidence_ticket_created ON ticket_evidence(ticket_id, created_at);
CREATE INDEX ix_ticket_evidence_uploader ON ticket_evidence(uploaded_by_user_id);

CREATE TABLE ticket_statements (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    author_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
    statement_text VARCHAR(2000) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_ticket_statements_party UNIQUE (ticket_id, author_id),
    CONSTRAINT ck_ticket_statements_text CHECK (length(trim(statement_text)) > 0)
);
CREATE INDEX ix_ticket_statements_ticket_created ON ticket_statements(ticket_id, created_at);
CREATE INDEX ix_ticket_statements_author ON ticket_statements(author_id);

CREATE TABLE ticket_decisions (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    result VARCHAR(16) NOT NULL,
    reason VARCHAR(1500) NOT NULL,
    penalty_points SMALLINT NOT NULL DEFAULT 0,
    decided_by UUID REFERENCES app_users(id) ON DELETE SET NULL,
    decided_by_system BOOLEAN NOT NULL DEFAULT FALSE,
    decision_number SMALLINT NOT NULL DEFAULT 1,
    final_decision BOOLEAN NOT NULL DEFAULT FALSE,
    decided_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_ticket_decisions_number UNIQUE (ticket_id, decision_number),
    CONSTRAINT ck_ticket_decisions_result CHECK (result IN ('CONFIRMED', 'REJECTED', 'PARTIAL')),
    CONSTRAINT ck_ticket_decisions_points CHECK (penalty_points BETWEEN 0 AND 12),
    CONSTRAINT ck_ticket_decisions_number CHECK (decision_number BETWEEN 1 AND 2)
);
CREATE INDEX ix_ticket_decisions_ticket_date ON ticket_decisions(ticket_id, decided_at);
CREATE INDEX ix_ticket_decisions_decider ON ticket_decisions(decided_by);

CREATE TABLE credibility_scores (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL UNIQUE REFERENCES app_users(id) ON DELETE CASCADE,
    score SMALLINT NOT NULL DEFAULT 100,
    blocked_until TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_credibility_scores_score CHECK (score BETWEEN 0 AND 100)
);
CREATE INDEX ix_credibility_scores_blocked ON credibility_scores(blocked_until);

CREATE TABLE support_ticket_status_history (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    from_status VARCHAR(20),
    to_status VARCHAR(20) NOT NULL,
    changed_by UUID REFERENCES app_users(id) ON DELETE SET NULL,
    changed_by_system BOOLEAN NOT NULL DEFAULT FALSE,
    reason VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_support_history_from_status CHECK (
        from_status IS NULL OR from_status IN ('OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW',
            'RESOLVED', 'CLOSED', 'WITHDRAWN', 'CONTESTED')
    ),
    CONSTRAINT ck_support_history_to_status CHECK (
        to_status IN ('OPEN', 'AWAITING_RESPONSE', 'UNDER_REVIEW', 'RESOLVED',
            'CLOSED', 'WITHDRAWN', 'CONTESTED')
    )
);
CREATE INDEX ix_support_history_ticket_created
    ON support_ticket_status_history(ticket_id, created_at);
CREATE INDEX ix_support_history_changed_by ON support_ticket_status_history(changed_by);
