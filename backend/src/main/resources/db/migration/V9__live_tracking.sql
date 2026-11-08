CREATE TABLE gps_points (
    id BIGSERIAL PRIMARY KEY,
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    lat DOUBLE PRECISION NOT NULL,
    lng DOUBLE PRECISION NOT NULL,
    speed_mps REAL,
    recorded_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT ck_gps_points_lat CHECK (lat BETWEEN -90 AND 90),
    CONSTRAINT ck_gps_points_lng CHECK (lng BETWEEN -180 AND 180),
    CONSTRAINT ck_gps_points_speed CHECK (speed_mps IS NULL OR speed_mps >= 0)
);

-- recorded_at is the phone's own timestamp, so an offline buffer keeps its real order; created_at
-- is when the server received it. The replay screen (step 10) reads them in recorded_at order.
COMMENT ON COLUMN gps_points.recorded_at IS 'When the phone took the fix, not when it arrived.';

CREATE INDEX ix_gps_points_trip_recorded ON gps_points(trip_id, recorded_at);

ALTER TABLE trips
    ADD COLUMN last_lat DOUBLE PRECISION,
    ADD COLUMN last_lng DOUBLE PRECISION,
    ADD COLUMN last_position_at TIMESTAMPTZ,
    ADD COLUMN route_polyline TEXT,
    ADD COLUMN deviating BOOLEAN NOT NULL DEFAULT FALSE;

-- The newest kept position, copied out of gps_points so the live view is one row read.
COMMENT ON COLUMN trips.last_position_at IS 'recorded_at of the newest kept gps_points row.';

-- Google encoded polyline of the planned route, sent by the app when the trip is published. The
-- deviation check needs it; with no polyline the check is skipped.
COMMENT ON COLUMN trips.route_polyline IS 'Google encoded polyline of the planned route.';

ALTER TABLE reservations ADD COLUMN checked_in_at TIMESTAMPTZ;

COMMENT ON COLUMN reservations.checked_in_at IS 'When the driver typed the right pickup code.';

-- Same approach as V8: drop whichever check guards trip_events.type rather than trusting the
-- constraint name, then re-add it with the two new tracking event types.
DO $$
DECLARE guard TEXT;
BEGIN
    FOR guard IN
        SELECT con.conname
        FROM pg_constraint con
        JOIN pg_class rel ON rel.oid = con.conrelid
        WHERE rel.relname = 'trip_events'
          AND con.contype = 'c'
          AND pg_get_constraintdef(con.oid) LIKE '%type%'
    LOOP
        EXECUTE format('ALTER TABLE trip_events DROP CONSTRAINT %I', guard);
    END LOOP;
END $$;

ALTER TABLE trip_events ADD CONSTRAINT ck_trip_events_type CHECK (type IN (
    'PUBLISHED', 'UPDATED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP', 'IN_PROGRESS',
    'COMPLETED', 'CANCELLED', 'CHECK_IN', 'NO_SHOW', 'DEVIATION',
    'RESERVATION_REQUESTED', 'RESERVATION_CONFIRMED', 'RESERVATION_REFUSED',
    'RESERVATION_CANCELLED', 'CHECK_IN_FAILED', 'DEVIATION_RESOLVED'));
