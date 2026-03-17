// create_document_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:doc_scan_flutter/doc_scan.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' hide Border;

// ─────────────────────────────────────────────────────────────
//  Result returned to SelectFileScreen
// ─────────────────────────────────────────────────────────────
class CreateDocumentResult {
  final String pdfPath;
  final String fileName;
  final int    sizeBytes;
  const CreateDocumentResult({
    required this.pdfPath,
    required this.fileName,
    required this.sizeBytes,
  });
}

// ─────────────────────────────────────────────────────────────
//  Page model
// ─────────────────────────────────────────────────────────────
enum _PageType { image, blankPortrait, blankLandscape }

class _PageItem {
  final String    path;
  final String    name;
  final _PageType type;
  const _PageItem({required this.path, required this.name, required this.type});
}

// ─────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────
class CreateDocumentScreen extends StatefulWidget {
  const CreateDocumentScreen({super.key});
  @override
  State<CreateDocumentScreen> createState() => _CreateDocumentScreenState();
}

class _CreateDocumentScreenState extends State<CreateDocumentScreen> {
  static const Color _blue   = Color(0xFF1565C0);
  static const Color _bgPage = Color(0xFFF0F2F5);

  final List<_PageItem> _pages    = [];
  final PageController  _pageCtrl = PageController();
  int    _currentPage = 0;
  double _brightness  = 50; // 0-100, neutral = 50
  bool   _isCreating  = false;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  // ─────────────────── brightness → ColorMatrix ─────────────
  ColorFilter _brightnessFilter() {
    final s = (_brightness / 50.0).clamp(0.0, 2.0);
    return ColorFilter.matrix([
      s, 0, 0, 0, 0,
      0, s, 0, 0, 0,
      0, 0, s, 0, 0,
      0, 0, 0, 1, 0,
    ]);
  }

  // ─────────────────── "Thêm trang" bottom sheet ────────────
  void _showAddPageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFF5F5F5),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          // drag handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFBDBDBD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 4),

          _SheetTile(
            icon: Icons.camera_alt_outlined,
            label: 'Thêm hình từ máy ảnh',
            onTap: () { Navigator.pop(context); _addFromCamera(); },
          ),
          const Divider(height: 1, indent: 68),
          _SheetTile(
            icon: Icons.photo_library_outlined,
            label: 'Chọn hình từ thư viện',
            onTap: () { Navigator.pop(context); _addFromGallery(); },
          ),

          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 6),

          _SheetTile(
            icon: Icons.crop_portrait,
            label: 'Thêm trang trắng dọc',
            onTap: () { Navigator.pop(context); _addBlankPage(portrait: true); },
          ),
          const Divider(height: 1, indent: 68),
          _SheetTile(
            icon: Icons.crop_landscape,
            label: 'Thêm trang trắng ngang',
            onTap: () { Navigator.pop(context); _addBlankPage(portrait: false); },
          ),

          const SizedBox(height: 6),
          const Divider(height: 1),
          const SizedBox(height: 6),

          _SheetTile(
            icon: Icons.exit_to_app,
            label: 'Đóng',
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ─────────────────── "Tùy chỉnh" sheet ────────────────────
  void _showCustomizeSheet() {
    String pdfSize  = 'Dọc';
    final  nameCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── title row ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                child: Row(children: [
                  const Expanded(
                    child: Text('Tùy chỉnh',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // ── PDF size ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Expanded(
                    child: Text('Chọn khổ PDF',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                  ),
                  DropdownButton<String>(
                    value: pdfSize,
                    underline: Container(height: 1, color: Colors.grey),
                    items: ['Dọc', 'Ngang']
                        .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v,
                                style: const TextStyle(fontSize: 15))))
                        .toList(),
                    onChanged: (v) => setSheet(() => pdfSize = v ?? pdfSize),
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // ── Filename ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Text('Tên tập tin',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 20),
                  Expanded(
                    child: TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: 'Nhập tên tập tin',
                        isDense: true,
                        border: UnderlineInputBorder(),
                        focusedBorder: UnderlineInputBorder(
                          borderSide:
                              BorderSide(color: Color(0xFF1565C0), width: 2),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),

              // ── Confirm ──
              GestureDetector(
                onTap: () {
                  final name = nameCtrl.text.trim().isEmpty
                      ? 'document'
                      : nameCtrl.text.trim();
                  Navigator.pop(ctx);
                  _createPdf(isPortrait: pdfSize == 'Dọc', name: name);
                },
                child: Container(
                  color: Colors.black,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: const Center(
                    child: Text('Tạo hồ sơ',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────── Create PDF ───────────────────────────
  Future<void> _createPdf(
      {required bool isPortrait, required String name}) async {
    setState(() => _isCreating = true);
    try {
      final pdfDoc = PdfDocument();
      final brightnessVal = (_brightness / 50.0).clamp(0.0, 2.0);

      for (final item in _pages) {
        final page  = pdfDoc.pages.add();
        final pageW = page.getClientSize().width;
        final pageH = page.getClientSize().height;

        if (item.type == _PageType.image && item.path.isNotEmpty) {
          final rawBytes = await File(item.path).readAsBytes();
          final img      = PdfBitmap(rawBytes);
          final imgW     = img.width.toDouble();
          final imgH     = img.height.toDouble();
          final scale    = (imgW / pageW > imgH / pageH)
              ? pageW / imgW
              : pageH / imgH;
          page.graphics.drawImage(
              img, Rect.fromLTWH(0, 0, imgW * scale, imgH * scale));
        }
        // Blank pages: nothing drawn — white page
      }

      final tmpDir  = await getTemporaryDirectory();
      final outPath = '${tmpDir.path}/$name.pdf';
      final savedBytes = await pdfDoc.save();
      final bytes      = savedBytes is Uint8List
          ? savedBytes
          : Uint8List.fromList(savedBytes);
      pdfDoc.dispose();
      await File(outPath).writeAsBytes(bytes, flush: true);

      // Open immediately so user can preview
      await OpenFile.open(outPath);

      if (mounted) {
        Navigator.pop(
          context,
          CreateDocumentResult(
            pdfPath:   outPath,
            fileName:  '$name.pdf',
            sizeBytes: bytes.length,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi tạo PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  // ─────────────────── Add pages ────────────────────────────
  Future<void> _addFromCamera() async {
    try {
      final pages = await DocumentScanner.scan();
      if (pages == null || pages.isEmpty) return;
      setState(() {
        for (final path in pages) {
          _pages.add(_PageItem(
              path: path,
              name: path.split('/').last,
              type: _PageType.image));
        }
      });
      _jumpToLast();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi máy ảnh: $e')));
      }
    }
  }

  Future<void> _addFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'docx'],
    );
    if (result == null) return;
    setState(() {
      for (final f in result.files) {
        if (f.path != null) {
          _pages.add(
              _PageItem(path: f.path!, name: f.name, type: _PageType.image));
        }
      }
    });
    _jumpToLast();
  }

  void _addBlankPage({required bool portrait}) {
    setState(() => _pages.add(_PageItem(
          path: '',
          name: portrait ? 'Trang trắng dọc' : 'Trang trắng ngang',
          type: portrait ? _PageType.blankPortrait : _PageType.blankLandscape,
        )));
    _jumpToLast();
  }

  void _jumpToLast() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients && _pages.length > 1) {
        _pageCtrl.animateToPage(
          _pages.length - 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────── BUILD ─────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_isCreating) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
        body: const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(color: Color(0xFF1565C0)),
            SizedBox(height: 16),
            Text('Đang tạo hồ sơ...', style: TextStyle(fontSize: 15)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(children: [
        // ── Preview area ─────────────────────────────────────
        Expanded(
          child: _pages.isEmpty
              ? Container(color: _bgPage) // light grey, no dim
              : Container(
                  color: _bgPage,
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _pages.length,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    itemBuilder: (_, i) => _buildPageView(i),
                  ),
                ),
        ),

        // ── Bottom panel ─────────────────────────────────────
        Container(
          color: Colors.white,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Brightness slider — visible only when there are image pages
            if (_pages.any((p) => p.type == _PageType.image))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(children: [
                  const Text('Độ sáng',
                      style:
                          TextStyle(fontSize: 14, color: Color(0xFF424242))),
                  Expanded(
                    child: Slider(
                      value: _brightness,
                      min: 0,
                      max: 100,
                      activeColor: _blue,
                      onChanged: (v) => setState(() => _brightness = v),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(
                      _brightness.round().toString(),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF424242)),
                    ),
                  ),
                ]),
              ),

            // Dashed "Thêm trang"
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16,
                  _pages.any((p) => p.type == _PageType.image) ? 8 : 16,
                  16,
                  0),
              child: GestureDetector(
                onTap: _showAddPageSheet,
                child: Container(
                  width: double.infinity,
                  height: 90,
                  decoration: BoxDecoration(
                    color: _bgPage,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DashedBorderPainter(
                            color: const Color(0xFF42A5F5), radius: 12),
                      ),
                    ),
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Center(
                          child: Icon(Icons.add_box_outlined,
                              size: 30, color: Color(0xFF42A5F5)),
                        ),
                        SizedBox(height: 4),
                        Text('Thêm trang',
                            style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF757575),
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ]),
                ),
              ),
            ),

            // Black "Tạo hồ sơ"
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pages.isEmpty ? null : _showCustomizeSheet,
              child: Container(
                color: Colors.black,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: const Center(
                  child: Text('Tạo hồ sơ',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text('Chọn hình (${_pages.length})',
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      );

  // ── Full-screen page with badge + delete ──────────────────
  Widget _buildPageView(int index) {
    final item = _pages[index];
    return Stack(children: [
      // Page content fills the area
      Positioned.fill(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _pageContent(item),
          ),
        ),
      ),

      // Blue page-number badge (top-left)
      Positioned(
        top: 14, left: 14,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.85),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text('${index + 1}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
        ),
      ),

      // Delete button (top-right)
      Positioned(
        top: 14, right: 14,
        child: GestureDetector(
          onTap: () => setState(() {
            _pages.removeAt(index);
            if (_currentPage >= _pages.length && _currentPage > 0) {
              _currentPage = _pages.length - 1;
            }
          }),
          child: Container(
            width: 28, height: 28,
            decoration: const BoxDecoration(
                color: Colors.black54, shape: BoxShape.circle),
            child:
                const Icon(Icons.close, size: 16, color: Colors.white),
          ),
        ),
      ),
    ]);
  }

  Widget _pageContent(_PageItem item) {
    if (item.type == _PageType.image && item.path.isNotEmpty) {
      return ColorFiltered(
        colorFilter: _brightnessFilter(),
        child: Image.file(File(item.path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _blankPlaceholder(
                icon: Icons.broken_image, label: item.name)),
      );
    }
    if (item.type == _PageType.blankPortrait) {
      return _blankPlaceholder(
          icon: Icons.crop_portrait, label: 'Trang trắng dọc');
    }
    if (item.type == _PageType.blankLandscape) {
      return _blankPlaceholder(
          icon: Icons.crop_landscape, label: 'Trang trắng ngang');
    }
    return _blankPlaceholder(
        icon: Icons.insert_drive_file_outlined, label: item.name);
  }

  Widget _blankPlaceholder(
          {required IconData icon, required String label}) =>
      Container(
        color: Colors.white,
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 56, color: const Color(0xFFBDBDBD)),
            const SizedBox(height: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Color(0xFF9E9E9E))),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  Bottom sheet tile
// ─────────────────────────────────────────────────────────────
class _SheetTile extends StatelessWidget {
  const _SheetTile(
      {required this.icon, required this.label, required this.onTap});
  final IconData     icon;
  final String       label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(children: [
            Icon(icon, size: 26, color: const Color(0xFF757575)),
            const SizedBox(width: 20),
            Text(label,
                style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF212121),
                    fontWeight: FontWeight.w400)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  Dashed border painter
// ─────────────────────────────────────────────────────────────
class _DashedBorderPainter extends CustomPainter {
  final Color  color;
  final double radius;
  final double dashWidth;
  final double dashGap;

  const _DashedBorderPainter({
    required this.color,
    this.radius    = 12,
    this.dashWidth = 6,
    this.dashGap   = 5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color       = color
      ..strokeWidth = 1.8
      ..style       = PaintingStyle.stroke;
    final path   = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(radius)));
    final metric = path.computeMetrics().first;
    double dist  = 0;
    while (dist < metric.length) {
      final end = (dist + dashWidth).clamp(0.0, metric.length);
      canvas.drawPath(metric.extractPath(dist, end), paint);
      dist += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}