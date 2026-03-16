// doc_utils.dart
// ─────────────────────────────────────────────────────────────
//  Shared PDF-conversion utilities
//  Imported by converter_screen.dart
// ─────────────────────────────────────────────────────────────
library doc_utils;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect, Offset;

import 'package:flutter/material.dart' show Color, IconData, Icons;

import 'package:syncfusion_flutter_pdf/pdf.dart' hide Border;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart' as xml;
import 'package:excel/excel.dart' hide Border;

// ─────────────────────────────────────────────────────────────
//  FILE TYPE
// ─────────────────────────────────────────────────────────────
enum DocType { word, excel, image, unknown }

DocType detectType(String path) {
  final ext = path.split('.').last.toLowerCase();
  if (['docx', 'doc'].contains(ext))               return DocType.word;
  if (['xlsx', 'xls'].contains(ext))               return DocType.excel;
  if (['jpg', 'jpeg', 'png', 'bmp'].contains(ext)) return DocType.image;
  return DocType.unknown;
}

String   docTypeLabel(DocType t) => {DocType.word: 'Word (.docx)', DocType.excel: 'Excel (.xlsx)', DocType.image: 'Image (.jpg/.png)', DocType.unknown: 'Unknown'}[t]!;
IconData docTypeIcon(DocType t)  => {DocType.word: Icons.description, DocType.excel: Icons.table_chart, DocType.image: Icons.image, DocType.unknown: Icons.help_outline}[t]!;
Color    docTypeColor(DocType t) => {DocType.word: const Color(0xFF1565C0), DocType.excel: const Color(0xFF2E7D32), DocType.image: const Color(0xFF6A1B9A), DocType.unknown: const Color(0xFF9E9E9E)}[t]!;

// ─────────────────────────────────────────────────────────────
//  DATA MODELS
// ─────────────────────────────────────────────────────────────
class DocRun {
  final String        text;
  final bool          bold;
  final bool          italic;
  final bool          underline;
  final double        fontSize;    // 0 = inherit from paragraph
  final PdfColor      color;
  final PdfFontFamily fontFamily;

  const DocRun({
    required this.text,
    required this.bold,
    required this.italic,
    required this.underline,
    required this.fontSize,
    required this.color,
    required this.fontFamily,
  });
}

class DocPara {
  final List<DocRun>     runs;
  final PdfTextAlignment alignment;
  final double           spaceBefore;
  final double           spaceAfter;
  final bool             isHeading;
  final double           headingSize;

  const DocPara({
    required this.runs,
    required this.alignment,
    required this.spaceBefore,
    required this.spaceAfter,
    required this.isHeading,
    required this.headingSize,
  });
}

// ─────────────────────────────────────────────────────────────
//  FONT MAPPER
// ─────────────────────────────────────────────────────────────
PdfFontFamily mapFontFamily(String? name) {
  if (name == null || name.isEmpty) return PdfFontFamily.helvetica;
  final n = name.toLowerCase();
  if (n.contains('courier') || n.contains('consolas') || n.contains('mono') ||
      n.contains('lucida console') || n.contains('menlo') || n.contains('source code'))
    return PdfFontFamily.courier;
  if (n.contains('times') || n.contains('georgia') || n.contains('garamond') ||
      n.contains('palatino') || n.contains('cambria') || n.contains('book antiqua') ||
      n.contains('serif'))
    return PdfFontFamily.timesRoman;
  return PdfFontFamily.helvetica;
}

// ─────────────────────────────────────────────────────────────
//  MAIN ENTRY — convert raw file bytes → PDF bytes
//
//  Called directly on the main isolate. All libraries used here
//  (syncfusion, archive, xml, excel) are pure-Dart — no FFI —
//  so no objective_c.dylib issues on iOS.
// ─────────────────────────────────────────────────────────────
Future<List<int>> convertToPdfBytes({
  required Uint8List fileBytes,
  required DocType   docType,
}) async {
  switch (docType) {

    // ── Word (.docx) → PDF ──────────────────────────────────
    case DocType.word:
      final archive  = ZipDecoder().decodeBytes(fileBytes);
      final docEntry = archive.files.firstWhere(
        (f) => f.name == 'word/document.xml',
        orElse: () => throw Exception('Not a valid .docx — word/document.xml missing'),
      );
      final xmlStr  = utf8.decode(docEntry.content as Uint8List);
      final xmlDoc  = xml.XmlDocument.parse(xmlStr);
      final docParas = <DocPara>[];

      for (final paraNode in xmlDoc.findAllElements('w:p')) {
        final pPr      = paraNode.findElements('w:pPr').firstOrNull;
        final jcVal    = pPr?.findElements('w:jc').firstOrNull?.getAttribute('w:val') ?? 'left';
        final styleVal = pPr?.findElements('w:pStyle').firstOrNull?.getAttribute('w:val') ?? '';
        final spBefore = double.tryParse(
            pPr?.findElements('w:spacing').firstOrNull?.getAttribute('w:before') ?? '0') ?? 0;
        final spAfter  = double.tryParse(
            pPr?.findElements('w:spacing').firstOrNull?.getAttribute('w:after')  ?? '160') ?? 160;

        final alignment = switch (jcVal) {
          'center' => PdfTextAlignment.center,
          'right'  => PdfTextAlignment.right,
          'both'   => PdfTextAlignment.justify,
          _        => PdfTextAlignment.left,
        };

        final runs = <DocRun>[];
        for (final runNode in paraNode.findAllElements('w:r')) {
          final rPr  = runNode.findElements('w:rPr').firstOrNull;
          final text = runNode.findAllElements('w:t')
              .map((n) => n.children.whereType<xml.XmlText>().map((t) => t.value).join())
              .join();
          if (text.isEmpty) continue;

          final bNode     = rPr?.findElements('w:b').firstOrNull;
          final bold      = bNode != null && bNode.getAttribute('w:val') != '0';
          final iNode     = rPr?.findElements('w:i').firstOrNull;
          final italic    = iNode != null && iNode.getAttribute('w:val') != '0';
          final uVal      = rPr?.findElements('w:u').firstOrNull?.getAttribute('w:val');
          final underline = uVal != null && uVal != 'none';

          final szStr   = rPr?.findElements('w:sz').firstOrNull?.getAttribute('w:val');
          final rawSize = double.tryParse(szStr ?? '');
          final fontSize = rawSize != null ? rawSize / 2 : 0.0;

          final colorHex = rPr?.findElements('w:color').firstOrNull?.getAttribute('w:val');
          PdfColor color = PdfColor(0, 0, 0);
          if (colorHex != null && colorHex.length == 6 && colorHex != 'auto') {
            color = PdfColor(
              int.parse(colorHex.substring(0, 2), radix: 16),
              int.parse(colorHex.substring(2, 4), radix: 16),
              int.parse(colorHex.substring(4, 6), radix: 16),
            );
          }

          final rFonts   = rPr?.findElements('w:rFonts').firstOrNull;
          final fontName = rFonts?.getAttribute('w:ascii')
                        ?? rFonts?.getAttribute('w:hAnsi')
                        ?? rFonts?.getAttribute('w:eastAsia');

          runs.add(DocRun(
            text: text, bold: bold, italic: italic, underline: underline,
            fontSize: fontSize, color: color, fontFamily: mapFontFamily(fontName),
          ));
        }
        if (runs.isEmpty) continue;

        bool isHeading = false;
        double headingSize = 0;
        if (styleVal.toLowerCase().startsWith('heading')) {
          isHeading = true;
          final level = int.tryParse(styleVal.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
          headingSize = switch (level) { 1 => 20, 2 => 16, 3 => 14, _ => 13 };
        }

        docParas.add(DocPara(
          runs: runs, alignment: alignment,
          spaceBefore: spBefore / 20, spaceAfter: spAfter / 20,
          isHeading: isHeading, headingSize: headingSize,
        ));
      }
      return _richDocToPdf(paragraphs: docParas);

    // ── Excel (.xlsx) → PDF ─────────────────────────────────
    case DocType.excel:
      final workbook = Excel.decodeBytes(fileBytes);
      final pdfDoc   = PdfDocument();
      final bodyFont = PdfStandardFont(PdfFontFamily.helvetica, 10);
      final headFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);

      for (final sheetName in workbook.tables.keys) {
        final sheet = workbook.tables[sheetName]!;
        if (sheet.rows.isEmpty) continue;

        final page  = pdfDoc.pages.add();
        final pageW = page.getClientSize().width;
        final pageH = page.getClientSize().height;

        page.graphics.drawString(
          'Sheet: $sheetName',
          PdfStandardFont(PdfFontFamily.helvetica, 13, style: PdfFontStyle.bold),
          brush:  PdfSolidBrush(PdfColor(33, 33, 33)),
          bounds: Rect.fromLTWH(0, 0, pageW, 22),
        );

        int maxCols = 0;
        for (final row in sheet.rows) {
          if (row.length > maxCols) maxCols = row.length;
        }
        if (maxCols == 0) continue;

        final grid = PdfGrid();
        grid.style.font = bodyFont;
        grid.columns.add(count: maxCols);

        bool isHeader = true;
        for (final row in sheet.rows) {
          final gridRow = grid.rows.add();
          for (int c = 0; c < maxCols; c++) {
            final cell = c < row.length ? row[c] : null;
            gridRow.cells[c].value = cell?.value?.toString() ?? '';
            if (isHeader) {
              gridRow.cells[c].style.font = headFont;
              gridRow.cells[c].style.backgroundBrush =
                  PdfSolidBrush(PdfColor(220, 230, 255));
            }
          }
          isHeader = false;
        }
        grid.draw(page: page, bounds: Rect.fromLTWH(0, 28, pageW, pageH - 28));
      }

      final excelBytes = await pdfDoc.save();
      pdfDoc.dispose();
      return excelBytes;

    // ── Image (.jpg / .png) → PDF ───────────────────────────
    case DocType.image:
      final pdfDoc = PdfDocument();
      final page   = pdfDoc.pages.add();
      final image  = PdfBitmap(fileBytes);
      final pageW  = page.getClientSize().width;
      final pageH  = page.getClientSize().height;
      final imgW   = image.width.toDouble();
      final imgH   = image.height.toDouble();
      final scale  = (imgW / pageW > imgH / pageH) ? pageW / imgW : pageH / imgH;
      page.graphics.drawImage(image, Rect.fromLTWH(0, 0, imgW * scale, imgH * scale));
      final imageBytes = await pdfDoc.save();
      pdfDoc.dispose();
      return imageBytes;

    default:
      throw UnsupportedError('Unsupported file type: $docType');
  }
}

// ─────────────────────────────────────────────────────────────
//  RICH DOC → PDF RENDERER  (private helper)
//  Preserves bold, italic, underline, font size, color, alignment
// ─────────────────────────────────────────────────────────────
Future<List<int>> _richDocToPdf({required List<DocPara> paragraphs}) async {
  const double margin      = 40;
  const double defaultSize = 11;
  const double minLineH    = 14;

  final pdfDoc = PdfDocument();
  PdfPage     page  = pdfDoc.pages.add();
  PdfGraphics g     = page.graphics;
  double      pageW = page.getClientSize().width - margin * 2;
  double      pageH = page.getClientSize().height;
  double      y     = margin;

  final fontCache = <String, PdfFont>{};

  PdfFont getFont(double size,
      {bool bold = false,
      bool italic = false,
      PdfFontFamily family = PdfFontFamily.helvetica}) {
    final key = '${family.index}_${size}_${bold}_$italic';
    return fontCache.putIfAbsent(key, () {
      final style = bold
          ? PdfFontStyle.bold
          : italic
              ? PdfFontStyle.italic
              : PdfFontStyle.regular;
      return PdfStandardFont(family, size, style: style);
    });
  }

  void ensureSpace(double needed) {
    if (y + needed > pageH - margin) {
      page = pdfDoc.pages.add();
      g    = page.graphics;
      y    = margin;
    }
  }

  for (final para in paragraphs) {
    y += para.spaceBefore;

    double paraFontSize = defaultSize;
    if (para.isHeading) {
      paraFontSize = para.headingSize;
    } else {
      for (final r in para.runs) {
        if (r.fontSize > paraFontSize) paraFontSize = r.fontSize;
      }
    }
    final lineH = (paraFontSize * 1.4).clamp(minLineH, 60.0);
    ensureSpace(lineH);

    final lineParts = <({String text, DocRun run, double width})>[];
    double lineWidth = 0;

    void flushLine({bool isLast = false}) {
      if (lineParts.isEmpty) return;
      ensureSpace(lineH);

      final totalW = lineParts.fold(0.0, (sum, p) => sum + p.width);
      double xOffset = switch (para.alignment) {
        PdfTextAlignment.center => (pageW - totalW) / 2,
        PdfTextAlignment.right  => pageW - totalW,
        _                       => 0,
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
        g.drawString(part.text, fnt,
            brush:  brush,
            bounds: Rect.fromLTWH(x, y, part.width + 2, lineH),
            format: PdfStringFormat(lineAlignment: PdfVerticalAlignment.middle));
        if (part.run.underline) {
          g.drawLine(
            PdfPen(part.run.color, width: 0.5),
            Offset(x, y + lineH - 2),
            Offset(x + part.width, y + lineH - 2),
          );
        }
        x += part.width;
      }
      y += lineH;
      lineParts.clear();
      lineWidth = 0;
    }

    for (final run in para.runs) {
      final sz     = run.fontSize > 0 ? run.fontSize : paraFontSize;
      final fnt    = getFont(sz,
          bold:   run.bold || para.isHeading,
          italic: run.italic,
          family: run.fontFamily);
      final spaceW = fnt.measureString('a a').width - fnt.measureString('aa').width;

      // Whitespace-only run (Word stores inter-word spaces as separate runs)
      if (run.text.trim().isEmpty) {
        for (int s = 0; s < run.text.length; s++) {
          if (lineWidth + spaceW > pageW && lineParts.isNotEmpty) flushLine();
          lineParts.add((text: ' ', run: run, width: spaceW));
          lineWidth += spaceW;
        }
        continue;
      }

      // Normal text run — split into words for wrapping
      final words = run.text.split(' ');
      for (int wi = 0; wi < words.length; wi++) {
        final word = words[wi];
        if (word.isEmpty) {
          if (wi > 0 && wi < words.length - 1) {
            lineParts.add((text: ' ', run: run, width: spaceW));
            lineWidth += spaceW;
          }
          continue;
        }
        final token = '$word ';
        final wordW = fnt.measureString(word).width + spaceW;
        if (lineWidth + wordW > pageW && lineParts.isNotEmpty) flushLine();
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