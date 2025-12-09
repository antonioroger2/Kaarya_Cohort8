
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart'; 
import 'worker_card.dart';
import '../shared/profile_screen.dart';
import '../auth/auth_screen.dart';
import 'bookings_screen.dart';
import 'booking_creation_screen.dart';
import 'general_booking_screen.dart';


class HeroData {
  final String title;
  final String subtitle;
  final String description;
  final String imageUrl;
  final Color primaryColor;
  final Color secondaryColor;
  final VoidCallback? onActionPressed;
  final String? actionLabel;

  const HeroData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.imageUrl,
    this.primaryColor = const Color(0xFF232F3E),
    this.secondaryColor = const Color(0xFFFF9900),
    this.onActionPressed,
    this.actionLabel,
  });
}



class P2_StyleHeroCard extends StatefulWidget {
  final HeroData heroData;
  final double height;
  
  const P2_StyleHeroCard({
    super.key,
    required this.heroData,
this.height = 260.0,
  });

  @override
  State<P2_StyleHeroCard> createState() => _P2_StyleHeroCardState();
}

class _P2_StyleHeroCardState extends State<P2_StyleHeroCard> 
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        height: widget.height,
        width: double.infinity,
        margin: const EdgeInsets.symmetric(horizontal: 0),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackgroundImage(),
            _buildGradientOverlay(),
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(0),
      child: Image.network(
        widget.heroData.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  widget.heroData.primaryColor,
                  widget.heroData.primaryColor.withOpacity(0.7),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: widget.heroData.primaryColor.withOpacity(0.3),
            child: Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(0),
        gradient: LinearGradient(
          colors: [
            widget.heroData.primaryColor.withOpacity(0.85),
            widget.heroData.primaryColor.withOpacity(0.65),
            widget.heroData.primaryColor.withOpacity(0.45),
            Colors.transparent,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          stops: const [0.0, 0.3, 0.6, 1.0],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.heroData.secondaryColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: widget.heroData.secondaryColor.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              widget.heroData.subtitle,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          Text(
            widget.heroData.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
              height: 1.1,
              shadows: [
                Shadow(
                  blurRadius: 10,
                  color: Colors.black45,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.6,
            child: Text(
              widget.heroData.description,
              style: TextStyle(
                color: Colors.white.withOpacity(0.95),
                fontSize: 16,
                fontWeight: FontWeight.w400,
                height: 1.4,
                shadows: const [
                  Shadow(
                    blurRadius: 8,
                    color: Colors.black38,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 20),
          
          if (widget.heroData.onActionPressed != null)
            ElevatedButton.icon(
              onPressed: widget.heroData.onActionPressed,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: Text(
                widget.heroData.actionLabel ?? 'Explore Now',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: widget.heroData.secondaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                elevation: 4,
                shadowColor: widget.heroData.secondaryColor.withOpacity(0.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
        ],
      ),
    );
  }
}



class CarouselHeroSection extends StatefulWidget {
  final List<HeroData> heroItems;
  final double height;
  final Duration autoPlayDuration;
  
  const CarouselHeroSection({
    super.key,
    required this.heroItems,
    this.height = 280,
    this.autoPlayDuration = const Duration(seconds: 5),
  });

  @override
  State<CarouselHeroSection> createState() => _CarouselHeroSectionState();
}

class _CarouselHeroSectionState extends State<CarouselHeroSection> {
  late PageController _pageController;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _startAutoPlay();
  }

  void _startAutoPlay() {
    if (widget.heroItems.isEmpty) return;

    Future.delayed(widget.autoPlayDuration, () {
      if (mounted) {
        final nextPage = (_currentPage + 1) % widget.heroItems.length;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        ).then((_) {
          _startAutoPlay();
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.heroItems.isEmpty) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemCount: widget.heroItems.length,
            itemBuilder: (context, index) {
              return P2_StyleHeroCard(
                heroData: widget.heroItems[index],
                height: widget.height,
              );
            },
          ),
        ),
        
        if (widget.heroItems.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.heroItems.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}



class BookingSliderCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const BookingSliderCard({super.key, required this.booking});

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] ?? 'Pending';
    final service = booking['service'] ?? 'Service Appointment';
    final worker = booking['workerName'] ?? 'Professional';
    
    
    String dateDisplay = 'Date/Time Unknown';
    if (booking.containsKey('dateTime') && booking['dateTime'] is Timestamp) {
      final dateTime = (booking['dateTime'] as Timestamp).toDate();
      dateDisplay = DateFormat('EEE, MMM d, h:mm a').format(dateTime);
    }
    
    final statusColor = status == 'Confirmed' ? Colors.lightGreen.shade400 : Colors.amber.shade400;

    return Container(
      width: 280, 
      margin: const EdgeInsets.only(right: 16.0),
      padding: const EdgeInsets.all(18.0),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  service,
                  style: TextStyle(
                      color: const Color(0xFF00695C), fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                      color: statusColor.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                      fontSize: 11),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 10),

          
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline, size: 14, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      worker,
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: Colors.grey.shade700),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      dateDisplay,
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => BookingsScreen(userId: booking['userId']))); 
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.teal,
                side: BorderSide(color: Colors.teal.shade200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('View Details',
                  style: TextStyle(color: Colors.teal, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}



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
  String _userName = 'Guest';
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
          _userName = data?['name'] ?? 'User';
          
          _locationName = (data?['locality'] as String?)?.isNotEmpty == true
              ? data!['locality']
              : 'Your Location';
          _profilePicUrl = data?['profilePicUrl'];
        });
      }
    } catch (e) {
      debugPrint('Error loading user data: $e');
    }

    
    await _detectLocation(); 
  }

  Future<void> _detectLocation() async {
    setState(() {
      _isLocationLoading = true;
      _locationName = 'Locating...';
      _userPin = ''; 
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
          _locationName = 'GPS Off';
          _userPin = '';
        });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            setState(() {
            _locationName = 'Permission Denied';
            _userPin = '';
          });
          }
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=json&lat=${position.latitude}&lon=${position.longitude}&addressdetails=1',
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

  void _startGeneralRequest(BuildContext context) {
    if (_isGuest) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
    } else {
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
          hintText: 'Filter workers by skill or name...',
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

  Widget _buildPopularCategoriesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 12.0),
          child: Text(
            'Popular Categories',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        SizedBox(
          height: 95,
          child: ListView.separated(
            shrinkWrap: true,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _buildCategoryItem(_categories[index]),
          ),
        ),
      ],
    );
  }

  
  Widget _buildYourBookingsSection() {
    if (_isGuest) {
      return const SizedBox.shrink(); 
    }
    
    
    return StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('userId', isEqualTo: widget.userId)
            .where('status', whereIn: ['Confirmed', 'Pending'])
            .orderBy('dateTime', descending: false)
            .limit(5)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            
            return Container(
              height: 150, 
              color: const Color(0xFFE8F6F6), 
              margin: const EdgeInsets.only(top: 24.0),
              child: const Center(child: CircularProgressIndicator.adaptive())
            );
          }
          
          final bookings = snapshot.hasData ? snapshot.data!.docs : [];
          
          if (bookings.isEmpty) {
            return const SizedBox.shrink(); 
          }

          
          return Container(
            color: const Color(0xFFE8F6F6), 
            padding: const EdgeInsets.only(top: 24.0, bottom: 24.0),
            margin: const EdgeInsets.only(top: 24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 0.0, 16.0, 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Your Upcoming Bookings',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingsScreen(userId: widget.userId)));
                        },
                        child: const Text('View All', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.w600)),
                      )
                    ],
                  ),
                ),
                
                SizedBox(
                  height: 180, 
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: bookings.length,
                    itemBuilder: (context, index) {
                      final bookingData = bookings[index].data() as Map<String, dynamic>;
                      return BookingSliderCard(booking: bookingData);
                    },
                  ),
                ),
              ],
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 800;
    final double headerHeight = isMobile ? 120 : 70;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _startGeneralRequest(context),
        label: const Text("SMART AI BOOKING"),
        icon: const Icon(Icons.handyman),
        backgroundColor: Colors.teal,
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
              child: CarouselHeroSection(
                heroItems: [
                  HeroData(
                    title: 'Welcome back,\n${_userName.split(' ').first}',
                    subtitle: 'Kaarya Seva',
                    description: 'Your next service is just a tap away. Book trusted professionals now.',
                    imageUrl: 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=1200&q=80',
                    primaryColor: Colors.deepPurple.shade700,
                    secondaryColor: Colors.teal,
                    onActionPressed: () => _startGeneralRequest(context),
                    actionLabel: 'Find Workers',
                  ),
                  HeroData(
                    title: 'Expert Electricians',
                    subtitle: 'Special Offer',
                    description: 'Get professional electrical services for your home today',
                    imageUrl: 'https://images.unsplash.com/photo-1621905251918-48416bd8575a?w=1200&q=80',
                    primaryColor: const Color(0xFF1E3A8A),
                    secondaryColor: const Color(0xFFFBBF24),
                  ),
                  HeroData(
                    title: 'Home Cleaning',
                    subtitle: 'Most Popular',
                    description: 'Sparkling clean homes, every time with our verified cleaners',
                    imageUrl: 'https://images.unsplash.com/photo-1585421514738-01798e348b17?w=1200&q=80',
                    primaryColor: const Color(0xFF059669),
                    secondaryColor: const Color(0xFF10B981),
                  ),
                  HeroData(
                    title: 'Skilled Carpenters',
                    subtitle: 'Premium Service',
                    description: 'Quality woodwork and furniture repairs by experienced professionals',
                    imageUrl: 'https://images.unsplash.com/photo-1504148455328-c376907d081c?w=1200&q=80',
                    primaryColor: const Color(0xFF92400E),
                    secondaryColor: const Color(0xFFF59E0B),
                  ),
                ],
              ),
            ),
            
            
            SliverToBoxAdapter(
              child: _buildPopularCategoriesSection(),
            ),
            
            SliverToBoxAdapter(
              child: _buildYourBookingsSection(),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 24.0, 16.0, 12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Nearby Workers",
                      style: TextStyle(
                        fontSize: 20,
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
                          border: Border.all(color: Colors.teal.shade200, width: 0.5),
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
                      child: Center(child: CircularProgressIndicator.adaptive()),
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

                  final pinA = _normalize(dataA['pincode']);
                  final pinB = _normalize(dataB['pincode']);
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
                        childAspectRatio: 5.5, 
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => WorkerCard(
                          worker: workers[index].data() as Map<String, dynamic>,
                          workerId: workers[index].id,
                          userId: widget.userId,
                          userPin: _userPin, 
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
                        userPin: _userPin, 
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
        width: 70, 
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2), 
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16), 
          border: Border.all(
            color: isSelected ? Colors.teal.shade400 : Colors.grey.shade200,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected ? Colors.teal.withOpacity(0.1) : Colors.black.withOpacity(0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 40, 
              height: 40,
              decoration: BoxDecoration(
                color: isSelected ? Colors.teal : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isSelected ? Colors.teal.shade700 : Colors.transparent,
                ),
              ),
              child: Icon(
                category['icon'],
                size: 22, 
                color: isSelected ? Colors.white : Colors.teal, 
              ),
            ),
            const SizedBox(height: 6),
            Text(
              category['name'],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10, 
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