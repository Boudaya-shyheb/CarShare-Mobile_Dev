CREATE TABLE reservations (
    id UUID PRIMARY KEY,
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    passenger_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    seats SMALLINT NOT NULL,
    status VARCHAR(16) NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING', 'CONFIRMED', 'REFUSED', 'CANCELLED', 'NO_SHOW', 'COMPLETED')),
    pickup_code CHAR(4) NOT NULL,
    pickup_code_attempts SMALLINT NOT NULL DEFAULT 0,
    late_cancellation BOOLEAN NOT NULL DEFAULT FALSE,
    cancel_reason VARCHAR(255),
    decided_at TIMESTAMPTZ,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ,
    CONSTRAINT ck_reservations_seats CHECK (seats BETWEEN 1 AND 8),
    CONSTRAINT ck_reservations_pickup_code CHECK (pickup_code ~ '^[0-9]{4}$'),
    CONSTRAINT ck_reservations_pickup_code_attempts CHECK (pickup_code_attempts >= 0)
);

-- The pickup code is stored in plain text on purpose: it is only ever returned to the passenger
-- who owns the reservation, and the driver has to type it in at pickup to compare against it.
COMMENT ON COLUMN reservations.pickup_code IS 'Shown to the owning passenger only; never to the driver.';

-- The attempt cap (3) is enforced by the service at check-in time, not by this constraint, so a
-- later step can change the cap without another migration.
COMMENT ON COLUMN reservations.pickup_code_attempts IS 'Wrong pickup codes typed by the driver.';

-- A passenger holds at most one live reservation per trip. REFUSED, CANCELLED, NO_SHOW and
-- COMPLETED rows stay out of the index, so the same passenger may book again after a refusal.
CREATE UNIQUE INDEX uq_reservations_active_per_passenger
    ON reservations(trip_id, passenger_id)
    WHERE status IN ('PENDING', 'CONFIRMED');

CREATE INDEX ix_reservations_trip_id ON reservations(trip_id);
CREATE INDEX ix_reservations_passenger_id ON reservations(passenger_id);
CREATE INDEX ix_reservations_status ON reservations(status);
-- The overlap rule reads a passenger's live reservations; the auto-refuse job reads PENDING ones.
CREATE INDEX ix_reservations_passenger_status ON reservations(passenger_id, status);

-- V7 declared the trip_events type check inline, so Postgres named it trip_events_type_check.
-- Drop whichever check currently guards the column rather than trusting that name, then re-add
-- it with the four reservation event types.
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
    'RESERVATION_CANCELLED'));
