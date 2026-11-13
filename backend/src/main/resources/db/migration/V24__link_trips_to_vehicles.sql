-- Trips now point at a real vehicle. V7 left trips.vehicle_id as a bare UUID "until the Vehicles
-- module adds the foreign key"; this is that migration.

-- Old rows may carry a value that points nowhere (a vehicle since deleted) or at somebody else's
-- vehicle. Clear those first, otherwise the constraint below could not be added.
UPDATE trips
SET vehicle_id = NULL
WHERE vehicle_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM vehicles v
      WHERE v.id = trips.vehicle_id AND v.owner_id = trips.driver_id
  );

-- Nullable for trips published before this migration; the API requires a vehicle for new ones.
-- Deleting a vehicle keeps the trip history and just forgets which car it was.
ALTER TABLE trips
    ADD CONSTRAINT fk_trips_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(id) ON DELETE SET NULL;

-- "Used in N trips" and the vehicle-in-use check both look trips up by vehicle.
CREATE INDEX ix_trips_vehicle_id ON trips(vehicle_id);

COMMENT ON COLUMN trips.vehicle_id IS 'The driver''s vehicle for this trip; null only on trips published before V24.';
