// Canonical lowercase letter decompositions whose suffix is entirely
// Unicode Combining Diacritical Marks (U+0300–036F). Derived from UnicodeData.
const _accentGroups = <String, String>{
  'a': 'àáâãäåāăąǎǟǡǻȁȃȧḁạảấầẩẫậắằẳẵặ',
  'c': 'çćĉċčḉ',
  'e': 'èéêëēĕėęěȅȇȩḕḗḙḛḝẹẻẽếềểễệ',
  'i': 'ìíîïĩīĭįǐȉȋḭḯỉị',
  'n': 'ñńņňǹṅṇṉṋ',
  'o': 'òóôõöōŏőơǒǫǭȍȏȫȭȯȱṍṏṑṓọỏốồổỗộớờởỡợ',
  'u': 'ùúûüũūŭůűųưǔǖǘǚǜȕȗṳṵṷṹṻụủứừửữự',
  'y': 'ýÿŷȳẏẙỳỵỷỹ',
  'd': 'ďḋḍḏḑḓ',
  'g': 'ĝğġģǧǵḡ',
  'h': 'ĥȟḣḥḧḩḫẖ',
  'j': 'ĵǰ',
  'k': 'ķǩḱḳḵ',
  'l': 'ĺļľḷḹḻḽ',
  'r': 'ŕŗřȑȓṙṛṝṟ',
  's': 'śŝşšșṡṣṥṧṩ',
  't': 'ţťțṫṭṯṱẗ',
  'w': 'ŵẁẃẅẇẉẘ',
  'z': 'źżžẑẓẕ',
  'æ': 'ǣǽ',
  'ʒ': 'ǯ',
  'ø': 'ǿ',
  'ι': 'ΐίϊἰἱἲἳἴἵἶἷὶίῐῑῒΐῖῗ',
  'α': 'άἀἁἂἃἄἅἆἇὰάᾀᾁᾂᾃᾄᾅᾆᾇᾰᾱᾲᾳᾴᾶᾷ',
  'ε': 'έἐἑἒἓἔἕὲέ',
  'η': 'ήἠἡἢἣἤἥἦἧὴήᾐᾑᾒᾓᾔᾕᾖᾗῂῃῄῆῇ',
  'υ': 'ΰϋύὐὑὒὓὔὕὖὗὺύῠῡῢΰῦῧ',
  'ο': 'όὀὁὂὃὄὅὸό',
  'ω': 'ώὠὡὢὣὤὥὦὧὼώᾠᾡᾢᾣᾤᾥᾦᾧῲῳῴῶῷ',
  'ϒ': 'ϓϔ',
  'и': 'йѝӣӥ',
  'е': 'ѐёӗ',
  'г': 'ѓ',
  'і': 'ї',
  'к': 'ќ',
  'у': 'ўӯӱӳ',
  'ѵ': 'ѷ',
  'ж': 'ӂӝ',
  'а': 'ӑӓ',
  'ә': 'ӛ',
  'з': 'ӟ',
  'о': 'ӧ',
  'ө': 'ӫ',
  'э': 'ӭ',
  'ч': 'ӵ',
  'ы': 'ӹ',
  'b': 'ḃḅḇ',
  'f': 'ḟ',
  'm': 'ḿṁṃ',
  'p': 'ṕṗ',
  'v': 'ṽṿ',
  'x': 'ẋẍ',
  'ſ': 'ẛ',
  'ρ': 'ῤῥ',
  '𐗒': '𐗉',
  '𐗚': '𐗤',
};

final _letters = {
  for (final group in _accentGroups.entries)
    for (final code in group.value.runes) code: group.key,
};

String foldSearchAccents(String word) {
  if (word.codeUnits.every((code) => code < 128)) return word;
  final result = StringBuffer();
  for (final code in word.runes) {
    if (code >= 0x300 && code <= 0x36f) continue;
    final folded = _letters[code];
    if (folded == null) {
      result.writeCharCode(code);
    } else {
      result.write(folded);
    }
  }
  return result.toString();
}
