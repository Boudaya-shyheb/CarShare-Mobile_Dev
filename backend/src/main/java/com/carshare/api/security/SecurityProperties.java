package com.carshare.api.security;

import org.springframework.boot.context.properties.ConfigurationProperties;
import java.time.Duration;

@ConfigurationProperties("carshare.security")
public record SecurityProperties(Duration sessionTtl, Duration resetTokenTtl) { }
