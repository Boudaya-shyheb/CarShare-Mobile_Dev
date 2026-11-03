package com.carshare.api.security;

import java.util.UUID;

public record SessionPrincipal(UUID userId, String tokenHash) { }
