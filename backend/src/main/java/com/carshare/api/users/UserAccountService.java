package com.carshare.api.users;

import com.carshare.api.auth.AuthDtos;
import com.carshare.api.common.ApiException;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.http.HttpStatus;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UserAccountService {
    private final UserRepository users;
    private final UserPreferencesRepository preferences;
    private final UserSanctionRepository sanctions;
    private final UserEmergencyContactRepository emergencyContacts;

    public UserAccountService(UserRepository users, UserPreferencesRepository preferences,
            UserSanctionRepository sanctions, UserEmergencyContactRepository emergencyContacts) {
        this.users = users;
        this.preferences = preferences;
        this.sanctions = sanctions;
        this.emergencyContacts = emergencyContacts;
    }

    @Transactional(readOnly = true)
    public AuthDtos.Preferences getPreferences(UUID userId) {
        AppUser user = requireUser(userId);
        return preferences.findById(userId).map(AuthDtos.Preferences::from)
                .orElseGet(() -> AuthDtos.Preferences.defaults(user.getId()));
    }

    @Transactional
    public AuthDtos.Preferences updatePreferences(UUID userId, AuthDtos.UpdatePreferences request) {
        AppUser user = requireUser(userId);
        String language = request.language().trim().toLowerCase();
        if (!List.of("en", "fr", "ar").contains(language)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_language",
                    "Choose English, French, or Arabic.");
        }
        if (!List.of("standard", "small", "large").contains(request.luggagePreference())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_luggage_preference",
                    "Choose standard, small, or large luggage.");
        }
        UserPreferences value = preferences.findById(userId).orElseGet(() -> new UserPreferences(user));
        value.update(language, clean(request.homePlace()), clean(request.workPlace()), clean(request.campusPlace()),
                request.musicAllowed(), request.smokingAllowed(), request.petsAllowed(), request.luggagePreference());
        return AuthDtos.Preferences.from(preferences.save(value));
    }

    @Transactional(readOnly = true)
    public List<AuthDtos.Sanction> getSanctions(UUID userId) {
        requireUser(userId);
        Instant now = Instant.now();
        return sanctions.findByUser_IdOrderByIssuedAtDesc(userId).stream()
                .map(value -> AuthDtos.Sanction.from(value, now))
                .toList();
    }

    @Transactional
    public void updatePhoto(UUID userId, byte[] photo, String mimeType) {
        AppUser user = requireUser(userId);
        if (photo == null || photo.length == 0 || photo.length > 2 * 1024 * 1024) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo_size", "Choose an image smaller than 2 MB.");
        }
        if (!List.of(MediaType.IMAGE_JPEG_VALUE, MediaType.IMAGE_PNG_VALUE, "image/webp").contains(mimeType)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_photo_type", "Choose a JPG, PNG, or WebP image.");
        }
        user.updateProfilePhoto(photo, mimeType);
    }

    @Transactional(readOnly = true)
    public AuthDtos.ProfilePhoto getPhoto(UUID userId) {
        AppUser user = requireUser(userId);
        if (user.getProfilePhoto() == null) {
            throw new ApiException(HttpStatus.NOT_FOUND, "profile_photo_not_found", "No profile photo has been added.");
        }
        return new AuthDtos.ProfilePhoto(user.getProfilePhoto(), user.getProfilePhotoMimeType());
    }

    @Transactional
    public void deletePhoto(UUID userId) {
        requireUser(userId).updateProfilePhoto(null, null);
    }

    @Transactional(readOnly = true)
    public List<AuthDtos.EmergencyContact> getEmergencyContacts(UUID userId) {
        requireUser(userId);
        return emergencyContacts.findByUser_IdOrderByName(userId).stream()
                .map(AuthDtos.EmergencyContact::from).toList();
    }

    @Transactional
    public AuthDtos.EmergencyContact addEmergencyContact(UUID userId, AuthDtos.EmergencyContactRequest request) {
        AppUser user = requireUser(userId);
        String phone = normalizePhone(request.phone());
        validatePhone(phone);
        UserEmergencyContact contact = new UserEmergencyContact(user, request.name().trim(), phone,
                request.relationship().trim());
        return AuthDtos.EmergencyContact.from(emergencyContacts.save(contact));
    }

    @Transactional
    public AuthDtos.EmergencyContact updateEmergencyContact(UUID userId, UUID contactId,
            AuthDtos.EmergencyContactRequest request) {
        UserEmergencyContact contact = emergencyContacts.findByIdAndUser_Id(contactId, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "contact_not_found", "Emergency contact not found."));
        String phone = normalizePhone(request.phone());
        validatePhone(phone);
        contact.update(request.name().trim(), phone,
                request.relationship().trim());
        return AuthDtos.EmergencyContact.from(contact);
    }

    @Transactional
    public void deleteEmergencyContact(UUID userId, UUID contactId) {
        UserEmergencyContact contact = emergencyContacts.findByIdAndUser_Id(contactId, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "contact_not_found", "Emergency contact not found."));
        emergencyContacts.delete(contact);
    }

    @Transactional
    @Scheduled(cron = "0 0 0 * * *", zone = "UTC")
    public void recomputeAccountStatuses() {
        Instant now = Instant.now();
        for (AppUser user : users.findAll()) {
            refreshStatus(user, now);
        }
    }

    public void refreshStatus(AppUser user, Instant now) {
        if (user.isStatusManuallySet()) {
            if (user.getStatusUntil() == null || user.getStatusUntil().isAfter(now)) {
                return;
            }
            user.clearExpiredAdminStatus();
        }
        long points = sanctions.sumActivePoints(user.getId(), now);
        Instant lastSanction = sanctions.lastActiveSanction(user.getId(), now);
        UserStatus status = UserStatus.ACTIVE;
        Instant until = null;
        if (points >= 12) {
            status = UserStatus.BANNED;
        } else if (points >= 9 && lastSanction != null
                && lastSanction.plusSeconds(30L * 24 * 60 * 60).isAfter(now)) {
            status = UserStatus.SUSPENDED;
            until = lastSanction.plusSeconds(30L * 24 * 60 * 60);
        } else if (points >= 6 && lastSanction != null
                && lastSanction.plusSeconds(7L * 24 * 60 * 60).isAfter(now)) {
            status = UserStatus.SUSPENDED;
            until = lastSanction.plusSeconds(7L * 24 * 60 * 60);
        } else if (points >= 3) {
            status = UserStatus.WARNING;
        }
        user.updateAccountStatus(status, until);
    }

    private AppUser requireUser(UUID userId) {
        return users.findById(userId).orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED,
                "account_not_found", "Your account could not be found."));
    }

    private String clean(String value) {
        if (value == null || value.isBlank()) return null;
        String trimmed = value.trim();
        if (trimmed.length() > 180) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "place_too_long", "Place names must be 180 characters or less.");
        }
        return trimmed;
    }

    private String normalizePhone(String value) {
        return value.trim().replaceAll("[\\s().-]", "");
    }

    private void validatePhone(String phone) {
        if (!phone.matches("^\\+?[0-9]{7,15}$")) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "invalid_phone", "Enter a valid phone number.");
        }
    }
}
