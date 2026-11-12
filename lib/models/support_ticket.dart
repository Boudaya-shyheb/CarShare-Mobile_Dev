enum TicketStatus {
  open,
  awaitingResponse,
  underReview,
  resolved,
  closed,
  withdrawn,
  contested,
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.reference,
    required this.category,
    required this.title,
    required this.description,
    required this.trip,
    required this.createdLabel,
    required this.status,
    required this.summary,
    this.deadline,
    this.resolution,
  });

  final String id;
  final String reference;
  final String category;
  final String title;
  final String description;
  final String trip;
  final String createdLabel;
  final TicketStatus status;
  final String summary;
  final DateTime? deadline;
  final String? resolution;

  bool get isResolved =>
      status == TicketStatus.resolved || status == TicketStatus.closed;

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    final state = json['status'] as String? ?? 'OPEN';
    final resolution = json['resolution'] as String?;
    final status = switch (state) {
      'UNDER_REVIEW' => TicketStatus.underReview,
      'RESOLVED' => TicketStatus.resolved,
      'CLOSED' => TicketStatus.closed,
      'WITHDRAWN' => TicketStatus.withdrawn,
      'CONTESTED' => TicketStatus.contested,
      'AWAITING_RESPONSE' => TicketStatus.awaitingResponse,
      _ => TicketStatus.open,
    };
    return SupportTicket(
      id: json['id'] as String? ?? '',
      reference:
          json['reference'] as String? ??
          'CS-${(json['id'] as String? ?? '').split('-').first.toUpperCase()}',
      category: json['category'] as String? ?? 'Support request',
      title: json['title'] as String? ?? 'Support request',
      description: json['description'] as String? ?? '',
      trip: json['tripId'] == null
          ? 'General request'
          : 'Trip ${json['tripId']}',
      createdLabel: _formatDate(json['createdAt']),
      status: status,
      summary: status == TicketStatus.resolved
          ? resolution ?? 'This request has been resolved.'
          : status == TicketStatus.underReview
          ? 'A CarShare support agent is reviewing this request.'
          : status == TicketStatus.withdrawn
          ? 'You withdrew this support request.'
          : 'Your request is waiting for review.',
      deadline: DateTime.tryParse('${json['deadline']}')?.toLocal(),
      resolution: resolution,
    );
  }

  static String _formatDate(Object? value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    if (date == null) return 'Recently';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
