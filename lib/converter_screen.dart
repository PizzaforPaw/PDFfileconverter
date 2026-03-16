// converter_screen.dart
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:doc_scan_flutter/doc_scan.dart';

import 'doc_utils.dart';
import 'select_file_screen.dart';

// ─────────────────────────────────────────────────────────────
//  FILE → PDF  CONVERTER SCREEN
// ─────────────────────────────────────────────────────────────
class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen>
    with SingleTickerProviderStateMixin {

  String?  _filePath;
  String?  _fileName;
  DocType  _docType       = DocType.unknown;
  String?  _outputPdfPath;
  bool     _isProcessing  = false;
  String   _status        = '';
  double   _progress      = 0;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _pulseAnim = Tween(begin: 0.95, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── File picker ──────────────────────────────────────────────
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx', 'xlsx', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    setState(() {
      _filePath      = path;
      _fileName      = result.files.single.name;
      _docType       = detectType(path);
      _outputPdfPath = null;
      _status        = '';
      _progress      = 0;
    });
  }

  // ── Camera scan ──────────────────────────────────────────────
  Future<void> _scanCamera() async {
    if (_isProcessing) return;
    try {
      final pages = await DocumentScanner.scan();
      if (pages == null || pages.isEmpty) return;
      setState(() {
        _filePath      = pages.first;
        _fileName      = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
        _docType       = DocType.image;
        _outputPdfPath = null;
        _status        = '';
        _progress      = 0;
      });
    } on Exception catch (e) {
      setState(() { _status = '❌ Scanner error: $e'; });
    }
  }

  // ── Conversion ───────────────────────────────────────────────
  // Runs on the main isolate — syncfusion/archive/xml/excel are
  // pure-Dart and need no native FFI. Spawning a separate isolate
  // crashes on iOS because objective_c.dylib is unavailable there.
  Future<void> _convert() async {
    if (_filePath == null) return;
    _pulseCtrl.repeat(reverse: true);
    setState(() {
      _isProcessing  = true;
      _outputPdfPath = null;
      _status        = 'Reading file…';
      _progress      = 0.15;
    });

    try {
      final bytes = await File(_filePath!).readAsBytes();
      setState(() { _status = 'Converting…'; _progress = 0.40; });

      final tmpDir  = await getTemporaryDirectory();
      final base    = _fileName!.replaceAll(RegExp(r'\.\w+$'), '');
      final outPath =
          '${tmpDir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      setState(() { _progress = 0.65; });

      final pdfBytes = await convertToPdfBytes(
        fileBytes: bytes,       // ← matches the named param in doc_utils.dart
        docType:   _docType,
      );

      await File(outPath).writeAsBytes(pdfBytes, flush: true);

      setState(() {
        _outputPdfPath = outPath;
        _status        = '✅ PDF ready!';
        _progress      = 1.0;
      });
    } catch (e) {
      setState(() { _status = '❌ $e'; _progress = 0; });
    } finally {
      _pulseCtrl.stop();
      _pulseCtrl.reset();
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _openPdf() async {
    if (_outputPdfPath != null) await OpenFile.open(_outputPdfPath);
  }

  // ─────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final accent = _docType != DocType.unknown
        ? docTypeColor(_docType)
        : const Color(0xFF3949AB);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('File → PDF Converter',
            style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE0E0E0)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // Supported type chips
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              children: [DocType.word, DocType.excel, DocType.image].map((t) {
                final c = docTypeColor(t);
                return Chip(
                  avatar: Icon(docTypeIcon(t), size: 14, color: c),
                  label: Text(docTypeLabel(t),
                      style: TextStyle(fontSize: 11, color: c)),
                  backgroundColor:
                      Color.fromRGBO(c.red, c.green, c.blue, 0.08),
                  side: BorderSide(
                      color: Color.fromRGBO(c.red, c.green, c.blue, 0.3)),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            // ── Source selector ──────────────────────────────────
            if (_filePath != null) ...[
              // Selected file card — tap to clear
              GestureDetector(
                onTap: _isProcessing
                    ? null
                    : () => setState(() {
                          _filePath      = null;
                          _fileName      = null;
                          _docType       = DocType.unknown;
                          _outputPdfPath = null;
                          _status        = '';
                          _progress      = 0;
                        }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 110,
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(accent.red, accent.green, accent.blue, 0.06),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accent, width: 1.8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Icon(docTypeIcon(_docType), size: 36, color: accent),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_fileName!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600, color: accent)),
                            const SizedBox(height: 4),
                            Text(
                              '${docTypeLabel(_docType)}  •  tap to change',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Color.fromRGBO(
                                      accent.red, accent.green, accent.blue, 0.6)),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.close, size: 18,
                          color: Color.fromRGBO(
                              accent.red, accent.green, accent.blue, 0.5)),
                    ]),
                  ),
                ),
              ),
            ] else ...[
              // Pick File button
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _isProcessing ? null : _pickFile,
                    child: Container(
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFFBDBDBD), width: 1.8),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_file,
                              size: 36, color: Color(0xFF3949AB)),
                          SizedBox(height: 8),
                          Text('Pick File',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF3949AB))),
                          SizedBox(height: 2),
                          Text('.docx  •  .xlsx  •  .jpg',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFFBDBDBD))),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Scan Document button
                Expanded(
                  child: GestureDetector(
                    onTap: _isProcessing ? null : _scanCamera,
                    child: Container(
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: const Color(0xFF00796B), width: 1.8),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt,
                              size: 36, color: Color(0xFF00796B)),
                          SizedBox(height: 8),
                          Text('Scan Document',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF00796B))),
                          SizedBox(height: 2),
                          Text('Take a photo → PDF',
                              style: TextStyle(
                                  fontSize: 10, color: Color(0xFFBDBDBD))),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),

              // ── Hồ sơ shortcut button ────────────────────────────
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                      builder: (_) => const SelectFileScreen()),
                ),
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: const Color(0xFF1565C0), width: 1.8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.folder_fill,
                          size: 20, color: Color(0xFF1565C0)),
                      SizedBox(width: 10),
                      Text('Hồ sơ cần ký',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              color: Color(0xFF1565C0))),
                      SizedBox(width: 6),
                      Icon(CupertinoIcons.chevron_right,
                          size: 14, color: Color(0xFF1565C0)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),

            // ── Convert button ───────────────────────────────────
            AnimatedBuilder(
              animation: _pulseAnim,
              builder: (_, child) => Transform.scale(
                  scale: _isProcessing ? _pulseAnim.value : 1.0,
                  child: child),
              child: FilledButton.icon(
                onPressed: (_filePath != null &&
                        _docType != DocType.unknown &&
                        !_isProcessing)
                    ? _convert
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _isProcessing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf),
                label: Text(
                  _isProcessing ? 'Converting…' : 'Convert to PDF',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ── Progress bar ─────────────────────────────────────
            if (_progress > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE0E0E0),
                  color: _outputPdfPath != null ? Colors.green : accent,
                ),
              ),
              const SizedBox(height: 8),
            ],

            if (_status.isNotEmpty)
              Text(_status,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: _status.startsWith('❌')
                          ? Colors.red
                          : const Color(0xFF757575))),

            // ── Open PDF button ──────────────────────────────────
            if (_outputPdfPath != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _openPdf,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.green, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.open_in_new, color: Colors.green),
                label: const Text('Open Generated PDF',
                    style: TextStyle(
                        color: Colors.green, fontWeight: FontWeight.bold)),
              ),
            ],

          ],
        ),
      ),
    );
  }
}