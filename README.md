```markdown
# 🧩 Kaarya_Cohort8 – Flutter App Structure


lib/
├── main.dart             # Main entry point (minimal setup, runs app.dart)
├── app.dart              # Root application widget (KaaryaConnectApp) + global ThemeData
│
├── core/                 # 🚀 Core services, theming, and constants
│   ├── theme.dart          # DoodleBackgroundTheme, DoodleBackground, DoodlePainter widgets
│   ├── constants.dart      # (Empty – reserved for app-wide constants)
│   └── utils.dart          # (Empty – reserved for utility/helper functions)
│
└── features/             # 📱 Feature-Specific Modules (Screen-First Grouping)
├── auth/             # 🔐 Authentication & Account Creation Flow
│   ├── auth_wrapper.dart      # StreamBuilder → routes users/workers to dashboards
│   └── auth_screen.dart       # Login/Signup StatefulWidget
│
├── user/             # 👤 Client/User Role Screens
│   ├── user_dashboard.dart           # Main navigation shell for the User (BottomNavigationBar)
│   ├── home_screen.dart              # User Home/Search screen
│   ├── bookings_screen.dart          # User Bookings (Upcoming, Pending, History tabs)
│   └── booking_creation_screen.dart  # Screen for initiating a booking
│
├── worker/           # 🧰 Worker Role Screens
│   ├── worker_dashboard.dart         # Main navigation shell for the Worker
│   ├── worker_jobs_screen.dart       # New Requests & Upcoming Jobs tabs
│   ├── worker_calendar_screen.dart   # Schedule Calendar view
│   ├── sos_screen.dart               # Emergency SOS screen
│   ├── job_request_card.dart         # Widget for displaying/acting on new requests
│   └── user_details_screen.dart      # Worker viewing Client profile
│
└── shared/           # 🔄 Shared Components (used by both roles)
├── profile_screen.dart           # Shared Profile Editor/Viewer
├── inbox_screen.dart             # Shared Notifications/Inbox screen
├── booking_tile.dart             # Reusable card for accepted/completed bookings
├── booking_details_screen.dart   # Full details of a single booking
├── rating_dialog.dart            # Dialog for submitting a rating
└── report_dialog.dart            # Dialog for submitting a report



Modularity: Each feature is self-contained easier testing & onboarding.
Scalability: Ready for new roles or features (e.g., Admin module).
Readability: Logical grouping makes file discovery faster.
Maintainability: Reduces merge conflicts and isolates changes.


```
