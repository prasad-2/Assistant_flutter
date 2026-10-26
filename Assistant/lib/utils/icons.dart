// Icon catalogues: transaction-category icons, generic account icons and the
// list of Indian banks that can be chosen as an account icon.
//
// Icons are stored in the database as short String keys so they survive
// backup/restore and app updates.
import 'package:flutter/material.dart';

/// Every icon that can be assigned to a transaction category.
/// Key (stored in DB) -> Material icon.
const Map<String, IconData> kCategoryIcons = {
  // money & banking
  'payments': Icons.payments,
  'attach_money': Icons.attach_money,
  'account_balance': Icons.account_balance,
  'account_balance_wallet': Icons.account_balance_wallet,
  'savings': Icons.savings,
  'local_atm': Icons.local_atm,
  'credit_card': Icons.credit_card,
  'currency_exchange': Icons.currency_exchange,
  'request_quote': Icons.request_quote,
  'percent': Icons.percent,
  'trending_up': Icons.trending_up,
  'show_chart': Icons.show_chart,
  'swap_horiz': Icons.swap_horiz,
  'receipt_long': Icons.receipt_long,
  'sell': Icons.sell,
  'redeem': Icons.redeem,
  'card_giftcard': Icons.card_giftcard,
  'volunteer_activism': Icons.volunteer_activism,
  'emoji_events': Icons.emoji_events,
  // shopping
  'shopping_cart': Icons.shopping_cart,
  'shopping_bag': Icons.shopping_bag,
  'local_mall': Icons.local_mall,
  'storefront': Icons.storefront,
  'checkroom': Icons.checkroom,
  'inventory_2': Icons.inventory_2,
  'local_shipping': Icons.local_shipping,
  'local_grocery_store': Icons.local_grocery_store,
  // food & drink
  'restaurant': Icons.restaurant,
  'fastfood': Icons.fastfood,
  'lunch_dining': Icons.lunch_dining,
  'local_pizza': Icons.local_pizza,
  'local_cafe': Icons.local_cafe,
  'bakery_dining': Icons.bakery_dining,
  'icecream': Icons.icecream,
  'cake': Icons.cake,
  'local_bar': Icons.local_bar,
  'liquor': Icons.liquor,
  // transport
  'directions_car': Icons.directions_car,
  'directions_bus': Icons.directions_bus,
  'train': Icons.train,
  'subway': Icons.subway,
  'flight': Icons.flight,
  'two_wheeler': Icons.two_wheeler,
  'local_taxi': Icons.local_taxi,
  'local_gas_station': Icons.local_gas_station,
  'ev_station': Icons.ev_station,
  'local_parking': Icons.local_parking,
  'toll': Icons.toll,
  'car_repair': Icons.car_repair,
  // home & utilities
  'home': Icons.home,
  'apartment': Icons.apartment,
  'real_estate_agent': Icons.real_estate_agent,
  'key': Icons.key,
  'weekend': Icons.weekend,
  'bolt': Icons.bolt,
  'electrical_services': Icons.electrical_services,
  'water_drop': Icons.water_drop,
  'local_fire_department': Icons.local_fire_department,
  'plumbing': Icons.plumbing,
  'cleaning_services': Icons.cleaning_services,
  'local_laundry_service': Icons.local_laundry_service,
  'build': Icons.build,
  'handyman': Icons.handyman,
  'construction': Icons.construction,
  // communication & tech
  'wifi': Icons.wifi,
  'router': Icons.router,
  'phone_android': Icons.phone_android,
  'smartphone': Icons.smartphone,
  'computer': Icons.computer,
  'laptop': Icons.laptop,
  'tv': Icons.tv,
  'subscriptions': Icons.subscriptions,
  // health & personal
  'medical_services': Icons.medical_services,
  'local_hospital': Icons.local_hospital,
  'local_pharmacy': Icons.local_pharmacy,
  'medication': Icons.medication,
  'fitness_center': Icons.fitness_center,
  'spa': Icons.spa,
  'content_cut': Icons.content_cut,
  'self_improvement': Icons.self_improvement,
  'shield': Icons.shield,
  'security': Icons.security,
  // education & family
  'school': Icons.school,
  'menu_book': Icons.menu_book,
  'child_care': Icons.child_care,
  'pets': Icons.pets,
  'local_florist': Icons.local_florist,
  // leisure & travel
  'movie': Icons.movie,
  'theaters': Icons.theaters,
  'sports_esports': Icons.sports_esports,
  'sports_soccer': Icons.sports_soccer,
  'sports_cricket': Icons.sports_cricket,
  'music_note': Icons.music_note,
  'headphones': Icons.headphones,
  'camera_alt': Icons.camera_alt,
  'celebration': Icons.celebration,
  'hotel': Icons.hotel,
  'luggage': Icons.luggage,
  'beach_access': Icons.beach_access,
  'travel_explore': Icons.travel_explore,
  'park': Icons.park,
  // work
  'work': Icons.work,
  'business_center': Icons.business_center,
  // misc
  'category': Icons.category,
  'more_horiz': Icons.more_horiz,
  'smoking_rooms': Icons.smoking_rooms,
};

/// Returns the icon for a stored key (falls back to a generic "category").
IconData categoryIconFor(String? key) => kCategoryIcons[key] ?? Icons.category;

/// Generic (non-bank) icons for accounts such as wallet / cash.
/// Stored as `icon:<key>` in `accounts.icon_key`.
const Map<String, IconData> kGenericAccountIcons = {
  'bank': Icons.account_balance,
  'wallet': Icons.account_balance_wallet,
  'card': Icons.credit_card,
  'cash': Icons.payments,
  'savings': Icons.savings,
  'invest': Icons.trending_up,
  'upi': Icons.qr_code_2,
  'home': Icons.home,
  'business': Icons.business_center,
};

/// Key used when the user has not picked anything.
const String kDefaultAccountIcon = 'icon:bank';

/// An Indian bank that can be used as an account icon.
///
/// NOTE: official bank logos are trademarked and cannot be bundled in this
/// app, so each bank is drawn as a brand-coloured monogram badge. Users can
/// upload the real logo themselves ("Upload image") if they want it.
class BankInfo {
  final String key; // stored as `bank:<key>`
  final String name;
  final String short; // text printed inside the badge
  final int color; // badge colour (ARGB)
  const BankInfo(this.key, this.name, this.short, this.color);
}

/// Indian banks (public, private, small-finance, payments banks, foreign).
const List<BankInfo> kIndianBanks = [
  BankInfo('sbi', 'State Bank of India', 'SBI', 0xFF1E6FC0),
  BankInfo('hdfc', 'HDFC Bank', 'HDFC', 0xFF004C8F),
  BankInfo('icici', 'ICICI Bank', 'ICICI', 0xFFB02A30),
  BankInfo('axis', 'Axis Bank', 'AXIS', 0xFF97144D),
  BankInfo('kotak', 'Kotak Mahindra Bank', 'KOTAK', 0xFFE31E24),
  BankInfo('pnb', 'Punjab National Bank', 'PNB', 0xFFA20A3A),
  BankInfo('bob', 'Bank of Baroda', 'BoB', 0xFFEF6A20),
  BankInfo('canara', 'Canara Bank', 'CAN', 0xFF0072BC),
  BankInfo('union', 'Union Bank of India', 'UBI', 0xFFC8102E),
  BankInfo('boi', 'Bank of India', 'BOI', 0xFF0B4EA2),
  BankInfo('indian', 'Indian Bank', 'IB', 0xFF1B3F8B),
  BankInfo('central', 'Central Bank of India', 'CBI', 0xFFD32F2F),
  BankInfo('iob', 'Indian Overseas Bank', 'IOB', 0xFF00539B),
  BankInfo('uco', 'UCO Bank', 'UCO', 0xFF1565A8),
  BankInfo('bom', 'Bank of Maharashtra', 'BoM', 0xFFF9A825),
  BankInfo('psb', 'Punjab & Sind Bank', 'PSB', 0xFF2E7D32),
  BankInfo('indusind', 'IndusInd Bank', 'IIB', 0xFF8E1B3A),
  BankInfo('yes', 'YES Bank', 'YES', 0xFF0B5CAB),
  BankInfo('idfc', 'IDFC FIRST Bank', 'IDFC', 0xFF9C1D3D),
  BankInfo('federal', 'Federal Bank', 'FED', 0xFF1F5FA8),
  BankInfo('rbl', 'RBL Bank', 'RBL', 0xFF1C3F94),
  BankInfo('bandhan', 'Bandhan Bank', 'BDN', 0xFFC8102E),
  BankInfo('sib', 'South Indian Bank', 'SIB', 0xFF1D6B3A),
  BankInfo('kbl', 'Karnataka Bank', 'KBL', 0xFF2A5CAA),
  BankInfo('kvb', 'Karur Vysya Bank', 'KVB', 0xFF0B7A3B),
  BankInfo('cub', 'City Union Bank', 'CUB', 0xFF7B1FA2),
  BankInfo('tmb', 'Tamilnad Mercantile Bank', 'TMB', 0xFF6A1B9A),
  BankInfo('dcb', 'DCB Bank', 'DCB', 0xFF00695C),
  BankInfo('jk', 'Jammu & Kashmir Bank', 'JKB', 0xFF00796B),
  BankInfo('dhan', 'Dhanlaxmi Bank', 'DLB', 0xFFAD1457),
  BankInfo('au', 'AU Small Finance Bank', 'AU', 0xFFE65100),
  BankInfo('equitas', 'Equitas Small Finance Bank', 'EQT', 0xFF8D1B2D),
  BankInfo('ujjivan', 'Ujjivan Small Finance Bank', 'UJV', 0xFFF57C00),
  BankInfo('fino', 'Fino Payments Bank', 'FINO', 0xFF0D47A1),
  BankInfo('paytm', 'Paytm Payments Bank', 'PAYTM', 0xFF00B9F1),
  BankInfo('ippb', 'India Post Payments Bank', 'IPPB', 0xFFD32F2F),
  BankInfo('airtel', 'Airtel Payments Bank', 'AIRTEL', 0xFFE40000),
  BankInfo('jio', 'Jio Payments Bank', 'JIO', 0xFF0F3CC9),
  BankInfo('post', 'Post Office Savings', 'POST', 0xFFC62828),
  BankInfo('cosmos', 'Cosmos Co-op Bank', 'COSMOS', 0xFF1E88E5),
  BankInfo('saraswat', 'Saraswat Co-op Bank', 'SRSWT', 0xFF455A64),
  BankInfo('sc', 'Standard Chartered', 'SC', 0xFF0473EA),
  BankInfo('hsbc', 'HSBC India', 'HSBC', 0xFFDB0011),
  BankInfo('citi', 'Citibank India', 'CITI', 0xFF056DAE),
  BankInfo('dbs', 'DBS Bank India', 'DBS', 0xFFE31837),
  BankInfo('deutsche', 'Deutsche Bank India', 'DB', 0xFF0018A8),
];

/// Looks up a bank by its stored key (the part after `bank:`).
BankInfo? bankByKey(String key) {
  for (final b in kIndianBanks) {
    if (b.key == key) return b;
  }
  return null;
}
