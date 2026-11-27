import 'src/rust/api.dart' show ShoppingItem;
import 'staple_matching.dart';
export 'staple_matching.dart';

ShoppingItem? uncheckedStapleMatch(
  String staple,
  Iterable<ShoppingItem> shopping,
) => shopping
    .where((item) => !item.checked && stapleMatchesFood(staple, item.name))
    .firstOrNull;
