// lib/features/user/home_screen.dart
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'worker_card.dart';
import '../shared/profile_screen.dart';
import '../auth/auth_screen.dart';
import 'bookings_screen.dart';
import 'booking_creation_screen.dart'; 
import 'general_booking_screen.dart'; // NEW IMPORT

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
  String _locationName = 'Detecting...';
  bool _isLocationLoading = false;
  String? _profilePicUrl;
  bool _isRefreshing = false;

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

  bool get _isGuest => widget.userId.isEmpty;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    if (!_isGuest) {
      _loadRegisteredUserData();
      
      // --- CHECK FOR PENDING BOOKING (LAZY LOGIN REDIRECT) ---
      if (BookingCreationScreen.pendingBookingData != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final data = BookingCreationScreen.pendingBookingData!;
          
          final Map<String, dynamic> workerMap = {
            'uid': data['workerId'],
            'name': data['workerName'],
            'phone': data['workerPhone'],
            'cw_data': data['cw_data'], 
            'perHourCharge': data['hourlyRate'], 
          };

          if (workerMap['uid'] != null && workerMap['cw_data'] != null) {
             Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => BookingCreationScreen(
                    userId: widget.userId, 
                    preSelectedWorker: workerMap, 
                  ),
                ),
              );
          }
          
          BookingCreationScreen.pendingBookingData = null; 
        });
      }
    } else {
      _detectLocation();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRegisteredUserData() async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
      if (userDoc.exists && mounted) {
        final data = userDoc.data();
        setState(() {
          _userPin = (data?['pin'] ?? '').toString().trim();
          _locationName = (data?['locality'] as String?)?.isNotEmpty == true
              ? data!['locality']
              : 'Your Location';
          _profilePicUrl = data?['profilePicUrl'];
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }
  }

  Future<void> _detectLocation() async {
    setState(() {
      _isLocationLoading = true;
      _locationName = 'Locating...';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _locationName = 'GPS Off');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _locationName = 'Permission Denied');
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1',
      );

      final response = await http.get(url, headers: {'User-Agent': 'KaaryaConnectApp'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'];

        if (mounted) {
          setState(() {
            _locationName = address['suburb'] ??
                address['neighbourhood'] ??
                address['residential'] ??
                address['village'] ??
                address['town'] ??
                address['city'] ??
                'Unknown Location';

            _userPin = (address['postcode'] ?? '').toString().trim();
          });
        }
      } else {
        if (mounted) setState(() => _locationName = 'Location Error');
      }
    } catch (e) {
      if (mounted) setState(() => _locationName = 'GPS Error');
      debugPrint('Location detect error: $e');
    } finally {
      if (mounted) setState(() => _isLocationLoading = false);
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _isRefreshing = true);
    await Future.wait([
      if (!_isGuest) _loadRegisteredUserData(),
      if (_isGuest) _detectLocation(),
    ]);
    if (mounted) setState(() => _isRefreshing = false);
  }

  // --- NEW: General Request Button Handler ---
  void _startGeneralRequest(BuildContext context) {
    if (_isGuest) {
      // For guest users, enforce login first
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
    } else {
      // For logged-in users, launch the general request screen
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GeneralBookingScreen(userId: widget.userId),
        ),
      );
    }
  }

  String _normalize(dynamic input) {
    if (input == null) return '';
    return input.toString().trim().replaceAll(RegExp(r'\s+'), '');
  }

  Widget _buildSearchField({bool isCompact = false}) {
    return SizedBox(
      height: 42,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 22),
          hintText: isCompact ? 'Filter workers by skill...' : 'Filter workers by skill...',
          hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.teal),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, double width) {
    final bool isMobile = width < 800;

    final leftSection = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.teal.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.handyman_rounded, color: Colors.teal, size: 22),
        ),
        const SizedBox(width: 10),
        const Text(
          'Kaarya Seva',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(width: 12),
        Container(height: 24, width: 1, color: Colors.grey[300]),
        const SizedBox(width: 12),
        InkWell(
          onTap: _detectLocation,
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, color: Colors.teal[700], size: 18),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isMobile ? 100 : 200),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLocationLoading ? 'Locating...' : _locationName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    if (_userPin.isNotEmpty && !isMobile)
                      Text(
                        'PIN: $_userPin',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final rightSection = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isMobile) ...[
          SizedBox(
            width: 280,
            child: _buildSearchField(isCompact: true),
          ),
          const SizedBox(width: 16),
        ],
        IconButton(
          icon: const Icon(Icons.calendar_month_outlined, color: Colors.black87),
          onPressed: () {
            if (_isGuest) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
            } else {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingsScreen(userId: widget.userId)));
            }
          },
          tooltip: 'Bookings',
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () {
            if (_isGuest) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
            } else {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: widget.userId, isWorker: false)));
            }
          },
          child: CircleAvatar(
            radius: 18,
            backgroundColor: Colors.teal.shade50,
            backgroundImage: (_profilePicUrl != null) ? NetworkImage(_profilePicUrl!) : null,
            child: (_profilePicUrl == null)
                ? Icon(_isGuest ? Icons.login : Icons.person, color: Colors.teal, size: 20)
                : null,
          ),
        ),
      ],
    );

    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: leftSection),
                rightSection,
              ],
            ),
            const SizedBox(height: 12),
            _buildSearchField(isCompact: false),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
      child: Row(
        children: [
          leftSection,
          const Spacer(),
          rightSection,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;
    final double headerHeight = isMobile ? 120 : 70;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      // NEW: Floating Action Button for General Request
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startGeneralRequest(context),
        label: const Text("Post a Job"),
        icon: const Icon(Icons.handyman),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: CustomScrollView(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeaderDelegate(
                minExtent: headerHeight,
                maxExtent: headerHeight,
                builder: (context, shrinkOffset, overlapsContent) => Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Center(
                      child: _buildHeader(context, width),
                    ),
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    height: 110,
                    child: ListView.separated(
                      shrinkWrap: true,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _categories.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) => _buildCategoryItem(_categories[index]),
                    ),
                  ),
                ),
              ),
            ),
            
            // NEW: Prompt for General Request above the list
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Card(
                  color: Colors.blue.shade50,
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.lightbulb_outline, color: Colors.blue),
                    title: const Text("Need quick help from the best available professional?"),
                    subtitle: const Text("Tap 'Post a Job' below to describe your issue and send your request to the top 5 matches instantly!"),
                    trailing: ElevatedButton(
                      onPressed: () => _startGeneralRequest(context),
                      child: const Text("Post Job"),
                    ),
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Professionals Nearby",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (_userPin.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "$_userPin Area",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.teal[800],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('workers')
                  .snapshots(),
              builder: (context, snapshot) {

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40.0),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40.0),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 10),
                            const Text(
                              'No workers found in database.',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                List<DocumentSnapshot> workers = snapshot.data!.docs;

                workers = workers.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  final availability = data['availability'] ?? 'Y'; 
                  if (availability != 'Y') return false;

                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final searchText = _searchController.text.trim().toLowerCase();

                  // NEW FILTER LOGIC: Checks both old and new multi-skill data structure
                  final cwData = data['cw_data'] as Map<String, dynamic>? ?? {};
                  final categoriesList = cwData.keys.map((c) => c.toLowerCase()).toList();

                  if (searchText.isNotEmpty) {
                    final matchesName = name.contains(searchText);
                    final matchesSkill = categoriesList.any((c) => c.contains(searchText));

                    if (!matchesName && !matchesSkill) return false;
                  }

                  if (_selectedCategory.isNotEmpty) {
                    final selected = _selectedCategory.toLowerCase();
                    if (!categoriesList.contains(selected)) return false;
                  }

                  return true;
                }).toList();

                workers.sort((a, b) {
                  final dataA = a.data() as Map<String, dynamic>;
                  final dataB = b.data() as Map<String, dynamic>;

                  final pinA = _normalize(dataA['pin']);
                  final pinB = _normalize(dataB['pin']);
                  final userPin = _normalize(_userPin);

                  final isLocalA = (pinA == userPin && userPin.isNotEmpty);
                  final isLocalB = (pinB == userPin && userPin.isNotEmpty);

                  if (isLocalA && !isLocalB) return -1; 
                  if (!isLocalA && isLocalB) return 1;

                  final ratingA = (dataA['avgRating'] ?? 0.0).toDouble();
                  final ratingB = (dataB['avgRating'] ?? 0.0).toDouble();
                  return ratingB.compareTo(ratingA);
                });

                if (workers.isEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('No matching professionals found.'),
                      ),
                    ),
                  );
                }

                if (width >= 900) {
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 3.8,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => WorkerCard(
                          worker: workers[index].data() as Map<String, dynamic>,
                          workerId: workers[index].id,
                          userId: widget.userId,
                        ),
                        childCount: workers.length,
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: WorkerCard(
                        worker: workers[index].data() as Map<String, dynamic>,
                        workerId: workers[index].id,
                        userId: widget.userId,
                      ),
                    ),
                    childCount: workers.length,
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryItem(Map<String, dynamic> category) {
    final isSelected = _selectedCategory == category['name'];
    return GestureDetector(
      onTap: () => setState(() {
        _selectedCategory = isSelected ? '' : category['name'];
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.teal : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected ? Colors.teal : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.teal : Colors.grey.shade100,
                ),
              ),
              child: Icon(
                category['icon'],
                size: 26,
                color: isSelected ? Colors.white : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              category['name'],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? Colors.teal.shade800 : Colors.grey.shade700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  @override
  final double minExtent;
  @override
  final double maxExtent;
  final Widget Function(BuildContext, double, bool) builder;

  _HeaderDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.builder,
  });

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return builder(context, shrinkOffset, overlapsContent);
  }

  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) {
    return oldDelegate.minExtent != minExtent || oldDelegate.maxExtent != maxExtent;
  }
}