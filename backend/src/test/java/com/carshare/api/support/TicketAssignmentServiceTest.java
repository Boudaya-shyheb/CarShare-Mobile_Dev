package com.carshare.api.support;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import com.carshare.api.users.AppUser;
import com.carshare.api.users.UserRepository;
import com.carshare.api.users.UserRole;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class TicketAssignmentServiceTest {
    @Test
    void proposesLeastLoadedAvailableAgentWithOrTools() {
        SupportTicketRepository tickets = mock(SupportTicketRepository.class);
        SupportAgentProfileRepository profiles = mock(SupportAgentProfileRepository.class);
        TicketAssignmentProposalRepository proposals = mock(TicketAssignmentProposalRepository.class);
        UserRepository users = mock(UserRepository.class);
        SupportTicket ticket = mock(SupportTicket.class);
        UUID ticketId = UUID.randomUUID();
        AppUser admin = new AppUser("Support Admin", "20000000", "support@example.com",
                "hash", UserRole.ADMIN);
        SupportAgentProfile profile = new SupportAgentProfile(admin);

        when(tickets.findDetailedById(ticketId)).thenReturn(Optional.of(ticket));
        when(ticket.getCategory()).thenReturn("Safety");
        when(users.findAllByRoleForUpdate(UserRole.ADMIN)).thenReturn(List.of(admin));
        when(profiles.existsById(admin.getId())).thenReturn(true);
        when(profiles.findAllByOrderByUser_FullNameAsc()).thenReturn(List.of(profile));
        when(tickets.countByAssignedAgent_IdAndStatusIn(any(), any())).thenReturn(0L);
        when(proposals.save(any(TicketAssignmentProposal.class)))
                .thenAnswer(call -> call.getArgument(0));

        TicketAssignmentService service = new TicketAssignmentService(
                tickets, profiles, proposals, users);
        TicketAssignmentService.AssignmentView result = service.propose(ticketId);

        assertEquals("OR_TOOLS_CP_SAT", result.algorithm());
        assertEquals(admin.getId(), result.agentId());
        assertEquals(TicketAssignmentProposal.Status.PROPOSED, result.status());
    }
}
