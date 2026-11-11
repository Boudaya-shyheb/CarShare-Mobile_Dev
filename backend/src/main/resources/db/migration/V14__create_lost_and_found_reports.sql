CREATE TABLE lost_and_found_reports (
    id UUID PRIMARY KEY,
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    reporter_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    report_type VARCHAR(10) NOT NULL
        CHECK (report_type IN ('LOST', 'FOUND')),
    title VARCHAR(100) NOT NULL CHECK (btrim(title) <> ''),
    description VARCHAR(1000) NOT NULL CHECK (btrim(description) <> ''),
    status VARCHAR(10) NOT NULL DEFAULT 'OPEN'
        CHECK (status IN ('OPEN', 'RESOLVED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ix_lost_and_found_reports_trip_created
    ON lost_and_found_reports(trip_id, created_at DESC);

CREATE INDEX ix_lost_and_found_reports_reporter
    ON lost_and_found_reports(reporter_id);