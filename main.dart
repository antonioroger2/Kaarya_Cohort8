import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "",
      authDomain: "",
      projectId: "",
      storageBucket: "",
      messagingSenderId: "",
      appId: ""
    ),
  );

  runApp(const KaaryaConnectApp());
}

class KaaryaConnectApp extends StatelessWidget {
  const KaaryaConnectApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kaarya Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[50],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
          elevation: 1,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('workers').doc(snapshot.data!.uid).get(),
            builder: (context, workerSnapshot) {
              if (workerSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (workerSnapshot.hasData && workerSnapshot.data!.exists) {
                return WorkerDashboard(workerId: snapshot.data!.uid);
              }
              return UserDashboard(userId: snapshot.data!.uid);
            },
          );
        }
        return const AuthScreen();
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoginMode = true;
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _pinController = TextEditingController();
  bool _isWorker = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  Future<void> _submitAuthForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isLoading = true);

    try {
      if (_isLoginMode) {
        await _login();
      } else {
        await _signUp();
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'An authentication error occurred.');
    } catch (e) {
      _showError('An unexpected error occurred: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signUp() async {
    final email = '${_phoneController.text.trim()}@kaaryaconnect.app';
    final userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: _passwordController.text,
    );
    final uid = userCredential.user!.uid;

    if (_isWorker) {
      await FirebaseFirestore.instance.collection('workers').doc(uid).set({
        'id': uid,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'pin': _pinController.text.trim(),
        'altPhone': '',
        'availability': 'Y',
        'totalBookings': 0,
        'completedBookings': 0,
        'fourPlusRatings': 0,
        'avgRating': 0.0,
        'trustScore': 5.0,
        'workCategories': [],
        'idDetails': {'type': 'Aadhar', 'number': ''},
        'experience': 0,
        'profileDescription': '',
        'perHourCharge': 50,
        'perDayCharge': 400,
        'createdAt': Timestamp.now(),
      });
    } else {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'id': uid,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'pin': _pinController.text.trim(),
        'altPhone': '',
        'email': '',
        'locality': '',
        'trustScore': 5.0,
        'userType': 'Standard',
        'createdAt': Timestamp.now(),
      });
    }
  }

  Future<void> _login() async {
    final email = '${_phoneController.text.trim()}@kaaryaconnect.app';
    await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kaarya Connect')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                Text(
                  _isLoginMode ? 'Welcome Back!' : 'Join Our Network',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 30),
                if (!_isLoginMode)
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (value) => value!.trim().isEmpty ? 'Please enter your name' : null,
                  ),
                if (!_isLoginMode) const SizedBox(height: 16),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: '10-Digit Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter a phone number';
                    if (value.length != 10) return 'Enter a valid 10-digit phone number';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                 if (!_isLoginMode)
                  TextFormField(
                    controller: _pinController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '6-Digit Pincode',
                      prefixIcon: const Icon(Icons.location_on_outlined), 
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Please enter a pincode';
                      if (value.length != 6) return 'Enter a valid 6-digit pincode';
                      return null;
                    },
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter a password';
                    if (value.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
                if (!_isLoginMode) const SizedBox(height: 16),
                if (!_isLoginMode)
                  TextFormField(
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    validator: (value) {
                      if (value != _passwordController.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                const SizedBox(height: 20),
                if (!_isLoginMode)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('I am a User'),
                        Switch(
                          value: _isWorker,
                          onChanged: (val) => setState(() => _isWorker = val),
                        ),
                        const Text('I am a Worker'),
                      ],
                    ),
                  ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submitAuthForm,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20, width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_isLoginMode ? 'Login' : 'Sign Up', style: const TextStyle(fontSize: 16)),
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _isLoginMode = !_isLoginMode),
                  child: Text(_isLoginMode
                      ? 'Don\'t have an account? Sign Up'
                      : 'Already have an account? Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UserDashboard extends StatefulWidget {
  final String userId;
  const UserDashboard({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  int _selectedIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(userId: widget.userId),
      BookingsScreen(userId: widget.userId),
      ProfileScreen(userId: widget.userId, isWorker: false),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.book_online), label: 'Bookings'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final String userId;
  const HomeScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = '';
  String _userPin = '';

  @override
  void initState() {
    super.initState();
    _getUserPin();
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
      appBar: AppBar(title: const Text('Find Local Workers')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or skill...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
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
          if (_selectedCategory.isNotEmpty && _userPin.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Text(
                'Showing top workers for "$_selectedCategory" near your pincode: $_userPin',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          const SizedBox(height: 12),
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

                workers = workers.where((doc) {
                   final data = doc.data() as Map<String, dynamic>;
                   if (data['availability'] != 'Y') return false;

                   final name = (data['name'] ?? '').toString().toLowerCase();
                   final searchText = _searchController.text.toLowerCase();
                   if (searchText.isNotEmpty && !name.contains(searchText)) return false;

                   if (_selectedCategory.isNotEmpty) {
                     final categories = (data['workCategories'] as List?)?.map((e) => e['mainCategory'] as String).toList() ?? [];
                     if (!categories.contains(_selectedCategory)) return false;
                   }
                   return true;
                }).toList();

                if (_userPin.isNotEmpty) {
                  workers.sort((a, b) {
                    final dataA = a.data() as Map<String, dynamic>;
                    final dataB = b.data() as Map<String, dynamic>;
                    final pinA = dataA['pin'] ?? '';
                    final pinB = dataB['pin'] ?? '';
                    final ratingA = dataA['avgRating'] ?? 0.0;
                    final ratingB = dataB['avgRating'] ?? 0.0;

                    if (pinA == _userPin && pinB != _userPin) return -1;
                    if (pinA != _userPin && pinB == _userPin) return 1;
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
    );
  }
}

class BookingCreationScreen extends StatefulWidget {
  final String userId;
  final String workerId;
  final String workerName;
  final String workerPhone;

  const BookingCreationScreen({
    Key? key, 
    required this.userId, 
    required this.workerId, 
    required this.workerName,
    required this.workerPhone,
  }) : super(key: key);

  @override
  State<BookingCreationScreen> createState() => _BookingCreationScreenState();
}

class _BookingCreationScreenState extends State<BookingCreationScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  int _hours = 2;
  bool _isLoading = false;

  Future<void> _confirmBooking() async {
    setState(() => _isLoading = true);
    try {
      final workerSnap = await FirebaseFirestore.instance.collection('workers').doc(widget.workerId).get();
      final userSnap = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();

      if (!workerSnap.exists || !userSnap.exists) {
        throw Exception("User or worker not found.");
      }

      final workerData = workerSnap.data()!;
      final userData = userSnap.data()!;

      final hourlyRate = (workerData['perHourCharge'] ?? 500).toDouble();
      final wage = hourlyRate * _hours;

      await FirebaseFirestore.instance.collection('bookings').add({
        'userId': widget.userId,
        'workerId': widget.workerId,
        'userInfo': {
          'name': userData['name'],
          'phone': userData['phone'],
        },
        'workerInfo': {
          'name': workerData['name'],
          'phone': workerData['phone'],
        },
        'bookingDate': Timestamp.fromDate(DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _selectedTime.hour, _selectedTime.minute)),
        'timeSlot': _hours,
        'bookingType': 'Hourly',
        'wage': wage,
        'status': 'Scheduled',
        'createdAt': Timestamp.now(),
        'remarks': [
          { 'log': 'Booking created by user.', 'timestamp': Timestamp.now() }
        ],
        'rating': 0,
        'review': ''
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking request sent!'), backgroundColor: Colors.green,));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent,));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Book ${widget.workerName}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select Date', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(DateFormat('MMMM dd, yyyy').format(_selectedDate)),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text('Select Start Time', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(_selectedTime.format(context)),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _selectedTime,
                  );
                  if (picked != null) {
                    setState(() => _selectedTime = picked);
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text('Select Duration (Hours)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _hours > 1 ? () => setState(() => _hours--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Expanded(
                      child: Text('$_hours hours', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _hours++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirmBooking,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,))
                    : const Text('Send Booking Request'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookingsScreen extends StatefulWidget {
  final String userId;
  const BookingsScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Bookings'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'UPCOMING'),
            Tab(text: 'PENDING'),
            Tab(text: 'HISTORY'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBookingsList(['Accepted']), 
          _buildBookingsList(['Scheduled']), 
          _buildBookingsList(['Completed', 'Cancelled', 'Rejected']), 
        ],
      ),
    );
  }

  Widget _buildBookingsList(List<String> statuses) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('userId', isEqualTo: widget.userId)
          .where('status', whereIn: statuses)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          String message;
          if (statuses.contains('Accepted')) {
            message = "You have no upcoming bookings.";
          } else if (statuses.contains('Scheduled')) {
            message = "You have no pending booking requests.";
          } else {
             message = "You have no past bookings.";
          }
          return Center(child: Text(message));
        }

        List<DocumentSnapshot> docs = snapshot.data!.docs;
        docs.sort((a, b) {
          Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
          Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;
          Timestamp timeA = dataA['bookingDate'] ?? dataA['createdAt'];
          Timestamp timeB = dataB['bookingDate'] ?? dataB['createdAt'];

          if (statuses.contains('Accepted')) {
            return timeA.compareTo(timeB); 
          }
          return timeB.compareTo(timeA); 
        });

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, idx) {
            final booking = docs[idx];
            final data = booking.data() as Map<String, dynamic>;
            return BookingTile(bookingData: data);
          },
        );
      },
    );
  }
}

class ProfileScreen extends StatefulWidget {
  final String userId;
  final bool isWorker;
  const ProfileScreen({Key? key, required this.userId, required this.isWorker}) : super(key: key);

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _altPhoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _idNumberController = TextEditingController();

  String _idType = 'Aadhar';
  int _experience = 0;
  List<Map<String, dynamic>> _workCategories = [];

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _altPhoneController.dispose();
    _pinController.dispose();
    _descriptionController.dispose();
    _hourlyRateController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  void _loadUserData(Map<String, dynamic> data) {
    _nameController.text = data['name'] ?? '';
    _phoneController.text = data['phone'] ?? '';
    _altPhoneController.text = data['altPhone'] ?? '';
    _pinController.text = data['pin'] ?? '';

    if (widget.isWorker) {
      _descriptionController.text = data['profileDescription'] ?? '';
      _hourlyRateController.text = (data['perHourCharge'] ?? 0).toString();
      _idNumberController.text = data['idDetails']?['number'] ?? '';
      _idType = data['idDetails']?['type'] ?? 'Aadhar';
      _experience = data['experience'] ?? 0;
      _workCategories = List<Map<String, dynamic>>.from(data['workCategories'] ?? []);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final collection = widget.isWorker ? 'workers' : 'users';

    Map<String, dynamic> dataToSave = {
      'name': _nameController.text.trim(),
      'phone': _phoneController.text.trim(),
      'altPhone': _altPhoneController.text.trim(),
      'pin': _pinController.text.trim(),
    };

    if (widget.isWorker) {
      dataToSave.addAll({
        'profileDescription': _descriptionController.text.trim(),
        'perHourCharge': int.tryParse(_hourlyRateController.text) ?? 0,
        'experience': _experience,
        'idDetails': {
          'type': _idType,
          'number': _idNumberController.text.trim()
        },
        'workCategories': _workCategories,
      });
    }

    try {
      await FirebaseFirestore.instance.collection(collection).doc(widget.userId).update(dataToSave);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved successfully!'), backgroundColor: Colors.green));
      setState(() => _isEditing = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save profile: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.isWorker ? 'workers' : 'users';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isWorker ? 'My Worker Profile' : 'My Profile'),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => setState(() => _isEditing = true),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection(collection).doc(widget.userId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                "Profile data not found.\nPlease try restarting the app.",
                textAlign: TextAlign.center,
              ),
            );
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;

          if (!_isEditing) {
            _loadUserData(data);
          }

          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTextField(controller: _nameController, label: 'Full Name', icon: Icons.person),
                  _buildTextField(controller: _phoneController, label: 'Primary Phone', icon: Icons.phone, keyboardType: TextInputType.phone),
                  _buildTextField(controller: _altPhoneController, label: 'Alternate Phone', icon: Icons.phone_android, required: false, keyboardType: TextInputType.phone),
                  _buildTextField(controller: _pinController, label: '6-Digit Pincode', icon: Icons.location_on, keyboardType: TextInputType.number),

                  if (widget.isWorker) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text('Worker Details', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 16),

                    _buildTextField(controller: _descriptionController, label: 'Profile Description (max 200 chars)', icon: Icons.description, maxLines: 3, maxLength: 200),
                    _buildTextField(controller: _hourlyRateController, label: 'Hourly Rate (₹)', icon: Icons.price_change, keyboardType: TextInputType.number),

                    _buildIdDetailsSection(),
                    const SizedBox(height: 16),

                     _buildExperienceSection(),
                    const SizedBox(height: 16),

                    _buildWorkCategoriesSection(),
                  ],

                  const SizedBox(height: 24),
                  if (_isEditing)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => setState(() => _isEditing = false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _saveProfile,
                          child: const Text('Save Profile'),
                        ),
                      ],
                    )
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool required = true, int? maxLines, int? maxLength, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: TextFormField(
        controller: controller,
        enabled: _isEditing,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
          filled: !_isEditing,
          fillColor: Colors.grey[200],
        ),
        maxLines: maxLines ?? 1,
        maxLength: maxLength,
        keyboardType: keyboardType,
        validator: (value) {
          if (required && (value == null || value.isEmpty)) {
            return 'This field is required';
          }
          return null;
        },
      ),
    );
  }

  Widget _buildIdDetailsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ID Verification', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _idType,
              items: ['Aadhar', 'PAN', 'Voter ID', 'Drivers License'].map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: _isEditing ? (newValue) {
                setState(() {
                  _idType = newValue!;
                });
              } : null,
              decoration: const InputDecoration(
                labelText: 'ID Type',
                 border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            _buildTextField(controller: _idNumberController, label: 'ID Number', icon: Icons.badge),
            if (_idType == 'Drivers License')
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text('Note: Driver\'s License is mandatory for driving-related jobs.', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildExperienceSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
             const Text('Years of Experience:', style: TextStyle(fontSize: 16)),
             const Spacer(),
             if (_isEditing)
              IconButton(onPressed: () => setState(() { if(_experience > 0) _experience--; }), icon: const Icon(Icons.remove)),
             Text('$_experience years', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
             if (_isEditing)
              IconButton(onPressed: () => setState(() => _experience++), icon: const Icon(Icons.add)),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkCategoriesSection() {
    return Card(
       child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('My Skills', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                 if (_isEditing)
                  IconButton(onPressed: _addWorkCategory, icon: const Icon(Icons.add_circle)),
              ],
            ),
            const SizedBox(height: 8),
            if (_workCategories.isEmpty)
              const Text('No skills added yet. Tap the + to add one.')
            else
              ..._workCategories.asMap().entries.map((entry) {
                int idx = entry.key;
                Map<String, dynamic> category = entry.value;
                return _buildCategoryEditor(idx, category);
              }).toList(),
          ],
        ),
      ),
    );
  }

  void _addWorkCategory() {
    setState(() {
      _workCategories.add({'mainCategory': 'Plumber', 'tags': []});
    });
  }

  Widget _buildCategoryEditor(int index, Map<String, dynamic> category) {
    List<String> tags = List<String>.from(category['tags'] ?? []);
    final tagController = TextEditingController();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: category['mainCategory'],
                    isExpanded: true,
                    items: ['Plumber', 'Electrician', 'Carpenter', 'Maid', 'Cook', 'Mechanic', 'Mover', 'Babysitter'].map((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
                    onChanged: _isEditing ? (newValue) {
                      setState(() {
                        _workCategories[index]['mainCategory'] = newValue!;
                      });
                    } : null,
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () {
                      setState(() {
                        _workCategories.removeAt(index);
                      });
                    },
                  )
              ],
            ),
            const SizedBox(height: 8),
             Wrap(
              spacing: 6,
              children: tags.map((tag) => Chip(
                label: Text(tag, style: const TextStyle(fontSize: 12)),
                onDeleted: _isEditing ? () {
                  setState(() {
                    (_workCategories[index]['tags'] as List).remove(tag);
                  });
                } : null,
              )).toList(),
            ),
            if (_isEditing && tags.length < 3)
              TextField(
                controller: tagController,
                maxLength: 20,
                decoration: InputDecoration(
                  labelText: 'Add a skill tag (e.g., "Non-veg expert")',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      if (tagController.text.isNotEmpty) {
                        setState(() {
                          (_workCategories[index]['tags'] as List).add(tagController.text);
                          tagController.clear();
                        });
                      }
                    },
                  )
                ),
              )
          ],
        ),
      ),
    );
  }
}

class WorkerDashboard extends StatefulWidget {
  final String workerId;
  const WorkerDashboard({Key? key, required this.workerId}) : super(key: key);

  @override
  State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard> {
  int _selectedIndex = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      WorkerJobsScreen(workerId: widget.workerId),
      WorkerCalendarScreen(workerId: widget.workerId),
      ProfileScreen(userId: widget.workerId, isWorker: true),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.work_history), label: 'Jobs'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Schedule'),
          BottomNavigationBarItem(icon: Icon(Icons.person_pin_circle), label: 'Profile'),
        ],
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

class WorkerJobsScreen extends StatefulWidget {
  final String workerId;
  const WorkerJobsScreen({Key? key, required this.workerId}) : super(key: key);

  @override
  State<WorkerJobsScreen> createState() => _WorkerJobsScreenState();
}

class _WorkerJobsScreenState extends State<WorkerJobsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Jobs'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'NEW REQUESTS'),
            Tab(text: 'UPCOMING'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewRequestsList(),
          _buildAcceptedJobsList(),
        ],
      ),
    );
  }

  Widget _buildNewRequestsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('workerId', isEqualTo: widget.workerId)
          .where('status', isEqualTo: 'Scheduled')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No new job requests.'));
        }

        List<DocumentSnapshot> docs = snapshot.data!.docs;
        docs.sort((a, b) {
          Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
          Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;
          Timestamp timeA = dataA['createdAt'];
          Timestamp timeB = dataB['createdAt'];
          return timeB.compareTo(timeA); 
        });

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, idx) {
            final booking = docs[idx];
            final data = booking.data() as Map<String, dynamic>;
            return JobRequestCard(bookingData: data, bookingId: booking.id, workerId: widget.workerId);
          },
        );
      },
    );
  }

  Widget _buildAcceptedJobsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('workerId', isEqualTo: widget.workerId)
          .where('status', isEqualTo: 'Accepted')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('You have no upcoming jobs.'));
        }

        List<DocumentSnapshot> docs = snapshot.data!.docs;
        docs.sort((a, b) {
          Map<String, dynamic> dataA = a.data() as Map<String, dynamic>;
          Map<String, dynamic> dataB = b.data() as Map<String, dynamic>;
          Timestamp timeA = dataA['bookingDate'];
          Timestamp timeB = dataB['bookingDate'];
          return timeA.compareTo(timeB); 
        });

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: docs.length,
          itemBuilder: (context, idx) {
            final booking = docs[idx];
            final data = booking.data() as Map<String, dynamic>;
            return BookingTile(bookingData: data);
          },
        );
      },
    );
  }
}

class WorkerCalendarScreen extends StatefulWidget {
  final String workerId;
  const WorkerCalendarScreen({Key? key, required this.workerId}) : super(key: key);

  @override
  State<WorkerCalendarScreen> createState() => _WorkerCalendarScreenState();
}

class _WorkerCalendarScreenState extends State<WorkerCalendarScreen> {
  DateTime _selectedDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Schedule')),
      body: Column(
        children: [
          CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
            onDateChanged: (newDate) => setState(() => _selectedDate = newDate),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('bookings')
                  .where('workerId', isEqualTo: widget.workerId)
                  .where('status', whereIn: ['Accepted', 'Completed'])
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final bookings = snapshot.data?.docs ?? [];
                final selectedDayBookings = bookings.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final bookingDate = (data['bookingDate'] as Timestamp).toDate();
                  return DateUtils.isSameDay(bookingDate, _selectedDate);
                }).toList();

                if (selectedDayBookings.isEmpty) {
                  return Center(
                    child: Text('No jobs scheduled for ${DateFormat('MMM dd').format(_selectedDate)}'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: selectedDayBookings.length,
                  itemBuilder: (context, idx) {
                    final data = selectedDayBookings[idx].data() as Map<String, dynamic>;
                    final bookingDate = (data['bookingDate'] as Timestamp).toDate();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text('Job at ${DateFormat.jm().format(bookingDate)} for ${data['timeSlot']} hours'),
                        subtitle: Text('Status: ${data['status']}'),
                        trailing: Text('₹${(data['wage'] ?? 0).toInt()}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class WorkerCard extends StatelessWidget {
  final Map<String, dynamic> worker;
  final String workerId;
  final String userId;

  const WorkerCard({Key? key, required this.worker, required this.workerId, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rating = (worker['avgRating'] ?? 0.0).toDouble();
    final hourlyRate = (worker['perHourCharge'] ?? 0).toInt();
    final name = worker['name'] ?? 'N/A';
    final categories = worker['workCategories'] as List? ?? [];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.indigo[100],
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'W', style: const TextStyle(color: Colors.white, fontSize: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text('${rating.toStringAsFixed(1)} (${worker['completedBookings'] ?? 0} jobs)'),
                        ],
                      ),
                    ],
                  ),
                ),
                Text('₹$hourlyRate/hr', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            if (categories.isNotEmpty) const Divider(height: 24),
            if (categories.isNotEmpty)
              Wrap(
                spacing: 6, runSpacing: 6,
                children: (categories).take(3).map((c) => Chip(label: Text(c['mainCategory'] ?? 'Skill'), padding: EdgeInsets.zero,)).toList(),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BookingCreationScreen(
                        userId: userId, 
                        workerId: workerId, 
                        workerName: name,
                        workerPhone: worker['phone'] ?? '',
                      ),
                    ),
                  );
                },
                child: const Text('Book Now'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BookingTile extends StatelessWidget {
  final Map<String, dynamic> bookingData;

  const BookingTile({Key? key, required this.bookingData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final date = (bookingData['bookingDate'] as Timestamp).toDate();
    final status = bookingData['status'] ?? 'Unknown';
    final wage = (bookingData['wage'] ?? 0).toInt();
    final workerName = bookingData['workerInfo']?['name'] ?? 'Worker';
    final userName = bookingData['userInfo']?['name'] ?? 'User';
    final currentUserIsWorker = FirebaseAuth.instance.currentUser!.uid == bookingData['workerId'];

    Color statusColor;

    switch (status) {
      case 'Completed': statusColor = Colors.green; break;
      case 'Cancelled': case 'Rejected': statusColor = Colors.red; break;
      case 'Accepted': statusColor = Colors.blue; break;
      default: statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('MMMM dd, yyyy').format(date),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
             const SizedBox(height: 8),
            Text(currentUserIsWorker ? 'Client: $userName' : 'Worker: $workerName'),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${DateFormat.jm().format(date)} • ${bookingData['timeSlot']} hours',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                Text('₹$wage', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.indigo)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class JobRequestCard extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final String bookingId;
  final String workerId;

  const JobRequestCard({Key? key, required this.bookingData, required this.bookingId, required this.workerId}) : super(key: key);

  @override
  State<JobRequestCard> createState() => _JobRequestCardState();
}

class _JobRequestCardState extends State<JobRequestCard> {
  bool _isLoading = false;

  Future<void> _updateJobStatus(String status) async {
    setState(() => _isLoading = true);
    try {
      final batch = FirebaseFirestore.instance.batch();

      final bookingRef = FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId);
      batch.update(bookingRef, {
        'status': status,
        'remarks': FieldValue.arrayUnion([
          { 'log': 'Worker $status the job.', 'timestamp': Timestamp.now() }
        ])
      });

      final workerRef = FirebaseFirestore.instance.collection('workers').doc(widget.workerId);
      if (status == 'Accepted') {
        batch.update(workerRef, {'availability': 'N'});
      } else if (status == 'Rejected') {

        batch.update(workerRef, {'availability': 'Y'});
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Job has been $status.'), backgroundColor: status == 'Accepted' ? Colors.green : Colors.orange,));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent,));
    } finally {

    }
  }

  @override
  Widget build(BuildContext context) {
    final date = (widget.bookingData['bookingDate'] as Timestamp).toDate();
    final wage = (widget.bookingData['wage'] ?? 0).toInt();
    final userName = widget.bookingData['userInfo']?['name'] ?? 'A user';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New request from $userName', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(DateFormat('MMMM dd, yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Time: ${DateFormat.jm().format(date)} • Duration: ${widget.bookingData['timeSlot']} hours',
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Earning:', style: TextStyle(fontSize: 16)),
                Text('₹$wage', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.green)),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: Padding(
                padding: EdgeInsets.all(8.0),
                child: CircularProgressIndicator(),
              ))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _updateJobStatus('Rejected'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateJobStatus('Accepted'),
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
