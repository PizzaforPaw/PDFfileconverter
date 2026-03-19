// sort_pages_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

// ─────────────────────────────────────────────────────────────
//  Shared page model
// ─────────────────────────────────────────────────────────────
class SortablePageItem {
  String path;
  String name;
  bool   isBlank;
  bool   isPortrait;

  SortablePageItem({
    required this.path,
    required this.name,
    required this.isBlank,
    this.isPortrait = true,
  });
}

// ─────────────────────────────────────────────────────────────
//  SCREEN
// ─────────────────────────────────────────────────────────────
class SortPagesScreen extends StatefulWidget {
  final List<SortablePageItem> pages;
  const SortPagesScreen({super.key, required this.pages});

  @override
  State<SortPagesScreen> createState() => _SortPagesScreenState();
}

class _SortPagesScreenState extends State<SortPagesScreen> {
  static const Color _blue = Color(0xFF1565C0);

  late final List<SortablePageItem> _pages;

  @override
  void initState() {
    super.initState();
    _pages = widget.pages
        .map((p) => SortablePageItem(
              path:       p.path,
              name:       p.name,
              isBlank:    p.isBlank,
              isPortrait: p.isPortrait,
            ))
        .toList();
  }

  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Sắp xếp hình',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context, null),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _pages),
            child: const Text(
              'Xong',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: ReorderableGridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   3,
          crossAxisSpacing: 10,
          mainAxisSpacing:  10,
          childAspectRatio: 0.72,
        ),
        itemCount: _pages.length,
        onReorder: _onReorder,
        // Lifted drag feedback — elevated card
        dragWidgetBuilder: (index, child) => Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(10),
          shadowColor: Colors.black45,
          child: child,
        ),
        itemBuilder: (ctx, index) => _PageCard(
          key:   ValueKey('page_$index'),
          item:  _pages[index],
          index: index,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  Page card
// ─────────────────────────────────────────────────────────────
class _PageCard extends StatelessWidget {
  const _PageCard({
    super.key,
    required this.item,
    required this.index,
  });

  final SortablePageItem item;
  final int              index;

  static const Color _blue = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            // Content
            Positioned.fill(child: _content()),

            // Blue number badge
            Positioned(
              top: 4, left: 4,
              child: Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.88),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    if (!item.isBlank && item.path.isNotEmpty) {
      return Image.file(
        File(item.path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _blank(),
      );
    }
    return _blank();
  }

  Widget _blank() => Container(
        color: Colors.white,
        child: Center(
          child: Icon(
            item.isPortrait ? Icons.crop_portrait : Icons.crop_landscape,
            size: 32,
            color: const Color(0xFFBDBDBD),
          ),
        ),
      );
}