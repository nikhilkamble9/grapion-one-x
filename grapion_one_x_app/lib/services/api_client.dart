// //Added By Nikhil 18Nov26 21:30 For API Client & Local Token Storage
import 'dart:async'; //Added By Nikhil 22Nov26 16:06 For TimeoutException
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'push_service.dart'; //Added By Nikhil 22Nov26 00:10 For unregistering the device on sign-out

class ApiClient {
  //Modified By Nikhil 22Nov26 15:17 For app using the API deployed on Render (local API via --dart-define). Old: static const String baseUrl = 'http://127.0.0.1:8000/api/v1';
  /// Default: the API on Render. For the API on this PC run with
  /// `--dart-define=API_BASE_URL=http://127.0.0.1:8000/api/v1`.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://grapion-one-x.onrender.com/api/v1',
  );
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

  /// Long enough for the free Render server to wake up (~30–60 s), short enough that a dead network gives a message.
  static const Duration _timeout = Duration(seconds: 75); //Added By Nikhil 22Nov26 16:06 For request timeout

  Future<http.Response> get(String endpoint) async {
    final headers = await _headers();
    return await http.get(Uri.parse('$baseUrl$endpoint'), headers: headers).timeout(_timeout); //Modified By Nikhil 22Nov26 16:06 For request timeout. Old: no .timeout
  }

  Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _headers();
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    ).timeout(_timeout); //Modified By Nikhil 22Nov26 16:06 For request timeout. Old: no .timeout
  }

  //Added By Nikhil 21Nov26 22:36 For profile updates START
  Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await _headers();
    return await http.put(Uri.parse('$baseUrl$endpoint'), headers: headers, body: jsonEncode(body)).timeout(_timeout); //Modified By Nikhil 22Nov26 16:06 For request timeout. Old: no .timeout
  }
  //Added By Nikhil 21Nov26 22:36 For profile updates END
}

//Added By Nikhil 22Nov26 16:06 For clear error messages instead of one "Connection error" for everything START
/// Turns an exception from an API call into a message the user can act on.
String friendlyError(Object e) {
  if (e is TimeoutException) {
    return 'The server is taking too long. It may be waking up, so please try again in a minute.';
  }
  if (e is http.ClientException) {
    return "Can't reach the server. Check your internet connection and try again.";
  }
  if (e is FormatException) {
    return 'The server is starting up or busy. Please try again in a minute.';
  }
  if (e is UnsupportedError && '${e.message}'.contains('secure context')) {
    return "This browser can't keep your login safe on this address. Use the mobile app, or open the site with https.";
  }
  return 'Something went wrong. Please try again.';
}
//Added By Nikhil 22Nov26 16:06 For clear error messages instead of one "Connection error" for everything END

final apiClient = ApiClient();
