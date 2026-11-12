-- The handover of a lost item: one row per (lost report, found report) pair that two people on the
-- same trip are trying to complete. Both reporters read and change the same row, so the meeting
-- point, the status and the check code are no longer kept on one phone each.
CREATE TABLE lost_and_found_handovers (
    id UUID PRIMARY KEY,
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    lost_report_id UUID NOT NULL REFERENCES lost_and_found_reports(id) ON DELETE CASCADE,
    found_report_id UUID NOT NULL REFERENCES lost_and_found_reports(id) ON DELETE CASCADE,
    status VARCHAR(10) NOT NULL DEFAULT 'PROPOSED',
    meeting_point VARCHAR(120),
    meeting_time VARCHAR(80),
    code VARCHAR(4),
    failed_attempts SMALLINT NOT NULL DEFAULT 0,
    created_by UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_lf_handovers_status
        CHECK (status IN ('PROPOSED', 'ARRANGED', 'COMPLETED', 'CANCELLED')),
    CONSTRAINT ck_lf_handovers_code CHECK (code IS NULL OR code ~ '^[0-9]{4}$'),
    CONSTRAINT ck_lf_handovers_attempts CHECK (failed_attempts >= 0),
    CONSTRAINT ck_lf_handovers_distinct_reports CHECK (lost_report_id <> found_report_id)
);

-- A report can be in at most one live handover at a time. Finished and cancelled ones stay as
-- history, so the partial indexes only cover the two live statuses.
CREATE UNIQUE INDEX uq_lf_handovers_active_lost
    ON lost_and_found_handovers(lost_report_id)
    WHERE status IN ('PROPOSED', 'ARRANGED');

CREATE UNIQUE INDEX uq_lf_handovers_active_found
    ON lost_and_found_handovers(found_report_id)
    WHERE status IN ('PROPOSED', 'ARRANGED');

CREATE INDEX ix_lf_handovers_trip ON lost_and_found_handovers(trip_id);
CREATE INDEX ix_lf_handovers_found_report ON lost_and_found_handovers(found_report_id);
