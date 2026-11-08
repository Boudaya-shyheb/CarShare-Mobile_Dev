/// The trip facts carried inside a passenger's own reservation (`TripBrief`).
///
/// Deliberately has no seat counts: the API leaves them out because they move whenever anyone
/// books. Read the trip itself for live availability.
class TripBrief {
  const TripBrief({
    required this.tripId,
    required this.driverId,
    required this.driverName,
    required this.originLabel,
    required this.destinationLabel,
    required this.departureTime,
    required this.expectedArrival,
    required this.pricePerSeat,
    required this.tripStatus,
    this.distanceM,
    this.durationS,
  });

  final String tripId;
  final String driverId;
  final String driverName;
  final String originLabel;
  final String destinationLabel;
  final DateTime departureTime;
  final DateTime expectedArrival;
  final double pricePerSeat;
  final String tripStatus;
  final int? distanceM;
  final int? durationS;

  factory TripBrief.fromJson(Map<String, dynamic> json) => TripBrief(
    tripId: json['tripId'] as String,
    driverId: json['driverId'] as String,
    driverName: json['driverName'] as String,
    originLabel: json['originLabel'] as String,
    destinationLabel: json['destinationLabel'] as String,
    departureTime: DateTime.parse(json['departureTime'] as String),
    expectedArrival: DateTime.parse(json['expectedArrival'] as String),
    pricePerSeat: (json['pricePerSeat'] as num).toDouble(),
    tripStatus: json['tripStatus'] as String,
    distanceM: json['distanceM'] as int?,
    durationS: json['durationS'] as int?,
  );

  Map<String, dynamic> toJson() => {
    'tripId': tripId,
    'driverId': driverId,
    'driverName': driverName,
    'originLabel': originLabel,
    'destinationLabel': destinationLabel,
    'departureTime': departureTime.toUtc().toIso8601String(),
    'expectedArrival': expectedArrival.toUtc().toIso8601String(),
    'pricePerSeat': pricePerSeat,
    'tripStatus': tripStatus,
    'distanceM': distanceM,
    'durationS': durationS,
  };
}

/// A passenger's own reservation (`ReservationDetail`).
class Reservation {
  const Reservation({
    required this.id,
    required this.trip,
    required this.passengerId,
    required this.seats,
    required this.status,
    required this.lateCancellation,
    required this.createdAt,
    this.pickupCode,
    this.cancelReason,
    this.decidedAt,
    this.cancelledAt,
  });

  final String id;
  final TripBrief trip;
  final String passengerId;
  final int seats;

  /// PENDING, CONFIRMED, REFUSED, CANCELLED, NO_SHOW or COMPLETED.
  final String status;
  final bool lateCancellation;
  final DateTime createdAt;

  /// The 4-digit code shown at pickup. The server fills it in only once the reservation is
  /// CONFIRMED, and only for the passenger who owns it, so it is null the rest of the time.
  final String? pickupCode;
  final String? cancelReason;
  final DateTime? decidedAt;
  final DateTime? cancelledAt;

  bool get isActive => status == 'PENDING' || status == 'CONFIRMED';
  bool get isConfirmed => status == 'CONFIRMED';

  factory Reservation.fromJson(Map<String, dynamic> json) => Reservation(
    id: json['id'] as String,
    trip: TripBrief.fromJson(json['trip'] as Map<String, dynamic>),
    passengerId: json['passengerId'] as String,
    seats: json['seats'] as int,
    status: json['status'] as String,
    lateCancellation: json['lateCancellation'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    pickupCode: json['pickupCode'] as String?,
    cancelReason: json['cancelReason'] as String?,
    decidedAt: json['decidedAt'] == null
        ? null
        : DateTime.parse(json['decidedAt'] as String),
    cancelledAt: json['cancelledAt'] == null
        ? null
        : DateTime.parse(json['cancelledAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'trip': trip.toJson(),
    'passengerId': passengerId,
    'seats': seats,
    'status': status,
    'pickupCode': pickupCode,
    'lateCancellation': lateCancellation,
    'cancelReason': cancelReason,
    'decidedAt': decidedAt?.toUtc().toIso8601String(),
    'cancelledAt': cancelledAt?.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

/// One row of what the driver sees about their trip's passengers (`PassengerView`).
///
/// There is no pickup code here, and there never will be: the API never gives a driver one.
class PassengerView {
  const PassengerView({
    required this.reservationId,
    required this.passengerId,
    required this.passengerName,
    required this.seats,
    required this.status,
    required this.lateCancellation,
    required this.createdAt,
    this.cancelReason,
    this.decidedAt,
    this.cancelledAt,
  });

  final String reservationId;
  final String passengerId;
  final String passengerName;
  final int seats;
  final String status;
  final bool lateCancellation;
  final DateTime createdAt;
  final String? cancelReason;
  final DateTime? decidedAt;
  final DateTime? cancelledAt;

  bool get awaitsDecision => status == 'PENDING';

  factory PassengerView.fromJson(Map<String, dynamic> json) => PassengerView(
    reservationId: json['reservationId'] as String,
    passengerId: json['passengerId'] as String,
    passengerName: json['passengerName'] as String,
    seats: json['seats'] as int,
    status: json['status'] as String,
    lateCancellation: json['lateCancellation'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    cancelReason: json['cancelReason'] as String?,
    decidedAt: json['decidedAt'] == null
        ? null
        : DateTime.parse(json['decidedAt'] as String),
    cancelledAt: json['cancelledAt'] == null
        ? null
        : DateTime.parse(json['cancelledAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'reservationId': reservationId,
    'passengerId': passengerId,
    'passengerName': passengerName,
    'seats': seats,
    'status': status,
    'lateCancellation': lateCancellation,
    'cancelReason': cancelReason,
    'decidedAt': decidedAt?.toUtc().toIso8601String(),
    'cancelledAt': cancelledAt?.toUtc().toIso8601String(),
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}
