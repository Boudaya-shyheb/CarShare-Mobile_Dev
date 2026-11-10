ALTER TABLE vehicles
    DROP CONSTRAINT ck_vehicles_registration_number_format;

UPDATE vehicles
SET registration_number = upper(regexp_replace(registration_number, '\s+', '', 'g'));

ALTER TABLE vehicles
    ADD CONSTRAINT ck_vehicles_registration_number_format
        CHECK (registration_number ~ '^([0-9]{3}TU[0-9]{4}|RS[0-9]{6})$');
