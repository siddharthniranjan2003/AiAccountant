import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/core/utils.dart';

// Real names from the Supabase `stock_items` catalog. Tally item names are
// attribute soup — type, size, grade, brand — punctuated inconsistently, so the
// same size shows up as "-BAH 725" on one row and "BAH725" on the next. The
// picker's old whitespace-only normalizer left that punctuation sitting between
// characters the user types as one run, which is what itemSearchKey fixes.
const _catalog = [
  '16ER 14W',
  '16ER 14W -BAH 725',
  '16ER 2.0 BAH725',
  '16ER 24UN',
  'TPG 5 X .8 6H SIZE CONTROL',
  '1/4X20 BSW SET',
  'HSS TAP 12 X 1.75 SET TOTEM',
  'HSS T/S DRILL 7/8" (22.22) ADDISON',
  'HSS DRILL 12.4 ADDISON',
];

// The picker's match rule (see _StockItemPickerSheetState._applyFilter and
// StockInfo's _search): normalize both sides, then substring.
List<String> _matches(String query) {
  final key = itemSearchKey(query);
  return [
    for (final name in _catalog)
      if (itemSearchKey(name).contains(key)) name,
  ];
}

void main() {
  group('itemSearchKey', () {
    test('strips every separator the catalog uses', () {
      expect(itemSearchKey('HSS T/S DRILL 7/8" (22.22) ADDISON'),
          'hsstsdrill782222addison');
      expect(itemSearchKey('16ER 14W -BAH 725'), '16er14wbah725');
      expect(itemSearchKey(r'a-b.c/d"e(f)g+h i'), 'abcdefghi');
    });

    test('punctuation-only input normalizes to empty', () {
      expect(itemSearchKey('..'), '');
      expect(itemSearchKey('-'), '');
      expect(itemSearchKey('   '), '');
    });
  });

  group('picker matching', () {
    // The reported bug: the hyphen sat between "w" and "b", so a query typed as
    // one run found nothing.
    test('"16er14wb" finds the hyphenated BAH variant', () {
      expect(_matches('16er14wb'), ['16ER 14W -BAH 725']);
    });

    // The case that already worked must keep working — this change is only ever
    // meant to widen the result set, never to drop a row from it.
    test('"16er14w" still finds both plain and suffixed rows', () {
      expect(_matches('16er14w'), ['16ER 14W', '16ER 14W -BAH 725']);
    });

    test('"tpg5x8" finds the item behind a decimal point', () {
      expect(_matches('tpg5x8'), ['TPG 5 X .8 6H SIZE CONTROL']);
    });

    test('a slash is skippable either way', () {
      expect(_matches('14x20'), ['1/4X20 BSW SET']);
      expect(_matches('1/4x20'), ['1/4X20 BSW SET']);
    });

    // itemSearchKey supersedes searchKey rather than replacing its behaviour:
    // whitespace-only queries resolve the same as before.
    test('space-insensitive matching is preserved', () {
      expect(_matches('hsstap'), ['HSS TAP 12 X 1.75 SET TOTEM']);
      expect(_matches('hss tap 12'), ['HSS TAP 12 X 1.75 SET TOTEM']);
    });

    test('every query that matched under searchKey still matches', () {
      for (final name in _catalog) {
        final old = searchKey(name);
        expect(_matches(old), contains(name),
            reason: '"$old" matched "$name" before and must still match');
      }
    });
  });
}
