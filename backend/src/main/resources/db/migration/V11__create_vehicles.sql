CREATE TABLE vehicles (
    id UUID PRIMARY KEY,
    owner_id UUID NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    brand VARCHAR(60) NOT NULL,
    model VARCHAR(60) NOT NULL,
    manufacturing_year INTEGER NOT NULL CHECK (manufacturing_year BETWEEN 1900 AND 2200),
    color VARCHAR(40) NOT NULL,
    registration_number VARCHAR(12) NOT NULL,
    seats_number INTEGER NOT NULL CHECK (seats_number BETWEEN 1 AND 9),
    trunk_size VARCHAR(10) NOT NULL CHECK (trunk_size IN ('SMALL', 'MEDIUM', 'LARGE')),
    air_conditioning BOOLEAN NOT NULL DEFAULT FALSE,
    status VARCHAR(16) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE', 'REPORTED')),
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_used_at TIMESTAMPTZ,
    CONSTRAINT uq_vehicles_registration_number UNIQUE (registration_number),
    CONSTRAINT ck_vehicles_registration_number_format
        CHECK (registration_number ~ '^[0-9]{3} TU [0-9]{4}$')
);

CREATE INDEX ix_vehicles_owner_created ON vehicles(owner_id, created_at DESC);
CREATE UNIQUE INDEX uq_vehicles_one_default_per_owner ON vehicles(owner_id) WHERE is_default;

CREATE TABLE vehicle_photos (
    id UUID PRIMARY KEY,
    vehicle_id UUID NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
    file_name VARCHAR(80) NOT NULL UNIQUE,
    mime_type VARCHAR(30) NOT NULL CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX ix_vehicle_photos_vehicle ON vehicle_photos(vehicle_id, created_at);
