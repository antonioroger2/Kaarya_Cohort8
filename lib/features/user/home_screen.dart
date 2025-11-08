// lib/features/user/home_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/theme.dart';
import '../../features/shared/inbox_screen.dart';
import '../../features/user/worker_card.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  const HomeScreen({super.key, required this.userId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = '';
  String _userPin = '';

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Plumber', 'icon': Icons.plumbing},
    {'name': 'Electrician', 'icon': Icons.electrical_services},
    {'name': 'Carpenter', 'icon': Icons.handyman},
    {'name': 'Maid', 'icon': Icons.cleaning_services},
    {'name': 'Cook', 'icon': Icons.restaurant},
    {'name': 'Mechanic', 'icon': Icons.build},
    {'name': 'Movers', 'icon': Icons.local_shipping},
    {'name': 'Babysitter', 'icon': Icons.child_care},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _getUserPin();
  }
  
  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {});
  }

  Future<void> _getUserPin() async {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    if (userDoc.exists) {
      setState(() {
        _userPin = userDoc.data()?['pin'] ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Find Local Workers'),
            if (_userPin.isNotEmpty)
              Text(
                'Location: $_userPin',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('recipientId', isEqualTo: widget.userId)
                .where('isRead', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data?.docs.length ?? 0;
              return IconButton(
                icon: Badge(
                  label: unreadCount > 0 ? Text(unreadCount.toString()) : null,
                  child: const Icon(Icons.inbox),
                ),
                tooltip: 'Inbox',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => InboxScreen(userId: widget.userId, isWorker: false),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: DoodleBackground(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search workers by name or skill...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),

                  // Category Selector (Icons)
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final isSelected = _selectedCategory == category['name'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: InkWell(
                            onTap: () => setState(() {
                              _selectedCategory = isSelected ? '' : category['name'];
                            }),
                            child: Container(
                              width: 80,
                              decoration: BoxDecoration(
                                color: isSelected ? Colors.teal : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isSelected ? Colors.teal : Colors.grey[300]!,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    category['icon'],
                                    color: isSelected ? Colors.white : Colors.grey[600],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    category['name'],
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            
            // Filter Chips - Added as requested, though redundant with the above, showing original structure.
            SizedBox(
              height: 50,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  'Plumber', 'Electrician', 'Carpenter', 'Maid', 'Movers', 'Mechanic', 'Cook', 'Babysitter'
                ].map((cat) => Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(cat),
                          selected: _selectedCategory == cat,
                          onSelected: (sel) => setState(() => _selectedCategory = sel ? cat : ''),
                        ),
                      ))
                      .toList(),
              ),
            ),
            
            // Filter status message
            if (_selectedCategory.isNotEmpty && _userPin.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Text(
                  'Showing top workers for "$_selectedCategory" near your pincode: $_userPin',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            const SizedBox(height: 12),

            // Worker List
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('workers').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('No workers available right now.'));
                  }

                  List<DocumentSnapshot> workers = snapshot.data!.docs;

                  // Filtering logic
                  workers = workers.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['availability'] != 'Y') return false; // Filter by availability

                    final name = (data['name'] ?? '').toString().toLowerCase();
                    final searchText = _searchController.text.toLowerCase();
                    
                    // Search Filter
                    if (searchText.isNotEmpty) {
                      final categories = (data['workCategories'] as List?)?.map((e) => (e['mainCategory'] as String?)?.toLowerCase()).toList() ?? [];
                      final matchesName = name.contains(searchText);
                      final matchesSkill = categories.any((category) => category?.contains(searchText) ?? false);
                      if (!matchesName && !matchesSkill) return false;
                    }

                    // Category Filter
                    if (_selectedCategory.isNotEmpty) {
                      final categories = (data['workCategories'] as List?)?.map((e) => e['mainCategory'] as String).toList() ?? [];
                      if (!categories.contains(_selectedCategory)) return false;
                    }

                    return true;
                  }).toList();

                  // Sorting logic: Pincode match first, then by rating
                  if (_userPin.isNotEmpty) {
                    workers.sort((a, b) {
                      final dataA = a.data() as Map<String, dynamic>;
                      final dataB = b.data() as Map<String, dynamic>;
                      final pinA = dataA['pin'] ?? '';
                      final pinB = dataB['pin'] ?? '';
                      final ratingA = dataA['avgRating'] ?? 0.0;
                      final ratingB = dataB['avgRating'] ?? 0.0;

                      // Prioritize local workers
                      if (pinA == _userPin && pinB != _userPin) return -1;
                      if (pinA != _userPin && pinB == _userPin) return 1;

                      // Secondary sort by rating (descending)
                      return ratingB.compareTo(ratingA);
                    });
                  }

                  if (workers.isEmpty) {
                    return const Center(child: Text('No workers found matching your criteria.'));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: 16),
                    itemCount: workers.length,
                    itemBuilder: (context, idx) {
                      final doc = workers[idx];
                      final data = doc.data() as Map<String, dynamic>;
                      return WorkerCard(worker: data, workerId: doc.id, userId: widget.userId);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
