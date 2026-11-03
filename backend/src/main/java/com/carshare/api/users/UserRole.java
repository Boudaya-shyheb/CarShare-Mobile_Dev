package com.carshare.api.users;

public enum UserRole {
    PASSENGER("passenger"),
    DRIVER("driver");

    private final String value;

    UserRole(String value) { this.value = value; }

    public String value() { return value; }

    public static UserRole fromValue(String value) {
        return switch (value == null ? "" : value.trim().toLowerCase()) {
            case "passenger" -> PASSENGER;
            case "driver" -> DRIVER;
            default -> throw new IllegalArgumentException("Role must be passenger or driver.");
        };
    }
}
