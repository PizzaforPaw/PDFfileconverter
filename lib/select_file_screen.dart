// select_file_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import 'create_document_screen.dart';

// ─────────────────────────────────────────────────────────────
//  HỒ SƠ  —  "Chọn hồ sơ cần ký"  (Step 1 of 3)
// ─────────────────────────────────────────────────────────────
class SelectFileScreen extends StatefulWidget {
  const SelectFileScreen({super.key});
  @override
  State<SelectFileScreen> createState() => _SelectFileScreenState();
}

class _SelectFileScreenState extends State<SelectFileScreen> {
  static const Color _blue   = Color(0xFF1565C0);
  static const Color _bgPage = Color(0xFFF3F4F8);

  // ── Hồ sơ chính state ────────────────────────────────────
  bool   _mainUploaded = false;
  bool   _mainCreated  = false;
  String? _mainFilePath;
  String? _mainFileName;
  int     _mainFileSizeBytes = 0;

  // Metadata for main doc
  final _mainNameCtrl = TextEditingController();
  String _mainDocType = 'Nhân viên';
  final _mainCodeCtrl = TextEditingController();

  // ── Hồ sơ giải trình state ───────────────────────────────
  bool   _annexUploaded = false;
  bool   _annexCreated  = false;
  String? _annexFilePath;
  String? _annexFileName;
  int     _annexFileSizeBytes = 0;

  final _annexNameCtrl = TextEditingController();
  String _annexDocType = 'Nhân viên';
  final _annexCodeCtrl = TextEditingController();

  final List<String> _docTypes = [
    'Nhân viên', 'Hợp đồng', 'Biên bản', 'Khác',
  ];

  @override
  void dispose() {
    _mainNameCtrl.dispose();
    _mainCodeCtrl.dispose();
    _annexNameCtrl.dispose();
    _annexCodeCtrl.dispose();
    super.dispose();
  }

  // ── File picker ───────────────────────────────────────────
  Future<void> _pickFile({required bool isMain}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['docx', 'doc', 'xlsx', 'xls', 'pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.single.path == null) return;
    final f    = result.files.single;
    final size = File(f.path!).lengthSync();
    setState(() {
      if (isMain) {
        _mainFilePath      = f.path;
        _mainFileName      = f.name;
        _mainFileSizeBytes = size;
        _mainUploaded      = true;
        _mainCreated       = false;
      } else {
        _annexFilePath      = f.path;
        _annexFileName      = f.name;
        _annexFileSizeBytes = size;
        _annexUploaded      = true;
        _annexCreated       = false;
      }
    });
  }

  // ── Navigate to CreateDocumentScreen ─────────────────────
  Future<void> _createDoc({required bool isMain}) async {
    final result = await Navigator.push<CreateDocumentResult>(
      context,
      MaterialPageRoute(builder: (_) => const CreateDocumentScreen()),
    );
    if (result == null) return;
    setState(() {
      if (isMain) {
        _mainFilePath      = result.pdfPath;
        _mainFileName      = result.fileName;
        _mainFileSizeBytes = result.sizeBytes;
        _mainCreated       = true;
        _mainUploaded      = false;
      } else {
        _annexFilePath      = result.pdfPath;
        _annexFileName      = result.fileName;
        _annexFileSizeBytes = result.sizeBytes;
        _annexCreated       = true;
        _annexUploaded      = false;
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tạo hồ sơ thành công!'),
          backgroundColor: Color(0xFF1565C0),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ── Helpers ───────────────────────────────────────────────
  bool _mainHasFile()  => _mainFilePath != null;
  bool _annexHasFile() => _annexFilePath != null;
  bool _canContinue()  => _mainHasFile() && _annexHasFile();

  String _sizeLabel(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(2)} KB';
    return '${(kb / 1024).toStringAsFixed(2)} MB';
  }

  // ─────────────────────────────────────────────────────────
  //  Step indicator ①——②——③
  // ─────────────────────────────────────────────────────────
  Widget _stepBubble(int n, bool active) => Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0xFF212121) : Colors.transparent,
          border: active
              ? null
              : Border.all(color: const Color(0xFFBDBDBD), width: 2),
        ),
        alignment: Alignment.center,
        child: Text('$n',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: active ? Colors.white : const Color(0xFFBDBDBD),
            )),
      );

  Widget _stepLine() => Expanded(
      child: Container(height: 2, color: const Color(0xFFBDBDBD)));

  Widget _buildStepIndicator() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Row(children: [
          _stepBubble(1, true), _stepLine(),
          _stepBubble(2, false), _stepLine(),
          _stepBubble(3, false),
        ]),
      );

  // ─────────────────────────────────────────────────────────
  //  Document section card
  // ─────────────────────────────────────────────────────────
  Widget _buildDocSection({
    required String       title,
    required bool         uploadSelected,
    required bool         createSelected,
    required bool         hasFile,
    required String?      fileName,
    required int          fileSizeBytes,
    required TextEditingController nameCtrl,
    required String       docType,
    required TextEditingController codeCtrl,
    required ValueChanged<String> onDocTypeChanged,
    required VoidCallback onUpload,
    required VoidCallback onCreate,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF212121))),
          ),
          const Divider(height: 16, thickness: 1, indent: 16, endIndent: 16),

          // Action buttons
          IntrinsicHeight(
            child: Row(children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.upload_file_outlined,
                  label: 'Tải lên hồ sơ',
                  selected: uploadSelected,
                  onTap: onUpload,
                ),
              ),
              Container(width: 1, color: const Color(0xFFE0E0E0)),
              Expanded(
                child: _ActionButton(
                  icon: Icons.add_box_outlined,
                  label: 'Tạo hồ sơ',
                  selected: createSelected,
                  onTap: onCreate,
                ),
              ),
            ]),
          ),

          // ── File card (shown after file is chosen / created) ──
          if (hasFile && fileName != null) ...[
            const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Container(
                  width: 44, height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.insert_drive_file_rounded,
                      size: 28, color: Color(0xFF9E9E9E)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF212121))),
                      const SizedBox(height: 2),
                      Text(_sizeLabel(fileSizeBytes),
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9E9E9E))),
                    ],
                  ),
                ),
              ]),
            ),

            // ── Metadata form ──────────────────────────────
            const Divider(height: 1, thickness: 1, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(children: [
                // Tên hồ sơ
                TextField(
                  controller: nameCtrl,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    labelText: 'Tên hồ sơ',
                    hintText: 'Vui lòng nhập',
                    hintStyle: const TextStyle(color: Color(0xFFBDBDBD)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 10),

                // Loại hồ sơ + Mã hồ sơ (side by side)
                Row(children: [
                  // Loại hồ sơ dropdown
                  Expanded(
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Loại hồ sơ',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: docType,
                          isDense: true,
                          isExpanded: true,
                          items: _docTypes
                              .map((v) => DropdownMenuItem(
                                  value: v,
                                  child: Text(v,
                                      style:
                                          const TextStyle(fontSize: 14))))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) onDocTypeChanged(v);
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Mã hồ sơ
                  Expanded(
                    child: TextField(
                      controller: codeCtrl,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Mã hồ sơ',
                        hintText: 'Vui lòng nhập',
                        hintStyle:
                            const TextStyle(color: Color(0xFFBDBDBD)),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          ],

          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Bottom bar
  // ─────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final ready = _canContinue();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
      color: _bgPage,
      child: GestureDetector(
        onTap: ready ? _onContinue : null,
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: ready ? Colors.black : const Color(0xFFBDBDBD),
            borderRadius: BorderRadius.circular(30),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('Tiếp tục',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  void _onContinue() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tiếp tục → Bước 2')),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgPage,
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('Chọn hồ sơ cần ký',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white)),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStepIndicator(),

                // Hồ sơ chính
                _buildDocSection(
                  title:           'Hồ sơ chính',
                  uploadSelected:  _mainUploaded,
                  createSelected:  _mainCreated,
                  hasFile:         _mainHasFile(),
                  fileName:        _mainFileName,
                  fileSizeBytes:   _mainFileSizeBytes,
                  nameCtrl:        _mainNameCtrl,
                  docType:         _mainDocType,
                  codeCtrl:        _mainCodeCtrl,
                  onDocTypeChanged: (v) => setState(() => _mainDocType = v),
                  onUpload:        () => _pickFile(isMain: true),
                  onCreate:        () => _createDoc(isMain: true),
                ),

                const SizedBox(height: 16),

                // Hồ sơ giải trình
                _buildDocSection(
                  title:           'Hồ sơ giải trình',
                  uploadSelected:  _annexUploaded,
                  createSelected:  _annexCreated,
                  hasFile:         _annexHasFile(),
                  fileName:        _annexFileName,
                  fileSizeBytes:   _annexFileSizeBytes,
                  nameCtrl:        _annexNameCtrl,
                  docType:         _annexDocType,
                  codeCtrl:        _annexCodeCtrl,
                  onDocTypeChanged: (v) => setState(() => _annexDocType = v),
                  onUpload:        () => _pickFile(isMain: false),
                  onCreate:        () => _createDoc(isMain: false),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        _buildBottomBar(),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Reusable action button
// ─────────────────────────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData     icon;
  final String       label;
  final bool         selected;
  final VoidCallback onTap;

  static const Color _blue  = Color(0xFF1565C0);
  static const Color _bgSel = Color(0xFFE3F0FF);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: selected ? _bgSel : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: _blue),
              const SizedBox(height: 8),
              Text(label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.w500,
                    color: _blue,
                  )),
            ],
          ),
        ),
      );
}