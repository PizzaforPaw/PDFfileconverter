import 'dart:convert';   // for utf8.decode
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:doc_scan_flutter/doc_scan.dart';

// ── FIX: hide Border because syncfusion exports its own Border class
//         which shadows Flutter's Border — causing the red squiggle
import 'package:syncfusion_flutter_pdf/pdf.dart' hide Border;

// Word (.docx) — a .docx is a ZIP containing XML
import 'package:archive/archive.dart'; // ^3.6.1  (NOT ^4.x)
import 'package:xml/xml.dart' as xml;  // ^5.0.2  (NOT ^6.x)

// Excel (.xlsx)
import 'package:excel/excel.dart' hide Border;     // ^4.0.6

void main() {
  // Free license: https://www.syncfusion.com/products/communitylicense
  // SyncfusionLicense.registerLicense('YOUR_KEY_HERE');
  runApp(const MyApp());
}

// ─────────────────────────────────────────────────────────────
//  FILE TYPE DETECTION
// ─────────────────────────────────────────────────────────────
enum DocType { word, excel, image, unknown }

DocType detectType(String path) {
  final ext = path.split('.').last.toLowerCase();
  if (['docx', 'doc'].contains(ext))               return DocType.word;
  if (['xlsx', 'xls'].contains(ext))               return DocType.excel;
  if (['jpg', 'jpeg', 'png', 'bmp'].contains(ext)) return DocType.image;
  return DocType.unknown;
}

String   docTypeLabel(DocType t) => { DocType.word: 'Word (.docx)', DocType.excel: 'Excel (.xlsx)', DocType.image: 'Image (.jpg/.png)', DocType.unknown: 'Unknown' }[t]!;
IconData docTypeIcon(DocType t)  => { DocType.word: Icons.description, DocType.excel: Icons.table_chart, DocType.image: Icons.image, DocType.unknown: Icons.help_outline }[t]!;
Color    docTypeColor(DocType t) => { DocType.word: const Color(0xFF1565C0), DocType.excel: const Color(0xFF2E7D32), DocType.image: const Color(0xFF6A1B9A), DocType.unknown: const Color(0xFF9E9E9E) }[t]!;

// ─────────────────────────────────────────────────────────────
//  ISOLATE PAYLOAD — plain/sendable only, no Flutter objects
// ─────────────────────────────────────────────────────────────
class _IsolatePayload {
  final SendPort  replyPort;
  final Uint8List fileBytes;
  final String    outputPath;
  final DocType   docType;
  const _IsolatePayload({
    required this.replyPort,
    required this.fileBytes,
    required this.outputPath,
    required this.docType,
  });
}

// ─────────────────────────────────────────────────────────────
//  ISOLATE ENTRY POINT — top-level function (required)
// ─────────────────────────────────────────────────────────────
Future<void> _convertInIsolate(_IsolatePayload p) async {
  try {
    List<int> pdfBytes;

    switch (p.docType) {

      // ── Word (.docx) → PDF ──────────────────────────────────
      case DocType.word:
        // 1. Unzip — .docx is a ZIP archive
        final archive  = ZipDecoder().decodeBytes(p.fileBytes);
        final docEntry = archive.files.firstWhere(
          (f) => f.name == 'word/document.xml',
          orElse: () => throw Exception('Not a valid .docx — word/document.xml missing'),
        );

        // 2. Decode as UTF-8
        final xmlStr = utf8.decode(docEntry.content as Uint8List);
        final xmlDoc = xml.XmlDocument.parse(xmlStr);

        // 3. Parse rich paragraphs — preserving bold, italic, size, color, alignment
        final docParas = <_DocPara>[];
        for (final paraNode in xmlDoc.findAllElements('w:p')) {

          // ── Paragraph-level properties (<w:pPr>) ──
          final pPr       = paraNode.findElements('w:pPr').firstOrNull;
          final jcVal     = pPr?.findElements('w:jc').firstOrNull
                              ?.getAttribute('w:val') ?? 'left';
          final styleVal  = pPr?.findElements('w:pStyle').firstOrNull
                              ?.getAttribute('w:val') ?? '';
          final spBefore  = double.tryParse(
              pPr?.findElements('w:spacing').firstOrNull
                  ?.getAttribute('w:before') ?? '0') ?? 0;
          final spAfter   = double.tryParse(
              pPr?.findElements('w:spacing').firstOrNull
                  ?.getAttribute('w:after') ?? '160') ?? 160;

          final alignment = switch (jcVal) {
            'center' => PdfTextAlignment.center,
            'right'  => PdfTextAlignment.right,
            'both'   => PdfTextAlignment.justify,
            _        => PdfTextAlignment.left,
          };

          // ── Run-level properties (<w:r> → <w:rPr>) ──
          final runs = <_DocRun>[];
          for (final runNode in paraNode.findAllElements('w:r')) {
            final rPr   = runNode.findElements('w:rPr').firstOrNull;
            final text  = runNode.findAllElements('w:t')
                .map((n) => n.children.whereType<xml.XmlText>().map((t) => t.value).join())
                .join();
            if (text.isEmpty) continue;

            // bold: <w:b/> present and not val="0"
            final bNode  = rPr?.findElements('w:b').firstOrNull;
            final bold   = bNode != null && bNode.getAttribute('w:val') != '0';

            // italic: <w:i/>
            final iNode  = rPr?.findElements('w:i').firstOrNull;
            final italic = iNode != null && iNode.getAttribute('w:val') != '0';

            // underline: <w:u w:val="single"/> (not "none")
            final uVal      = rPr?.findElements('w:u').firstOrNull?.getAttribute('w:val');
            final underline = uVal != null && uVal != 'none';

            // font size: <w:sz w:val="24"/> → 24 half-points = 12pt
            final szStr   = rPr?.findElements('w:sz').firstOrNull?.getAttribute('w:val');
            final rawSize = double.tryParse(szStr ?? '');
            double fontSize = rawSize != null ? rawSize / 2 : 0; // 0 = use para default

            // color: <w:color w:val="FF0000"/> 
            final colorHex = rPr?.findElements('w:color').firstOrNull?.getAttribute('w:val');
            PdfColor color = PdfColor(0, 0, 0);
            if (colorHex != null && colorHex.length == 6 && colorHex != 'auto') {
              color = PdfColor(
                int.parse(colorHex.substring(0, 2), radix: 16),
                int.parse(colorHex.substring(2, 4), radix: 16),
                int.parse(colorHex.substring(4, 6), radix: 16),
              );
            }

            // font family: <w:rFonts w:ascii="Times New Roman"/>
            // Try ascii first, fall back to hAnsi, then eastAsia
            final rFonts    = rPr?.findElements('w:rFonts').firstOrNull;
            final fontName  = rFonts?.getAttribute('w:ascii')
                           ?? rFonts?.getAttribute('w:hAnsi')
                           ?? rFonts?.getAttribute('w:eastAsia');
            final fontFamily = _mapFontFamily(fontName);

            runs.add(_DocRun(
              text:       text,
              bold:       bold,
              italic:     italic,
              underline:  underline,
              fontSize:   fontSize,
              color:      color,
              fontFamily: fontFamily,
            ));
          }

          if (runs.isEmpty) continue;

          // Heading styles → boost font size + bold
          bool isHeading = false;
          double headingSize = 0;
          if (styleVal.toLowerCase().startsWith('heading')) {
            isHeading = true;
            final level = int.tryParse(styleVal.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
            headingSize = switch (level) {
              1 => 20,
              2 => 16,
              3 => 14,
              _ => 13,
            };
          }

          docParas.add(_DocPara(
            runs:        runs,
            alignment:   alignment,
            spaceBefore: spBefore / 20, // twips → points
            spaceAfter:  spAfter  / 20,
            isHeading:   isHeading,
            headingSize: headingSize,
          ));
        }

        // 4. Render rich paragraphs → PDF
        pdfBytes = await _richDocToPdf(paragraphs: docParas);
        break;

      // ── Excel (.xlsx) → PDF ─────────────────────────────────
      case DocType.excel:
        final workbook = Excel.decodeBytes(p.fileBytes);
        final pdfDoc   = PdfDocument();
        final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
        final headFont = PdfStandardFont(PdfFontFamily.helvetica, 10,
            style: PdfFontStyle.bold);

        for (final sheetName in workbook.tables.keys) {
          final sheet = workbook.tables[sheetName]!;
          if (sheet.rows.isEmpty) continue;

          final page  = pdfDoc.pages.add();
          final pageW = page.getClientSize().width;
          final pageH = page.getClientSize().height;

          // Sheet title
          page.graphics.drawString(
            'Sheet: $sheetName',
            PdfStandardFont(PdfFontFamily.helvetica, 13,
                style: PdfFontStyle.bold),
            brush: PdfSolidBrush(PdfColor(33, 33, 33)),
            bounds: Rect.fromLTWH(0, 0, pageW, 22),
          );

          // Column count
          int maxCols = 0;
          for (final row in sheet.rows) {
            if (row.length > maxCols) maxCols = row.length;
          }
          if (maxCols == 0) continue;

          // Build PdfGrid table
          final grid = PdfGrid();
          grid.style.font = bodyFont;
          grid.columns.add(count: maxCols);

          bool isHeader = true;
          for (final row in sheet.rows) {
            final gridRow = grid.rows.add();
            for (int c = 0; c < maxCols; c++) {
              final cell  = c < row.length ? row[c] : null;
              final value = cell?.value?.toString() ?? '';
              gridRow.cells[c].value = value;
              if (isHeader) {
                gridRow.cells[c].style.font = headFont;
                gridRow.cells[c].style.backgroundBrush =
                    PdfSolidBrush(PdfColor(220, 230, 255));
              }
            }
            isHeader = false;
          }

          grid.draw(
            page:   page,
            bounds: Rect.fromLTWH(0, 28, pageW, pageH - 28),
          );
        }

        pdfBytes = await pdfDoc.save();
        pdfDoc.dispose();
        break;

      // ── Image (.jpg / .png) → PDF ───────────────────────────
      case DocType.image:
        final pdfDoc = PdfDocument();
        final page   = pdfDoc.pages.add();
        final image  = PdfBitmap(p.fileBytes);

        final double pageW = page.getClientSize().width;
        final double pageH = page.getClientSize().height;
        final double imgW  = image.width.toDouble();
        final double imgH  = image.height.toDouble();
        final double scale = (imgW / pageW > imgH / pageH)
            ? pageW / imgW
            : pageH / imgH;

        page.graphics.drawImage(
          image,
          Rect.fromLTWH(0, 0, imgW * scale, imgH * scale),
        );

        pdfBytes = await pdfDoc.save();
        pdfDoc.dispose();
        break;

      default:
        throw UnsupportedError('Unsupported file type: ${p.docType}');
    }

    await File(p.outputPath).writeAsBytes(pdfBytes, flush: true);
    p.replyPort.send({'success': true, 'path': p.outputPath});

  } catch (e, stack) {
    p.replyPort.send({
      'success': false,
      'error':   e.toString(),
      'stack':   stack.toString(),
    });
  }
}

// ─────────────────────────────────────────────────────────────
//  Rich document data models
// ─────────────────────────────────────────────────────────────

/// A single text run inside a paragraph — carries its own formatting
class _DocRun {
  final String         text;
  final bool           bold;
  final bool           italic;
  final bool           underline;
  final double         fontSize;      // 0 = inherit from paragraph
  final PdfColor       color;
  final PdfFontFamily  fontFamily;    // mapped from Word font name

  const _DocRun({
    required this.text,
    required this.bold,
    required this.italic,
    required this.underline,
    required this.fontSize,
    required this.color,
    required this.fontFamily,
  });
}

// ─────────────────────────────────────────────────────────────
//  Font name → PdfFontFamily mapper
//
//  PdfStandardFont supports only 3 useful families:
//    helvetica  → sans-serif  (Arial, Calibri, Tahoma, Verdana …)
//    timesRoman → serif       (Times New Roman, Georgia, Garamond …)
//    courier    → monospace   (Courier New, Consolas, Lucida Console …)
//
//  Everything else falls back to helvetica.
// ─────────────────────────────────────────────────────────────
PdfFontFamily _mapFontFamily(String? name) {
  if (name == null || name.isEmpty) return PdfFontFamily.helvetica;
  final n = name.toLowerCase();

  // Monospace fonts
  if (n.contains('courier') || n.contains('consolas') ||
      n.contains('mono')    || n.contains('lucida console') ||
      n.contains('menlo')   || n.contains('source code'))
    return PdfFontFamily.courier;

  // Serif fonts
  if (n.contains('times')   || n.contains('georgia') ||
      n.contains('garamond') || n.contains('palatino') ||
      n.contains('cambria')  || n.contains('book antiqua') ||
      n.contains('serif'))
    return PdfFontFamily.timesRoman;

  // Everything else → sans-serif (helvetica)
  return PdfFontFamily.helvetica;
}

/// A paragraph with alignment, spacing, and a list of runs
class _DocPara {
  final List<_DocRun>    runs;
  final PdfTextAlignment alignment;
  final double           spaceBefore;
  final double           spaceAfter;
  final bool             isHeading;
  final double           headingSize;

  const _DocPara({
    required this.runs,
    required this.alignment,
    required this.spaceBefore,
    required this.spaceAfter,
    required this.isHeading,
    required this.headingSize,
  });
}

// ─────────────────────────────────────────────────────────────
//  Helper: render rich paragraphs into a PDF
//  Preserves bold, italic, underline, font size, color, alignment
// ─────────────────────────────────────────────────────────────
Future<List<int>> _richDocToPdf({
  required List<_DocPara> paragraphs,
}) async {
  const double margin      = 40;
  const double defaultSize = 11;
  const double minLineH    = 14;

  final pdfDoc = PdfDocument();

  PdfPage     page  = pdfDoc.pages.add();
  PdfGraphics g     = page.graphics;
  double      pageW = page.getClientSize().width  - margin * 2;
  double      pageH = page.getClientSize().height;
  double      y     = margin;

  // ── Font cache — avoid creating duplicate font objects ──
  final fontCache = <String, PdfFont>{};

  // Returns the best available font for the given family + style.
  // PdfStandardFont has no boldItalic variant, so bold+italic uses bold.
  // We simulate italic visually via a separate skewed draw pass (see below).
  PdfFont getFont(
    double size, {
    bool bold   = false,
    bool italic = false,
    PdfFontFamily family = PdfFontFamily.helvetica,
  }) {
    final key = '${family.index}_${size}_${bold}_$italic';
    return fontCache.putIfAbsent(key, () {
      final style = bold   ? PdfFontStyle.bold
                  : italic ? PdfFontStyle.italic
                  :          PdfFontStyle.regular;
      return PdfStandardFont(family, size, style: style);
    });
  }

  void ensureSpace(double needed) {
    if (y + needed > pageH - margin) {
      page  = pdfDoc.pages.add();
      g     = page.graphics;
      y     = margin;
    }
  }

  for (final para in paragraphs) {
    y += para.spaceBefore;

    // Determine the dominant font size for this paragraph
    // (used for line height and when a run has fontSize == 0)
    double paraFontSize = defaultSize;
    if (para.isHeading) {
      paraFontSize = para.headingSize;
    } else {
      // Use the largest explicit size among runs, fallback to default
      for (final r in para.runs) {
        if (r.fontSize > paraFontSize) paraFontSize = r.fontSize;
      }
    }
    final lineH = (paraFontSize * 1.4).clamp(minLineH, 60.0);

    ensureSpace(lineH);

    // ── Render runs left-to-right, word-wrapping as needed ──
    // We buffer a line's worth of (run, text, width) triples.
    // width is pre-calculated including space so the draw pass
    // never needs to re-measure (measureString strips trailing spaces).
    final lineParts = <({String text, _DocRun run, double width})>[];
    double lineWidth = 0;

    void flushLine({bool isLast = false}) {
      if (lineParts.isEmpty) return;
      ensureSpace(lineH);

      // Use pre-stored widths for alignment — avoids re-measuring
      // (measureString strips trailing spaces, so re-measuring loses space width)
      final totalW = lineParts.fold(0.0, (sum, p) => sum + p.width);

      double xOffset = switch (para.alignment) {
        PdfTextAlignment.center  => (pageW - totalW) / 2,
        PdfTextAlignment.right   => pageW - totalW,
        PdfTextAlignment.justify => 0,
        _                        => 0,
      };
      xOffset = xOffset.clamp(0, pageW);

      double x = margin + xOffset;
      for (final part in lineParts) {
        final sz    = part.run.fontSize > 0 ? part.run.fontSize : paraFontSize;
        final fnt   = getFont(sz,
            bold:   part.run.bold || para.isHeading,
            italic: part.run.italic,
            family: part.run.fontFamily);
        final brush = PdfSolidBrush(part.run.color);

        // Draw the text (trailing space in part.text is fine — PDF ignores it visually)
        g.drawString(part.text, fnt,
            brush:  brush,
            bounds: Rect.fromLTWH(x, y, part.width + 2, lineH),
            format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.middle));

        // Underline
        if (part.run.underline) {
          g.drawLine(
            PdfPen(part.run.color, width: 0.5),
            Offset(x, y + lineH - 2),
            Offset(x + part.width, y + lineH - 2),
          );
        }

        // ✅ Advance by pre-calculated width (includes space) — not re-measured
        x += part.width;
      }
      y += lineH;
      lineParts.clear();
      lineWidth = 0;
    }

    // Split each run into words and word-wrap.
    //
    // ROOT CAUSE OF MISSING SPACES:
    // Word stores spaces as separate runs: <w:t xml:space="preserve"> </w:t>
    // " ".split(' ') → ["", ""] — all empty strings → all skipped → space lost.
    //
    // FIX: detect whitespace-only runs and emit a space token directly
    // instead of going through split().
    //
    // Also: measureString() in Syncfusion strips trailing spaces, so we
    // compute true space width via: measure("a a") - measure("aa").
    for (final run in para.runs) {
      final sz  = run.fontSize > 0 ? run.fontSize : paraFontSize;
      final fnt = getFont(sz,
          bold:   run.bold || para.isHeading,
          italic: run.italic,
          family: run.fontFamily);

      // True space width for this specific font & size
      final spaceW = fnt.measureString('a a').width -
                     fnt.measureString('aa').width;

      // ── Case 1: whitespace-only run (e.g. " " between words in Word) ──
      // split() would turn this into ["",""] and skip everything.
      // Instead, count the spaces and emit them directly.
      if (run.text.trim().isEmpty) {
        final spaces = run.text.length; // how many spaces Word stored
        for (int s = 0; s < spaces; s++) {
          if (lineWidth + spaceW > pageW && lineParts.isNotEmpty) {
            flushLine();
          }
          lineParts.add((text: ' ', run: run, width: spaceW));
          lineWidth += spaceW;
        }
        continue;
      }

      // ── Case 2: normal text run — split into words for wrapping ──
      final words = run.text.split(' ');
      for (int wi = 0; wi < words.length; wi++) {
        final word = words[wi];

        // An empty token means there was a space in the original text
        // (e.g. "hello world".split(' ') → ["hello", "world"] — the space
        // between them is implicitly a separator we re-add below).
        // A fully empty split artifact (start/end of string) we skip.
        if (word.isEmpty) {
          // This was an inter-word space inside the run — emit it
          if (wi > 0 && wi < words.length - 1) {
            lineParts.add((text: ' ', run: run, width: spaceW));
            lineWidth += spaceW;
          }
          continue;
        }

        // Word token — always append a trailing space so the next word
        // (or run) doesn't collide. measureString trims spaces so we
        // account for it manually in wordW.
        final token = '$word ';
        final wordW = fnt.measureString(word).width + spaceW;

        if (lineWidth + wordW > pageW && lineParts.isNotEmpty) {
          flushLine();
        }
        lineParts.add((text: token, run: run, width: wordW));
        lineWidth += wordW;
      }
    }
    flushLine(isLast: true);

    y += para.spaceAfter.clamp(0, 20);
  }

  final bytes = await pdfDoc.save();
  pdfDoc.dispose();
  return bytes;
}

// ─────────────────────────────────────────────────────────────
//  APP
// ─────────────────────────────────────────────────────────────
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'File → PDF',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const ConverterScreen(),
      );
}

// ─────────────────────────────────────────────────────────────
//  MAIN SCREEN
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

  Future<void> _scanCamera() async {
    if (_isProcessing) return;

    try {
      // doc_scan_flutter uses Apple VisionKit on iOS —
      // opens camera, detects edges automatically, crops and
      // perspective-corrects with zero user interaction needed.
      // DocumentScanner.scan() uses VisionKit on iOS —
      // auto edge detection + perspective correction, no manual cropping needed
      final pages = await DocumentScanner.scan();

      if (pages == null || pages.isEmpty) return; // user cancelled

      final path = pages.first;

      setState(() {
        _filePath      = path;
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

  void _showPermissionDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Camera Permission Required'),
        content: const Text(
          'This app needs camera access to scan documents.\n\n'
          'Please go to Settings → Privacy → Camera and enable access for this app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // On iOS/Android this does nothing — user must go to Settings manually.
              // If you add the permission_handler package you can call
              // openAppSettings() here instead.
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  Future<void> _convert() async {
    if (_filePath == null) return;
    _pulseCtrl.repeat(reverse: true); // start pulse only during conversion
    setState(() {
      _isProcessing  = true;
      _outputPdfPath = null;
      _status        = 'Reading file…';
      _progress      = 0.15;
    });

    try {
      final bytes = await File(_filePath!).readAsBytes();
      setState(() { _status = 'Spawning isolate…'; _progress = 0.35; });

      final tmpDir  = await getTemporaryDirectory();
      final base    = _fileName!.replaceAll(RegExp(r'\.\w+$'), '');
      final outPath =
          '${tmpDir.path}/${base}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final receivePort = ReceivePort();

      await Isolate.spawn(
        _convertInIsolate,
        _IsolatePayload(
          replyPort:  receivePort.sendPort,
          fileBytes:  bytes,
          outputPath: outPath,
          docType:    _docType,
        ),
        debugName: 'FileToPdfIsolate',
      );

      setState(() {
        _status   = 'Converting in background isolate…';
        _progress = 0.65;
      });

      final result = await receivePort.first as Map<String, dynamic>;
      receivePort.close();

      if (result['success'] == true) {
        setState(() {
          _outputPdfPath = result['path'] as String;
          _status        = '✅ PDF ready!';
          _progress      = 1.0;
        });
      } else {
        setState(() { _status = '❌ ${result['error']}'; _progress = 0; });
      }
    } catch (e) {
      setState(() { _status = '❌ $e'; _progress = 0; });
    } finally {
      _pulseCtrl.stop();
      _pulseCtrl.reset(); // stop pulse when done
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _openPdf() async {
    if (_outputPdfPath != null) await OpenFile.open(_outputPdfPath);
  }

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
              children: [DocType.word, DocType.excel, DocType.image]
                  .map((t) {
                    // Cache color — called once per chip, not 4x
                    final c = docTypeColor(t);
                    return Chip(
                      avatar: Icon(docTypeIcon(t), size: 14, color: c),
                      label: Text(docTypeLabel(t),
                          style: TextStyle(fontSize: 11, color: c)),
                      backgroundColor: Color.fromRGBO(c.red, c.green, c.blue, 0.08),
                      side: BorderSide(color: Color.fromRGBO(c.red, c.green, c.blue, 0.3)),
                      visualDensity: VisualDensity.compact,
                    );
                  })
                  .toList(),
            ),
            const SizedBox(height: 20),

            // ── Source selector: file or camera ──────────────────────
            // Shows selected file info if a file is already chosen,
            // otherwise shows the two source buttons side by side.
            if (_filePath != null) ...[
              // Selected file card — tap to clear and pick again
              GestureDetector(
                onTap: _isProcessing ? null : () => setState(() {
                  _filePath = null; _fileName = null;
                  _docType = DocType.unknown;
                  _outputPdfPath = null; _status = ''; _progress = 0;
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
                    child: Row(
                      children: [
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
                                      fontWeight: FontWeight.w600,
                                      color: accent)),
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
                            color: Color.fromRGBO(accent.red, accent.green, accent.blue, 0.5)),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              // Two source buttons — pick file  |  scan with camera
              Row(
                children: [
                  // ── Pick from files ────────────────────────────────────
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
                  // ── Scan with camera ───────────────────────────────────
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
                ],
              ),
            ],
            const SizedBox(height: 16),

            // Convert button
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
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf),
                label: Text(
                  _isProcessing
                      ? 'Converting in isolate…'
                      : 'Convert to PDF',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Progress bar
            if (_progress > 0) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFE0E0E0),
                  color: _outputPdfPath != null
                      ? Colors.green
                      : accent,
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

            // Open PDF button
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
                        color: Colors.green,
                        fontWeight: FontWeight.bold)),
              ),
            ],

          ],
        ),
      ),
    );
  }

}