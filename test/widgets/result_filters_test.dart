import 'package:carshare/models/trip_search_result.dart';
import 'package:carshare/widgets/result_filters.dart';
import 'package:flutter_test/flutter_test.dart';

TripSearchResult result({
  double price = 10,
  int seats = 2,
  bool instant = false,
  double? rating,
}) => TripSearchResult(
  tripId: 't',
  driverId: 'd',
  driverName: 'Driver',
  originLabel: 'A',
  destinationLabel: 'B',
  departureTime: DateTime(2026, 11, 13, 9),
  expectedArrival: DateTime(2026, 11, 13, 11),
  seatsAvailable: seats,
  pricePerSeat: price,
  instantBooking: instant,
  driverRating: rating,
  pickupDistanceM: 0,
  dropoffDistanceM: 0,
  timeGapMin: 0,
  matchScore: 100,
);

void main() {
  test('no filter keeps everything and counts as zero active', () {
    final all = [result(), result(price: 99, seats: 1)];

    expect(ResultFilters.none.apply(all), all);
    expect(ResultFilters.none.activeCount, 0);
    expect(ResultFilters.none.isActive, isFalse);
  });

  test('max price keeps trips at or under it', () {
    final cheap = result(price: 8);
    final exact = result(price: 10);
    final dear = result(price: 10.5);

    final kept = const ResultFilters(maxPrice: 10).apply([cheap, exact, dear]);

    expect(kept, [cheap, exact]);
  });

  test('min seats drops trips with fewer free seats', () {
    final one = result(seats: 1);
    final three = result(seats: 3);

    expect(const ResultFilters(minSeats: 2).apply([one, three]), [three]);
  });

  test('instant booking only drops request-to-book trips', () {
    final instant = result(instant: true);
    final request = result();

    expect(const ResultFilters(instantOnly: true).apply([instant, request]), [
      instant,
    ]);
  });

  test('min rating drops lower-rated and unrated drivers', () {
    final good = result(rating: 4.6);
    final fair = result(rating: 3.8);
    final unrated = result();

    expect(
      const ResultFilters(minRating: 4).apply([good, fair, unrated]),
      [good],
    );
  });

  test('filters combine and each active one is counted', () {
    const filters = ResultFilters(
      maxPrice: 12,
      minSeats: 2,
      instantOnly: true,
      minRating: 4,
    );
    final match = result(price: 12, seats: 2, instant: true, rating: 4);
    final tooDear = result(price: 13, seats: 2, instant: true, rating: 4.9);

    expect(filters.activeCount, 4);
    expect(filters.apply([match, tooDear]), [match]);
  });

  test('reset goes back to none, and copyWith can clear a limit', () {
    const some = ResultFilters(maxPrice: 5, minRating: 4);

    expect(some.copyWith(clearMaxPrice: true).maxPrice, isNull);
    expect(some.copyWith(clearMaxPrice: true).minRating, 4);
    expect(ResultFilters.none == const ResultFilters(), isTrue);
  });
}
