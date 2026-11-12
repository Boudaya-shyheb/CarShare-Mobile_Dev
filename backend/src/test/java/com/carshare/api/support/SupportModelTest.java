package com.carshare.api.support;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Duration;
import org.junit.jupiter.api.Test;

class SupportModelTest {
    @Test
    void ticketUsesCategoryDeadlineAndCreatesReference() {
        TicketCategory category = new TicketCategory("Driver was late", 2,
                TicketCategory.Priority.HIGH, 24,
                TicketCategory.VerificationType.AUTOMATIC);
        SupportTicket ticket = new SupportTicket(null, null, category,
                "Driver was late", "The driver arrived after the agreed time.");

        ticket.created();

        assertNotNull(ticket.getId());
        assertTrue(ticket.getReference().matches("DSP-\\d{4}-[0-9A-F]{8}"));
        assertEquals("Driver was late", ticket.getCategory());
        long hours = Duration.between(ticket.getCreatedAt(), ticket.getDeadline()).toHours();
        assertTrue(hours == 23 || hours == 24);
    }

    @Test
    void credibilityScoreAlwaysStaysBetweenZeroAndOneHundred() {
        CredibilityScore score = new CredibilityScore(null);

        score.changeBy(-150);
        assertEquals(0, score.getScore());

        score.changeBy(250);
        assertEquals(100, score.getScore());
    }

    @Test
    void anOpenTicketCanOnlyBeWithdrawnOnce() {
        TicketCategory category = new TicketCategory("Other", 1,
                TicketCategory.Priority.NORMAL, 72,
                TicketCategory.VerificationType.MANUAL);
        SupportTicket ticket = new SupportTicket(null, null, category,
                "Other", "A support request.");

        ticket.withdraw();

        assertEquals(SupportTicket.Status.WITHDRAWN, ticket.getStatus());
        assertNotNull(ticket.getWithdrawnAt());
        assertThrows(IllegalStateException.class, ticket::withdraw);
    }

    @Test
    void ticketFollowsTheOfficialStatusWorkflow() {
        TicketCategory category = new TicketCategory("Other", 1,
                TicketCategory.Priority.NORMAL, 72,
                TicketCategory.VerificationType.MANUAL);
        SupportTicket ticket = new SupportTicket(null, null, category,
                "Other", "A support request.");

        assertThrows(IllegalStateException.class, ticket::close);
        ticket.awaitResponse();
        ticket.review();
        ticket.resolve("First decision");
        ticket.contest();
        ticket.review();
        ticket.resolve("Final decision");
        ticket.close();

        assertEquals(SupportTicket.Status.CLOSED, ticket.getStatus());
    }
}
