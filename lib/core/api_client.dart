// lib/core/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ApiClient {

  static const String _baseUrl = "https://hawk4aynahtirk.pythonanywhere.com";

  static const String _apiSecret = "HiFhGDorJRULc1Z";

  static const Map<String, String> _headers = {
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
}

// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => message;
}