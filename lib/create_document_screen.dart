// create_document_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui show Canvas, Color, ImageByteFormat, Paint, PictureRecorder, Rect;
import 'dart:ui' show Rect;

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:doc_scan_flutter/doc_scan.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' hide Border;

import 'sort_pages_screen.dart';

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
  String    path;
  String    name;
  _PageType type;
  _PageItem({required this.path, required this.name, required this.type});
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
  double _brightness  = 50;
  bool   _isCreating  = false;

  // Insert position for blank pages: 'before' or 'after'
  String _blankPortraitPos  = 'sau';
  String _blankLandscapePos = 'sau';

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

  // ─────────────────── "Thêm trang" bottom sheet ─────────────
  void _showAddPageSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFBDBDBD),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 4),

            // Camera
            _SheetTile(
              icon: Icons.camera_alt_outlined,
              label: 'Thêm hình từ máy ảnh',
              onTap: () { Navigator.pop(ctx); _addFromCamera(); },
            ),
            const Divider(height: 1, indent: 68),

            // Gallery
            _SheetTile(
              icon: Icons.photo_library_outlined,
              label: 'Chọn hình từ thư viện',
              onTap: () { Navigator.pop(ctx); _addFromGallery(); },
            ),

            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),

            // Portrait blank — with trước/sau dropdown
            _SheetTileWithPosition(
              icon: Icons.crop_portrait,
              label: 'Thêm trang trắng dọc',
              position: _blankPortraitPos,
              onPositionChanged: (v) =>
                  setSheet(() => _blankPortraitPos = v),
              onTap: () {
                final pos = _blankPortraitPos;
                Navigator.pop(ctx);
                _addBlankPage(portrait: true, pos: pos);
              },
            ),
            const Divider(height: 1, indent: 68),

            // Landscape blank — with trước/sau dropdown
            _SheetTileWithPosition(
              icon: Icons.crop_landscape,
              label: 'Thêm trang trắng ngang',
              position: _blankLandscapePos,
              onPositionChanged: (v) =>
                  setSheet(() => _blankLandscapePos = v),
              onTap: () {
                final pos = _blankLandscapePos;
                Navigator.pop(ctx);
                _addBlankPage(portrait: false, pos: pos);
              },
            ),

            const SizedBox(height: 4),
            const Divider(height: 1),
            const SizedBox(height: 4),

            // Close
            _SheetTile(
              icon: Icons.exit_to_app,
              label: 'Đóng',
              onTap: () => Navigator.pop(ctx),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  // ─────────────────── Long-press context menu ───────────────
  void _showPageContextMenu(int index) {
    final item = _pages[index];

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => Material(
        type: MaterialType.transparency,
        child: GestureDetector(
        onTap: () => Navigator.pop(ctx),
        behavior: HitTestBehavior.opaque,
        child: MediaQuery.removePadding(
          context: ctx,
          removeBottom: false,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final menuHeight = item.type == _PageType.image ? 200.0 : 200.0;
                final previewHeight = (constraints.maxHeight - menuHeight - 80).clamp(100.0, constraints.maxHeight);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Enlarged page preview ──────────────────────
                    GestureDetector(
                      onTap: () {},
                      child: SizedBox(
                        height: previewHeight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                          child: Material(
                            color: Colors.transparent,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: _pageContent(item),
                            ),
                          ),
                        ),
                      ),
                    ),

              // ── Context menu card ──────────────────────────
              GestureDetector(
                onTap: () {}, // absorb
                child: Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Xóa trang
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14)),
                        onTap: () {
                          Navigator.pop(ctx);
                          setState(() {
                            _pages.removeAt(index);
                            if (_currentPage >= _pages.length &&
                                _currentPage > 0) {
                              _currentPage = _pages.length - 1;
                            }
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(children: [
                            const Expanded(
                              child: Text('Xóa trang',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Color(0xFFE53935),
                                      fontWeight: FontWeight.w600)),
                            ),
                            const Icon(Icons.delete_outline,
                                color: Color(0xFFE53935), size: 22),
                          ]),
                        ),
                      ),
                      const Divider(height: 1, indent: 20, endIndent: 20),

                      // Sửa trang — available for ALL page types
                      InkWell(
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _editPage(index);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(children: [
                            Expanded(
                              child: Text('Sửa trang',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade900,
                                      fontWeight: FontWeight.w500)),
                            ),
                            Icon(Icons.edit_outlined,
                                color: Colors.grey.shade600,
                                size: 22),
                          ]),
                        ),
                      ),
                      const Divider(height: 1, indent: 20, endIndent: 20),

                      // Đảo vị trí trang
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(14)),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await _openSortScreen();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(children: [
                            Expanded(
                              child: Text('Đảo vị trí trang',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade900,
                                      fontWeight: FontWeight.w500)),
                            ),
                            Icon(Icons.swap_horiz,
                                color: Colors.grey.shade600, size: 22),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
                  ],
                );
              },
            ),
          ),
        ),
        ),
      ),
    );
  }

  // ─────────────────── Edit page (crop) ─────────────────────
  Future<void> _editPage(int index) async {
    final item = _pages[index];
    String sourcePath;

    if (item.type == _PageType.image && item.path.isNotEmpty) {
      // Image page — crop directly
      sourcePath = item.path;
    } else {
      // Blank page — render a white A4 image to a temp file first
      sourcePath = await _renderBlankToImage(
          portrait: item.type != _PageType.blankLandscape);
    }

    final cropped = await _cropImage(sourcePath);
    if (cropped == null || !mounted) return;

    // Evict old cached image so Flutter reloads from disk
    await FileImage(File(cropped)).evict();
    if (!mounted) return;

    // After cropping a blank page it becomes an image page
    setState(() {
      _pages[index] = _PageItem(
        path: cropped,
        type: _PageType.image,
        name: cropped.split('/').last,
      );
    });
  }

  // Renders a plain white rectangle at A4 proportions into a temp PNG
  Future<String> _renderBlankToImage({required bool portrait}) async {
    const int shortSide = 794;  // A4 at 96 dpi
    const int longSide  = 1123;
    final int w = portrait ? shortSide : longSide;
    final int h = portrait ? longSide  : shortSide;

    // Use dart:ui to paint a white canvas and encode to PNG
    final recorder = ui.PictureRecorder();
    final canvas    = ui.Canvas(recorder,
        ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    final picture = recorder.endRecording();
    final image   = await picture.toImage(w, h);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();

    final bytes   = byteData!.buffer.asUint8List();
    final tmpDir  = await getTemporaryDirectory();
    final outPath =
        '${tmpDir.path}/blank_${DateTime.now().millisecondsSinceEpoch}.png';
    await File(outPath).writeAsBytes(bytes, flush: true);
    return outPath;
  }

  // ─────────────────── Sort screen ──────────────────────────
  Future<void> _openSortScreen() async {
    final sortable = _pages
        .map((p) => SortablePageItem(
              path:       p.path,
              name:       p.name,
              isBlank:    p.type != _PageType.image,
              isPortrait: p.type != _PageType.blankLandscape,
            ))
        .toList();

    final result = await Navigator.push<List<SortablePageItem>>(
      context,
      MaterialPageRoute(
          builder: (_) => SortPagesScreen(pages: sortable)),
    );

    if (result == null || !mounted) return;
    setState(() {
      _pages.clear();
      for (final s in result) {
        if (s.isBlank) {
          _pages.add(_PageItem(
            path: '',
            name: s.name,
            type: s.isPortrait
                ? _PageType.blankPortrait
                : _PageType.blankLandscape,
          ));
        } else {
          _pages.add(_PageItem(
              path: s.path, name: s.name, type: _PageType.image));
        }
      }
    });
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
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                child: Row(children: [
                  const Expanded(
                    child: Text('Tùy chỉnh',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // PDF size
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Expanded(
                    child: Text('Chọn khổ PDF',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                  ),
                  DropdownButton<String>(
                    value: pdfSize,
                    underline:
                        Container(height: 1, color: Colors.grey),
                    items: ['Dọc', 'Ngang']
                        .map((v) => DropdownMenuItem(
                            value: v,
                            child: Text(v,
                                style: const TextStyle(
                                    fontSize: 15))))
                        .toList(),
                    onChanged: (v) =>
                        setSheet(() => pdfSize = v ?? pdfSize),
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // Filename
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  const Text('Tên tập tin',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 20),
                  Expanded(
                    child: TextField(
                      controller: nameCtrl,
                      autofocus: true,
                      style: const TextStyle(fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: 'Vui lòng nhập tên',
                        isDense: true,
                        border: UnderlineInputBorder(),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: Color(0xFF1565C0), width: 2),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),

              // Confirm
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
                  padding:
                      const EdgeInsets.symmetric(vertical: 18),
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
        } else if (item.type == _PageType.blankPortrait ||
                   item.type == _PageType.blankLandscape) {
          // Draw a light-grey orientation placeholder so the user can
          // see in the PDF which pages are portrait vs landscape blanks.
          final isPortraitBlank = item.type == _PageType.blankPortrait;

          // Light grey page background
          page.graphics.drawRectangle(
            brush: PdfSolidBrush(PdfColor(245, 245, 245)),
            bounds: Rect.fromLTWH(0, 0, pageW, pageH),
          );

          // Centered inner rectangle representing the page orientation
          // Portrait inner: narrow & tall  |  Landscape inner: wide & short
          const double innerRatio = 1.0 / 1.414;
          final double innerW = isPortraitBlank ? pageW * 0.35 : pageW * 0.55;
          final double innerH = isPortraitBlank
              ? innerW / innerRatio
              : innerW * innerRatio;
          final double innerX = (pageW - innerW) / 2;
          final double innerY = (pageH - innerH) / 2 - 20;

          // White fill with light grey border
          page.graphics.drawRectangle(
            brush: PdfSolidBrush(PdfColor(255, 255, 255)),
            bounds: Rect.fromLTWH(innerX, innerY, innerW, innerH),
          );
          page.graphics.drawRectangle(
            pen: PdfPen(PdfColor(200, 200, 200), width: 1.5),
            bounds: Rect.fromLTWH(innerX, innerY, innerW, innerH),
          );

          // Label below the shape — ASCII only (standard PDF fonts don't support Vietnamese)
          final labelFont = PdfStandardFont(PdfFontFamily.helvetica, 11);
          final label = isPortraitBlank ? 'Trang trang doc' : 'Trang trang ngang';
          final labelSize = labelFont.measureString(label);
          page.graphics.drawString(
            label,
            labelFont,
            brush: PdfSolidBrush(PdfColor(160, 160, 160)),
            bounds: Rect.fromLTWH(
              (pageW - labelSize.width) / 2,
              innerY + innerH + 12,
              labelSize.width + 2,
              labelSize.height + 2,
            ),
          );
        }
      }

      final tmpDir     = await getTemporaryDirectory();
      final outPath    = '${tmpDir.path}/$name.pdf';
      final savedBytes = await pdfDoc.save();
      final bytes      = savedBytes is Uint8List
          ? savedBytes
          : Uint8List.fromList(savedBytes);
      pdfDoc.dispose();
      await File(outPath).writeAsBytes(bytes, flush: true);

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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi tạo PDF: $e')));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  // ─────────────────── Crop helper ──────────────────────────
  Future<String?> _cropImage(String sourcePath) async {
    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle:             'Chỉnh sửa ảnh',
          toolbarColor:             _blue,
          toolbarWidgetColor:       Colors.white,
          activeControlsWidgetColor: _blue,
          statusBarColor:           _blue,
          backgroundColor:          Colors.black,
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio16x9,
            CropAspectRatioPreset.ratio3x2,
          ],
          initAspectRatio: CropAspectRatioPreset.original,
          lockAspectRatio: false,
        ),
        IOSUiSettings(
          title: 'Chỉnh sửa ảnh',
          aspectRatioPresets: [
            CropAspectRatioPreset.original,
            CropAspectRatioPreset.square,
            CropAspectRatioPreset.ratio16x9,
            CropAspectRatioPreset.ratio3x2,
          ],
        ),
      ],
    );
    return cropped?.path;
  }

  // ─────────────────── Add pages ────────────────────────────
  Future<void> _addFromCamera() async {
    try {
      final pages = await DocumentScanner.scan();
      if (pages == null || pages.isEmpty) return;
      for (final rawPath in pages) {
        final cropped = await _cropImage(rawPath);
        if (!mounted) return;
        final finalPath = cropped ?? rawPath;
        setState(() => _pages.add(_PageItem(
              path: finalPath,
              name: finalPath.split('/').last,
              type: _PageType.image,
            )));
      }
      _jumpToLast();
    } on Exception catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi máy ảnh: $e')));
      }
    }
  }

  Future<void> _addFromGallery() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'bmp', 'webp', 'heic'],
    );
    if (result == null) return;
    for (final f in result.files) {
      if (f.path == null) continue;
      final cropped   = await _cropImage(f.path!);
      if (!mounted) return;
      final finalPath = cropped ?? f.path!;
      setState(() => _pages.add(
            _PageItem(path: finalPath, name: f.name, type: _PageType.image),
          ));
    }
    _jumpToLast();
  }

  void _addBlankPage({required bool portrait, String pos = 'sau'}) {
    final item = _PageItem(
      path: '',
      name: portrait ? 'Trang trắng dọc' : 'Trang trắng ngang',
      type: portrait ? _PageType.blankPortrait : _PageType.blankLandscape,
    );
    setState(() {
      if (pos == 'trước') {
        // Insert before current page
        final insertAt = _currentPage.clamp(0, _pages.length);
        _pages.insert(insertAt, item);
      } else {
        // Insert after current page (or at end if no pages)
        final insertAt = _pages.isEmpty
            ? 0
            : (_currentPage + 1).clamp(0, _pages.length);
        _pages.insert(insertAt, item);
        // Navigate to newly inserted page
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageCtrl.hasClients) {
            _pageCtrl.animateToPage(insertAt,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut);
          }
        });
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageCtrl.hasClients && _pages.length > 1) {
          final target = pos == 'trước'
              ? _currentPage.clamp(0, _pages.length - 1)
              : (_currentPage + 1).clamp(0, _pages.length - 1);
          _pageCtrl.animateToPage(target,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut);
        }
      });
    });
  }

  void _jumpToLast() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageCtrl.hasClients && _pages.length > 1) {
        _pageCtrl.animateToPage(_pages.length - 1,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF1565C0)),
              SizedBox(height: 16),
              Text('Đang tạo hồ sơ...', style: TextStyle(fontSize: 15)),
            ],
          ),
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
              ? Container(color: _bgPage)
              : Container(
                  color: _bgPage,
                  child: PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _pages.length,
                    onPageChanged: (i) =>
                        setState(() => _currentPage = i),
                    itemBuilder: (_, i) => _buildPageView(i),
                  ),
                ),
        ),

        // ── Bottom panel ─────────────────────────────────────
        Container(
          color: Colors.white,
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Brightness slider
            if (_pages.any((p) => p.type == _PageType.image))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(children: [
                  const Text('Độ sáng',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF424242))),
                  Expanded(
                    child: Slider(
                      value: _brightness,
                      min: 0, max: 100,
                      activeColor: _blue,
                      onChanged: (v) =>
                          setState(() => _brightness = v),
                    ),
                  ),
                  SizedBox(
                    width: 32,
                    child: Text(_brightness.round().toString(),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF424242))),
                  ),
                ]),
              ),

            // Dashed "Thêm trang"
            Padding(
              padding: EdgeInsets.fromLTRB(
                  16,
                  _pages.any((p) => p.type == _PageType.image) ? 6 : 12,
                  16,
                  0),
              child: GestureDetector(
                onTap: _showAddPageSheet,
                child: Container(
                  width: double.infinity, height: 76,
                  decoration: BoxDecoration(
                    color: _bgPage,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _DashedBorderPainter(
                            color: const Color(0xFF42A5F5),
                            radius: 12),
                      ),
                    ),
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Center(
                          child: Icon(Icons.add_box_outlined,
                              size: 28,
                              color: Color(0xFF42A5F5)),
                        ),
                        SizedBox(height: 3),
                        Text('Thêm trang',
                            style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF757575),
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ]),
                ),
              ),
            ),

            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pages.isEmpty ? null : _showCustomizeSheet,
              child: Container(
                color: Colors.black,
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
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

  // ── Page view with long-press → context menu ──────────────
  Widget _buildPageView(int index) {
    final item = _pages[index];
    return GestureDetector(
      onLongPress: () => _showPageContextMenu(index),
      child: Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _pageContent(item),
            ),
          ),
        ),
        // Blue badge
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
      ]),
    );
  }

  Widget _pageContent(_PageItem item) {
    if (item.type == _PageType.image && item.path.isNotEmpty) {
      return ColorFiltered(
        colorFilter: _brightnessFilter(),
        child: Image.file(
            File(item.path),
            key: ValueKey(item.path), // bust cache when path changes
            fit: BoxFit.contain,
            gaplessPlayback: false,
            errorBuilder: (_, __, ___) => _blankPlaceholder(
                icon: Icons.broken_image, label: item.name, portrait: true)),
      );
    }
    if (item.type == _PageType.blankPortrait) {
      return _blankPage(portrait: true);
    }
    if (item.type == _PageType.blankLandscape) {
      return _blankPage(portrait: false);
    }
    return _blankPlaceholder(
        icon: Icons.insert_drive_file_outlined,
        label: item.name,
        portrait: true);
  }

  Widget _blankPage({required bool portrait}) {
    const double ratio = 1.0 / 1.414;
    // Inner demo shape: a smaller rounded rect at the correct orientation,
    // slightly grey so it's visible but clearly a watermark/placeholder
    final innerAspect = portrait ? 1.0 / ratio : ratio / 1.0;

    return Container(
      color: const Color(0xFFE0E0E0),
      child: Center(
        child: AspectRatio(
          aspectRatio: portrait ? ratio : 1.0 / ratio,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Watermark page shape — grey outline rectangle
                  // sized to ~55% of the page, oriented correctly
                  FractionallySizedBox(
                    widthFactor: portrait ? 0.38 : 0.55,
                    child: AspectRatio(
                      aspectRatio: portrait ? ratio : 1.0 / ratio,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F0F0),
                          border: Border.all(
                              color: const Color(0xFFCCCCCC), width: 1.5),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Center(
                          child: Icon(
                            portrait
                                ? Icons.crop_portrait
                                : Icons.crop_landscape,
                            size: portrait ? 22 : 26,
                            color: const Color(0xFFCCCCCC),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    portrait ? 'Trang trắng dọc' : 'Trang trắng ngang',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF9E9E9E)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _blankPlaceholder(
          {required IconData icon,
          required String label,
          required bool portrait}) =>
      Container(
        color: Colors.white,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: const Color(0xFFBDBDBD)),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF9E9E9E))),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  Sheet tile (plain)
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
//  Sheet tile with trước/sau position dropdown
// ─────────────────────────────────────────────────────────────
class _SheetTileWithPosition extends StatelessWidget {
  const _SheetTileWithPosition({
    required this.icon,
    required this.label,
    required this.position,
    required this.onPositionChanged,
    required this.onTap,
  });
  final IconData              icon;
  final String                label;
  final String                position;
  final ValueChanged<String>  onPositionChanged;
  final VoidCallback          onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 26, color: const Color(0xFF757575)),
            const SizedBox(width: 20),
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF212121),
                      fontWeight: FontWeight.w400)),
            ),
            // Position dropdown — tap stops propagation
            GestureDetector(
              onTap: () {}, // absorb tap so row tap still works
              child: DropdownButton<String>(
                value: position,
                underline: Container(height: 1, color: Colors.grey),
                isDense: true,
                items: ['trước', 'sau']
                    .map((v) => DropdownMenuItem(
                        value: v,
                        child: Text(v,
                            style: const TextStyle(fontSize: 14))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onPositionChanged(v);
                },
              ),
            ),
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