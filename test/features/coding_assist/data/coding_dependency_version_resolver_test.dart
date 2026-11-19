import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lmcode/features/coding_assist/data/coding_dependency_version_resolver.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('lmcode_deps_');
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('pubspec.lock から版を読む', () async {
    await File(p.join(temp.path, 'pubspec.lock')).writeAsString('''
packages:
  http:
    dependency: "direct main"
    description:
      name: http
      sha256: abc
      url: "https://pub.dev"
    source: hosted
    version: "1.2.2"
  path:
    dependency: transitive
    description:
      name: path
      sha256: def
      url: "https://pub.dev"
    source: hosted
    version: "1.9.0"
''');
    final resolved = await CodingDependencyVersionResolver(
      temp.path,
    ).resolve('http');
    expect(resolved?.version, '1.2.2');
    expect(resolved?.ecosystem, 'dart');
    expect(resolved?.sourceHint, 'pubspec.lock');
  });

  test('package_config の localRoot を優先する', () async {
    final pkgRoot = Directory(p.join(temp.path, 'pkg_http'));
    await pkgRoot.create(recursive: true);
    await File(p.join(pkgRoot.path, 'pubspec.yaml')).writeAsString('''
name: http
version: 1.3.0
''');
    final dartTool = Directory(p.join(temp.path, '.dart_tool'));
    await dartTool.create();
    final rootUri = Uri.file(pkgRoot.path).toString();
    await File(p.join(dartTool.path, 'package_config.json')).writeAsString('''
{
  "configVersion": 2,
  "packages": [
    {
      "name": "http",
      "rootUri": "$rootUri",
      "packageUri": "lib/"
    }
  ]
}
''');
    final resolved = await CodingDependencyVersionResolver(
      temp.path,
    ).resolve('http');
    expect(resolved?.localRoot, pkgRoot.path);
    expect(resolved?.version, '1.3.0');
    expect(resolved?.sourceHint, 'package_config');
  });

  test('package-lock.json から npm 版を読む', () async {
    await File(p.join(temp.path, 'package-lock.json')).writeAsString('''
{
  "packages": {
    "node_modules/lodash": {
      "version": "4.17.21"
    }
  }
}
''');
    final resolved = await CodingDependencyVersionResolver(
      temp.path,
    ).resolve('lodash', ecosystem: 'npm');
    expect(resolved?.version, '4.17.21');
    expect(resolved?.ecosystem, 'npm');
  });
}
