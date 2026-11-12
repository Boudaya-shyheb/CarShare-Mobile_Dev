CREATE TABLE ticket_contestations (
    id UUID PRIMARY KEY,
    ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
    contested_by UUID REFERENCES app_users(id) ON DELETE SET NULL,
    reason VARCHAR(1000) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_ticket_contestation_party UNIQUE (ticket_id, contested_by),
    CONSTRAINT ck_ticket_contestation_reason CHECK (length(trim(reason)) > 0)
);

CREATE INDEX ix_ticket_contestations_ticket_created
    ON ticket_contestations(ticket_id, created_at);
CREATE INDEX ix_ticket_contestations_user ON ticket_contestations(contested_by);
