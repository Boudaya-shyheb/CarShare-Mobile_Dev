import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/reservation.dart';
import '../../models/trip.dart';
import '../../models/user_profile.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../services/reservation_local_store.dart';
import '../../services/reservation_service.dart';
import '../../theme.dart';
import '../../widgets/form_field.dart';
import '../../widgets/route_title.dart';
import '../../widgets/status_chip.dart';
import '../../widgets/trip_formats.dart';
import '../main_shell.dart';
import 'driver_trip_page.dart';
import 'publish_trip_page.dart';
import 'trip_completed_page.dart';
import 'trip_details_page.dart';

/// Mockup 07 — the Trips tab.
///
/// A passenger sees the reservations they hold; a driver sees the trips they published. The
/// three tabs are the API's own scopes, so each one is a single call.
class MyTripsPage extends StatefulWidget {
  const MyTripsPage({super.key, required this.user});

  final UserProfile user;

  @override
  State<MyTripsPage> createState() => _MyTripsPageState();
}

class _MyTripsPageState extends State<MyTripsPage>
    with SingleTickerProviderStateMixin {
  static const _scopes = ['upcoming', 'past', 'cancelled'];

  late final TabController _tabs = TabController(length: 3, vsync: this)
    ..addListener(_onTabChanged);

  bool get _isDriver => widget.user.role == 'driver';

  /// One future per tab, so moving between them does not re-fetch what is already loaded.
  final Map<int, Future<List<Object>>> _loaded = {};

  /// The tabs whose list came from the SQLite copy because the server could not be reached,
  /// with the time that copy was saved. A tab that loaded normally is not in the map.
  final Map<int, DateTime> _offlineSince = {};

  @override
  void initState() {
    super.initState();
    _loaded[0] = _fetch(0);
    carShareShellTab.addListener(_onShellTab);
  }

  @override
  void dispose() {
    carShareShellTab.removeListener(_onShellTab);
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  /// The shell keeps this page alive behind the other tabs, so its lists would otherwise stay as
  /// they were when the app opened. Whenever the Trips tab is brought to the front — by the
  /// bottom bar, or by the booking screen after a successful booking — the list on show is
  /// loaded again and the other lists are dropped, to be fetched when their tab is opened.
  void _onShellTab() {
    if (carShareShellTab.value != 1 || !mounted) return;
    _refreshAll(_tabs.index);
  }

  /// Loads [index] again and forgets every other tab's list.
  Future<void> _refreshAll(int index) {
    _loaded.removeWhere((key, _) => key != index);
    return _refresh(index);
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    if (!_loaded.containsKey(_tabs.index)) {
      // Block body: an arrow body would return the Future, which setState rejects.
      setState(() {
        _loaded[_tabs.index] = _fetch(_tabs.index);
      });
    }
  }

  /// Loads one tab from the API and saves the answer in SQLite. If the phone cannot reach the
  /// server, the last saved answer is used instead and the tab shows an "Offline" banner.
  Future<List<Object>> _fetch(int index) async {
    final scope = _scopes[index];
    final kind = _isDriver ? 'driver' : 'passenger';
    final userId = widget.user.id;
    final store = ReservationLocalStore.instance;
    try {
      final rows = _isDriver
          ? await ReservationService.instance.myTripsJson(scope: scope)
          : await ReservationService.instance.myReservationsJson(scope: scope);
      final loaded = _parse(
        rows,
      ); // read it first: never save what the app cannot read
      try {
        await store.saveTripsCache(
          userId: userId,
          kind: kind,
          scope: scope,
          json: jsonEncode(rows),
        );
      } catch (_) {
        // Losing the offline copy must not hide the trips that were just loaded.
      }
      if (mounted && _offlineSince.containsKey(index)) {
        setState(() => _offlineSince.remove(index));
      }
      return loaded;
    } on ApiException catch (error) {
      // A status code means the server answered, so that error is shown as it is. No status
      // code means the request never got through: use the saved copy if there is one.
      if (error.statusCode != null) rethrow;
      final cached = await store.loadTripsCache(
        userId: userId,
        kind: kind,
        scope: scope,
      );
      if (cached == null) rethrow;
      final rows = (jsonDecode(cached.json) as List)
          .cast<Map<String, dynamic>>();
      if (mounted) {
        setState(() => _offlineSince[index] = cached.cachedAt);
      }
      return _parse(rows);
    }
  }

  /// Turns the API's JSON rows into trips (driver) or reservations (passenger).
  List<Object> _parse(List<Map<String, dynamic>> rows) => [
    for (final row in rows)
      _isDriver ? Trip.fromJson(row) : Reservation.fromJson(row),
  ];

  Future<void> _refresh(int index) async {
    final future = _fetch(index);
    setState(() {
      _loaded[index] = future;
    });
    await future.catchError((_) => <Object>[]);
  }

  Future<void> _publish() async {
    final published = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const PublishTripPage()));
    if (published == true && mounted) await _refreshAll(_tabs.index);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    floatingActionButton: _isDriver
        ? FloatingActionButton.extended(
            onPressed: _publish,
            backgroundColor: carShareGreen,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text(
              'Publish a trip',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        : null,
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  'My trips',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: carShareText,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: TabBar(
                    controller: _tabs,
                    dividerColor: Colors.transparent,
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: carShareGreen,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: carShareMuted,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                    ),
                    tabs: const [
                      Tab(text: 'Upcoming'),
                      Tab(text: 'Past'),
                      Tab(text: 'Cancelled'),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: [for (var i = 0; i < 3; i++) _buildTab(i)],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _buildTab(int index) {
    final future = _loaded[index];
    if (future == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final since = _offlineSince[index];
    final tab = RefreshIndicator(
      onRefresh: () => _refresh(index),
      color: carShareGreen,
      child: FutureBuilder<List<Object>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _scrollable(
              _Message(
                icon: Icons.cloud_off,
                title: 'Could not load your trips',
                line: authErrorMessage(snapshot.error!),
                action: FilledButton(
                  onPressed: () => _refresh(index),
                  child: const Text('Retry'),
                ),
              ),
            );
          }
          final rows = snapshot.data ?? const <Object>[];
          if (rows.isEmpty) {
            return _scrollable(
              _Message(
                icon: Icons.route_outlined,
                title: _emptyTitle(index),
                line: _isDriver
                    ? 'Trips you publish show up here.'
                    : 'Seats you book show up here.',
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 90),
            itemCount: rows.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: rows[i] is Trip
                  ? _DriverTripCard(
                      trip: rows[i] as Trip,
                      onOpen: () => _openDriverTrip(rows[i] as Trip, index),
                    )
                  : _ReservationCard(
                      reservation: rows[i] as Reservation,
                      onCancel: () => _cancel(rows[i] as Reservation, index),
                      onDetails: () => _openTripDetails(
                        (rows[i] as Reservation).trip.tripId,
                        // The Past tab holds the COMPLETED and NO_SHOW rows.
                        finished: index == 1,
                      ),
                      onTrack: () {
                        // Name the trip first: the Live tab reads it as it opens.
                        carShareLiveTripId.value =
                            (rows[i] as Reservation).trip.tripId;
                        carShareShellTab.value = 2;
                      },
                    ),
            ),
          );
        },
      ),
    );
    if (since == null) return tab;
    return Column(
      children: [
        _OfflineBanner(since: since),
        Expanded(child: tab),
      ],
    );
  }

  String _emptyTitle(int index) => switch (index) {
    0 => 'Nothing coming up',
    1 => 'No past trips yet',
    _ => 'Nothing cancelled',
  };

  /// A RefreshIndicator only fires on a scrollable, so the empty and error states need one.
  Widget _scrollable(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(height: constraints.maxHeight, child: child),
    ),
  );

  Future<void> _openDriverTrip(Trip trip, int index) async {
    // Past means COMPLETED, where the driver wants the summary and the rating rows.
    if (index == 1) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TripCompletedPage(tripId: trip.id)),
      );
      return;
    }
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => DriverTripPage(tripId: trip.id)),
    );
    if (changed == true && mounted) await _refreshAll(index);
  }

  /// A finished trip opens its summary — replay, timeline and rating — rather than the
  /// booking screen, which has nothing left to offer once the trip is over.
  void _openTripDetails(String tripId, {bool finished = false}) =>
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => finished
              ? TripCompletedPage(tripId: tripId)
              : TripDetailsPage(tripId: tripId),
        ),
      );

  Future<void> _cancel(Reservation reservation, int index) async {
    final late =
        reservation.trip.departureTime.difference(DateTime.now()).inMinutes <
        120;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelDialog(
        title: 'Cancel this reservation?',
        warning: late
            ? 'Departure is less than two hours away, so this counts as a late '
                  'cancellation on your record.'
            : null,
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await ReservationService.instance.cancelReservation(
        reservation.id,
        reason,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reservation cancelled.')));
      // A cancelled row leaves Upcoming for the Cancelled tab, so every other list is dropped.
      await _refreshAll(index);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    }
  }
}

// --- cards -----------------------------------------------------------------------------------

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.onCancel,
    required this.onDetails,
    required this.onTrack,
  });

  final Reservation reservation;
  final VoidCallback onCancel;
  final VoidCallback onDetails;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    final trip = reservation.trip;
    final canTrack =
        reservation.isConfirmed && tripIsTrackable(trip.tripStatus);
    return CarShareCard(
      onTap: onDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(
                label: reservationStatusLabel(reservation.status),
                colour: reservationStatusColour(reservation.status),
              ),
              const Spacer(),
              Text(
                formatWhen(trip.departureTime),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: carShareMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RouteTitle(
            origin: RouteTitle.shortName(trip.originLabel),
            destination: RouteTitle.shortName(trip.destinationLabel),
            fontSize: 18,
          ),
          const SizedBox(height: 4),
          Text(
            reservation.status == 'PENDING'
                ? 'Waiting for driver approval'
                : 'Pickup ${formatClock(trip.departureTime)} · '
                      '${formatSeats(reservation.seats)}',
            style: const TextStyle(fontSize: 13, color: carShareMuted),
          ),
          if (reservation.pickupCode != null) ...[
            const SizedBox(height: 12),
            _PickupCode(code: reservation.pickupCode!),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: carShareBorder),
          ),
          Row(
            children: [
              InitialsAvatar(initials: initialsOf(trip.driverName), size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trip.driverName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: carShareText,
                  ),
                ),
              ),
              if (canTrack)
                FilledButton.icon(
                  onPressed: onTrack,
                  icon: const Icon(Icons.near_me, size: 18),
                  label: const Text('Track live'),
                )
              else if (reservation.isActive)
                OutlinedButton(onPressed: onCancel, child: const Text('Cancel'))
              else
                TextButton(onPressed: onDetails, child: const Text('Details')),
            ],
          ),
        ],
      ),
    );
  }
}

/// The four digits the passenger reads out at pickup. Never shown to a driver.
class _PickupCode extends StatelessWidget {
  const _PickupCode({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: carShareTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.pin_outlined, size: 20, color: carShareGreen),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Show this code to the driver',
            style: TextStyle(fontSize: 13, color: carShareGreen),
          ),
        ),
        Text(
          code,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
            color: carShareGreen,
          ),
        ),
      ],
    ),
  );
}

class _DriverTripCard extends StatelessWidget {
  const _DriverTripCard({required this.trip, required this.onOpen});

  final Trip trip;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final booked = trip.seatsTotal - trip.seatsAvailable;
    return CarShareCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(
                label: prettyStatus(trip.status),
                colour: tripStatusColour(trip.status),
              ),
              const Spacer(),
              Text(
                formatWhen(trip.departureTime),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: carShareMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          RouteTitle(
            origin: RouteTitle.shortName(trip.originLabel),
            destination: RouteTitle.shortName(trip.destinationLabel),
            fontSize: 18,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.event_seat_outlined,
                size: 18,
                color: carShareMuted,
              ),
              const SizedBox(width: 6),
              Text(
                '$booked/${trip.seatsTotal} seats booked',
                style: const TextStyle(fontSize: 13, color: carShareMuted),
              ),
              const Spacer(),
              Text(
                formatPrice(trip.pricePerSeat),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: carShareGreen,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks for the reason the API requires, with the course's Form + validator pattern.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog({required this.title, this.warning});

  final String title;
  final String? warning;

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_reason.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.warning != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: carShareWarning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 20, color: carShareWarning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.warning!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: carShareText,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          CarShareTextField(
            controller: _reason,
            label: 'Reason',
            icon: Icons.edit_outlined,
            validator: (value) {
              final text = value?.trim() ?? '';
              if (text.isEmpty) return 'Please say why you are cancelling.';
              if (text.length > 200) return 'Keep it under 200 characters.';
              return null;
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Keep it'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Cancel it')),
    ],
  );
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.line,
    this.action,
  });

  final IconData icon;
  final String title;
  final String line;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: carShareTint,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 34, color: carShareGreen),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: carShareText,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            line,
            textAlign: TextAlign.center,
            style: const TextStyle(color: carShareMuted, height: 1.4),
          ),
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    ),
  );
}

/// Shown above a tab whose list came from the saved SQLite copy instead of the API.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.since});

  final DateTime since;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(16, 4, 16, 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: carShareWarning.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.cloud_off, size: 18, color: carShareText),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Offline: showing data from ${formatWhen(since.toLocal())}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: carShareText,
            ),
          ),
        ),
      ],
    ),
  );
}
