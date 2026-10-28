import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/coding_swift_launch.dart';
import 'sourcekit_toolchain.dart';

/// ワークスペース直下の `.xcodeproj` / `Package.swift` を見る。
CodingSwiftRootPlan inspectSwiftWorkspaceRoot(String root) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const CodingSwiftRootPlan.inactive();
  final projects = <String>[];
  var hasPackage = false;
  for (final entity in dir.listSync(followLinks: false)) {
    final name = p.basename(entity.path);
    if (name.endsWith('.xcodeproj') && entity is Directory) {
      projects.add(name);
    } else if (name == 'Package.swift' && entity is File) {
      hasPackage = true;
    }
  }
  return CodingSwiftRootPlan.from(
    xcodeprojNames: projects,
    hasPackageSwift: hasPackage,
  );
}

class XcodeIndexSettings {
  const XcodeIndexSettings({
    required this.schemes,
    required this.compilerArguments,
  });

  final List<String> schemes;

  /// 空なら索引設定を取っていない（スキームが1つでない、または取得失敗）。
  final Map<String, List<String>> compilerArguments;

  bool get loaded => compilerArguments.isNotEmpty;
}

/// スキームが1つのときだけ `showBuildSettingsForIndex` を実行する。
Future<XcodeIndexSettings?> loadXcodeIndexSettings({
  required SourceKitToolchain toolchain,
  required String projectPath,
}) async {
  final listed = await _run(
    toolchain,
    [
      '-list',
      '-json',
      '-project',
      projectPath,
    ],
  );
  if (listed == null) return null;
  final schemes = codingSwiftSchemes(listed);
  if (schemes.length != 1) {
    return XcodeIndexSettings(schemes: schemes, compilerArguments: const {});
  }
  const destinations = <String>[
    'platform=macOS,arch=arm64',
    'generic/platform=macOS',
  ];
  for (final destination in destinations) {
    final raw = await _run(
      toolchain,
      [
        '-project',
        projectPath,
        '-scheme',
        schemes.single,
        '-destination',
        destination,
        '-showBuildSettingsForIndex',
      ],
    );
    if (raw == null) continue;
    final args = codingSwiftCompilerArguments(raw);
    if (args.isNotEmpty) {
      return XcodeIndexSettings(schemes: schemes, compilerArguments: args);
    }
  }
  return XcodeIndexSettings(schemes: schemes, compilerArguments: const {});
}

Future<String?> _run(SourceKitToolchain toolchain, List<String> args) async {
  try {
    final result = await Process.run(
      toolchain.xcodebuild,
      args,
      environment: toolchain.environment,
    ).timeout(const Duration(seconds: 90));
    final stdout = result.stdout;
    if (stdout is! String || !stdout.contains('{')) return null;
    if (result.exitCode != 0 && stdout.trim().isEmpty) return null;
    return stdout;
  } catch (_) {
    return null;
  }
}

/// sourcekit-lsp が起動する BSP。索引引数を temp に書き、`buildServer.json` は無いときだけ作る。
class SwiftBuildServerFiles {
  SwiftBuildServerFiles._({
    required this.buildServerPath,
    required this.ownedBuildServer,
    required this.writtenBuildServer,
  });

  final String buildServerPath;
  final bool ownedBuildServer;
  final String? writtenBuildServer;

  static const _scriptName = 'lmcode_swift_bsp.py';

  static Future<SwiftBuildServerFiles?> install({
    required String workspaceRoot,
    required Map<String, List<String>> compilerArguments,
  }) async {
    final python = await _python3();
    if (python == null) return null;
    final dir = Directory(
      p.join(Directory.systemTemp.path, 'lmcode_swift_bsp'),
    );
    await dir.create(recursive: true);
    final script = File(p.join(dir.path, _scriptName));
    final index = File(p.join(dir.path, 'index.json'));
    await script.writeAsString(_bspScript);
    await index.writeAsString(jsonEncode(compilerArguments));

    final buildServerPath = p.join(workspaceRoot, 'buildServer.json');
    final buildServer = File(buildServerPath);
    if (buildServer.existsSync()) {
      return SwiftBuildServerFiles._(
        buildServerPath: buildServerPath,
        ownedBuildServer: false,
        writtenBuildServer: null,
      );
    }
    final body = const JsonEncoder.withIndent('  ').convert({
      'name': 'lmcode-sourcekit',
      'version': '0.1',
      'bspVersion': '2.2.0',
      'languages': ['swift'],
      'argv': [python, script.path, index.path, workspaceRoot],
    });
    await buildServer.writeAsString('$body\n');
    return SwiftBuildServerFiles._(
      buildServerPath: buildServerPath,
      ownedBuildServer: true,
      writtenBuildServer: '$body\n',
    );
  }

  /// アプリが書いた `buildServer.json` だけ消す。
  Future<void> removeOwnedBuildServer() async {
    if (!ownedBuildServer || writtenBuildServer == null) return;
    final file = File(buildServerPath);
    if (!file.existsSync()) return;
    try {
      final current = await file.readAsString();
      if (current == writtenBuildServer) {
        await file.delete();
      }
    } catch (_) {}
  }
}

Future<String?> _python3() async {
  const candidates = ['/usr/bin/python3', '/opt/homebrew/bin/python3'];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  try {
    final result = await Process.run('which', ['python3']);
    if (result.exitCode != 0) return null;
    final line = (result.stdout as String)
        .split('\n')
        .map((e) => e.trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
    if (line.isEmpty || !File(line).existsSync()) return null;
    return line;
  } catch (_) {
    return null;
  }
}

const _bspScript = r'''
import json
import sys
from urllib.parse import unquote, urlparse

INDEX = json.load(open(sys.argv[1], encoding="utf-8"))
ROOT = sys.argv[2]
TARGET = "build://lmcode/swift"


def uri_path(uri):
    if not isinstance(uri, str) or not uri.startswith("file://"):
        return ""
    return unquote(urlparse(uri).path)


def read_message():
    headers = {}
    while True:
        line = sys.stdin.buffer.readline()
        if not line:
            return None
        if line in (b"\r\n", b"\n"):
            break
        key, value = line.decode("ascii", "replace").split(":", 1)
        headers[key.strip().lower()] = value.strip()
    length = int(headers.get("content-length", "0"))
    body = sys.stdin.buffer.read(length)
    if len(body) < length:
        return None
    return json.loads(body.decode("utf-8"))


def send(payload):
    raw = json.dumps(payload).encode("utf-8")
    sys.stdout.buffer.write(
        ("Content-Length: %d\r\n\r\n" % len(raw)).encode("ascii") + raw
    )
    sys.stdout.buffer.flush()


def reply(msg, value):
    send({"jsonrpc": "2.0", "id": msg["id"], "result": value})


def sources():
    return [
        {"uri": "file://" + path, "kind": 1, "generated": False}
        for path in INDEX
    ]


def handle(msg):
    method = msg.get("method")
    if "id" not in msg:
        return
    if method == "build/initialize":
        reply(
            msg,
            {
                "displayName": "lmcode",
                "version": "0.1",
                "bspVersion": "2.2.0",
                "capabilities": {},
                "dataKind": "sourceKit",
                "data": {"sourceKitOptionsProvider": True},
            },
        )
        return
    if method == "workspace/buildTargets":
        reply(
            msg,
            {
                "targets": [
                    {
                        "id": {"uri": TARGET},
                        "displayName": "swift",
                        "baseDirectory": "file://" + ROOT,
                        "tags": ["application"],
                        "capabilities": {"canCompile": True},
                        "languageIds": ["swift"],
                        "dependencies": [],
                    }
                ]
            },
        )
        return
    if method == "buildTarget/sources":
        reply(msg, {"items": [{"target": {"uri": TARGET}, "sources": sources()}]})
        return
    if method in (
        "textDocument/sourceKitOptions",
        "sourcekit/textDocument/sourceKitOptions",
    ):
        params = msg.get("params") or {}
        text = params.get("textDocument") or {}
        path = uri_path(text.get("uri"))
        args = INDEX.get(path)
        if not isinstance(args, list):
            reply(msg, None)
            return
        reply(
            msg,
            {"compilerArguments": args, "workingDirectory": ROOT},
        )
        return
    reply(msg, None)


def main():
    while True:
        msg = read_message()
        if msg is None:
            return
        try:
            handle(msg)
        except Exception as exc:
            if "id" in msg:
                send(
                    {
                        "jsonrpc": "2.0",
                        "id": msg["id"],
                        "error": {"code": -32603, "message": str(exc)},
                    }
                )


if __name__ == "__main__":
    main()
''';
