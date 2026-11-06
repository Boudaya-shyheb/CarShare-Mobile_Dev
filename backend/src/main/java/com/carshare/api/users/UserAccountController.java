package com.carshare.api.users;

import com.carshare.api.auth.AuthDtos;
import com.carshare.api.security.SessionPrincipal;
import jakarta.validation.Valid;
import java.util.List;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/users/me")
public class UserAccountController {
    private final UserAccountService accountService;

    public UserAccountController(UserAccountService accountService) {
        this.accountService = accountService;
    }

    @GetMapping("/preferences")
    public AuthDtos.Preferences preferences(@AuthenticationPrincipal SessionPrincipal principal) {
        return accountService.getPreferences(principal.userId());
    }

    @PutMapping("/preferences")
    public AuthDtos.Preferences updatePreferences(@AuthenticationPrincipal SessionPrincipal principal,
            @Valid @RequestBody AuthDtos.UpdatePreferences request) {
        return accountService.updatePreferences(principal.userId(), request);
    }

    @GetMapping("/sanctions")
    public List<AuthDtos.Sanction> sanctions(@AuthenticationPrincipal SessionPrincipal principal) {
        return accountService.getSanctions(principal.userId());
    }

    @GetMapping("/photo")
    public ResponseEntity<byte[]> photo(@AuthenticationPrincipal SessionPrincipal principal) {
        AuthDtos.ProfilePhoto photo = accountService.getPhoto(principal.userId());
        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(photo.contentType()))
                .cacheControl(CacheControl.noStore())
                .header("X-Content-Type-Options", "nosniff")
                .body(photo.bytes());
    }

    @PostMapping(value = "/photo", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void uploadPhoto(@AuthenticationPrincipal SessionPrincipal principal,
            @RequestPart("photo") MultipartFile photo) throws java.io.IOException {
        accountService.updatePhoto(principal.userId(), photo.getBytes(), photo.getContentType());
    }

    @DeleteMapping("/photo")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deletePhoto(@AuthenticationPrincipal SessionPrincipal principal) {
        accountService.deletePhoto(principal.userId());
    }

    @GetMapping("/emergency-contacts")
    public List<AuthDtos.EmergencyContact> emergencyContacts(@AuthenticationPrincipal SessionPrincipal principal) {
        return accountService.getEmergencyContacts(principal.userId());
    }

    @PostMapping("/emergency-contacts")
    @ResponseStatus(HttpStatus.CREATED)
    public AuthDtos.EmergencyContact addEmergencyContact(@AuthenticationPrincipal SessionPrincipal principal,
            @Valid @RequestBody AuthDtos.EmergencyContactRequest request) {
        return accountService.addEmergencyContact(principal.userId(), request);
    }

    @PutMapping("/emergency-contacts/{contactId}")
    public AuthDtos.EmergencyContact updateEmergencyContact(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable java.util.UUID contactId, @Valid @RequestBody AuthDtos.EmergencyContactRequest request) {
        return accountService.updateEmergencyContact(principal.userId(), contactId, request);
    }

    @DeleteMapping("/emergency-contacts/{contactId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteEmergencyContact(@AuthenticationPrincipal SessionPrincipal principal,
            @PathVariable java.util.UUID contactId) {
        accountService.deleteEmergencyContact(principal.userId(), contactId);
    }
}
