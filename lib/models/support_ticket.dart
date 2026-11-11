enum TicketStatus { awaitingResponse, underReview, resolved, closed, contested }

class SupportTicket {
  const SupportTicket({
    required this.reference,
    required this.category,
    required this.title,
    required this.description,
    required this.trip,
    required this.createdLabel,
    required this.status,
    required this.summary,
    this.responseDeadline,
  });

  final String reference;
  final String category;
  final String title;
  final String description;
  final String trip;
  final String createdLabel;
  final TicketStatus status;
  final String summary;
  final String? responseDeadline;

  bool get isResolved =>
      status == TicketStatus.resolved || status == TicketStatus.closed;
}
