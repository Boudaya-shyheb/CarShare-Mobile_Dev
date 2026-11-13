package com.carshare.api.reservation;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.carshare.api.common.ApiException;
import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import com.carshare.api.users.UserStatus;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

class RatingAccountRulesTest {
    @Test
    @DisplayName("a suspended or banned user cannot rate or change a rating")
    void restrictedUsersCannotRate() {
        UserRepository users = mock(UserRepository.class);
        RatingRepository ratings = mock(RatingRepository.class);
        RatingService service = new RatingService(ratings, mock(TripRepository.class),
                mock(ReservationRepository.class), users);
        AppUser rater = new AppUser("Mariem", "+21622222222", "m@carshare.tn", "hash", UserRole.PASSENGER);
        when(users.findById(rater.getId())).thenReturn(Optional.of(rater));
        UUID tripId = UUID.randomUUID();
        UUID ratedId = UUID.randomUUID();

        rater.updateAccountStatus(UserStatus.SUSPENDED, Instant.now().plus(1, ChronoUnit.DAYS));
        assertEquals("account_suspended", assertThrows(ApiException.class, () -> service.rate(rater.getId(),
                tripId, new RatingDtos.RateRequest(ratedId, 5, "great"))).getCode());
        assertEquals("account_suspended", assertThrows(ApiException.class, () -> service.revise(rater.getId(),
                tripId, ratedId, new RatingDtos.ReviseRatingRequest(4, "ok"))).getCode());

        rater.updateAccountStatus(UserStatus.BANNED, null);
        assertEquals("account_banned", assertThrows(ApiException.class, () -> service.rate(rater.getId(),
                tripId, new RatingDtos.RateRequest(ratedId, 5, "great"))).getCode());
        verify(ratings, never()).save(any());
    }
}
