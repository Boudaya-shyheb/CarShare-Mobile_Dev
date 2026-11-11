package com.carshare.api.vehicles;

import com.carshare.api.common.ApiException;
import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import java.util.List;
import java.util.UUID;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/vehicles")
public class VehicleController {
    private final VehicleService vehicleService;

    public VehicleController(VehicleService vehicleService) {
        this.vehicleService = vehicleService;
    }

    @GetMapping
    public List<VehicleDtos.VehicleResponse> getVehicles(
            @AuthenticationPrincipal SessionPrincipal principal) {
        return vehicleService.getVehicles(principal.userId());
    }

    @GetMapping("/{vehicleId}")
    public VehicleDtos.VehicleResponse getVehicle(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID vehicleId) {
        return vehicleService.getVehicle(principal.userId(), vehicleId);
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public VehicleDtos.VehicleResponse createVehicle(
            @AuthenticationPrincipal SessionPrincipal principal,
            @Valid @RequestBody VehicleDtos.VehicleRequest request) {
        return vehicleService.createVehicle(principal.userId(), request);
    }

    @PutMapping("/{vehicleId}")
    public VehicleDtos.VehicleResponse updateVehicle(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID vehicleId,
            @Valid @RequestBody VehicleDtos.VehicleRequest request) {
        return vehicleService.updateVehicle(principal.userId(), vehicleId, request);
    }

    @DeleteMapping("/{vehicleId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteVehicle(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID vehicleId) {
        vehicleService.deleteVehicle(principal.userId(), vehicleId);
    }

    @PostMapping("/{vehicleId}/default")
    public VehicleDtos.VehicleResponse setDefault(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID vehicleId) {
        return vehicleService.setDefault(principal.userId(), vehicleId);
    }

    @PostMapping(value = "/{vehicleId}/photos", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public VehicleDtos.VehicleResponse uploadPhoto(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID vehicleId,
            @RequestPart("photo") MultipartFile photo) {
        try {
            return vehicleService.uploadPhoto(principal.userId(), vehicleId, photo.getBytes());
        } catch (java.io.IOException exception) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo",
                    "The selected photo could not be read.");
        }
    }

    @GetMapping("/{vehicleId}/photos/{photoId}")
    public ResponseEntity<byte[]> getPhoto(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID vehicleId,
            @PathVariable UUID photoId) {
        VehicleService.PhotoContent photo = vehicleService.getPhoto(principal.userId(), vehicleId, photoId);
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(photo.mimeType()))
                .cacheControl(CacheControl.noStore())
                .header("X-Content-Type-Options", "nosniff")
                .body(photo.bytes());
    }

    @PostMapping("/{vehicleId}/photos/{photoId}/primary")
    public VehicleDtos.VehicleResponse setPrimaryPhoto(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID vehicleId,
            @PathVariable UUID photoId) {
        return vehicleService.setPrimaryPhoto(principal.userId(), vehicleId, photoId);
    }

    @DeleteMapping("/{vehicleId}/photos/{photoId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deletePhoto(
            @AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable UUID vehicleId,
            @PathVariable UUID photoId) {
        vehicleService.deletePhoto(principal.userId(), vehicleId, photoId);
    }
}
