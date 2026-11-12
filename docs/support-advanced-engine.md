# Module 5 - Advanced Support engine

This engine belongs only to Support/Tickets. It reads linked trip data without changing Trip,
Reservation, Vehicle or Lost & Found.

## Local Apache Tika

For development, start the optional local service from `backend`:

```powershell
docker compose -f support-tika-compose.yml up -d
```

The default URL is `http://localhost:9998`. Override it with `SUPPORT_TIKA_URL`.
When Tika is absent, evidence analysis is saved as `PARTIAL`: SHA-256, duplicate detection and
the upload MIME type still work, while the UI clearly reports that text/metadata extraction is
unavailable. Tika does not prove authenticity and is not antivirus software.

## External context

- Open-Meteo historical weather uses the trip origin and departure time with `Africa/Tunis`.
- Overpass searches named places within 500 metres of the latest available GPS point, or the
  planned origin when actual GPS is unavailable.
- Results are persisted in Neon by Flyway migration `V21`.
- Weather and map data are investigation context only and never trigger a sanction or decision.
- Attribution: Open-Meteo; OpenStreetMap contributors / Overpass API.

The API contract is documented in `docs/support-advanced-openapi.yaml`.
