/// The 28 states + 8 union territories, spelled exactly as Tally writes them into
/// the Supabase `ledgers.state` column.
///
/// Spelling matters: the sale GST head is chosen by comparing this value against
/// the company's home state (`SALE_HOME_STATE`, "Haryana") in the parsing service,
/// so a variant spelling would silently book IGST on a local sale. The 22 values
/// that already appear in `ledgers` are reproduced verbatim — note the ampersands
/// ("Jammu & Kashmir", not "Jammu and Kashmir") and the mixed form of
/// "Dadra & Nagar Haveli and Daman & Diu", which is how the data actually reads.
/// The remaining 14 follow the same convention.
const List<String> kIndianStates = [
  'Andaman & Nicobar Islands',
  'Andhra Pradesh',
  'Arunachal Pradesh',
  'Assam',
  'Bihar',
  'Chandigarh',
  'Chhattisgarh',
  'Dadra & Nagar Haveli and Daman & Diu',
  'Delhi',
  'Goa',
  'Gujarat',
  'Haryana',
  'Himachal Pradesh',
  'Jammu & Kashmir',
  'Jharkhand',
  'Karnataka',
  'Kerala',
  'Ladakh',
  'Lakshadweep',
  'Madhya Pradesh',
  'Maharashtra',
  'Manipur',
  'Meghalaya',
  'Mizoram',
  'Nagaland',
  'Odisha',
  'Puducherry',
  'Punjab',
  'Rajasthan',
  'Sikkim',
  'Tamil Nadu',
  'Telangana',
  'Tripura',
  'Uttar Pradesh',
  'Uttarakhand',
  'West Bengal',
];

/// The company's own state. A sale to a party in this state books CGST + SGST;
/// anywhere else books IGST. Mirrors `SALE_HOME_STATE` in
/// `parsing/server/handler.py` — change both together.
const String kHomeState = 'Haryana';

/// Intra-state (CGST + SGST) vs inter-state (IGST), from the party's state.
///
/// A blank/unknown state resolves to intra-state rather than IGST: it means "not
/// recorded", not "out of state", and for this company the local split is the
/// overwhelmingly common case. Mirrors the same fallback in `handler.py` so the
/// app and the parser never disagree about a voucher's tax head.
bool isIntraState(String? state) {
  final normalized = (state ?? '').trim().toLowerCase();
  return normalized.isEmpty || normalized == kHomeState.toLowerCase();
}
