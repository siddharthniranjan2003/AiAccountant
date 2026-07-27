import 'package:flutter_test/flutter_test.dart';

import 'package:aiaccountant/core/indian_states.dart';

// Every distinct non-empty value in the Supabase `ledgers.state` column as of
// 2026-07-23. These must appear VERBATIM in kIndianStates: the parsing service
// compares this string against SALE_HOME_STATE to pick CGST+SGST vs IGST, so a
// variant spelling ("Jammu and Kashmir") would silently bill the wrong tax head
// and would not round-trip an existing ledger row through the picker.
const _spellingsInLedgers = [
  'Andhra Pradesh',
  'Assam',
  'Chandigarh',
  'Chhattisgarh',
  'Dadra & Nagar Haveli and Daman & Diu',
  'Delhi',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu & Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Madhya Pradesh',
  'Maharashtra',
  'Odisha',
  'Punjab',
  'Rajasthan',
  'Tamil Nadu',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

void main() {
  group('kIndianStates', () {
    test('contains every spelling already present in ledgers.state', () {
      for (final state in _spellingsInLedgers) {
        expect(kIndianStates, contains(state),
            reason: '"$state" exists in ledgers but is missing from the picker, '
                'so that customer could not round-trip their own state');
      }
    });

    test('covers all 28 states + 8 union territories', () {
      expect(kIndianStates, hasLength(36));
    });

    test('has no duplicates and is sorted', () {
      expect(kIndianStates.toSet(), hasLength(kIndianStates.length));
      expect(kIndianStates, orderedEquals([...kIndianStates]..sort()));
    });

    test('the home state is selectable', () {
      expect(kIndianStates, contains(kHomeState));
    });
  });

  group('isIntraState', () {
    test('home state books CGST+SGST', () {
      expect(isIntraState('Haryana'), isTrue);
    });

    test('is case- and whitespace-insensitive, matching handler.py casefold()', () {
      expect(isIntraState('haryana'), isTrue);
      expect(isIntraState('  HARYANA  '), isTrue);
    });

    test('any other state books IGST', () {
      expect(isIntraState('Delhi'), isFalse);
      expect(isIntraState('Uttar Pradesh'), isFalse);
    });

    // The fallback the parsing service also applies: unknown means "not
    // recorded", not "out of state". Guessing IGST is the expensive error.
    test('unknown state falls back to intra-state, not IGST', () {
      expect(isIntraState(null), isTrue);
      expect(isIntraState(''), isTrue);
      expect(isIntraState('   '), isTrue);
    });
  });
}
