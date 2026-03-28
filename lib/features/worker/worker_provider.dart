import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lightweight domain model for worker availability and status.
class Worker {
  const Worker({
    required this.id,
    required this.name,
    required this.isOnline,
    this.availabilityMask,
    this.community,
    this.metadata = const {},
  });

  final String id;
  final String name;
  final bool isOnline;

  /// Bitmask for high-speed schedule updates (one bit per slot/day).
  final int? availabilityMask;

  /// Optional cluster/community tag (e.g., Louvain output).
  final String? community;

  /// Raw map for additional fields already stored in Firestore.
  final Map<String, dynamic> metadata;

  Worker copyWith({
    bool? isOnline,
    int? availabilityMask,
    String? community,
    Map<String, dynamic>? metadata,
  }) {
    return Worker(
      id: id,
      name: name,
      isOnline: isOnline ?? this.isOnline,
      availabilityMask: availabilityMask ?? this.availabilityMask,
      community: community ?? this.community,
      metadata: metadata ?? this.metadata,
    );
  }

  static Worker fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Worker(
      id: doc.id,
      name: data['name']?.toString() ?? 'Worker',
      isOnline: data['isOnline'] as bool? ?? false,
      availabilityMask: (data['availabilityMask'] as num?)?.toInt(),
      community: data['community']?.toString(),
      metadata: data,
    );
  }
}

class WorkerNotifier extends StateNotifier<List<Worker>> {
  WorkerNotifier() : super(const []) {
    _subscribe();
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;

  void _subscribe() {
    _subscription = FirebaseFirestore.instance
        .collection('workers')
        .snapshots()
        .listen((snapshot) {
      state = snapshot.docs.map(Worker.fromSnapshot).toList(growable: false);
    });
  }

  /// Update a worker's online flag locally; Firestore write can follow elsewhere.
  void updateWorkerStatus(String id, bool isOnline) {
    state = [
      for (final worker in state)
        if (worker.id == id)
          worker.copyWith(isOnline: isOnline)
        else
          worker,
    ];
  }

  /// Bitwise availability update (atomic mask edits beat iterative writes).
  void setAvailabilityBit(String id, int slotIndex, {required bool available}) {
    state = [
      for (final worker in state)
        if (worker.id == id)
          worker.copyWith(
            availabilityMask: _applyBit(worker.availabilityMask ?? 0, slotIndex, available),
          )
        else
          worker,
    ];
  }

  void updateCommunityTag(String id, String? community) {
    state = [
      for (final worker in state)
        if (worker.id == id)
          worker.copyWith(community: community)
        else
          worker,
    ];
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  int _applyBit(int mask, int bitIndex, bool value) {
    if (value) return mask | (1 << bitIndex);
    return mask & ~(1 << bitIndex);
  }
}

final workerListProvider =
    StateNotifierProvider<WorkerNotifier, List<Worker>>((ref) => WorkerNotifier());

/// Convenience provider for online workers only.
final onlineWorkersProvider = Provider<List<Worker>>(
  (ref) => ref.watch(workerListProvider).where((w) => w.isOnline).toList(growable: false),
);
