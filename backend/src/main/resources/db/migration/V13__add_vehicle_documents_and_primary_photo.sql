ALTER TABLE vehicles
    ADD COLUMN insurance_expiry_date DATE,
    ADD COLUMN inspection_expiry_date DATE;

ALTER TABLE vehicle_photos
    ADD COLUMN is_primary BOOLEAN NOT NULL DEFAULT FALSE;

WITH ranked_photos AS (
    SELECT id,
           ROW_NUMBER() OVER (PARTITION BY vehicle_id ORDER BY created_at ASC, id ASC) AS photo_rank
    FROM vehicle_photos
)
UPDATE vehicle_photos
SET is_primary = TRUE
FROM ranked_photos
WHERE vehicle_photos.id = ranked_photos.id
  AND ranked_photos.photo_rank = 1;

CREATE UNIQUE INDEX uq_vehicle_photos_one_primary_per_vehicle
    ON vehicle_photos(vehicle_id)
    WHERE is_primary;
