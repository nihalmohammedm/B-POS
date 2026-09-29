import 'package:bistro_pos/models.dart';
import 'package:bistro_pos/print_layout.dart';
import 'package:bistro_pos/widgets/receipt.dart';
import 'package:flutter_test/flutter_test.dart';

/// 2-inch printers that treat a carriage return as a line feed printed every
/// bold KOT line twice (the printer library re-prints bold table columns after
/// a CR). Tickets are now plain padded lines: each item once, no CR.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int count(String hay, String needle) => needle.allMatches(hay).length;

  ReceiptData kot() => ReceiptData(
        isKot: true,
        no: '7',
        type: OrderType.dineIn,
        where: '12',
        server: 'Arun',
        pax: 2,
        at: DateTime(2026, 9, 29, 13, 5),
        group: 'Grill',
        lines: [
          ReceiptLine(2, 'Alfaham', 300, ['> 1 Half', '+ Mayo'], 'Extra spicy'),
          ReceiptLine(1, 'Chicken Shawarma Plate With Extra Garlic Sauce', 180, [], ''),
        ],
      );

  for (final mm in [58, 80]) {
    test('$mm mm KOT: every item line printed once, no carriage returns', () async {
      final bytes = await receiptBytes(kot(), layout: PrintLayout(paperMm: mm));
      final text = String.fromCharCodes(bytes);
      expect(bytes.contains(13), isFalse, reason: 'no CR anywhere');
      expect(count(text, 'ALFAHAM'), 1);
      expect(count(text, 'CHICKEN'), 1);
      expect(count(text, '> 1 Half'), 1);
      expect(count(text, '** Extra spicy **'), 1);
      // The long name wraps under itself instead of running off the paper.
      final width = mm == 58 ? 32 : 48;
      final totalLine = text.split('\n').firstWhere((x) => x.contains('Total items'));
      expect(RegExp(r'Total items\s+3').hasMatch(totalLine), isTrue);
      final visible = totalLine.substring(totalLine.indexOf('Total items')).trimRight();
      expect(visible.length, width, reason: 'label left, count right, exactly the paper width');
    });
  }

  test('58 mm bill: heading and item rows once each, numbers right-aligned', () async {
    final d = ReceiptData(
      isKot: false,
      no: 'B12',
      type: OrderType.takeaway,
      where: 'TA-7',
      server: '',
      pax: 0,
      at: DateTime(2026, 9, 29),
      lines: [ReceiptLine(2, 'Porotta', 20, [], '')],
    );
    final text = String.fromCharCodes(await receiptBytes(d, layout: PrintLayout(paperMm: 58)));
    expect(count(text, 'ITEM'), 1);
    expect(count(text, 'Porotta'), 1);
    expect(RegExp(r'Porotta\s+2\s+20\s+40\.00').hasMatch(text), isTrue);
    expect(text.contains('\r'), isFalse);
  });
}
