// Where the app keeps the server address, its device token and the red light choice.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredSession {
  const StoredSession(this.serverUrl, this.token);

  final String serverUrl;

  /// Null for an instance in local mode, which needs no login.
  final String? token;
}

abstract class SessionStore {
  Future<StoredSession?> load();
  Future<void> save(StoredSession session);
  Future<void> clear();
  Future<bool> redLight();
  Future<void> setRedLight(bool on);
}

/// Keychain (iOS) / Keystore-backed storage (Android).
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const _serverKey = 'server_url';
  static const _tokenKey = 'app_token';
  static const _localKey = 'local_mode';
  static const _redKey = 'red_light';

  @override
  Future<StoredSession?> load() async {
    final server = await _storage.read(key: _serverKey);
    if (server == null) return null;
    final token = await _storage.read(key: _tokenKey);
    final local = await _storage.read(key: _localKey) == '1';
    if (token == null && !local) return null;
    return StoredSession(server, token);
  }

  @override
  Future<void> save(StoredSession session) async {
    await _storage.write(key: _serverKey, value: session.serverUrl);
    if (session.token == null) {
      await _storage.delete(key: _tokenKey);
      await _storage.write(key: _localKey, value: '1');
    } else {
      await _storage.write(key: _tokenKey, value: session.token);
      await _storage.delete(key: _localKey);
    }
  }

  /// Signs out but remembers the address, so the next login starts from it.
  @override
  Future<void> clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _localKey);
  }

  @override
  Future<bool> redLight() async => await _storage.read(key: _redKey) == '1';

  @override
  Future<void> setRedLight(bool on) => _storage.write(key: _redKey, value: on ? '1' : '0');

  Future<String?> lastServer() => _storage.read(key: _serverKey);
}

/// For tests.
class MemorySessionStore implements SessionStore {
  StoredSession? session;
  bool red = false;

  @override
  Future<StoredSession?> load() async => session;

  @override
  Future<void> save(StoredSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;

  @override
  Future<bool> redLight() async => red;

  @override
  Future<void> setRedLight(bool on) async => red = on;
}
