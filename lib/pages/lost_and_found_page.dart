import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:image_picker/image_picker.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart' show authErrorMessage;
import '../services/local_database.dart';
import '../services/photo_category_mapper.dart';
import '../services/photo_labeling_service.dart';
import '../theme.dart';

const _module = '/lost-and-found';
const _colorMarker = '\n\nColor: ';
const _draftMarker = 'carshare-lost-found-v1:';

/// The sample match and handover behind "Preview match" exist only in a build made with
/// `--dart-define=LF_DEMO_PREVIEW=true`; the screens people use never show them.
const _demoPreview = bool.fromEnvironment('LF_DEMO_PREVIEW');

enum _ReportType {
  lost('LOST', 'lost'),
  found('FOUND', 'found');

  const _ReportType(this.apiValue, this.label);
  final String apiValue;
  final String label;

  static _ReportType parse(Object? value) =>
      value == 'FOUND' ? _ReportType.found : _ReportType.lost;
}

enum _Category {
  phone('Phone', Icons.smartphone_outlined),
  keys('Keys', Icons.key_outlined),
  wallet('Wallet', Icons.account_balance_wallet_outlined),
  bag('Bag', Icons.backpack_outlined),
  glasses('Glasses', Icons.visibility_outlined),
  clothing('Clothing', Icons.checkroom_outlined),
  documents('Documents', Icons.description_outlined),
  other('Other', Icons.inventory_2_outlined);

  const _Category(this.label, this.icon);
  final String label;
  final IconData icon;

  static _Category? parse(String title) {
    final normalized = title.trim().toLowerCase();
    for (final category in values) {
      if (category.label.toLowerCase() == normalized) return category;
    }
    return null;
  }
}

String? _text(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

class _Trip {
  _Trip(Map<String, dynamic> json)
    : id = _text(json, ['id', 'tripId']) ?? (throw const FormatException()),
      origin = _text(json, ['originLabel', 'origin', 'departureLabel']),
      destination = _text(json, [
        'destinationLabel',
        'destination',
        'arrivalLabel',
      ]),
      driver = _text(json, ['driverName']),
      departure = DateTime.tryParse(
        _text(json, ['departureTime', 'departureAt', 'departure']) ?? '',
      );

  final String id;
  final String? origin;
  final String? destination;
  final String? driver;
  final DateTime? departure;

  String get route => origin != null && destination != null
      ? '$origin → $destination'
      : origin ?? destination ?? 'CarShare trip';

  String subtitle(BuildContext context) => [
    if (departure != null) _dateTimeLabel(context, departure!),
    if (driver != null) 'Driver: $driver',
  ].join(' · ');
}

String _dateTimeLabel(BuildContext context, DateTime date) {
  final local = date.toLocal();
  final formats = MaterialLocalizations.of(context);
  return '${formats.formatMediumDate(local)} · '
      '${formats.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

class _Report {
  _Report(this.trip, Map<String, dynamic> json)
    : id = _text(json, ['id', 'reportId']) ?? (throw const FormatException()),
      reporterId =
          _text(json, [
            'reporterId',
            'reporterUserId',
            'reportedById',
            'authorId',
            'userId',
          ]) ??
          (throw const FormatException()),
      reporterName = _text(json, ['reporterName', 'reporterFullName']),
      type = _ReportType.parse(json['type'] ?? json['reportType']),
      title = _text(json, ['title']) ?? 'Item',
      details = _text(json, ['description']) ?? '',
      resolved = json['status'] == 'RESOLVED',
      created = DateTime.tryParse(_text(json, ['createdAt']) ?? ''),
      hasPhoto = json['hasPhoto'] == true;

  final _Trip trip;
  final String id;
  final String reporterId;
  final String? reporterName;
  final _ReportType type;
  final String title;
  final String details;
  final bool resolved;
  final DateTime? created;

  /// The server holds a photo for this report (`GET /reports/{id}/photo`).
  final bool hasPhoto;

  _Category? get category => _Category.parse(title);
  String get description {
    final start = details.lastIndexOf(_colorMarker);
    return start < 0 ? details : details.substring(0, start);
  }

  String get color {
    final start = details.lastIndexOf(_colorMarker);
    return start < 0 ? '' : details.substring(start + _colorMarker.length);
  }

  String get displayTitle => category != null && description.trim().isNotEmpty
      ? description.trim().split('\n').first
      : title;
}

/// The handover the server keeps for one matched pair (`/lost-and-found/handovers`). Both people
/// read the same one; only the owner of the lost item is sent the code.
class _Handover {
  _Handover(Map<String, dynamic> json)
    : id = _text(json, ['id']) ?? (throw const FormatException()),
      lostReportId =
          _text(json, ['lostReportId']) ?? (throw const FormatException()),
      foundReportId =
          _text(json, ['foundReportId']) ?? (throw const FormatException()),
      status = _text(json, ['status']) ?? 'PROPOSED',
      meetingPoint = _text(json, ['meetingPoint']),
      meetingTime = _text(json, ['meetingTime']),
      isOwner = json['role'] == 'OWNER',
      otherName = _text(json, ['otherReporterName']),
      code = _text(json, ['code']);

  final String id;
  final String lostReportId;
  final String foundReportId;
  final String status;
  final String? meetingPoint;
  final String? meetingTime;

  /// True for the person who lost the item, false for the one who found it.
  final bool isOwner;
  final String? otherName;
  final String? code;

  bool get isArranged => status == 'ARRANGED';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';

  /// The id of the report on the other side of this handover.
  String otherReportId(String mine) =>
      mine == lostReportId ? foundReportId : lostReportId;
}

class _Snapshot {
  const _Snapshot(this.trips, this.reports, this.handovers);
  final List<_Trip> trips;
  final List<_Report> reports;

  /// Every handover the signed-in user is part of, newest change first.
  final List<_Handover> handovers;

  /// The live or finished handover a report is in. A cancelled one does not count: the report
  /// is back to searching.
  _Handover? handoverFor(String reportId) {
    for (final handover in handovers) {
      if (handover.isCancelled) continue;
      if (handover.lostReportId == reportId ||
          handover.foundReportId == reportId) {
        return handover;
      }
    }
    return null;
  }

  /// Whether this pair was called off ("Not my item") by either side.
  bool wasRejected(String lostReportId, String foundReportId) => handovers.any(
    (handover) =>
        handover.isCancelled &&
        handover.lostReportId == lostReportId &&
        handover.foundReportId == foundReportId,
  );
}

class LostAndFoundPage extends StatefulWidget {
  const LostAndFoundPage({
    super.key,
    required this.userId,
    this.initialReportId,
  });

  final String userId;

  /// Opens this report's page as soon as the list has loaded (from a notification).
  final String? initialReportId;

  @override
  State<LostAndFoundPage> createState() => _LostAndFoundPageState();
}

class _LostAndFoundPageState extends State<LostAndFoundPage> {
  final _api = ApiClient.instance;
  final _photos = <String, Uint8List>{};
  final _search = TextEditingController();
  late Future<_Snapshot> _snapshot;
  _ReportType _tab = _ReportType.lost;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _snapshot = _load();
    if (widget.initialReportId != null) {
      _snapshot.then(_openInitial, onError: (_) {});
    }
  }

  Future<void> _openInitial(_Snapshot data) async {
    final id = widget.initialReportId;
    if (id == null || !mounted) return;
    for (final report in data.reports) {
      if (report.id == id && report.reporterId == widget.userId) {
        setState(() => _tab = report.type);
        await _details(report, _findMatch(report, data), data);
        return;
      }
    }
  }

  @override
  void didUpdateWidget(covariant LostAndFoundPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _photos.clear();
      _search.clear();
      _snapshot = _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<_Snapshot> _load() async {
    final rows = await _api.getList('$_module/trips');
    final trips = rows.map(_Trip.new).toList();
    final reportsByTrip = await Future.wait(
      trips.map((trip) async {
        final reports = await _api.getList('$_module/trips/${trip.id}/reports');
        return reports.map((row) => _Report(trip, row)).toList();
      }),
    );
    final reports = reportsByTrip.expand((items) => items).toList();
    reports.sort(
      (a, b) => (b.created?.millisecondsSinceEpoch ?? 0).compareTo(
        a.created?.millisecondsSinceEpoch ?? 0,
      ),
    );
    final handovers = (await _api.getList('$_module/handovers/mine'))
        .map(_Handover.new)
        .toList();
    await _addReportsOutsideTrips(reports, handovers);
    final data = _Snapshot(trips, reports, handovers);
    await _loadPhotos(data);
    return data;
  }

  /// A trip that ended drops out of the trip list, and its reports with it. A report still held
  /// by a handover, or the one a notification opens, is read directly by id instead.
  Future<void> _addReportsOutsideTrips(
    List<_Report> reports,
    List<_Handover> handovers,
  ) async {
    final known = reports.map((report) => report.id).toSet();
    final wanted = <String>{
      for (final handover in handovers) ...[
        handover.lostReportId,
        handover.foundReportId,
      ],
      ?widget.initialReportId,
    }..removeAll(known);
    final fetched = await Future.wait(
      wanted.map((id) async {
        try {
          final json = await _api.get('$_module/reports/$id');
          return _Report(
            _Trip({
              'id': json['tripId'],
              'originLabel': json['originLabel'],
              'destinationLabel': json['destinationLabel'],
              'departureTime': json['departureTime'],
            }),
            json,
          );
        } catch (_) {
          return null;
        }
      }),
    );
    reports.addAll(fetched.whereType<_Report>());
    reports.sort(
      (a, b) => (b.created?.millisecondsSinceEpoch ?? 0).compareTo(
        a.created?.millisecondsSinceEpoch ?? 0,
      ),
    );
  }

  /// Fetches the photos the user may see and does not have yet: their own reports' and the
  /// photo of the report each one matches. A photo that cannot be fetched is simply not shown.
  Future<void> _loadPhotos(_Snapshot data) async {
    final wanted = <String>{};
    for (final report in data.reports) {
      if (report.reporterId != widget.userId) continue;
      if (report.hasPhoto) wanted.add(report.id);
      final match = _findMatch(report, data);
      if (match != null && match.hasPhoto) wanted.add(match.id);
    }
    await Future.wait(
      wanted.where((id) => !_photos.containsKey(id)).map((id) async {
        try {
          _photos[id] = await _api.getBytes('$_module/reports/$id/photo');
        } catch (_) {
          // no photo to show
        }
      }),
    );
  }

  Future<void> _refresh() async {
    final next = _load();
    // A block body: an arrow body would return the Future, which setState refuses.
    setState(() {
      _snapshot = next;
    });
    try {
      await next;
    } catch (_) {
      // FutureBuilder renders the error and the retry action.
    }
  }

  /// The phone decides who matches whom: same trip, opposite type, a different person, same
  /// category and, when both gave one, the same colour. Once a pair has a handover on the
  /// server, that pair is the match; a pair someone called off is never offered again.
  _Report? _findMatch(_Report report, _Snapshot snapshot) {
    final handover = snapshot.handoverFor(report.id);
    if (handover != null) {
      final otherId = handover.otherReportId(report.id);
      for (final candidate in snapshot.reports) {
        if (candidate.id == otherId) return candidate;
      }
      return null;
    }

    final category = report.category;
    if (report.resolved || category == null || category == _Category.other) {
      return null;
    }
    final isLost = report.type == _ReportType.lost;
    _Report? sameCategory;
    for (final candidate in snapshot.reports) {
      if (candidate.resolved ||
          candidate.type == report.type ||
          candidate.trip.id != report.trip.id ||
          candidate.reporterId == widget.userId ||
          candidate.category != category ||
          snapshot.wasRejected(
            isLost ? report.id : candidate.id,
            isLost ? candidate.id : report.id,
          ) ||
          snapshot.handoverFor(candidate.id) != null) {
        continue;
      }
      if (report.color.isNotEmpty && candidate.color.isNotEmpty) {
        if (report.color.toLowerCase() == candidate.color.toLowerCase()) {
          return candidate;
        }
      } else {
        sameCategory ??= candidate;
      }
    }
    return sameCategory;
  }

  Future<void> _newReport(List<_Trip> trips) async {
    final created = await Navigator.of(context).push<_PublishedReport>(
      MaterialPageRoute(
        builder: (_) =>
            _ReportForm(userId: widget.userId, initialType: _tab, trips: trips),
      ),
    );
    if (!mounted || created == null) return;
    final photo = created.photo;
    if (photo != null && created.id != null) _photos[created.id!] = photo;
    setState(() => _tab = created.type);
    _message(context, 'Report submitted.');
    await _refresh();
  }

  Future<void> _details(
    _Report report,
    _Report? match,
    _Snapshot snapshot,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _ReportDetails(
          report: report,
          match: match,
          handover: snapshot.handoverFor(report.id),
          reload: () => _reloadDetails(report.id),
          photo: _photos[report.id],
          photos: _photos,
        ),
      ),
    );
    // Whatever happened over there (a handover, a rejection, a closed report) is on the list now.
    if (mounted) await _refresh();
  }

  /// Reads everything again for the details page, and keeps the list behind it up to date.
  Future<_DetailState> _reloadDetails(String reportId) async {
    final next = _load();
    if (mounted) {
      setState(() {
        _snapshot = next;
      });
    }
    final data = await next;
    final report = data.reports.firstWhere((item) => item.id == reportId);
    return _DetailState(
      report,
      _findMatch(report, data),
      data.handoverFor(reportId),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: carShareBackground,
    appBar: AppBar(
      backgroundColor: carShareBackground,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Lost & Found',
        style: TextStyle(color: carShareText, fontWeight: FontWeight.w800),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: IconButton.filledTonal(
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: carShareText,
            ),
            tooltip: _searching ? 'Close search' : 'Search reports',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _search.clear();
            }),
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
        ),
      ],
    ),
    body: FutureBuilder<_Snapshot>(
      future: _snapshot,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final query = _search.text.trim().toLowerCase();
        final mine = data?.reports
            .where(
              (report) =>
                  report.reporterId == widget.userId &&
                  report.type == _tab &&
                  '${report.title} ${report.description} ${report.trip.route}'
                      .toLowerCase()
                      .contains(query),
            )
            .toList();
        return _PageWidth(
          child: Column(
            children: [
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: [
                      _tabs(),
                      if (_searching) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _search,
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                          decoration: _field(
                            'Search reports',
                            icon: Icons.search,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _Notice(
                        text: _tab == _ReportType.lost
                            ? 'Lost something in a car? Check for similar items '
                                  'reported on the same trip.'
                            : 'Found something in a car? Report it so the owner '
                                  'can identify it.',
                        highlighted: true,
                      ),
                      const SizedBox(height: 14),
                      if (snapshot.connectionState != ConnectionState.done)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (snapshot.hasError)
                        _Panel(
                          child: Column(
                            children: [
                              Text(_errorMessage(snapshot.error)),
                              TextButton(
                                onPressed: _refresh,
                                child: const Text('Try again'),
                              ),
                            ],
                          ),
                        )
                      else if (mine == null || mine.isEmpty)
                        _Panel(
                          child: Text(
                            query.isNotEmpty
                                ? 'No reports match your search.'
                                : data?.trips.isEmpty == true
                                ? 'No eligible trips yet. Your eligible CarShare '
                                      'trips will appear here.'
                                : 'Your ${_tab.label} item reports will appear here.',
                          ),
                        )
                      else
                        for (final report in mine) _reportCard(report, data!),
                    ],
                  ),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.done)
                // SafeArea keeps the button clear of the phone's navigation bar.
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: FilledButton.icon(
                    style: _filledStyle(pill: true),
                    onPressed: () => _newReport(data?.trips ?? const []),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text('Report a ${_tab.label} item'),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );

  Widget _tabs() => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    padding: const EdgeInsets.all(4),
    child: Row(
      children: [
        for (final type in _ReportType.values)
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor: _tab == type ? carShareGreen : Colors.white,
                foregroundColor: _tab == type ? Colors.white : carShareMuted,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              onPressed: () => setState(() => _tab = type),
              child: Text(
                type == _ReportType.lost ? 'My lost items' : 'Items I found',
              ),
            ),
          ),
      ],
    ),
  );

  Widget _reportCard(_Report report, _Snapshot snapshot) {
    final match = _findMatch(report, snapshot);
    final handover = snapshot.handoverFor(report.id);
    final status = report.resolved
        ? 'Returned'
        : handover?.isArranged == true
        ? 'Handover'
        : handover != null
        ? 'Matched'
        : match != null
        ? 'Match found'
        : 'Searching';
    final statusColor = report.resolved
        ? carShareMuted
        : match != null
        ? carShareGreen
        : const Color(0xFF8B5400);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _details(report, match, snapshot),
              child: Row(
                children: [
                  _ItemIcon(report.category, photo: _photos[report.id]),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _strong,
                        ),
                        Text(
                          [
                            report.trip.route,
                            if (report.created != null)
                              _dateTimeLabel(context, report.created!),
                          ].join(' · '),
                          style: _muted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _Pill(
                  status,
                  color: statusColor,
                  background: report.resolved
                      ? carShareBackground
                      : match != null
                      ? carShareTint
                      : const Color(0xFFFFF1C2),
                ),
                const Spacer(),
                if (match != null && !report.resolved)
                  FilledButton(
                    style: _filledStyle(pill: true, height: 40),
                    onPressed: () => _details(report, match, snapshot),
                    child: Text(handover == null ? 'See match' : 'View report'),
                  )
                else
                  TextButton(
                    onPressed: () => _details(report, match, snapshot),
                    child: const Text('View report'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishedReport {
  const _PublishedReport(this.id, this.type, this.photo);
  final String? id;
  final _ReportType type;
  final Uint8List? photo;
}

class _ReportForm extends StatefulWidget {
  const _ReportForm({
    required this.userId,
    required this.initialType,
    required this.trips,
  });

  final String userId;
  final _ReportType initialType;
  final List<_Trip> trips;

  @override
  State<_ReportForm> createState() => _ReportFormState();
}

class _ReportFormState extends State<_ReportForm> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _color = TextEditingController();
  final _imagePicker = ImagePicker();
  final _database = LocalDatabase.instance;
  late final _ReportType _type;
  _Trip? _trip;
  _Category? _category;
  String? _legacyTitle;
  Uint8List? _photo;
  bool _busy = false;
  bool _missingCategory = false;

  /// "Looks like: Phone (87%)", from labelling the photo on the phone.
  PhotoCategorySuggestion? _suggestion;

  bool get _supportsDrafts =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    if (widget.trips.length == 1) _trip = widget.trips.single;
    if (_supportsDrafts) _restoreDraft();
  }

  @override
  void dispose() {
    _description.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _restoreDraft() async {
    setState(() => _busy = true);
    try {
      final draft = await _database.getLostAndFoundDraft(widget.userId);
      if (!mounted || draft == null) return;
      final type = _ReportType.parse(draft['report_type']);
      if (type != widget.initialType) return;

      final title = draft['title'] as String? ?? '';
      final storedDescription = draft['description'] as String? ?? '';
      if (storedDescription.startsWith(_draftMarker)) {
        final saved = jsonDecode(
          storedDescription.substring(_draftMarker.length),
        ) as Map<String, dynamic>;
        _description.text = saved['description'] as String? ?? '';
        _color.text = saved['color'] as String? ?? '';
        final savedTrip = saved['tripId'];
        if (savedTrip != null) {
          _trip = null;
          for (final trip in widget.trips) {
            if (trip.id == savedTrip) _trip = trip;
          }
        }
      } else {
        _description.text = storedDescription;
      }
      _category = _Category.parse(title);
      if (title.isNotEmpty && _category == null) {
        _legacyTitle = title;
        _category = _Category.other;
      }
      _photo = draft['photo'] as Uint8List?;
    } catch (_) {
      if (mounted) _message(context, 'Could not restore your draft.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveDraft() async {
    if (_category == null &&
        _description.text.trim().isEmpty &&
        _color.text.trim().isEmpty &&
        _photo == null) {
      _message(context, 'Add some item details first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _database.saveLostAndFoundDraft(
        userId: widget.userId,
        reportType: _type.apiValue,
        title: _legacyTitle ?? _category?.label ?? '',
        description:
            '$_draftMarker${jsonEncode({'description': _description.text.trim(), 'color': _color.text.trim(), 'tripId': _trip?.id})}',
        photo: _photo,
      );
      if (mounted) _message(context, 'Draft saved on this device.');
    } catch (_) {
      if (mounted) _message(context, 'Could not save your draft.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Camera or gallery, then labels the photo on the phone to suggest a category.
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheet, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(sheet, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 82,
      );
      if (image == null || !mounted) return;
      if (await image.length() > 2 * 1024 * 1024) {
        if (mounted) _message(context, 'Choose a photo smaller than 2 MB.');
        return;
      }
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _suggestion = null;
      });
      if (_labelsOnDevice) {
        final suggestion = await PhotoLabelingService.instance.suggest(
          image.path,
        );
        if (mounted && identical(_photo, bytes)) {
          setState(() => _suggestion = suggestion);
        }
      }
    } catch (_) {
      if (mounted) _message(context, 'Could not open that photo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// ML Kit runs on Android and iOS only.
  bool get _labelsOnDevice =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _applySuggestion() {
    final suggested = _suggestion;
    final category = suggested == null
        ? null
        : _Category.parse(suggested.category);
    if (category == null) return;
    setState(() {
      _category = category;
      _legacyTitle = null;
      _missingCategory = false;
    });
  }

  Future<void> _chooseTrip() async {
    final trip = await showModalBottomSheet<_Trip>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            for (final trip in widget.trips)
              ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(trip.route),
                subtitle: Text(trip.subtitle(sheet)),
                trailing: _trip?.id == trip.id
                    ? const Icon(Icons.check_circle, color: carShareGreen)
                    : null,
                onTap: () => Navigator.pop(sheet, trip),
              ),
          ],
        ),
      ),
    );
    if (mounted && trip != null) setState(() => _trip = trip);
  }

  Future<void> _submit() async {
    setState(() => _missingCategory = _category == null);
    if (_form.currentState?.validate() != true || _missingCategory) return;
    final trip = _trip;
    if (trip == null) {
      _message(
        context,
        widget.trips.isEmpty
            ? 'An eligible trip is required to submit a report.'
            : 'Choose the trip first.',
      );
      return;
    }

    final color = _color.text.trim();
    final description = _description.text.trim();
    final details = color.isEmpty
        ? description
        : '$description$_colorMarker$color';
    if (details.length > 1000) {
      _message(context, 'Shorten the description or color and try again.');
      return;
    }
    setState(() => _busy = true);
    try {
      final title = _legacyTitle ?? _category!.label;
      final photo = _photo;
      final fields = {
        'type': _type.apiValue,
        'title': title,
        'description': details,
      };
      final json = photo == null
          ? await ApiClient.instance.post(
              '$_module/trips/${trip.id}/reports',
              fields,
            )
          : await ApiClient.instance.uploadMultipart(
              path: '$_module/trips/${trip.id}/reports',
              fieldName: 'photo',
              bytes: photo,
              fileName: 'item.${_photoExtension(photo)}',
              mimeType: _photoMimeType(photo),
              fields: fields,
            );
      final id = _text(json, ['id', 'reportId']);
      if (mounted) Navigator.pop(context, _PublishedReport(id, _type, _photo));
    } catch (error) {
      if (mounted) _message(context, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    final photo = _photo;
    final hasTrips = widget.trips.isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _detailBar('Report a ${_type.label} item'),
      body: _PageWidth(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              const Text('Which trip?', style: _strong),
              const SizedBox(height: 6),
              Material(
                color: trip == null ? carShareBackground : carShareTint,
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: trip == null ? carShareBorder : carShareGreen,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  title: Text(
                    trip?.route ??
                        (hasTrips ? 'Choose a trip' : 'No eligible trips yet'),
                    style: _strong,
                  ),
                  subtitle: trip == null
                      ? null
                      : Text(trip.subtitle(context), style: _muted),
                  trailing: Icon(
                    trip == null ? Icons.expand_more : Icons.check_circle,
                    color: carShareGreen,
                  ),
                  onTap: _busy || !hasTrips ? null : _chooseTrip,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'What did you ${_type == _ReportType.lost ? 'lose' : 'find'}?',
                style: _strong,
              ),
              const SizedBox(height: 6),
              _categoryRow(_Category.values.take(4)),
              const SizedBox(height: 8),
              _categoryRow(_Category.values.skip(4)),
              if (_missingCategory)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Choose an item type.',
                    style: TextStyle(color: carShareDanger),
                  ),
                ),
              if (_legacyTitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Draft item: $_legacyTitle', style: _muted),
                ),
              const SizedBox(height: 14),
              const Text('Description', style: _strong),
              const SizedBox(height: 6),
              TextFormField(
                controller: _description,
                readOnly: _busy,
                minLines: 1,
                maxLines: 3,
                maxLength: 900,
                decoration: _field('Black phone, cracked top corner'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Enter a description.'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Color', style: _strong),
                        const SizedBox(height: 6),
                        TextFormField(
                          controller: _color,
                          readOnly: _busy,
                          maxLength: 60,
                          decoration: _field('Black'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text('Photo (optional)', style: _strong),
                        const SizedBox(height: 6),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 50),
                            foregroundColor: carShareGreen,
                            side: const BorderSide(color: carShareGreen),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          ),
                          onPressed: _busy ? null : _pickPhoto,
                          icon: const Icon(
                            Icons.photo_camera_outlined,
                            size: 18,
                          ),
                          label: Text(
                            photo == null ? 'Add photo' : 'Replace photo',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (photo != null && _suggestion != null) ...[
                const SizedBox(height: 10),
                _lookLikeChip(),
              ],
              if (photo != null) ...[
                const SizedBox(height: 10),
                _Photo(photo, height: 120),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _photo = null),
                    child: const Text('Remove photo'),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _Notice(
                text: hasTrips
                    ? 'People on this trip can see your report. The optional '
                          'photo is only shown to the person your report '
                          'matches. It is read on this phone, never sent '
                          'for analysis.'
                    : 'An eligible trip is required to submit a report.',
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _Footer(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_supportsDrafts)
              TextButton.icon(
                onPressed: _busy ? null : _saveDraft,
                icon: const Icon(Icons.bookmark_border),
                label: const Text('Save draft'),
              ),
            FilledButton(
              style: _filledStyle(),
              onPressed: _busy || !hasTrips ? null : _submit,
              child: Text(_busy ? 'Please wait…' : 'Submit report'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lookLikeChip() {
    final suggestion = _suggestion!;
    final category = _Category.parse(suggestion.category);
    final applied = category != null && _category == category;
    return Align(
      alignment: Alignment.centerLeft,
      child: ActionChip(
        avatar: Icon(
          applied ? Icons.check_circle : Icons.auto_awesome,
          size: 18,
          color: carShareGreen,
        ),
        backgroundColor: carShareTint,
        side: const BorderSide(color: carShareGreen),
        label: Text(
          'Looks like: ${suggestion.category} (${suggestion.percent}%)',
          style: const TextStyle(
            color: carShareGreen,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: _busy ? null : _applySuggestion,
      ),
    );
  }

  Widget _categoryRow(Iterable<_Category> categories) => Row(
    children: [
      for (final category in categories)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                backgroundColor: _category == category
                    ? carShareTint
                    : carShareBackground,
                foregroundColor: _category == category
                    ? carShareGreen
                    : carShareMuted,
                side: BorderSide(
                  color: _category == category
                      ? carShareGreen
                      : Colors.transparent,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 2,
                  vertical: 10,
                ),
              ),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _category = category;
                      _legacyTitle = null;
                      _missingCategory = false;
                    }),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(category.icon, size: 21),
                  const SizedBox(height: 4),
                  Text(category.label, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

/// What the details page shows about one report, recomputed from the server on every refresh.
class _DetailState {
  const _DetailState(this.report, this.match, this.handover);
  final _Report report;
  final _Report? match;
  final _Handover? handover;
}

/// A sample match and handover, only reachable in a build made with
/// `--dart-define=LF_DEMO_PREVIEW=true`. Nothing in it touches the server.
void _openMatchPreview(
  BuildContext context, {
  required _Report report,
  Uint8List? photo,
}) {
  final isLost = report.type == _ReportType.lost;
  final label = report.category?.label.toLowerCase() ?? 'item';
  final description = isLost
      ? 'Found $label on the back seat after the trip.'
      : 'Lost $label on the back seat during the trip.';
  final demoMatch = _Report(report.trip, {
    'id': 'preview-match',
    'reporterId': 'preview-participant',
    'reporterName': 'Demo participant',
    'type': isLost ? 'FOUND' : 'LOST',
    'title': report.title,
    'description': report.color.isEmpty
        ? description
        : '$description$_colorMarker${report.color}',
    'createdAt': DateTime.now().toIso8601String(),
  });

  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => _ReportDetails(
        report: report,
        match: demoMatch,
        handover: _Handover({
          'id': 'preview-handover',
          'lostReportId': isLost ? report.id : demoMatch.id,
          'foundReportId': isLost ? demoMatch.id : report.id,
          'status': 'ARRANGED',
          'meetingPoint': 'Ariana station, main entrance',
          'meetingTime': 'Today · 18:30',
          'role': isLost ? 'OWNER' : 'FINDER',
          'otherReporterName': 'Demo participant',
          'code': isLost ? _previewCode : null,
        }),
        reload: null,
        photo: photo,
        preview: true,
      ),
    ),
  );
}

const _previewCode = '5319';

class _ReportDetails extends StatefulWidget {
  const _ReportDetails({
    required this.report,
    required this.match,
    required this.handover,
    required this.reload,
    this.photo,
    this.photos,
    this.preview = false,
  });

  final _Report report;
  final _Report? match;
  final _Handover? handover;

  /// Reads the report, its match and its handover again from the server; null in the preview.
  final Future<_DetailState> Function()? reload;
  final Uint8List? photo;

  /// The page's photo cache by report id, so the match's photo shows once it has loaded.
  final Map<String, Uint8List>? photos;
  final bool preview;

  @override
  State<_ReportDetails> createState() => _ReportDetailsState();
}

class _ReportDetailsState extends State<_ReportDetails> {
  final _codeForm = GlobalKey<FormState>();
  final _code = TextEditingController();
  late _Report _report = widget.report;
  late _Report? _match = widget.match;
  late _Handover? _handover = widget.handover;
  bool _saving = false;
  bool _dismissed = false;
  bool _previewReturned = false;

  /// The finder's inline error after a wrong code ("3 tries left"), from the server.
  String? _codeError;

  bool get _isLost => _report.type == _ReportType.lost;
  bool get _returned => widget.preview
      ? _previewReturned
      : _report.resolved || (_handover?.isCompleted ?? false);

  @override
  void initState() {
    super.initState();
    // The other person may have acted since the list was loaded: ask the server again.
    if (widget.reload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Uint8List? _photoOf(_Report report) =>
      widget.photos?[report.id] ??
      (report.id == widget.report.id ? widget.photo : null);

  /// Pull-to-refresh, the first load, and the end of every action.
  Future<void> _reload() async {
    final reload = widget.reload;
    if (reload == null) return;
    try {
      final state = await reload();
      if (!mounted) return;
      setState(() {
        _report = state.report;
        _match = state.match;
        _handover = state.handover;
        if (state.handover != null) _dismissed = false;
      });
    } catch (error) {
      if (mounted) _message(context, _errorMessage(error));
    }
  }

  /// Runs one server action with the busy flag, shows its error, then reloads.
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _saving = true);
    try {
      await action();
      await _reload();
    } catch (error) {
      if (mounted) _message(context, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Starts the handover for the match the phone found. Both sides may press this; the server
  /// gives the second one the handover the first one created.
  Future<_Handover> _propose(_Report match) async {
    final json = await ApiClient.instance.post('$_module/handovers', {
      'lostReportId': _isLost ? _report.id : match.id,
      'foundReportId': _isLost ? match.id : _report.id,
    });
    return _Handover(json);
  }

  Future<void> _confirmMatch() async {
    final match = _match;
    if (match == null) return;
    await _run(() async {
      final handover = await _propose(match);
      if (mounted) setState(() => _handover = handover);
    });
  }

  Future<void> _arrange() async {
    final handover = _handover;
    if (handover == null) return;

    var place = handover.meetingPoint ?? '';
    var when = handover.meetingTime ?? '';
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Arrange handover'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: place,
                maxLength: 120,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Meeting point',
                  hintText: 'Ariana station, main entrance',
                ),
                onChanged: (value) => setDialogState(() => place = value),
              ),
              TextFormField(
                initialValue: when,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Date & time',
                  hintText: 'Tuesday, 18:30',
                ),
                onChanged: (value) => setDialogState(() => when = value),
              ),
            ],
          ),
          scrollable: true,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: place.trim().isEmpty || when.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, (
                      place.trim(),
                      when.trim(),
                    )),
              child: const Text('Save handover'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || result == null) return;
    final (meetingPoint, meetingTime) = result;

    if (widget.preview) {
      setState(
        () => _handover = _Handover({
          ..._previewJson(handover),
          'meetingPoint': meetingPoint,
          'meetingTime': meetingTime,
        }),
      );
      return;
    }
    await _run(() async {
      final json = await ApiClient.instance.put(
        '$_module/handovers/${handover.id}/arrange',
        {'meetingPoint': meetingPoint, 'meetingTime': meetingTime},
      );
      if (mounted) setState(() => _handover = _Handover(json));
    });
  }

  /// The finder types the code the owner read out; the server decides whether it is right.
  Future<void> _verify() async {
    final handover = _handover;
    if (handover == null) return;
    setState(() => _codeError = null);
    if (_codeForm.currentState?.validate() != true) return;
    final code = _code.text.trim();

    if (widget.preview) {
      setState(() {
        if (code == _previewCode) {
          _previewReturned = true;
        } else {
          _codeError = 'That code is not right.';
        }
      });
      return;
    }
    setState(() => _saving = true);
    try {
      final json = await ApiClient.instance.post(
        '$_module/handovers/${handover.id}/verify',
        {'code': code},
      );
      if (mounted) setState(() => _handover = _Handover(json));
      _code.clear();
      await _reload();
    } on ApiException catch (error) {
      // A wrong code is an expected answer, not a failure: say so next to the field.
      if (mounted) setState(() => _codeError = error.message);
      await _reload();
    } catch (error) {
      if (mounted) _message(context, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// "Not my item": asks first, then calls the match off for both people. Both reports stay
  /// open, and neither side is offered this same pair again.
  Future<void> _reject() async {
    final other =
        _handover?.otherName ?? _match?.reporterName ?? 'the other person';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Not your item?'),
        content: Text(
          'This calls off the match with $other. Both reports stay open and '
          'you will not be shown this match again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep match'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: carShareDanger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Not my item'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (widget.preview) {
      Navigator.of(context).pop();
      return;
    }
    final match = _match;
    setState(() => _saving = true);
    try {
      final handover = _handover;
      if (handover != null) {
        await ApiClient.instance.post(
          '$_module/handovers/${handover.id}/reject',
        );
      } else if (match != null) {
        // Nobody confirmed this match: the server records the refusal without ever starting
        // a handover, so the other person is told once ("Match called off") and never "confirmed".
        await ApiClient.instance.post('$_module/handovers/reject', {
          'lostReportId': _isLost ? _report.id : match.id,
          'foundReportId': _isLost ? match.id : _report.id,
        });
      }
      if (!mounted) return;
      setState(() {
        _dismissed = true;
        _handover = null;
        _match = null;
      });
      await _reload();
      if (mounted) setState(() => _dismissed = _match == null);
    } catch (error) {
      if (mounted) _message(context, _errorMessage(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Closes a report nobody matched ("I recovered my item"). A report in a handover cannot be
  /// closed this way: the server answers 409 and the finder's code does it for both sides.
  Future<void> _resolve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _isLost ? 'I recovered my item' : 'I already returned the item',
        ),
        content: const Text('Close this report?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Close report'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (widget.preview) {
      setState(() => _previewReturned = true);
      return;
    }
    await _run(() async {
      await ApiClient.instance.put(
        '$_module/reports/${_report.id}/resolve',
        {},
      );
    });
  }

  Map<String, dynamic> _previewJson(_Handover h) => {
    'id': h.id,
    'lostReportId': h.lostReportId,
    'foundReportId': h.foundReportId,
    'status': h.status,
    'meetingPoint': h.meetingPoint,
    'meetingTime': h.meetingTime,
    'role': h.isOwner ? 'OWNER' : 'FINDER',
    'otherReporterName': h.otherName,
    'code': h.code,
  };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final match = _dismissed ? null : _match;
    final handover = _handover;
    final returned = _returned;
    final arranged = handover?.isArranged ?? false;
    final sameColor =
        match != null &&
        report.color.isNotEmpty &&
        report.color.toLowerCase() == match.color.toLowerCase();
    final matchingCriteria = sameColor ? 3 : 2;
    final confidence = (100 * matchingCriteria / 3).round();
    final otherName =
        handover?.otherName ?? match?.reporterName ?? 'the other person';

    // The one button at the bottom: what this person can do next. The owner has none once the
    // meeting is arranged, because only the finder's code ends the handover.
    String? action;
    VoidCallback? onAction;
    if (!returned && match != null) {
      if (handover == null) {
        action = 'Confirm match';
        onAction = _confirmMatch;
      } else if (!arranged) {
        action = 'Arrange handover';
        onAction = _arrange;
      } else if (!handover.isOwner) {
        action = 'Confirm returned';
        onAction = _verify;
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _detailBar(
        match != null && !returned ? 'Match found' : 'Item report',
      ),
      body: _PageWidth(
        child: RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: [
              _Progress(
                matched: handover != null || returned,
                handover: arranged || returned,
                returned: returned,
              ),
              const SizedBox(height: 18),
              if (widget.preview) ...[
                const _Notice(text: 'Demo preview · Sample match and handover'),
                const SizedBox(height: 12),
              ],
              if (match == null)
                _comparison(report, 'Your report', photo: _photoOf(report))
              else ...[
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _comparison(
                          report,
                          'Your report',
                          photo: _photoOf(report),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _comparison(
                          match,
                          match.type == _ReportType.found
                              ? 'Found item'
                              : 'Lost item',
                          photo: _photoOf(match),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Flexible(
                            child: Text('Match confidence', style: _strong),
                          ),
                          Text(
                            '$confidence%',
                            style: _strong.copyWith(color: carShareGreen),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: matchingCriteria / 3,
                        minHeight: 6,
                        color: carShareGreen,
                        backgroundColor: carShareBorder,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          const _Criterion('Same trip'),
                          const _Criterion('Same item type'),
                          _Criterion(
                            sameColor ? 'Color matches' : 'Color unknown',
                            matches: sameColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              if (handover != null &&
                  (handover.meetingPoint != null || !returned)) ...[
                const SizedBox(height: 22),
                const Text('Handover', style: _strong),
                const SizedBox(height: 8),
                if (handover.meetingPoint != null)
                  _HandoverCard(
                    place: handover.meetingPoint!,
                    when: handover.meetingTime,
                    code: handover.isOwner ? handover.code : null,
                    onEdit: _saving || returned ? null : _arrange,
                  )
                else
                  _Notice(
                    text: 'Agree on a meeting place and time with $otherName.',
                  ),
                if (arranged && !returned) ...[
                  const SizedBox(height: 12),
                  if (handover.isOwner)
                    _Notice(
                      text:
                          'Give this code to $otherName when you get your item back. '
                          'The handover ends when they enter it.',
                    )
                  else
                    _codeEntry(otherName, handover),
                ],
              ],
              if (match != null && !returned)
                Center(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: carShareDanger,
                    ),
                    onPressed: _saving ? null : _reject,
                    child: const Text('Not my item'),
                  ),
                ),
              if (returned) ...[
                const SizedBox(height: 18),
                _Notice(
                  text: widget.preview
                      ? 'Demo item marked as returned.'
                      : 'The item has been returned. Report closed.',
                ),
              ] else if (match == null && handover == null) ...[
                const SizedBox(height: 18),
                const _Notice(
                  text: 'Waiting for a matching report on this trip.',
                ),
                if (_demoPreview) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _openMatchPreview(
                            context,
                            report: report,
                            photo: widget.photo,
                          ),
                    icon: const Icon(Icons.preview_outlined),
                    label: const Text('Preview match'),
                  ),
                ],
                Center(
                  child: TextButton(
                    onPressed: _saving ? null : _resolve,
                    child: Text(
                      _isLost
                          ? 'I recovered my item'
                          : 'I already returned the item',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: action == null
          ? null
          : _Footer(
              child: FilledButton(
                style: _filledStyle(),
                onPressed: _saving ? null : onAction,
                child: Text(_saving ? 'Saving…' : action),
              ),
            ),
    );
  }

  /// The finder's side of the check: the owner reads four digits out, the finder types them.
  Widget _codeEntry(String ownerName, _Handover handover) => Form(
    key: _codeForm,
    child: _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Enter the code', style: _strong),
          const SizedBox(height: 4),
          Text(
            'Ask $ownerName for the 4-digit code when you hand the item over.',
            style: _muted,
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _code,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            textInputAction: TextInputAction.done,
            decoration: _field('4-digit code', icon: Icons.pin_outlined)
                .copyWith(
                  counterText: '',
                  errorText: _codeError,
                  errorMaxLines: 2,
                ),
            validator: (value) =>
                RegExp(r'^\d{4}$').hasMatch(value?.trim() ?? '')
                ? null
                : 'Enter exactly 4 digits.',
            onChanged: (_) {
              if (_codeError != null) setState(() => _codeError = null);
            },
            onFieldSubmitted: (_) => _verify(),
          ),
        ],
      ),
    ),
  );

  Widget _comparison(_Report report, String label, {Uint8List? photo}) =>
      Container(
        decoration: BoxDecoration(
          color: carShareBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (photo != null)
              _Photo(photo, height: 84)
            else
              Container(
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  report.category?.icon ?? Icons.inventory_2_outlined,
                  color: carShareGreen,
                  size: 27,
                ),
              ),
            const SizedBox(height: 8),
            Text(label, style: _strong),
            Text(
              [
                if (label == 'Your report')
                  'You'
                else
                  report.reporterName ?? 'Other participant',
                if (report.created != null)
                  _dateTimeLabel(context, report.created!),
              ].join(' · '),
              style: _muted,
            ),
            const SizedBox(height: 6),
            Text(report.description),
            if (report.color.isNotEmpty)
              Text('Color: ${report.color}', style: _muted),
          ],
        ),
      );
}

class _Progress extends StatelessWidget {
  const _Progress({
    required this.matched,
    required this.handover,
    required this.returned,
  });

  final bool matched;
  final bool handover;
  final bool returned;

  @override
  Widget build(BuildContext context) {
    final active = [true, matched, handover, returned];
    const labels = ['Reported', 'Matched', 'Handover', 'Returned'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var step = 0; step < labels.length; step++) ...[
          Expanded(
            flex: 4,
            child: Column(
              children: [
                Icon(
                  step == 2 && handover && !returned
                      ? Icons.radio_button_checked
                      : active[step]
                      ? Icons.check_circle
                      : Icons.circle_outlined,
                  color: active[step] ? carShareGreen : carShareBorder,
                  size: 22,
                ),
                const SizedBox(height: 4),
                Text(
                  labels[step],
                  textAlign: TextAlign.center,
                  style: _muted.copyWith(
                    fontSize: 10,
                    color: active[step] ? carShareGreen : carShareMuted,
                  ),
                ),
              ],
            ),
          ),
          if (step < labels.length - 1)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  height: 2,
                  color: active[step] && active[step + 1]
                      ? carShareGreen
                      : carShareBorder,
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Criterion extends StatelessWidget {
  const _Criterion(this.label, {this.matches = true});
  final String label;
  final bool matches;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        matches ? Icons.check : Icons.remove,
        color: matches ? carShareGreen : carShareMuted,
        size: 15,
      ),
      const SizedBox(width: 3),
      Text(label, style: _muted),
    ],
  );
}

class _HandoverCard extends StatelessWidget {
  const _HandoverCard({required this.place, this.when, this.code, this.onEdit});

  final String place;
  final String? when;
  final String? code;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final meetingTime = when;
    final handoverCode = code;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detail(Icons.location_on_outlined, 'Meeting point', place),
          if (meetingTime != null) ...[
            const SizedBox(height: 10),
            _detail(Icons.schedule, 'Date & time', meetingTime),
          ],
          if (handoverCode != null) ...[
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                const Text('Give this code to the finder', style: _muted),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final digit in handoverCode.split(''))
                      Container(
                        alignment: Alignment.center,
                        width: 25,
                        height: 29,
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: carShareTint,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          digit,
                          style: _strong.copyWith(color: carShareGreen),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
          if (onEdit != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onEdit,
                child: const Text('Edit handover'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detail(IconData icon, String label, String value) => Row(
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: carShareTint,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: carShareGreen, size: 18),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _muted),
            Text(value, style: _strong),
          ],
        ),
      ),
    ],
  );
}

class _PageWidth extends StatelessWidget {
  const _PageWidth({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 600),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: Center(
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 568),
        child: SizedBox(width: double.infinity, child: child),
      ),
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: carShareBorder),
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0F172A),
          blurRadius: 9,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: child,
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.highlighted = false});
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    decoration: BoxDecoration(
      color: highlighted ? carShareTint : carShareBackground,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: carShareGreen, size: 19),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: highlighted ? _strong.copyWith(fontSize: 12) : _muted,
          ),
        ),
      ],
    ),
  );
}

class _ItemIcon extends StatelessWidget {
  const _ItemIcon(this.category, {this.photo});
  final _Category? category;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 44,
    child: photo == null
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: carShareTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              category?.icon ?? Icons.inventory_2_outlined,
              color: carShareGreen,
            ),
          )
        : _Photo(photo!, height: 44),
  );
}

class _Photo extends StatelessWidget {
  const _Photo(this.bytes, {required this.height});
  final Uint8List bytes;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: Image.memory(
      bytes,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      semanticLabel: 'Item photo',
      errorBuilder: (_, _, _) => SizedBox(
        height: height,
        child: const Icon(Icons.broken_image_outlined),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, {required this.color, required this.background});
  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(30),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

const _strong = TextStyle(
  color: carShareText,
  fontSize: 14,
  fontWeight: FontWeight.w700,
);
const _muted = TextStyle(color: carShareMuted, fontSize: 12);

InputDecoration _field(String hint, {IconData? icon}) => InputDecoration(
  hintText: hint,
  prefixIcon: icon == null ? null : Icon(icon),
  counterText: '',
  isDense: true,
  filled: true,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  enabledBorder: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: carShareBorder),
  ),
);

ButtonStyle _filledStyle({bool pill = false, double height = 48}) =>
    FilledButton.styleFrom(
      backgroundColor: carShareGreen,
      foregroundColor: Colors.white,
      minimumSize: Size(0, height),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(pill ? 30 : 14),
      ),
    );

AppBar _detailBar(String title) => AppBar(
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.transparent,
  title: Text(
    title,
    style: const TextStyle(color: carShareText, fontWeight: FontWeight.w800),
  ),
);

String _errorMessage(Object? error) => error is ApiException
    ? authErrorMessage(error)
    : 'Could not read the Lost & Found response. Try again.';

void _message(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

String _photoExtension(Uint8List bytes) => bytes.length > 3 && bytes[0] == 0x89
    ? 'png'
    : bytes.length > 3 && bytes[0] == 0x52
    ? 'webp'
    : 'jpg';

String _photoMimeType(Uint8List bytes) => switch (_photoExtension(bytes)) {
  'png' => 'image/png',
  'webp' => 'image/webp',
  _ => 'image/jpeg',
};
