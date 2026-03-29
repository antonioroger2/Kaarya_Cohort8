import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';
import '../../features/shared/booking_tile.dart';

// ─────────────────────────────────────────────
//  Design tokens
// ─────────────────────────────────────────────
class _BS {
  static const Color primary = Color(0xFF00897B);
  static const Color surface = Color(0xFFF7FAFA);

  static const List<Tab> tabs = [
    Tab(text: 'Upcoming'),
    Tab(text: 'Pending'),
    Tab(text: 'History'),
  ];
}

// ─────────────────────────────────────────────
//  BookingsScreen
// ─────────────────────────────────────────────
class BookingsScreen extends StatefulWidget {
  final String userId;
  const BookingsScreen({super.key, required this.userId});

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isFurthestFirst = true;

  // Debounce timer — prevents rapid sort toggles from firing
  // multiple subscribe/unsubscribe cycles on the Firestore Web SDK.
  Timer? _sortDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _sortDebounce?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _applySort(bool descending) {
    _sortDebounce?.cancel();
    _sortDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _isFurthestFirst = descending);
    });
  }

  void _showFilterBottomSheet() {
    bool sheetValue = _isFurthestFirst;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Sort Order',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Color(0xFF263238))),
              const SizedBox(height: 14),
              Row(children: [
                _SortChip(
                  label: 'Ascending',
                  icon: Icons.arrow_upward_rounded,
                  selected: !sheetValue,
                  onTap: () => setModalState(() => sheetValue = false),
                ),
                const SizedBox(width: 10),
                _SortChip(
                  label: 'Descending',
                  icon: Icons.arrow_downward_rounded,
                  selected: sheetValue,
                  onTap: () => setModalState(() => sheetValue = true),
                ),
              ]),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    // Only trigger rebuild if value actually changed.
                    if (sheetValue != _isFurthestFirst) {
                      _applySort(sheetValue);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _BS.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Apply',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _BS.surface,
      appBar: _buildAppBar(),
      body: DoodleBackground(
        child: Column(
          children: [
            _FilterBar(
              isFurthestFirst: _isFurthestFirst,
              onTapSort: _showFilterBottomSheet,
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _BookingsList(
                    key: const ValueKey('upcoming'),
                    userId: widget.userId,
                    statuses: const ['a1', 'w1', 'w2'],
                    isFurthestFirst: _isFurthestFirst,
                  ),
                  _BookingsList(
                    key: const ValueKey('pending'),
                    userId: widget.userId,
                    statuses: const ['b1', 'b2'],
                    isFurthestFirst: _isFurthestFirst,
                  ),
                  _BookingsList(
                    key: const ValueKey('history'),
                    userId: widget.userId,
                    statuses: const [
                      'e3', 'cancelled', 'rejected', 'Cancelled', 'Rejected'
                    ],
                    isFurthestFirst: _isFurthestFirst,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black12,
      title: const Text(
        'My Bookings',
        style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF00897B),
            fontSize: 18,
            letterSpacing: -0.3),
      ),
      bottom: TabBar(
        controller: _tabController,
        tabs: _BS.tabs,
        labelColor: _BS.primary,
        unselectedLabelColor: Colors.grey,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        indicatorColor: _BS.primary,
        indicatorWeight: 2.5,
        dividerColor: Colors.grey.shade200,
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  _BookingsList — StatefulWidget with cached stream
//
//  ROOT CAUSE FIX: When this was a StatelessWidget, every setState()
//  on the parent caused Flutter to call didUpdateWidget on the inner
//  StreamBuilder, which cancelled and immediately re-subscribed the
//  Firestore stream. The Web SDK's onSnapshotUnsubscribe handle was
//  not yet initialised at cancellation time, triggering:
//    "LateInitializationError: Local 'onSnapshotUnsubscribe'"
//  and cascading INTERNAL ASSERTION FAILED (ID: b815 / ca9) errors.
//
//  Solution: own the Stream object in a StatefulWidget and only
//  recreate it when the query parameters genuinely change.
// ─────────────────────────────────────────────
class _BookingsList extends StatefulWidget {
  final String userId;
  final List<String> statuses;
  final bool isFurthestFirst;

  const _BookingsList({
    super.key,
    required this.userId,
    required this.statuses,
    required this.isFurthestFirst,
  });

  @override
  State<_BookingsList> createState() => _BookingsListState();
}

class _BookingsListState extends State<_BookingsList> {
  late Stream<QuerySnapshot> _stream;
  DocumentSnapshot? _lastDoc;
  bool _isLoadingMore = false;
  final List<DocumentSnapshot> _docs = [];
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _stream = _buildStream(limit: 10);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_BookingsList old) {
    super.didUpdateWidget(old);
    if (old.userId != widget.userId ||
        old.isFurthestFirst != widget.isFurthestFirst ||
        !_listEquals(old.statuses, widget.statuses)) {
      _resetAndFetch();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels ==
            _scrollController.position.maxScrollExtent &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  void _resetAndFetch() {
    setState(() {
      _docs.clear();
      _lastDoc = null;
      _stream = _buildStream(limit: 10);
    });
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _lastDoc == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final snap = await _buildQuery(limit: 10).startAfterDocument(_lastDoc!).get();
      if (snap.docs.isNotEmpty) {
        _lastDoc = snap.docs.last;
        setState(() => _docs.addAll(snap.docs));
      } else {
        // No more documents
        _lastDoc = null;
      }
    } catch (e) {
      debugPrint("Error loading more bookings: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Query _buildQuery({required int limit}) {
    Query query = FirebaseFirestore.instance
        .collection('bookings')
        .where('userId', isEqualTo: widget.userId)
        .where('status', whereIn: widget.statuses)
        .orderBy('appointmentDate', descending: widget.isFurthestFirst);

    return query.limit(limit);
  }

  Stream<QuerySnapshot> _buildStream({required int limit}) {
    return _buildQuery(limit: limit).snapshots();
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return _ErrorState(error: snap.error.toString());
        }
        if (snap.connectionState == ConnectionState.waiting && _docs.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(
                color: Color(0xFF00897B), strokeWidth: 2.5),
          );
        }

        if (snap.hasData && snap.data!.docs.isNotEmpty && _docs.isEmpty) {
          _docs.addAll(snap.data!.docs);
          _lastDoc = snap.data!.docs.last;
        }

        if (_docs.isEmpty) {
          return _EmptyState(statuses: widget.statuses);
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: _docs.length + (_isLoadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == _docs.length) {
              return const Center(
                  child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(
                    color: Color(0xFF00897B), strokeWidth: 2),
              ));
            }
            final doc = _docs[index];
            return BookingTile(
              bookingData: doc.data() as Map<String, dynamic>,
              bookingId: doc.id,
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
//  Remaining sub-widgets (UI only, unchanged)
// ─────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final bool isFurthestFirst;
  final VoidCallback onTapSort;
  const _FilterBar({required this.isFurthestFirst, required this.onTapSort});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border:
            Border(bottom: BorderSide(color: Colors.grey.shade100, width: 1)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(children: [
        Icon(Icons.swap_vert_rounded, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Text(
          isFurthestFirst ? 'Newest first' : 'Oldest first',
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF546E7A)),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onTapSort,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withOpacity(0.07),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF00897B).withOpacity(0.2)),
            ),
            child: const Row(children: [
              Icon(Icons.tune_rounded, size: 14, color: Color(0xFF00897B)),
              SizedBox(width: 5),
              Text('Sort',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00897B))),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final List<String> statuses;
  const _EmptyState({required this.statuses});

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final String headline;
    final String sub;

    if (statuses.contains('a1')) {
      icon = Icons.event_available_rounded;
      headline = 'No upcoming bookings';
      sub = 'Your scheduled jobs will appear here.';
    } else if (statuses.contains('b2')) {
      icon = Icons.hourglass_empty_rounded;
      headline = 'No pending requests';
      sub = 'Booking requests awaiting confirmation show here.';
    } else {
      icon = Icons.history_rounded;
      headline = 'No booking history';
      sub = 'Completed, cancelled, and declined bookings appear here.';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xFF00897B).withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(icon,
                size: 44,
                color: const Color(0xFF00897B).withOpacity(0.5)),
          ),
          const SizedBox(height: 20),
          Text(headline,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF37474F))),
          const SizedBox(height: 8),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey[500], height: 1.5)),
        ]),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFEF5350).withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.warning_amber_rounded,
                size: 40, color: Color(0xFFEF5350)),
          ),
          const SizedBox(height: 16),
          const Text('Database Error',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF37474F))),
          const SizedBox(height: 8),
          Text('Check the debug console for an index link.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[500])),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                    fontFamily: 'monospace')),
          ),
        ]),
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _SortChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF00897B).withOpacity(0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? const Color(0xFF00897B)
                : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              size: 16,
              color:
                  selected ? const Color(0xFF00897B) : Colors.grey[600]),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? const Color(0xFF00897B)
                    : Colors.grey[700],
              )),
        ]),
      ),
    );
  }
}