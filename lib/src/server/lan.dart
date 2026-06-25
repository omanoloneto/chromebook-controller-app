// Descoberta do IP do celular na rede local (LAN).

import 'dart:io';

bool _isPrivate(String ip) {
  if (ip.startsWith('192.168.')) return true;
  if (ip.startsWith('10.')) return true;
  // 172.16.0.0 – 172.31.255.255
  if (ip.startsWith('172.')) {
    final parts = ip.split('.');
    if (parts.length > 1) {
      final second = int.tryParse(parts[1]) ?? 0;
      return second >= 16 && second <= 31;
    }
  }
  return false;
}

/// Retorna o IPv4 privado do celular na LAN (preferindo Wi-Fi), ou null.
Future<String?> descobrirIpLan() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );

  String? fallback;
  for (final iface in interfaces) {
    for (final addr in iface.addresses) {
      if (!_isPrivate(addr.address)) continue;
      final nome = iface.name.toLowerCase();
      // Wi-Fi costuma ser wlan0 (Android) ou en0 (alguns aparelhos).
      if (nome.contains('wlan') || nome.contains('wifi') || nome == 'en0') {
        return addr.address;
      }
      fallback ??= addr.address;
    }
  }
  return fallback;
}

/// Todos os IPv4 privados do celular (para o teste cru / IP manual).
Future<List<String>> descobrirIpsLan() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  final out = <String>[];
  for (final iface in interfaces) {
    for (final addr in iface.addresses) {
      if (_isPrivate(addr.address)) out.add(addr.address);
    }
  }
  return out;
}
