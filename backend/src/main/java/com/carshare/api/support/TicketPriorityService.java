package com.carshare.api.support;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.Normalizer;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.UUID;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TicketPriorityService {
    private static final List<String> TERMS = List.of(
            "accident", "danger", "menace", "agression", "unsafe", "emergency");
    private static final Set<String> NEGATIONS = Set.of(
            "pas", "aucun", "aucune", "sans", "non", "not", "no", "never");
    private final SupportTicketRepository tickets;
    private final TicketDecisionRepository decisions;
    private final TicketRiskSignalRepository signals;

    public TicketPriorityService(SupportTicketRepository tickets,
            TicketDecisionRepository decisions, TicketRiskSignalRepository signals) {
        this.tickets = tickets; this.decisions = decisions; this.signals = signals;
    }

    @Transactional
    public Analysis refresh(SupportTicket ticket) {
        long reports = ticket.getReportedUser() == null ? 1
                : tickets.countByReportedUser_IdAndStatusNot(
                        ticket.getReportedUser().getId(), SupportTicket.Status.WITHDRAWN);
        long infractions = ticket.getReportedUser() == null ? 0
                : decisions.countInfractions(ticket.getReportedUser().getId(),
                        List.of(TicketDecision.Result.CONFIRMED, TicketDecision.Result.PARTIAL));
        double waiting = ticket.getCreatedAt() == null ? 0
                : Math.max(0, Duration.between(ticket.getCreatedAt(), Instant.now()).toMinutes() / 60.0);
        int severity = ticket.getCategoryDefinition().getSeverity();
        BigDecimal score = BigDecimal.valueOf(severity * 10.0 + reports * 5.0
                + infractions * 3.0 + waiting * 0.5).setScale(2, RoundingMode.HALF_UP);
        ticket.updatePriority(score);
        refreshSignals(ticket);
        return view(ticket, severity, reports, infractions, waiting);
    }

    @Transactional(readOnly = true)
    public Analysis view(SupportTicket ticket) {
        long reports = ticket.getReportedUser() == null ? 1
                : tickets.countByReportedUser_IdAndStatusNot(
                        ticket.getReportedUser().getId(), SupportTicket.Status.WITHDRAWN);
        long infractions = ticket.getReportedUser() == null ? 0
                : decisions.countInfractions(ticket.getReportedUser().getId(),
                        List.of(TicketDecision.Result.CONFIRMED, TicketDecision.Result.PARTIAL));
        double waiting = ticket.getCreatedAt() == null ? 0
                : Math.max(0, Duration.between(ticket.getCreatedAt(), Instant.now()).toMinutes() / 60.0);
        return view(ticket, ticket.getCategoryDefinition().getSeverity(), reports, infractions, waiting);
    }

    private Analysis view(SupportTicket ticket, int severity, long reports,
            long infractions, double waiting) {
        List<RiskSignalView> risk = signals.findByTicket_IdOrderByCreatedAtAsc(ticket.getId())
                .stream().map(s -> new RiskSignalView(s.getTerm(), s.getExcerpt(), s.isNegated()))
                .toList();
        long remaining = Duration.between(Instant.now(), ticket.getDeadline()).toMinutes();
        String sla = remaining < 0 ? "OVERDUE" : remaining <= 360 ? "NEAR_DEADLINE" : "ON_TIME";
        return new Analysis(ticket.getPriorityScore(), severity, reports, infractions,
                Math.round(waiting * 100.0) / 100.0, sla, remaining, risk,
                ticket.getPriorityCalculatedAt());
    }

    private void refreshSignals(SupportTicket ticket) {
        signals.deleteForTicket(ticket.getId());
        String text = normalize(ticket.getTitle() + " " + ticket.getDescription());
        String[] words = text.split("\\s+");
        Set<String> stored = new java.util.HashSet<>();
        for (int i = 0; i < words.length; i++) {
            String term = words[i].replaceAll("[^a-z]", "");
            if (!TERMS.contains(term)) continue;
            boolean negated = false;
            for (int j = Math.max(0, i - 3); j < i; j++) {
                if (NEGATIONS.contains(words[j].replaceAll("[^a-z]", ""))) negated = true;
            }
            if (!stored.add(term + ":" + negated)) continue;
            int start = Math.max(0, i - 4);
            int end = Math.min(words.length, i + 5);
            String excerpt = String.join(" ", java.util.Arrays.copyOfRange(words, start, end));
            signals.save(new TicketRiskSignal(ticket, term, excerpt, negated));
        }
    }

    private String normalize(String value) {
        return Normalizer.normalize(value, Normalizer.Form.NFD)
                .replaceAll("\\p{M}", "").toLowerCase(Locale.ROOT)
                .replaceAll("[^a-z]+", " ").strip();
    }

    public record Analysis(BigDecimal score, int severity, long reportCount,
            long previousInfractions, double waitingHours, String slaState,
            long remainingMinutes, List<RiskSignalView> riskSignals, Instant calculatedAt) { }
    public record RiskSignalView(String term, String excerpt, boolean negated) { }
}
