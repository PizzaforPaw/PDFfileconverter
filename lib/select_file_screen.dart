// select_file_screen.dart
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────
//  HỒ SƠ  —  "Chọn hồ sơ cần ký"  (Step 1 of 3)
//
//  Displayed as a tab inside HomeScreen, so it owns its own
//  inner Scaffold with the blue app-bar and step progress.
// ─────────────────────────────────────────────────────────────
class SelectFileScreen extends StatefulWidget {
  const SelectFileScreen({super.key});

  @override
  State<SelectFileScreen> createState() => _SelectFileScreenState();
}

class _SelectFileScreenState extends State<SelectFileScreen> {

  bool _mainUploaded  = false;
  bool _mainCreated   = false;
  bool _annexUploaded = false;
  bool _annexCreated  = false;

  static const Color _blue   = Color(0xFF1565C0);
  static const Color _bgPage = Color(0xFFF3F4F8);

  // ── Step indicator ①——②——③ ────────────────────────────────
  Widget _stepBubble(int n, bool active) => Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0xFF212121) : Colors.transparent,
          border: active ? null : Border.all(color: const Color(0xFFBDBDBD), width: 2),
        ),
        alignment: Alignment.center,
        child: Text('$n', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.bold,
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

  // ── Document section card ─────────────────────────────────
  Widget _buildDocSection({
    required String       title,
    required bool         uploadSelected,
    required bool         createSelected,
    required VoidCallback onUpload,
    required VoidCallback onCreate,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF212121))),
          ),
          const Divider(height: 16, thickness: 1, indent: 16, endIndent: 16),
          IntrinsicHeight(
            child: Row(children: [
              Expanded(child: _ActionButton(icon: Icons.upload_file_outlined, label: 'Tải lên hồ sơ', selected: uploadSelected, onTap: onUpload)),
              Container(width: 1, color: const Color(0xFFE0E0E0)),
              Expanded(child: _ActionButton(icon: Icons.add_box_outlined, label: 'Tạo hồ sơ', selected: createSelected, onTap: onCreate)),
            ]),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────
  Widget _buildBottomBar() => Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        color: _bgPage,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: double.infinity, height: 48,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                backgroundColor: const Color(0xFFCFCFCF),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: const Text('Cuộc gọi và thông báo sẽ rung',
                  style: TextStyle(color: Color(0xFF616161), fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton.icon(
              onPressed: _canContinue() ? _onContinue : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canContinue() ? _blue : const Color(0xFFBDBDBD),
                disabledBackgroundColor: const Color(0xFFBDBDBD),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                elevation: 0,
              ),
              icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
              label: const Text('Tiếp tục',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ]),
      );

  bool _canContinue() => (_mainUploaded || _mainCreated) && (_annexUploaded || _annexCreated);

  void _onContinue() {
    // TODO: push step-2 screen via Navigator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tiếp tục → Bước 2')),
    );
  }

  void _handleMainUpload()  => setState(() => _mainUploaded  = !_mainUploaded);
  void _handleMainCreate()  => setState(() => _mainCreated   = !_mainCreated);
  void _handleAnnexUpload() => setState(() => _annexUploaded = !_annexUploaded);
  void _handleAnnexCreate() => setState(() => _annexCreated  = !_annexCreated);

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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _buildStepIndicator(),
              _buildDocSection(
                title: 'Hồ sơ chính',
                uploadSelected: _mainUploaded, createSelected: _mainCreated,
                onUpload: _handleMainUpload, onCreate: _handleMainCreate,
              ),
              const SizedBox(height: 16),
              _buildDocSection(
                title: 'Hồ sơ giải trình',
                uploadSelected: _annexUploaded, createSelected: _annexCreated,
                onUpload: _handleAnnexUpload, onCreate: _handleAnnexCreate,
              ),
              const SizedBox(height: 24),
            ]),
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
    required this.icon, required this.label,
    required this.selected, required this.onTap,
  });

  final IconData     icon;
  final String       label;
  final bool         selected;
  final VoidCallback onTap;

  static const Color _blue  = Color(0xFF1565C0);
  static const Color _bgSel = Color(0xFFE3F0FF);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: selected ? _bgSel : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 32, color: _blue),
          const SizedBox(height: 8),
          Text(label, style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: _blue,
          )),
        ]),
      ),
    );
  }
}