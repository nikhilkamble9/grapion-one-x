// //Added By Nikhil 18Nov26 21:30 For API Client & Local Token Storage
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'push_service.dart'; //Added By Nikhil 22Nov26 00:10 For unregistering the device on sign-out

class ApiClient {
  static const String baseUrl = 'http://127.0.0.1:8000/api/v1';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<String?> getToken() async {
    return await _storage.read(key: 'jwt_token');
  }

  Future<void> saveToken(String token) async {
    await _storage.write(key: 'jwt_token', value: token);
  }

  Future<void> clearToken() async {
    await PushService.unregisterDevice(); //Added By Nikhil 22Nov26 00:10 For stopping pushes to this phone after sign-out
    await _storage.delete(key: 'jwt_token');
  }

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> get(String endpoint) async {
    final headers = await _headers();
    return await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers);
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _headers();
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  //Added By Nikhil 21Nov26 22:36 For profile updates START
  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await _headers();
    return await http.put(Uri.parse('$baseUrl$endpoint'), headers: headers, body: jsonEncode(body));
  }
  //Added By Nikhil 21Nov26 22:36 For profile updates END
}

final apiClient = ApiClient();
