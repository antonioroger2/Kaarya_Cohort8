// lib/core/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiClient {

  static const String _baseUrl = "https://hawk4aynahtirk.pythonanywhere.com";

  static String get _apiSecret => dotenv.env['API_SECRET_KEY'] ?? '';

  static Map<String, String> get _headers => {
    "Content-Type": "application/json",
    "x-secret-key": _apiSecret,
  };

  // Helper method for POST requests
  static Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl$endpoint'),
        headers: _headers,
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 20));

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // Return the full response body if it's a success
        return responseBody as Map<String, dynamic>;
      } else {
        // Throw a specific exception with the server's error message
        final errorMessage = responseBody['error'] ?? 'Unknown server error';
        throw ApiException('Error ${response.statusCode}: $errorMessage');
      }
    } catch (e) {
      debugPrint("API Client Error ($endpoint): $e");
      // Re-throw as a specific exception
      throw ApiException(e.toString());
    }
  }

  // Example of a GET request helper (if you need it later)
  static Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl$endpoint'),
        headers: _headers,
      ).timeout(const Duration(seconds: 20));

      final responseBody = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return responseBody as Map<String, dynamic>;
      } else {
        final errorMessage = responseBody['error'] ?? 'Unknown server error';
        throw ApiException('Error ${response.statusCode}: $errorMessage');
      }
    } catch (e) {
      debugPrint("API Client Error ($endpoint): $e");
      throw ApiException(e.toString());
    }
  }

  // Submit rating with review for Profile Healer AI
  static Future<void> submitRating(String bookingId, double rating, String workerId, String userId, String reviewText) async {
    await post('/submit-rating', {
      "bookingId": bookingId,
      "rating": rating,
      "workerId": workerId,
      "userId": userId,
      "review": reviewText, // Crucial for AI Profile Healer!
    });
  }

  // Generate Start OTP
  static Future<Map<String, dynamic>> generateStartOtp(String bookingId) async {
    return await post('/generate-start-otp', {
      "bookingId": bookingId,
    });
  }

  // Verify Start OTP
  static Future<Map<String, dynamic>> verifyStartOtp(String bookingId, String correlationId, String code) async {
    return await post('/verify-start-otp', {
      "bookingId": bookingId,
      "correlationId": correlationId,
      "code": code,
    });
  }

  // Generate End OTP
  static Future<Map<String, dynamic>> generateEndOtp(String bookingId) async {
    return await post('/generate-end-otp', {
      "bookingId": bookingId,
    });
  }

  // Verify End OTP
  static Future<Map<String, dynamic>> verifyEndOtp(String bookingId, String correlationId, String code) async {
    return await post('/verify-end-otp', {
      "bookingId": bookingId,
      "correlationId": correlationId,
      "code": code,
    });
  }

  // TODO: Add cancelBooking method
  // TODO: Add getBooking method
  // TODO: Add getWorkerAvailability method
  // TODO: Add expireRequests method
  // TODO: Add createBooking method
  // TODO: Add workerAccept method
  // TODO: Add workerReject method
}

// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}