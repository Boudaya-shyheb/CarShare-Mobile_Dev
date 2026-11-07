CREATE TABLE trips (
    id UUID PRIMARY KEY,
    driver_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    vehicle_id UUID,
    origin_label VARCHAR(180) NOT NULL,
    origin_lat DOUBLE PRECISION NOT NULL,
    origin_lng DOUBLE PRECISION NOT NULL,
    destination_label VARCHAR(180) NOT NULL,
    destination_lat DOUBLE PRECISION NOT NULL,
    destination_lng DOUBLE PRECISION NOT NULL,
    departure_time TIMESTAMPTZ NOT NULL,
    seats_total INTEGER NOT NULL CHECK (seats_total BETWEEN 1 AND 8),
    seats_available INTEGER NOT NULL,
    confirmed_seats INTEGER NOT NULL DEFAULT 0,
    price_per_seat NUMERIC(8, 2) NOT NULL CHECK (price_per_seat >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'SCHEDULED'
        CHECK (status IN ('SCHEDULED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP',
                          'IN_PROGRESS', 'COMPLETED', 'CANCELLED')),
    instant_booking BOOLEAN NOT NULL DEFAULT FALSE,
    notes VARCHAR(500),
    cancel_reason VARCHAR(300),
    distance_m INTEGER CHECK (distance_m IS NULL OR distance_m >= 0),
    duration_s INTEGER CHECK (duration_s IS NULL OR duration_s >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ,
    CONSTRAINT ck_trips_seats_available CHECK (seats_available BETWEEN 0 AND seats_total),
    CONSTRAINT ck_trips_confirmed_seats CHECK (confirmed_seats BETWEEN 0 AND seats_total),
    CONSTRAINT ck_trips_origin_lat CHECK (origin_lat BETWEEN -90 AND 90),
    CONSTRAINT ck_trips_origin_lng CHECK (origin_lng BETWEEN -180 AND 180),
    CONSTRAINT ck_trips_destination_lat CHECK (destination_lat BETWEEN -90 AND 90),
    CONSTRAINT ck_trips_destination_lng CHECK (destination_lng BETWEEN -180 AND 180)
);

-- The Vehicles module owns the vehicles table. It will add
-- "ALTER TABLE trips ADD CONSTRAINT fk_trips_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(id)"
-- in its own migration. Until then vehicle_id is an unconstrained nullable UUID.
COMMENT ON COLUMN trips.vehicle_id IS 'Vehicles module adds the foreign key later.';

-- confirmed_seats counts the seats held by CONFIRMED reservations. The reservation step keeps it
-- up to date; a trip with confirmed_seats > 0 is locked against time, route and price changes.
COMMENT ON COLUMN trips.confirmed_seats IS 'Seats held by CONFIRMED reservations; locks the trip.';

CREATE INDEX ix_trips_status_departure ON trips(status, departure_time);
CREATE INDEX ix_trips_driver_departure ON trips(driver_id, departure_time DESC);
CREATE INDEX ix_trips_origin_box ON trips(origin_lat, origin_lng);
CREATE INDEX ix_trips_destination_box ON trips(destination_lat, destination_lng);

CREATE TABLE trip_events (
    id UUID PRIMARY KEY,
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    type VARCHAR(32) NOT NULL
        CHECK (type IN ('PUBLISHED', 'UPDATED', 'DRIVER_EN_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP',
                        'IN_PROGRESS', 'COMPLETED', 'CANCELLED', 'CHECK_IN', 'NO_SHOW', 'DEVIATION')),
    actor_id UUID REFERENCES app_users(id) ON DELETE SET NULL,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION,
    detail VARCHAR(300),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ix_trip_events_trip_created ON trip_events(trip_id, created_at);
