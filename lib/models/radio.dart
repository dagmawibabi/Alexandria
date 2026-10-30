/// A live radio station from the directory.
class Station {
  const Station({required this.id, required this.name, required this.url, this.favicon, this.country = '', this.countryCode = '', this.tags = const [], this.language = '', this.bitrate = 0, this.homepage});

  final String id;
  final String name;

  /// The stream itself.
  final String url;
  final String? favicon;
  final String country;
  final String countryCode;
  final List<String> tags;
  final String language;

  /// In kbps; 0 if unknown.
  final int bitrate;
  final String? homepage;

  /// 🇪🇹 from "ET".
  String get flag => flagOf(countryCode);

  /// "jazz · news • 🇪🇹 Ethiopia"
  String get subtitle => [
        if (tags.isNotEmpty) tags.take(2).join(' · '),
        if (country.isNotEmpty) '$flag $country'.trim(),
      ].join(' • ');

  /// TuneIn stations don't carry a stream address until asked for one.
  bool get needsResolving => id.startsWith('ti:');

  /// From a TuneIn outline. [url] then holds the address that yields the stream.
  static Station? fromTuneIn(Map m) {
    final guide = '${m['guide_id'] ?? ''}';
    final name = '${m['text'] ?? ''}'.trim();
    if (m['type'] != 'audio' || m['item'] != 'station' || guide.isEmpty || name.isEmpty) return null;
    final image = '${m['image'] ?? ''}'.trim().replaceFirst('http://', 'https://');
    final note = '${m['subtext'] ?? ''}'.trim();
    return Station(
      id: 'ti:$guide',
      name: name,
      url: 'https://opml.radiotime.com/Tune.ashx?id=$guide&formats=mp3,aac&render=json',
      favicon: image.startsWith('https://') ? image : null,
      tags: note.isEmpty ? const [] : [note],
      bitrate: int.tryParse('${m['bitrate'] ?? ''}') ?? 0,
    );
  }

  /// From the directory's JSON. Null for anything that can't play: phones block
  /// plain-http audio, so only https streams are usable.
  static Station? fromDirectory(Map m) {
    final url = '${m['url_resolved'] ?? ''}'.trim();
    final id = '${m['stationuuid'] ?? ''}';
    final name = '${m['name'] ?? ''}'.trim();
    if (!url.startsWith('https://') || id.isEmpty || name.isEmpty) return null;
    final icon = '${m['favicon'] ?? ''}'.trim();
    final home = '${m['homepage'] ?? ''}'.trim();
    return Station(
      id: id,
      name: name,
      url: url,
      favicon: icon.startsWith('https://') ? icon : null,
      country: '${m['country'] ?? ''}'.trim(),
      countryCode: '${m['countrycode'] ?? ''}'.trim().toUpperCase(),
      tags: '${m['tags'] ?? ''}'.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      language: '${m['language'] ?? ''}'.trim(),
      bitrate: m['bitrate'] is int ? m['bitrate'] : 0,
      homepage: home.startsWith('http') ? home : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'favicon': favicon,
        'country': country,
        'countryCode': countryCode,
        'tags': tags,
        'language': language,
        'bitrate': bitrate,
        'homepage': homepage,
      };

  factory Station.fromJson(Map<String, dynamic> j) => Station(
        id: j['id'] ?? '',
        name: j['name'] ?? '',
        url: j['url'] ?? '',
        favicon: j['favicon'],
        country: j['country'] ?? '',
        countryCode: j['countryCode'] ?? '',
        tags: ((j['tags'] as List?) ?? const []).cast<String>(),
        language: j['language'] ?? '',
        bitrate: j['bitrate'] ?? 0,
        homepage: j['homepage'],
      );
}

/// A country and how many stations it has.
class RadioCountry {
  const RadioCountry(this.code, this.name, this.count);
  final String code;
  final String name;
  final int count;

  String get flag => countryFlag(code, name);
}

/// A country's flag: from its ISO code, or from its name for a directory without codes.
String countryFlag(String code, String name) {
  final direct = flagOf(code);
  if (direct.isNotEmpty) return direct;
  final key = name.trim().toLowerCase().replaceFirst(RegExp(r'^the '), '');
  return flagOf(_isoByName[key] ?? '');
}

String flagOf(String code) {
  if (code.length != 2) return '';
  final c = code.toUpperCase();
  final a = c.codeUnitAt(0), b = c.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

const _isoByName = <String, String>{
  'afghanistan': 'AF',
  'albania': 'AL',
  'algeria': 'DZ',
  'american samoa': 'AS',
  'andorra': 'AD',
  'angola': 'AO',
  'anguilla': 'AI',
  'antigua and barbuda': 'AG',
  'antigua & barbuda': 'AG',
  'argentina': 'AR',
  'armenia': 'AM',
  'aruba': 'AW',
  'australia': 'AU',
  'austria': 'AT',
  'azerbaijan': 'AZ',
  'bahamas': 'BS',
  'bahrain': 'BH',
  'bangladesh': 'BD',
  'barbados': 'BB',
  'belarus': 'BY',
  'belgium': 'BE',
  'belize': 'BZ',
  'benin': 'BJ',
  'bermuda': 'BM',
  'bhutan': 'BT',
  'bolivia': 'BO',
  'bonaire': 'BQ',
  'caribbean netherlands': 'BQ',
  'bosnia and herzegovina': 'BA',
  'bosnia': 'BA',
  'bosnia & herzegovina': 'BA',
  'bosnia-herzegovina': 'BA',
  'botswana': 'BW',
  'brazil': 'BR',
  'british virgin islands': 'VG',
  'brunei': 'BN',
  'brunei darussalam': 'BN',
  'bulgaria': 'BG',
  'burkina faso': 'BF',
  'burundi': 'BI',
  'cambodia': 'KH',
  'cameroon': 'CM',
  'canada': 'CA',
  'cape verde': 'CV',
  'cabo verde': 'CV',
  'cayman islands': 'KY',
  'central african republic': 'CF',
  'chad': 'TD',
  'chile': 'CL',
  'china': 'CN',
  'colombia': 'CO',
  'comoros': 'KM',
  'congo': 'CG',
  'republic of congo': 'CG',
  'republic of the congo': 'CG',
  'congo-brazzaville': 'CG',
  'congo, republic of': 'CG',
  'democratic republic of congo': 'CD',
  'democratic republic of the congo': 'CD',
  'dr congo': 'CD',
  'congo-kinshasa': 'CD',
  'congo, democratic republic of': 'CD',
  'congo democratic republic': 'CD',
  'cook islands': 'CK',
  'costa rica': 'CR',
  'ivory coast': 'CI',
  "cote d'ivoire": 'CI',
  "côte d'ivoire": 'CI',
  'croatia': 'HR',
  'cuba': 'CU',
  'curacao': 'CW',
  'curaçao': 'CW',
  'cyprus': 'CY',
  'czech republic': 'CZ',
  'czechia': 'CZ',
  'denmark': 'DK',
  'djibouti': 'DJ',
  'dominica': 'DM',
  'dominican republic': 'DO',
  'ecuador': 'EC',
  'egypt': 'EG',
  'el salvador': 'SV',
  'equatorial guinea': 'GQ',
  'eritrea': 'ER',
  'estonia': 'EE',
  'eswatini': 'SZ',
  'swaziland': 'SZ',
  'ethiopia': 'ET',
  'falkland islands': 'FK',
  'faroe islands': 'FO',
  'faeroe islands': 'FO',
  'fiji': 'FJ',
  'finland': 'FI',
  'france': 'FR',
  'french guiana': 'GF',
  'french polynesia': 'PF',
  'gabon': 'GA',
  'gambia': 'GM',
  'georgia': 'GE',
  'germany': 'DE',
  'ghana': 'GH',
  'gibraltar': 'GI',
  'greece': 'GR',
  'greenland': 'GL',
  'grenada': 'GD',
  'guadeloupe': 'GP',
  'guam': 'GU',
  'guatemala': 'GT',
  'guernsey': 'GG',
  'guinea': 'GN',
  'guinea-bissau': 'GW',
  'guinea bissau': 'GW',
  'guyana': 'GY',
  'haiti': 'HT',
  'honduras': 'HN',
  'hong kong': 'HK',
  'hungary': 'HU',
  'iceland': 'IS',
  'india': 'IN',
  'indonesia': 'ID',
  'iran': 'IR',
  'iraq': 'IQ',
  'ireland': 'IE',
  'isle of man': 'IM',
  'israel': 'IL',
  'italy': 'IT',
  'jamaica': 'JM',
  'japan': 'JP',
  'jersey': 'JE',
  'jordan': 'JO',
  'kazakhstan': 'KZ',
  'kenya': 'KE',
  'kiribati': 'KI',
  'kosovo': 'XK',
  'kuwait': 'KW',
  'kyrgyzstan': 'KG',
  'laos': 'LA',
  'latvia': 'LV',
  'lebanon': 'LB',
  'lesotho': 'LS',
  'liberia': 'LR',
  'libya': 'LY',
  'liechtenstein': 'LI',
  'lithuania': 'LT',
  'luxembourg': 'LU',
  'macau': 'MO',
  'macao': 'MO',
  'madagascar': 'MG',
  'malawi': 'MW',
  'malaysia': 'MY',
  'maldives': 'MV',
  'mali': 'ML',
  'malta': 'MT',
  'marshall islands': 'MH',
  'martinique': 'MQ',
  'mauritania': 'MR',
  'mauritius': 'MU',
  'mayotte': 'YT',
  'mexico': 'MX',
  'micronesia': 'FM',
  'moldova': 'MD',
  'monaco': 'MC',
  'mongolia': 'MN',
  'montenegro': 'ME',
  'montserrat': 'MS',
  'morocco': 'MA',
  'mozambique': 'MZ',
  'myanmar': 'MM',
  'burma': 'MM',
  'namibia': 'NA',
  'nauru': 'NR',
  'nepal': 'NP',
  'netherlands': 'NL',
  'holland': 'NL',
  'netherlands antilles': 'AN',
  'new caledonia': 'NC',
  'new zealand': 'NZ',
  'nicaragua': 'NI',
  'niger': 'NE',
  'nigeria': 'NG',
  'niue': 'NU',
  'north korea': 'KP',
  'north macedonia': 'MK',
  'macedonia': 'MK',
  'northern mariana islands': 'MP',
  'norway': 'NO',
  'oman': 'OM',
  'pakistan': 'PK',
  'palau': 'PW',
  'palestine': 'PS',
  'palestinian territories': 'PS',
  'palestinian territory': 'PS',
  'panama': 'PA',
  'papua new guinea': 'PG',
  'paraguay': 'PY',
  'peru': 'PE',
  'philippines': 'PH',
  'poland': 'PL',
  'portugal': 'PT',
  'puerto rico': 'PR',
  'qatar': 'QA',
  'reunion': 'RE',
  'réunion': 'RE',
  'romania': 'RO',
  'russia': 'RU',
  'russian federation': 'RU',
  'rwanda': 'RW',
  'saint barthelemy': 'BL',
  'st. barthelemy': 'BL',
  'saint helena': 'SH',
  'st. helena': 'SH',
  'saint kitts and nevis': 'KN',
  'st. kitts and nevis': 'KN',
  'st kitts and nevis': 'KN',
  'saint kitts & nevis': 'KN',
  'st. kitts & nevis': 'KN',
  'saint lucia': 'LC',
  'st. lucia': 'LC',
  'st lucia': 'LC',
  'saint martin': 'MF',
  'st. martin': 'MF',
  'saint pierre and miquelon': 'PM',
  'st. pierre and miquelon': 'PM',
  'saint vincent and the grenadines': 'VC',
  'st. vincent and the grenadines': 'VC',
  'st. vincent': 'VC',
  'saint vincent & the grenadines': 'VC',
  'st. vincent & the grenadines': 'VC',
  'samoa': 'WS',
  'san marino': 'SM',
  'sao tome and principe': 'ST',
  'são tomé and príncipe': 'ST',
  'sao tome & principe': 'ST',
  'saudi arabia': 'SA',
  'senegal': 'SN',
  'serbia': 'RS',
  'seychelles': 'SC',
  'sierra leone': 'SL',
  'singapore': 'SG',
  'sint maarten': 'SX',
  'st. maarten': 'SX',
  'slovakia': 'SK',
  'slovenia': 'SI',
  'solomon islands': 'SB',
  'somalia': 'SO',
  'south africa': 'ZA',
  'south korea': 'KR',
  'korea': 'KR',
  'south sudan': 'SS',
  'spain': 'ES',
  'sri lanka': 'LK',
  'sudan': 'SD',
  'suriname': 'SR',
  'sweden': 'SE',
  'switzerland': 'CH',
  'syria': 'SY',
  'syrian arab republic': 'SY',
  'taiwan': 'TW',
  'tajikistan': 'TJ',
  'tanzania': 'TZ',
  'thailand': 'TH',
  'timor-leste': 'TL',
  'east timor': 'TL',
  'togo': 'TG',
  'tonga': 'TO',
  'trinidad and tobago': 'TT',
  'trinidad & tobago': 'TT',
  'tunisia': 'TN',
  'turkey': 'TR',
  'türkiye': 'TR',
  'turkmenistan': 'TM',
  'turks and caicos islands': 'TC',
  'turks & caicos islands': 'TC',
  'turks and caicos': 'TC',
  'tuvalu': 'TV',
  'uganda': 'UG',
  'ukraine': 'UA',
  'united arab emirates': 'AE',
  'uae': 'AE',
  'united kingdom': 'GB',
  'uk': 'GB',
  'great britain': 'GB',
  'england': 'GB',
  'scotland': 'GB',
  'wales': 'GB',
  'northern ireland': 'GB',
  'united states': 'US',
  'usa': 'US',
  'united states of america': 'US',
  'us': 'US',
  'uruguay': 'UY',
  'us virgin islands': 'VI',
  'u.s. virgin islands': 'VI',
  'virgin islands (u.s.)': 'VI',
  'uzbekistan': 'UZ',
  'vanuatu': 'VU',
  'vatican city': 'VA',
  'vatican': 'VA',
  'holy see': 'VA',
  'venezuela': 'VE',
  'vietnam': 'VN',
  'viet nam': 'VN',
  'wallis and futuna': 'WF',
  'western sahara': 'EH',
  'yemen': 'YE',
  'zambia': 'ZM',
  'zimbabwe': 'ZW',
};
