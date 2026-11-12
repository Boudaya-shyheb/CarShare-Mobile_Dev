package com.carshare.api.support;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "ticket_geo_investigations")
public class TicketGeoInvestigation {
    public enum Status { AVAILABLE, PARTIAL, UNAVAILABLE }
    @Id private UUID id;
    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "ticket_id", nullable = false, unique = true) private SupportTicket ticket;
    @Enumerated(EnumType.STRING) @Column(nullable = false, length = 20) private Status status;
    @Column(name = "planned_lat", nullable = false) private double plannedLat;
    @Column(name = "planned_lng", nullable = false) private double plannedLng;
    @Column(name = "destination_lat") private Double destinationLat;
    @Column(name = "destination_lng") private Double destinationLng;
    @Column(name = "actual_lat") private Double actualLat;
    @Column(name = "actual_lng") private Double actualLng;
    @Column(name = "actual_recorded_at") private Instant actualRecordedAt;
    @Column(name = "nearby_places", columnDefinition = "text") private String nearbyPlaces;
    @Column(name = "ideal_distance_m") private Integer idealDistanceM;
    @Column(name = "ideal_duration_s") private Integer idealDurationS;
    @Column(name = "actual_distance_m") private Integer actualDistanceM;
    @Column(name = "route_polyline", columnDefinition = "text") private String routePolyline;
    @Column(name = "route_verdict", length = 30) private String routeVerdict;
    @Column(name = "route_error", length = 500) private String routeError;
    @Column(nullable = false, length = 100) private String source;
    @Column(name = "error_message", length = 500) private String errorMessage;
    @Column(name = "fetched_at", nullable = false) private Instant fetchedAt;

    protected TicketGeoInvestigation() { }
    public TicketGeoInvestigation(SupportTicket ticket, double lat, double lng,
            double destinationLat, double destinationLng) {
        id = UUID.randomUUID(); this.ticket = ticket; plannedLat = lat; plannedLng = lng;
        this.destinationLat = destinationLat; this.destinationLng = destinationLng;
        source = "OpenStreetMap contributors / Overpass API"; status = Status.UNAVAILABLE;
        fetchedAt = Instant.now();
    }
    public void finish(Status state, Double actualLat, Double actualLng, Instant actualAt,
            String places, String error, double destinationLat, double destinationLng,
            Integer idealDistanceM, Integer idealDurationS, Integer actualDistanceM,
            String routePolyline, String routeVerdict, String routeError) {
        status = state; this.actualLat = actualLat; this.actualLng = actualLng;
        actualRecordedAt = actualAt; nearbyPlaces = places; errorMessage = error;
        this.destinationLat = destinationLat; this.destinationLng = destinationLng;
        this.idealDistanceM = idealDistanceM; this.idealDurationS = idealDurationS;
        this.actualDistanceM = actualDistanceM; this.routePolyline = routePolyline;
        this.routeVerdict = routeVerdict; this.routeError = routeError;
        fetchedAt = Instant.now();
    }
    public Status getStatus() { return status; }
    public double getPlannedLat() { return plannedLat; }
    public double getPlannedLng() { return plannedLng; }
    public Double getDestinationLat() { return destinationLat; }
    public Double getDestinationLng() { return destinationLng; }
    public Double getActualLat() { return actualLat; }
    public Double getActualLng() { return actualLng; }
    public Instant getActualRecordedAt() { return actualRecordedAt; }
    public String getNearbyPlaces() { return nearbyPlaces; }
    public Integer getIdealDistanceM() { return idealDistanceM; }
    public Integer getIdealDurationS() { return idealDurationS; }
    public Integer getActualDistanceM() { return actualDistanceM; }
    public String getRoutePolyline() { return routePolyline; }
    public String getRouteVerdict() { return routeVerdict; }
    public String getRouteError() { return routeError; }
    public String getSource() { return source; }
    public String getErrorMessage() { return errorMessage; }
    public Instant getFetchedAt() { return fetchedAt; }
}
