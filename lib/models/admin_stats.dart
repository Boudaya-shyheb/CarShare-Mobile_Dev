/// The counters at the top of the admin dashboard (`GET /admin/stats`).
class AdminStats {
  const AdminStats({
    required this.users,
    required this.tripsTotal,
    required this.tripsInProgress,
    required this.tripsCompleted,
    required this.tripsCancelled,
    required this.reservations,
    required this.lostAndFoundReports,
  });

  final int users;
  final int tripsTotal;

  /// Trips the driver has set off on and not yet finished.
  final int tripsInProgress;
  final int tripsCompleted;
  final int tripsCancelled;
  final int reservations;
  final int lostAndFoundReports;

  factory AdminStats.fromJson(Map<String, dynamic> json) => AdminStats(
    users: json['users'] as int,
    tripsTotal: json['tripsTotal'] as int,
    tripsInProgress: json['tripsInProgress'] as int,
    tripsCompleted: json['tripsCompleted'] as int,
    tripsCancelled: json['tripsCancelled'] as int,
    reservations: json['reservations'] as int,
    lostAndFoundReports: json['lostAndFoundReports'] as int,
  );

  Map<String, dynamic> toJson() => {
    'users': users,
    'tripsTotal': tripsTotal,
    'tripsInProgress': tripsInProgress,
    'tripsCompleted': tripsCompleted,
    'tripsCancelled': tripsCancelled,
    'reservations': reservations,
    'lostAndFoundReports': lostAndFoundReports,
  };
}
