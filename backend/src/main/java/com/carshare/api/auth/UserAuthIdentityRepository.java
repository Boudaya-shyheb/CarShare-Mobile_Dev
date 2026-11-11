package com.carshare.api.auth;

import java.util.Optional;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface UserAuthIdentityRepository extends JpaRepository<UserAuthIdentity, UUID> {
    Optional<UserAuthIdentity> findByProviderAndProviderSubject(String provider, String providerSubject);
}
