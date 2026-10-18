import 'src/rust/api.dart';

String shoppingScaleSuffix(ShoppingItem item, String id) {
  final index = item.contributorIds.indexOf(id);
  if (index < 0 || index >= item.contributorScales.length) return '';
  final scale = item.contributorScales[index];
  return scale.isEmpty ? '' : ' $scale';
}
