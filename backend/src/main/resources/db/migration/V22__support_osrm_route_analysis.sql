ALTER TABLE ticket_geo_investigations
    ADD COLUMN IF NOT EXISTS destination_lat DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS destination_lng DOUBLE PRECISION,
    ADD COLUMN IF NOT EXISTS ideal_distance_m INTEGER,
    ADD COLUMN IF NOT EXISTS ideal_duration_s INTEGER,
    ADD COLUMN IF NOT EXISTS actual_distance_m INTEGER,
    ADD COLUMN IF NOT EXISTS route_polyline TEXT,
    ADD COLUMN IF NOT EXISTS route_verdict VARCHAR(30),
    ADD COLUMN IF NOT EXISTS route_error VARCHAR(500);
