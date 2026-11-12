package com.carshare.api.support;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_weather_contexts")
public class TicketWeatherContext {
    public enum Status { AVAILABLE, UNAVAILABLE }
    @Id private UUID id;
    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false, unique = true) private SupportTicket ticket;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 20) private Status status;
    @Column(nullable = false) private double latitude;
    @Column(nullable = false) private double longitude;
    @Column(name = "observed_at", nullable = false) private Instant observedAt;
    @Column(name = "temperature_c") private Double temperatureC;
    @Column(name = "precipitation_mm") private Double precipitationMm;
    @Column(name = "wind_speed_kmh") private Double windSpeedKmh;
    @Column(name = "weather_code") private Integer weatherCode;
    @Column(nullable = false, length = 100) private String source;
    @Column(name = "error_message", length = 500) private String errorMessage;
    @Column(name = "fetched_at", nullable = false) private Instant fetchedAt;

    protected TicketWeatherContext() { }
    public TicketWeatherContext(SupportTicket ticket, double lat, double lng, Instant observedAt) {
        id = UUID.randomUUID(); this.ticket = ticket; latitude = lat; longitude = lng;
        this.observedAt = observedAt; source = "Open-Meteo Historical Weather API";
        status = Status.UNAVAILABLE; fetchedAt = Instant.now();
    }
    public void available(Double temp, Double rain, Double wind, Integer code) {
        status = Status.AVAILABLE; temperatureC = temp; precipitationMm = rain;
        windSpeedKmh = wind; weatherCode = code; errorMessage = null; fetchedAt = Instant.now();
    }
    public void unavailable(String error) { status = Status.UNAVAILABLE; errorMessage = error; fetchedAt = Instant.now(); }
    public Status getStatus() { return status; }
    public double getLatitude() { return latitude; }
    public double getLongitude() { return longitude; }
    public Instant getObservedAt() { return observedAt; }
    public Double getTemperatureC() { return temperatureC; }
    public Double getPrecipitationMm() { return precipitationMm; }
    public Double getWindSpeedKmh() { return windSpeedKmh; }
    public Integer getWeatherCode() { return weatherCode; }
    public String getSource() { return source; }
    public String getErrorMessage() { return errorMessage; }
    public Instant getFetchedAt() { return fetchedAt; }
}
