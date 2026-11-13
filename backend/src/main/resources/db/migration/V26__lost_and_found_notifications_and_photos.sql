-- In-app notifications for Lost & Found, and the photo a reporter can attach to a report.

CREATE TABLE lost_and_found_notifications (
    id UUID PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    type VARCHAR(24) NOT NULL
        CONSTRAINT ck_lf_notifications_type CHECK (type IN
            ('MATCH_FOUND', 'MATCH_CONFIRMED', 'MEETING_ARRANGED', 'ITEM_RETURNED', 'NOT_MY_ITEM')),
    -- The notified person's own report, so tapping the notification opens it.
    report_id UUID REFERENCES lost_and_found_reports(id) ON DELETE CASCADE,
    handover_id UUID REFERENCES lost_and_found_handovers(id) ON DELETE CASCADE,
    title VARCHAR(120) NOT NULL,
    body VARCHAR(400) NOT NULL,
    read_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ix_lf_notifications_user_created ON lost_and_found_notifications(user_id, created_at DESC);
CREATE INDEX ix_lf_notifications_unread ON lost_and_found_notifications(user_id) WHERE read_at IS NULL;

-- The photo lives on disk (like Support evidence); the report keeps its file name and type.
ALTER TABLE lost_and_found_reports
    ADD COLUMN photo_file_name VARCHAR(60),
    ADD COLUMN photo_content_type VARCHAR(30);
