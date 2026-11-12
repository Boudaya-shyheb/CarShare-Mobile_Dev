package com.carshare.api.support;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.math.BigDecimal;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class TicketPriorityServiceTest {
    @Test
    void calculatesOfficialScoreAndKeepsNegatedRiskSignalForTransparency() {
        SupportTicketRepository tickets = mock(SupportTicketRepository.class);
        TicketDecisionRepository decisions = mock(TicketDecisionRepository.class);
        TicketRiskSignalRepository signals = mock(TicketRiskSignalRepository.class);
        List<TicketRiskSignal> saved = new ArrayList<>();
        when(signals.save(any(TicketRiskSignal.class))).thenAnswer(call -> {
            TicketRiskSignal signal = call.getArgument(0);
            saved.add(signal);
            return signal;
        });
        when(signals.findByTicket_IdOrderByCreatedAtAsc(any())).thenAnswer(call -> saved);

        TicketCategory category = new TicketCategory("Safety", 4,
                TicketCategory.Priority.HIGH, 99, TicketCategory.VerificationType.HYBRID);
        SupportTicket ticket = new SupportTicket(null, null, category, "Danger",
                "Pas d'accident mais la situation semble unsafe.");
        ticket.created();
        TicketPriorityService service = new TicketPriorityService(tickets, decisions, signals);

        TicketPriorityService.Analysis result = service.refresh(ticket);

        assertEquals(new BigDecimal("45.00"), result.score());
        assertEquals(3, saved.size());
        assertTrue(saved.stream().anyMatch(s -> s.getTerm().equals("accident") && s.isNegated()));
        assertTrue(saved.stream().anyMatch(s -> s.getTerm().equals("danger") && !s.isNegated()));
    }

    @Test
    void highPriorityUsesFixedTwentyFourHourSlaEvenWhenCategoryFieldDiffers() {
        TicketCategory category = new TicketCategory("Safety", 5,
                TicketCategory.Priority.HIGH, 80, TicketCategory.VerificationType.MANUAL);
        SupportTicket ticket = new SupportTicket(null, null, category, "Safety", "Details");
        ticket.created();

        long hours = java.time.Duration.between(ticket.getCreatedAt(), ticket.getDeadline()).toHours();
        assertTrue(hours == 23 || hours == 24);
    }
}
