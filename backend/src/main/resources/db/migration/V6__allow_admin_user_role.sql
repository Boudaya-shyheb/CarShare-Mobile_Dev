ALTER TABLE app_users DROP CONSTRAINT app_users_role_check;
ALTER TABLE app_users ADD CONSTRAINT ck_app_users_role
    CHECK (role IN ('PASSENGER', 'DRIVER', 'ADMIN'));
