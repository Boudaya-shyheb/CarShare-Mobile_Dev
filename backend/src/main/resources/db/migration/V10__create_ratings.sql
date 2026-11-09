CREATE TABLE ratings (
    id UUID PRIMARY KEY,
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    from_user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    to_user_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    stars SMALLINT NOT NULL,
    comment VARCHAR(500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ,
    CONSTRAINT ck_ratings_stars CHECK (stars BETWEEN 1 AND 5),
    CONSTRAINT ck_ratings_not_self CHECK (from_user_id <> to_user_id),
    CONSTRAINT uq_ratings_trip_from_to UNIQUE (trip_id, from_user_id, to_user_id)
);

-- One rating per (trip, rater, rated): a passenger rates the driver once per trip, and the
-- driver rates each passenger once. The unique constraint is what makes a second POST a 409
-- rather than a duplicate row; editing goes through PUT while the 24 h window is open.
COMMENT ON CONSTRAINT uq_ratings_trip_from_to ON ratings IS
    'One rating per rater/rated pair per trip; edits replace it in place.';

-- The profile average reads the newest ratings a user received, so this is the access path.
CREATE INDEX ix_ratings_to_user_created ON ratings(to_user_id, created_at DESC);

-- "Have I already rated this trip?" on the completion screen.
CREATE INDEX ix_ratings_trip_from ON ratings(trip_id, from_user_id);
