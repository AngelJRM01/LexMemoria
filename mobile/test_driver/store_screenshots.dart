import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      const allowed = [
        '01-inicio',
        '02-biblioteca',
        '03-articulo',
        '04-tarjeta',
        '05-respuesta'
      ];
      if (!allowed.contains(name) ||
          bytes.length < 8 ||
          bytes[0] != 137 ||
          bytes[1] != 80 ||
          bytes[2] != 78 ||
          bytes[3] != 71) {
        return false;
      }
      final root = Directory('../docs/release-1.0/screenshots');
      await root.create(recursive: true);
      await File('${root.path}/$name.png').writeAsBytes(bytes, flush: true);
      return true;
    });
