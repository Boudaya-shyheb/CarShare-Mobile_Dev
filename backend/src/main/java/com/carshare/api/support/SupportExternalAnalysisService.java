package com.carshare.api.support;

import com.carshare.api.common.ApiException;
import com.carshare.api.reservation.GpsPoint;
import com.carshare.api.reservation.GpsPointRepository;
import com.carshare.api.reservation.Trip;
import com.carshare.api.reservation.TripRepository;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HexFormat;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

@Service
public class SupportExternalAnalysisService {
    private final SupportTicketRepository tickets;
    private final TicketEvidenceRepository evidence;
    private final TicketEvidenceAnalysisRepository analyses;
    private final TicketWeatherContextRepository weather;
    private final TicketGeoInvestigationRepository geo;
    private final SupportEvidenceStorage storage;
    private final TripRepository trips;
    private final GpsPointRepository gpsPoints;
    private final RestClient http;
    private final String tikaUrl;
    private final String weatherUrl;
    private final String overpassUrl;
    private final String osrmUrl;

    public SupportExternalAnalysisService(SupportTicketRepository tickets,
            TicketEvidenceRepository evidence, TicketEvidenceAnalysisRepository analyses,
            TicketWeatherContextRepository weather, TicketGeoInvestigationRepository geo,
            SupportEvidenceStorage storage, TripRepository trips, GpsPointRepository gpsPoints,
            @Value("${carshare.support.tika-url:http://localhost:9998}") String tikaUrl,
            @Value("${carshare.support.open-meteo-url:https://archive-api.open-meteo.com/v1/archive}") String weatherUrl,
            @Value("${carshare.support.overpass-url:https://overpass-api.de/api/interpreter}") String overpassUrl,
            @Value("${carshare.support.osrm-url:https://router.project-osrm.org}") String osrmUrl,
            @Value("${carshare.support.external-timeout-seconds:12}") int timeoutSeconds) {
        this.tickets = tickets; this.evidence = evidence; this.analyses = analyses;
        this.weather = weather; this.geo = geo; this.storage = storage; this.trips = trips;
        this.gpsPoints = gpsPoints;
        this.tikaUrl = stripSlash(tikaUrl); this.weatherUrl = weatherUrl;
        this.overpassUrl = overpassUrl; this.osrmUrl = stripSlash(osrmUrl);
        SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(java.time.Duration.ofSeconds(timeoutSeconds));
        requestFactory.setReadTimeout(java.time.Duration.ofSeconds(timeoutSeconds));
        this.http = RestClient.builder().requestFactory(requestFactory).build();
    }

    @Transactional
    public EvidenceAnalysisView analyzeEvidence(UUID ticketId, UUID evidenceId) {
        ticket(ticketId);
        TicketEvidence item = evidence.findByIdAndTicket_Id(evidenceId, ticketId)
                .orElseThrow(() -> notFound("evidence_not_found", "Evidence not found."));
        byte[] bytes = storage.read(item.getFilePath());
        String hash = sha256(bytes);
        TicketEvidenceAnalysis analysis = analyses.findByEvidence_Id(evidenceId)
                .orElseGet(() -> new TicketEvidenceAnalysis(item, hash));
        TicketEvidence duplicate = analyses.findFirstBySha256AndEvidence_IdNot(hash, evidenceId)
                .map(TicketEvidenceAnalysis::getEvidence).orElse(null);
        String detected = item.getContentType();
        String metadata = null;
        String text = null;
        String error = null;
        TicketEvidenceAnalysis.Status status = TicketEvidenceAnalysis.Status.COMPLETE;
        try {
            detected = tika("/detect", bytes, MediaType.TEXT_PLAIN_VALUE);
            metadata = tika("/meta", bytes, MediaType.APPLICATION_JSON_VALUE);
            text = tika("/tika", bytes, MediaType.TEXT_PLAIN_VALUE);
        } catch (RuntimeException exception) {
            status = TicketEvidenceAnalysis.Status.PARTIAL;
            error = "Apache Tika is unavailable. SHA-256 and upload MIME type remain available.";
        }
        analysis.finish(status, clean(detected), duplicate, metadata, text, error);
        return EvidenceAnalysisView.from(analyses.save(analysis));
    }

    @Transactional(readOnly = true)
    public List<EvidenceAnalysisView> evidenceAnalyses(UUID ticketId) {
        ticket(ticketId);
        return analyses.findByEvidence_Ticket_IdOrderByAnalyzedAtDesc(ticketId).stream()
                .map(EvidenceAnalysisView::from).toList();
    }

    @Transactional
    public WeatherView refreshWeather(UUID ticketId) {
        SupportTicket ticket = ticket(ticketId);
        Trip trip = trip(ticket);
        TicketWeatherContext context = weather.findByTicket_Id(ticketId).orElseGet(() ->
                new TicketWeatherContext(ticket, trip.getOriginLat(), trip.getOriginLng(),
                        trip.getDepartureTime()));
        try {
            String date = DateTimeFormatter.ISO_LOCAL_DATE.format(
                    trip.getDepartureTime().atZone(ZoneId.of("Africa/Tunis")));
            String uri = weatherUrl + "?latitude=" + trip.getOriginLat()
                    + "&longitude=" + trip.getOriginLng() + "&start_date=" + date
                    + "&end_date=" + date
                    + "&hourly=temperature_2m,precipitation,wind_speed_10m,weather_code"
                    + "&timezone=Africa%2FTunis";
            String json = http.get().uri(URI.create(uri)).retrieve().body(String.class);
            String wanted = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:00")
                    .format(trip.getDepartureTime().atZone(ZoneId.of("Africa/Tunis")));
            List<String> times = strings(array(json, "time"));
            int index = times.indexOf(wanted);
            if (index < 0) throw new IllegalStateException("No hourly weather value for trip time.");
            context.available(number(json, "temperature_2m", index),
                    number(json, "precipitation", index), number(json, "wind_speed_10m", index),
                    integer(json, "weather_code", index));
        } catch (RuntimeException exception) {
            context.unavailable("Open-Meteo historical weather is currently unavailable.");
        }
        return WeatherView.from(weather.save(context));
    }

    @Transactional
    public GeoView refreshGeo(UUID ticketId) {
        SupportTicket ticket = ticket(ticketId);
        Trip trip = trip(ticket);
        TicketGeoInvestigation context = geo.findByTicket_Id(ticketId).orElseGet(() ->
                new TicketGeoInvestigation(ticket, trip.getOriginLat(), trip.getOriginLng(),
                        trip.getDestinationLat(), trip.getDestinationLng()));
        Double actualLat = trip.getLastLat();
        Double actualLng = trip.getLastLng();
        Instant actualAt = trip.getLastPositionAt();
        boolean actualIsPlausible = isPlausibleTripPoint(trip, actualLat, actualLng);
        double centerLat = actualIsPlausible ? actualLat : trip.getOriginLat();
        double centerLng = actualIsPlausible ? actualLng : trip.getOriginLng();
        String places = null;
        String nearbyError = null;
        try {
            String query = "[out:json][timeout:10];(node(around:500," + centerLat + ","
                    + centerLng + ")[name];way(around:500," + centerLat + "," + centerLng
                    + ")[name];);out tags center 20;";
            String body = "data=" + URLEncoder.encode(query, StandardCharsets.UTF_8);
            String json = http.post().uri(URI.create(overpassUrl))
                    .header(HttpHeaders.USER_AGENT, "CarShare-student-app")
                    .contentType(MediaType.APPLICATION_FORM_URLENCODED).body(body)
                    .retrieve().body(String.class);
            places = placeNames(json, centerLat, centerLng);
        } catch (RuntimeException exception) {
            nearbyError = "Nearby places are temporarily unavailable. Please retry later.";
        }

        Integer idealDistanceM = null;
        Integer idealDurationS = null;
        Integer actualDistanceM = null;
        String routePolyline = null;
        String routeVerdict = "INSUFFICIENT_GPS";
        String routeError = null;
        List<GpsPoint> trace = gpsPoints.findByTrip_IdOrderByRecordedAtAsc(trip.getId());
        try {
            String coordinates = trip.getOriginLng() + "," + trip.getOriginLat() + ";"
                    + trip.getDestinationLng() + "," + trip.getDestinationLat();
            String uri = osrmUrl + "/route/v1/driving/" + coordinates
                    + "?overview=full&geometries=polyline";
            String json = http.get().uri(URI.create(uri))
                    .header(HttpHeaders.USER_AGENT, "CarShare-student-app")
                    .retrieve().body(String.class);
            JsonObject response = JsonParser.parseString(json).getAsJsonObject();
            if (!response.has("routes") || response.getAsJsonArray("routes").isEmpty()) {
                throw new IllegalStateException("OSRM returned no route.");
            }
            JsonObject best = response.getAsJsonArray("routes").get(0).getAsJsonObject();
            idealDistanceM = (int) Math.round(best.get("distance").getAsDouble());
            idealDurationS = (int) Math.round(best.get("duration").getAsDouble());
            routePolyline = best.get("geometry").getAsString();
            actualDistanceM = recordedDistance(trace);
            routeVerdict = routeVerdict(trip, trace, idealDistanceM, actualDistanceM);
        } catch (Exception exception) {
            routeError = "OSRM route estimation is temporarily unavailable. Please retry later.";
        }

        String locationNote = actualLat == null
                ? "No recorded GPS position; nearby places use the planned origin."
                : !actualIsPlausible
                ? "The latest GPS position is outside the trip area; nearby places use the planned origin."
                : null;
        String error = joinNotes(locationNote, nearbyError);
        TicketGeoInvestigation.Status state = places != null && routePolyline != null
                && actualIsPlausible ? TicketGeoInvestigation.Status.AVAILABLE
                : places != null || routePolyline != null ? TicketGeoInvestigation.Status.PARTIAL
                : TicketGeoInvestigation.Status.UNAVAILABLE;
        context.finish(state, actualLat, actualLng, actualAt, places, error,
                trip.getDestinationLat(), trip.getDestinationLng(), idealDistanceM,
                idealDurationS, actualDistanceM, routePolyline, routeVerdict, routeError);
        return GeoView.from(geo.save(context), trace);
    }

    @Transactional(readOnly = true)
    public Optional<WeatherView> weather(UUID ticketId) {
        return weather.findByTicket_Id(ticketId).map(WeatherView::from);
    }
    @Transactional(readOnly = true)
    public Optional<GeoView> geo(UUID ticketId) {
        return geo.findByTicket_Id(ticketId).map(item -> GeoView.from(item,
                gpsPoints.findByTrip_IdOrderByRecordedAtAsc(ticket(ticketId).getTripId())));
    }

    private String tika(String path, byte[] bytes, String accept) {
        return http.put().uri(URI.create(tikaUrl + path))
                .header(HttpHeaders.ACCEPT, accept)
                .contentType(MediaType.APPLICATION_OCTET_STREAM).body(bytes)
                .retrieve().body(String.class);
    }
    private String sha256(byte[] bytes) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
        catch (Exception error) { throw new IllegalStateException("SHA-256 unavailable", error); }
    }
    private String placeNames(String json, double centerLat, double centerLng) {
        try {
            List<NearbyPlace> places = new ArrayList<>();
            JsonObject response = JsonParser.parseString(json).getAsJsonObject();
            if (!response.has("elements")) return "No named place was found within 500 m.";
            for (JsonElement element : response.getAsJsonArray("elements")) {
                JsonObject item = element.getAsJsonObject();
                JsonObject tags = item.has("tags") ? item.getAsJsonObject("tags")
                        : new JsonObject();
                String name = text(tags, "name");
                if (name.isEmpty()) continue;
                JsonObject point = item.has("lat") ? item
                        : item.has("center") ? item.getAsJsonObject("center") : null;
                if (point == null || !point.has("lat") || !point.has("lon")) continue;
                double distance = distanceMeters(centerLat, centerLng,
                        point.get("lat").getAsDouble(), point.get("lon").getAsDouble());
                String type = firstText(tags, "amenity", "shop", "tourism", "leisure",
                        "public_transport", "highway");
                places.add(new NearbyPlace(name, type, distance));
            }
            places.sort(Comparator.comparingDouble(NearbyPlace::distanceM));
            return places.stream().limit(8).map(place -> place.name() + " ("
                    + place.type().replace('_', ' ') + ", " + formatDistance(place.distanceM())
                    + ")").reduce((left, right) -> left + ", " + right)
                    .orElse("No named place was found within 500 m.");
        } catch (Exception exception) {
            throw new IllegalStateException("Unreadable Overpass response", exception);
        }
    }
    private String firstText(JsonObject node, String... keys) {
        for (String key : keys) {
            String value = text(node, key);
            if (!value.isEmpty()) return value;
        }
        return "place";
    }
    private String text(JsonObject object, String key) {
        return object.has(key) && !object.get(key).isJsonNull()
                ? object.get(key).getAsString().strip() : "";
    }
    private String formatDistance(double meters) {
        return meters < 1000 ? Math.round(meters) + " m"
                : String.format(Locale.ROOT, "%.1f km", meters / 1000);
    }
    private Integer recordedDistance(List<GpsPoint> trace) {
        if (trace.size() < 2) return null;
        double total = 0;
        for (int index = 1; index < trace.size(); index++) {
            GpsPoint previous = trace.get(index - 1);
            GpsPoint current = trace.get(index);
            total += distanceMeters(previous.getLat(), previous.getLng(),
                    current.getLat(), current.getLng());
        }
        return (int) Math.round(total);
    }
    private String routeVerdict(Trip trip, List<GpsPoint> trace, Integer ideal, Integer actual) {
        if (trace.size() < 2 || actual == null || ideal == null || ideal <= 0) {
            return "INSUFFICIENT_GPS";
        }
        boolean invalid = trace.stream().anyMatch(point ->
                !isPlausibleTripPoint(trip, point.getLat(), point.getLng()));
        if (invalid) return "INVALID_GPS";
        double extra = (actual - ideal) / (double) ideal;
        if (trip.isDeviating() || extra > 0.30) return "SIGNIFICANT_DEVIATION";
        if (extra > 0.15) return "MINOR_DEVIATION";
        return "CONSISTENT";
    }
    private boolean isPlausibleTripPoint(Trip trip, Double lat, Double lng) {
        if (lat == null || lng == null) return false;
        double tripLength = distanceMeters(trip.getOriginLat(), trip.getOriginLng(),
                trip.getDestinationLat(), trip.getDestinationLng());
        double allowedDistance = Math.max(100_000, tripLength + 50_000);
        return Math.min(distanceMeters(lat, lng, trip.getOriginLat(), trip.getOriginLng()),
                distanceMeters(lat, lng, trip.getDestinationLat(), trip.getDestinationLng()))
                <= allowedDistance;
    }
    private double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
    private String joinNotes(String first, String second) {
        if (first == null) return second;
        if (second == null) return first;
        return first + " " + second;
    }
    private String array(String json, String key) {
        if (json == null) throw new IllegalStateException("Empty response");
        Matcher match = Pattern.compile("\\\"" + Pattern.quote(key)
                + "\\\"\\s*:\\s*\\[([^]]*)]", Pattern.DOTALL).matcher(json);
        if (!match.find()) throw new IllegalStateException("Missing " + key);
        return match.group(1);
    }
    private List<String> strings(String values) {
        List<String> result = new ArrayList<>();
        Matcher matcher = Pattern.compile("\\\"([^\\\"]*)\\\"").matcher(values);
        while (matcher.find()) result.add(matcher.group(1));
        return result;
    }
    private Double number(String json, String key, int index) {
        String[] values = array(json, key).split(",");
        if (index >= values.length || values[index].trim().equals("null")) return null;
        return Double.valueOf(values[index].trim());
    }
    private Integer integer(String json, String key, int index) {
        Double value = number(json, key, index); return value == null ? null : value.intValue();
    }
    private Trip trip(SupportTicket ticket) {
        if (ticket.getTripId() == null) throw new ApiException(HttpStatus.CONFLICT,
                "trip_context_unavailable", "This support ticket is not linked to a trip.");
        return trips.findById(ticket.getTripId()).orElseThrow(() ->
                notFound("trip_not_found", "The linked trip is unavailable."));
    }
    private SupportTicket ticket(UUID id) {
        return tickets.findDetailedById(id).orElseThrow(() ->
                notFound("ticket_not_found", "Support ticket not found."));
    }
    private ApiException notFound(String code, String message) {
        return new ApiException(HttpStatus.NOT_FOUND, code, message);
    }
    private String clean(String value) { return value == null ? null : value.strip(); }
    private String stripSlash(String value) { return value.endsWith("/")
            ? value.substring(0, value.length() - 1) : value; }

    public record EvidenceAnalysisView(UUID evidenceId, String status, String detectedType,
            String sha256, UUID duplicateEvidenceId, String metadata, String extractedText,
            String errorMessage, Instant analyzedAt) {
        static EvidenceAnalysisView from(TicketEvidenceAnalysis a) {
            return new EvidenceAnalysisView(a.getEvidence().getId(), a.getStatus().name(),
                    a.getDetectedType(), a.getSha256(), a.getDuplicateEvidence() == null ? null
                    : a.getDuplicateEvidence().getId(), a.getMetadata(), a.getExtractedText(),
                    a.getErrorMessage(), a.getAnalyzedAt());
        }
    }
    public record WeatherView(String status, double latitude, double longitude, Instant observedAt,
            Double temperatureC, Double precipitationMm, Double windSpeedKmh, Integer weatherCode,
            String source, String errorMessage, Instant fetchedAt) {
        static WeatherView from(TicketWeatherContext c) { return new WeatherView(c.getStatus().name(),
                c.getLatitude(), c.getLongitude(), c.getObservedAt(), c.getTemperatureC(),
                c.getPrecipitationMm(), c.getWindSpeedKmh(), c.getWeatherCode(), c.getSource(),
                c.getErrorMessage(), c.getFetchedAt()); }
    }
    private record NearbyPlace(String name, String type, double distanceM) { }
    public record GeoPointView(double lat, double lng) { }
    public record GeoView(String status, double plannedLat, double plannedLng,
            Double destinationLat, Double destinationLng, Double actualLat, Double actualLng,
            Instant actualRecordedAt, String nearbyPlaces, Integer idealDistanceM,
            Integer idealDurationS, Integer actualDistanceM, String routePolyline,
            String routeVerdict, String routeError, List<GeoPointView> actualPoints,
            String source, String errorMessage, Instant fetchedAt) {
        static GeoView from(TicketGeoInvestigation c, List<GpsPoint> trace) {
            List<GeoPointView> points = trace.stream()
                    .map(point -> new GeoPointView(point.getLat(), point.getLng())).toList();
            return new GeoView(c.getStatus().name(), c.getPlannedLat(), c.getPlannedLng(),
                    c.getDestinationLat(), c.getDestinationLng(), c.getActualLat(), c.getActualLng(),
                    c.getActualRecordedAt(), c.getNearbyPlaces(), c.getIdealDistanceM(),
                    c.getIdealDurationS(), c.getActualDistanceM(), c.getRoutePolyline(),
                    c.getRouteVerdict(), c.getRouteError(), points, c.getSource(),
                    c.getErrorMessage(), c.getFetchedAt());
        }
    }
}
