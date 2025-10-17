import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

// ============================================================================
// SECTION: Main App Initialization
// ============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDm4xvZbc35ZNucXFoIBwdVyLd8h22NI1o",
      authDomain: "cohort8-f5139.firebaseapp.com",
      projectId: "cohort8-f5139",
      storageBucket: "cohort8-f5139.appspot.com", // Corrected storage bucket
      messagingSenderId: "1006872143391",
      appId: "1:1006872143391:web:08873239c279e68f12172a"
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
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const AuthScreen(),
    );
  }
}

// ============================================================================
// SECTION: Authentication Screen
// ============================================================================

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoginMode = true;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isWorker = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
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
        'id': uid, 'name': _nameController.text, 'phone': _phoneController.text,
        'availability': 'Y', 'totalBookings': 0, 'completedBookings': 0,
        'avgRating': 0.0, 'trustScore': 5.0, 'works': [],
        'createdAt': Timestamp.now(), 'perHourCharge': 0, 'perDayCharge': 0,
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WorkerDashboard(workerId: uid)),
      );
    } else {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'id': uid, 'name': _nameController.text, 'phone': _phoneController.text,
        'trustScore': 5.0, 'userType': 'Standard', 'createdAt': Timestamp.now(),
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => UserDashboard(userId: uid)),
      );
    }
  }

  Future<void> _login() async {
    final email = '${_phoneController.text.trim()}@kaaryaconnect.app';
    final userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: _passwordController.text,
    );
    final uid = userCredential.user!.uid;

    final workerDoc = await FirebaseFirestore.instance.collection('workers').doc(uid).get();

    if (!mounted) return;
    if (workerDoc.exists) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => WorkerDashboard(workerId: uid)),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => UserDashboard(userId: uid)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Kaarya Connect')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 40),
              Text(
                _isLoginMode ? 'Welcome Back!' : 'Create an Account',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 30),
              if (!_isLoginMode)
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  validator: (value) => value!.isEmpty ? 'Please enter your name' : null,
                ),
              if (!_isLoginMode) const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone Number',
                  hintText: 'Use as your login ID',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                validator: (value) => value!.isEmpty ? 'Please enter a phone number' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
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
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
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
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(_isWorker ? 'Worker Mode' : 'User Mode')),
                      Switch(
                        value: _isWorker,
                        onChanged: (val) => setState(() => _isWorker = val),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitAuthForm,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(_isLoginMode ? 'Login' : 'Sign Up'),
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
    );
  }
}

// ============================================================================
// SECTION: User Screens
// ============================================================================

// FILE: lib/screens/user/user_dashboard.dart
class UserDashboard extends StatefulWidget {
  final String userId;
  const UserDashboard({Key? key, required this.userId}) : super(key: key);

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      HomeScreen(userId: widget.userId),
      BookingsScreen(userId: widget.userId),
      ProfileScreen(userId: widget.userId),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
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

// FILE: lib/screens/user/home_screen.dart
class HomeScreen extends StatefulWidget {
  final String userId;
  const HomeScreen({Key? key, required this.userId}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Find Workers')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name or skill',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: ['Plumber', 'Electrician', 'Handyman', 'Maid', 'Coolie']
                  .map((cat) => FilterChip(
                        label: Text(cat),
                        selected: _selectedCategory == cat,
                        onSelected: (sel) => setState(() => _selectedCategory = sel ? cat : ''),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('workers')
                  .where('availability', isEqualTo: 'Y')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No workers available'));
                }
                var workers = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] ?? '').toString().toLowerCase();
                  final searchText = _searchController.text.toLowerCase();
                  if (searchText.isNotEmpty && !name.contains(searchText)) {
                    return false;
                  }
                  if (_selectedCategory.isNotEmpty) {
                    final works = data['works'] as List? ?? [];
                    return works.any((w) => w['workType'] == _selectedCategory);
                  }
                  return true;
                }).toList();

                return ListView.builder(
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

// FILE: lib/screens/user/booking_screen.dart
class BookingScreen extends StatefulWidget {
  final String userId;
  final String workerId;
  final String workerName;

  const BookingScreen({Key? key, required this.userId, required this.workerId, required this.workerName}) : super(key: key);

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = const TimeOfDay(hour: 9, minute: 0);
  int _hours = 2;
  bool _isLoading = false;

  Future<void> _confirmBooking() async {
    setState(() => _isLoading = true);
    try {
      final workerSnap = await FirebaseFirestore.instance.collection('workers').doc(widget.workerId).get();
      final hourlyRate = (workerSnap.data()?['perHourCharge'] ?? 500).toDouble();
      final wage = hourlyRate * _hours;

      await FirebaseFirestore.instance.collection('bookings').add({
        'userId': widget.userId, 'workerId': widget.workerId,
        'bookingDate': Timestamp.fromDate(_selectedDate),
        'fromTime': _selectedTime.format(context), 'timeSlot': _hours,
        'bookingType': 'Hourly', 'wage': wage, 'status': 'Scheduled',
        'createdAt': Timestamp.now(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Booking confirmed!')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
            const Text('Select Date', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(DateFormat('MMM dd, yyyy').format(_selectedDate)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
            const Text('Start Time', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(_selectedTime.format(context)),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
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
            const Text('Duration (Hours)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _hours > 1 ? () => setState(() => _hours--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Expanded(
                      child: Text('$_hours hours', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _hours++),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _confirmBooking,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                child: _isLoading
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Confirm Booking'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// FILE: lib/screens/user/bookings_screen.dart
class BookingsScreen extends StatelessWidget {
  final String userId;
  const BookingsScreen({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('userId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('You have no bookings yet.'));
          }
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, idx) {
              final booking = snapshot.data!.docs[idx];
              final data = booking.data() as Map<String, dynamic>;
              return BookingTile(bookingData: data, bookingId: booking.id);
            },
          );
        },
      ),
    );
  }
}

// FILE: lib/screens/user/profile_screen.dart
class ProfileScreen extends StatelessWidget {
  final String userId;
  const ProfileScreen({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const AuthScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Profile not found.'));
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 32,
                          backgroundColor: Colors.blue[100],
                          child: Text(
                            (data['name'] ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(fontSize: 24, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['name'] ?? 'N/A', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 4),
                            Text(data['phone'] ?? 'N/A', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text('Account Details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: const Text('Trust Score'),
                    trailing: Text(
                      '${data['trustScore'] ?? 5.0}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.card_membership),
                    title: const Text('Plan'),
                    trailing: Text(
                      data['userType'] ?? 'Standard',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// SECTION: Worker Screens
// ============================================================================

// FILE: lib/screens/worker/worker_dashboard.dart
class WorkerDashboard extends StatefulWidget {
  final String workerId;
  const WorkerDashboard({Key? key, required this.workerId}) : super(key: key);

  @override
  State<WorkerDashboard> createState() => _WorkerDashboardState();
}

class _WorkerDashboardState extends State<WorkerDashboard> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      WorkerJobsScreen(workerId: widget.workerId),
      WorkerCalendarScreen(workerId: widget.workerId),
      WorkerProfileScreen(workerId: widget.workerId),
    ];

    return Scaffold(
      body: screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.work_history), label: 'Jobs'),
          BottomNavigationBarItem(icon: Icon(Icons.calendar_month), label: 'Calendar'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
        onTap: (index) => setState(() => _selectedIndex = index),
      ),
    );
  }
}

// FILE: lib/screens/worker/worker_jobs_screen.dart
class WorkerJobsScreen extends StatelessWidget {
  final String workerId;
  const WorkerJobsScreen({Key? key, required this.workerId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Job Requests')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('bookings')
            .where('workerId', isEqualTo: workerId)
            .where('status', isEqualTo: 'Scheduled')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No pending job requests.'));
          }
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, idx) {
              final booking = snapshot.data!.docs[idx];
              final data = booking.data() as Map<String, dynamic>;
              return JobRequestCard(bookingData: data, bookingId: booking.id, workerId: workerId);
            },
          );
        },
      ),
    );
  }
}

// FILE: lib/screens/worker/worker_calendar_screen.dart
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
                    child: Text('No jobs on ${DateFormat('MMM dd').format(_selectedDate)}'),
                  );
                }
                return ListView.builder(
                  itemCount: selectedDayBookings.length,
                  itemBuilder: (context, idx) {
                    final data = selectedDayBookings[idx].data() as Map<String, dynamic>;
                    return ListTile(
                      title: Text('${data['fromTime']} • ${data['timeSlot']} hours'),
                      subtitle: Text('Status: ${data['status']}'),
                      trailing: Text('₹${(data['wage'] ?? 0).toInt()}'),
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

// FILE: lib/screens/worker/worker_profile_screen.dart
class WorkerProfileScreen extends StatefulWidget {
  final String workerId;
  const WorkerProfileScreen({Key? key, required this.workerId}) : super(key: key);

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  final _hourlyRateController = TextEditingController();
  bool _isEditing = false;

  @override
  void dispose() {
    _hourlyRateController.dispose();
    super.dispose();
  }

  Future<void> _updateRate() async {
    final newRate = int.tryParse(_hourlyRateController.text) ?? 0;
    await FirebaseFirestore.instance
        .collection('workers')
        .doc(widget.workerId)
        .update({'perHourCharge': newRate});
    setState(() => _isEditing = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rate updated successfully!')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Worker Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const AuthScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('workers').doc(widget.workerId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Profile not found.'));
          }
          final data = snapshot.data!.data() as Map<String, dynamic>;
          if (!_isEditing) {
            _hourlyRateController.text = (data['perHourCharge'] ?? 0).toString();
          }
          final availability = data['availability'] == 'Y';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 32,
                              backgroundColor: Colors.blue[100],
                              child: Text((data['name'] ?? 'W')[0].toUpperCase(), style: const TextStyle(fontSize: 24, color: Colors.white)),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(data['name'] ?? 'N/A', style: Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 4),
                                Text(data['phone'] ?? 'N/A', style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Chip(
                              avatar: const Icon(Icons.star, color: Colors.amber, size: 18),
                              label: Text('${data['avgRating'] ?? 0.0} Rating'),
                            ),
                            Chip(
                              avatar: CircleAvatar(radius: 5, backgroundColor: availability ? Colors.green : Colors.grey),
                              label: Text(availability ? 'Available' : 'Busy'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _isEditing
                      ? Column(
                          children: [
                            TextField(
                              controller: _hourlyRateController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Hourly Rate (₹)', border: OutlineInputBorder()),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(onPressed: () => setState(() => _isEditing = false), child: const Text('Cancel')),
                                ElevatedButton(onPressed: _updateRate, child: const Text('Save')),
                              ],
                            ),
                          ],
                        )
                      : ListTile(
                          leading: const Icon(Icons.price_change_outlined),
                          title: const Text('Hourly Rate'),
                          trailing: Text('₹${data['perHourCharge'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          onTap: () => setState(() => _isEditing = true),
                        ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.work_history_outlined),
                    title: const Text('Completed Jobs'),
                    trailing: Text('${data['completedBookings'] ?? 0}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// SECTION: Reusable Widgets
// ============================================================================

// FILE: lib/widgets/worker_card.dart
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

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.blue[100],
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
                          Text('$rating (${worker['completedBookings'] ?? 0} jobs)'),
                        ],
                      ),
                    ],
                  ),
                ),
                if (worker['availability'] == 'Y')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green[100], borderRadius: BorderRadius.circular(4)),
                    child: const Text('Available', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (worker['works'] != null && (worker['works'] as List).isNotEmpty)
              Wrap(
                spacing: 6, runSpacing: 6,
                children: (worker['works'] as List).take(3).map((w) => Chip(label: Text(w['workType'] ?? 'Skill'))).toList(),
              ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₹$hourlyRate/hour', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BookingScreen(userId: userId, workerId: workerId, workerName: name),
                      ),
                    );
                  },
                  child: const Text('Book Now'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// FILE: lib/widgets/booking_tile.dart
class BookingTile extends StatelessWidget {
  final Map<String, dynamic> bookingData;
  final String bookingId;

  const BookingTile({Key? key, required this.bookingData, required this.bookingId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final date = (bookingData['bookingDate'] as Timestamp).toDate();
    final status = bookingData['status'] ?? 'Unknown';
    final wage = (bookingData['wage'] ?? 0).toInt();
    Color statusColor;

    switch (status) {
      case 'Completed': statusColor = Colors.green; break;
      case 'Cancelled': case 'Rejected': statusColor = Colors.red; break;
      case 'Accepted': statusColor = Colors.blue; break;
      default: statusColor = Colors.orange;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${bookingData['fromTime']} • ${bookingData['timeSlot']} hours',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
                Text('₹$wage', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// FILE: lib/widgets/job_request_card.dart
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
      await FirebaseFirestore.instance.collection('bookings').doc(widget.bookingId).update({'status': status});
      if (status == 'Accepted') {
        await FirebaseFirestore.instance.collection('workers').doc(widget.workerId).update({'availability': 'N'});
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Job has been $status.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = (widget.bookingData['bookingDate'] as Timestamp).toDate();
    final wage = (widget.bookingData['wage'] ?? 0).toInt();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMMM dd, yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              '${widget.bookingData['fromTime']} • ${widget.bookingData['timeSlot']} hours',
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
              const Center(child: CircularProgressIndicator())
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
