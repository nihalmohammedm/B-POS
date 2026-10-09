/// One UPI ID the restaurant collects payments on. Bills carry a QR built from
/// it (with the bill amount filled in), so the guest's app opens ready to pay.
class UpiAccount {
  final String id;
  String label; // what staff see, e.g. "Counter GPay"
  String vpa; // the UPI ID, e.g. shop@okhdfcbank
  String payee; // name the guest's app shows; empty = [label]

  UpiAccount({required this.id, required this.label, required this.vpa, this.payee = ''});

  /// Loose check: something before and after one "@".
  static bool validVpa(String v) => RegExp(r'^[\w.\-]{2,}@[A-Za-z][\w.\-]*$').hasMatch(v);

  /// The deep link encoded in the QR. Any UPI app can scan it.
  String uri(double amount, {String note = ''}) {
    final q = <String, String>{
      'pa': vpa,
      'pn': payee.isEmpty ? label : payee,
      if (amount > 0) 'am': amount.toStringAsFixed(2),
      'cu': 'INR',
      if (note.isNotEmpty) 'tn': note,
    };
    return 'upi://pay?${q.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
  }

  Map<String, dynamic> toJson() => {'id': id, 'label': label, 'vpa': vpa, 'payee': payee};

  factory UpiAccount.fromJson(Map<String, dynamic> j) => UpiAccount(
        id: '${j['id'] ?? ''}',
        label: '${j['label'] ?? ''}',
        vpa: '${j['vpa'] ?? ''}',
        payee: '${j['payee'] ?? ''}',
      );
}

/// What goes on printed bills and KOTs. Read by both the on-screen preview
/// ([ReceiptView]) and the ESC/POS renderer ([receiptBytes]), so the preview
/// always matches the paper. Edited in Settings › Print layout.
///
/// Presentation only: tax rate and totals still come from the order itself,
/// so a layout change never alters an amount.
class PrintLayout {
  int paperMm; // 58 or 80

  // ---------- bill / invoice ----------
  bool billShowName;
  String billName; // empty = outlet name from the backoffice
  bool billShowAddress;
  bool billShowPhone;
  String billHeader; // extra lines under the address, e.g. GSTIN / FSSAI
  String billTitlePaid;
  String billTitleUnpaid;
  bool billShowServer;
  bool billShowPax;
  bool billShowCustomer;
  bool billShowRate;
  bool billShowMods;
  bool billSplitGst; // CGST + SGST lines instead of one GST line
  bool billShowRoundOff;
  bool billShowQr;
  List<UpiAccount> upiAccounts; // every UPI ID the restaurant uses
  String billUpiId; // which one's QR goes on bills; empty/unknown = the first
  String billFooter;
  String billFooterTakeaway; // extra footer lines, takeaway bills only
  bool billShowWords;
  int billCopies;
  int billTopLines; // blank lines fed before the header
  int billBottomLines; // blank lines fed after the footer, before the cut
  bool takeawayBillWithKot; // takeaway: print the bill right after the KOTs

  // ---------- KOT ----------
  String kotTitle;
  String kotCancelTitle; // heading on a cancellation KOT
  String kotModifyTitle; // heading when an item was changed
  bool kotShowReason; // cancellation reason and who cancelled
  bool kotShowGroup; // KOT group name (Grill, Bread…) under the KOT number
  bool kotShowSplit; // "KOT 1 of 3 · Also: Bread #13" when an order split into several KOTs
  bool kotShowBanner;
  bool kotShowServer;
  bool kotShowPax;
  bool kotShowCustomer;
  bool kotUppercase;
  bool kotLargeItems;
  bool kotShowMods;
  bool kotShowNotes;
  bool kotShowTotal;
  bool kotShowOutlet;
  String kotFooter;
  int kotCopies;
  int kotTopLines;
  int kotBottomLines;

  PrintLayout({
    this.paperMm = 80,
    this.billShowName = true,
    this.billName = '',
    this.billShowAddress = true,
    this.billShowPhone = true,
    this.billHeader = '',
    this.billTitlePaid = 'TAX INVOICE',
    this.billTitleUnpaid = 'BILL · NOT PAID',
    this.billShowServer = true,
    this.billShowPax = true,
    this.billShowCustomer = true,
    this.billShowRate = true,
    this.billShowMods = true,
    this.billSplitGst = true,
    this.billShowRoundOff = true,
    this.billShowQr = true,
    List<UpiAccount>? upiAccounts,
    this.billUpiId = '',
    this.billFooter = 'Thank you! Visit again',
    this.billFooterTakeaway = '',
    this.billShowWords = true,
    this.billCopies = 1,
    this.billTopLines = 0,
    this.billBottomLines = 3,
    this.takeawayBillWithKot = true,
    this.kotTitle = 'KITCHEN ORDER TICKET',
    this.kotCancelTitle = 'CANCELLED',
    this.kotModifyTitle = 'ITEM CHANGED',
    this.kotShowReason = true,
    this.kotShowGroup = true,
    this.kotShowSplit = true,
    this.kotShowBanner = true,
    this.kotShowServer = true,
    this.kotShowPax = true,
    this.kotShowCustomer = true,
    this.kotUppercase = true,
    this.kotLargeItems = true,
    this.kotShowMods = true,
    this.kotShowNotes = true,
    this.kotShowTotal = true,
    this.kotShowOutlet = true,
    this.kotFooter = '',
    this.kotCopies = 1,
    this.kotTopLines = 0,
    this.kotBottomLines = 3,
  }) : upiAccounts = upiAccounts ?? [];

  /// The account whose QR is printed on bills, if any are set up.
  UpiAccount? get billUpi {
    if (upiAccounts.isEmpty) return null;
    return upiAccounts.firstWhere((a) => a.id == billUpiId, orElse: () => upiAccounts.first);
  }

  static const maxFeedLines = 12;

  int topLines(bool kot) => kot ? kotTopLines : billTopLines;
  int bottomLines(bool kot) => kot ? kotBottomLines : billBottomLines;

  PrintLayout copy() => PrintLayout.fromJson(toJson());

  static List<String> linesOf(String s) => s.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

  Map<String, dynamic> toJson() => {
        'paperMm': paperMm,
        'billShowName': billShowName,
        'billName': billName,
        'billShowAddress': billShowAddress,
        'billShowPhone': billShowPhone,
        'billHeader': billHeader,
        'billTitlePaid': billTitlePaid,
        'billTitleUnpaid': billTitleUnpaid,
        'billShowServer': billShowServer,
        'billShowPax': billShowPax,
        'billShowCustomer': billShowCustomer,
        'billShowRate': billShowRate,
        'billShowMods': billShowMods,
        'billSplitGst': billSplitGst,
        'billShowRoundOff': billShowRoundOff,
        'billShowQr': billShowQr,
        'upiAccounts': upiAccounts.map((a) => a.toJson()).toList(),
        'billUpiId': billUpiId,
        'billFooter': billFooter,
        'billFooterTakeaway': billFooterTakeaway,
        'billShowWords': billShowWords,
        'billCopies': billCopies,
        'billTopLines': billTopLines,
        'billBottomLines': billBottomLines,
        'takeawayBillWithKot': takeawayBillWithKot,
        'kotTitle': kotTitle,
        'kotCancelTitle': kotCancelTitle,
        'kotModifyTitle': kotModifyTitle,
        'kotShowReason': kotShowReason,
        'kotShowGroup': kotShowGroup,
        'kotShowSplit': kotShowSplit,
        'kotShowBanner': kotShowBanner,
        'kotShowServer': kotShowServer,
        'kotShowPax': kotShowPax,
        'kotShowCustomer': kotShowCustomer,
        'kotUppercase': kotUppercase,
        'kotLargeItems': kotLargeItems,
        'kotShowMods': kotShowMods,
        'kotShowNotes': kotShowNotes,
        'kotShowTotal': kotShowTotal,
        'kotShowOutlet': kotShowOutlet,
        'kotFooter': kotFooter,
        'kotCopies': kotCopies,
        'kotTopLines': kotTopLines,
        'kotBottomLines': kotBottomLines,
      };

  /// Missing keys fall back to the defaults, so layouts saved by an older
  /// build keep working when new options are added.
  factory PrintLayout.fromJson(Map<String, dynamic> j) {
    final d = PrintLayout();
    bool b(String k, bool def) => j[k] is bool ? j[k] as bool : def;
    String s(String k, String def) => j[k] is String ? j[k] as String : def;
    int i(String k, int def) => j[k] is num ? (j[k] as num).toInt() : def;
    return PrintLayout(
      paperMm: i('paperMm', d.paperMm) == 58 ? 58 : 80,
      billShowName: b('billShowName', d.billShowName),
      billName: s('billName', d.billName),
      billShowAddress: b('billShowAddress', d.billShowAddress),
      billShowPhone: b('billShowPhone', d.billShowPhone),
      billHeader: s('billHeader', d.billHeader),
      billTitlePaid: s('billTitlePaid', d.billTitlePaid),
      billTitleUnpaid: s('billTitleUnpaid', d.billTitleUnpaid),
      billShowServer: b('billShowServer', d.billShowServer),
      billShowPax: b('billShowPax', d.billShowPax),
      billShowCustomer: b('billShowCustomer', d.billShowCustomer),
      billShowRate: b('billShowRate', d.billShowRate),
      billShowMods: b('billShowMods', d.billShowMods),
      billSplitGst: b('billSplitGst', d.billSplitGst),
      billShowRoundOff: b('billShowRoundOff', d.billShowRoundOff),
      billShowQr: b('billShowQr', d.billShowQr),
      upiAccounts: [
        if (j['upiAccounts'] is List)
          for (final a in j['upiAccounts'] as List)
            if (a is Map<String, dynamic>) UpiAccount.fromJson(a),
      ],
      billUpiId: s('billUpiId', d.billUpiId),
      billFooter: s('billFooter', d.billFooter),
      billFooterTakeaway: s('billFooterTakeaway', d.billFooterTakeaway),
      billShowWords: b('billShowWords', d.billShowWords),
      billCopies: i('billCopies', d.billCopies).clamp(1, 3),
      billTopLines: i('billTopLines', d.billTopLines).clamp(0, maxFeedLines),
      billBottomLines: i('billBottomLines', d.billBottomLines).clamp(0, maxFeedLines),
      takeawayBillWithKot: b('takeawayBillWithKot', d.takeawayBillWithKot),
      kotTitle: s('kotTitle', d.kotTitle),
      kotCancelTitle: s('kotCancelTitle', d.kotCancelTitle),
      kotModifyTitle: s('kotModifyTitle', d.kotModifyTitle),
      kotShowReason: b('kotShowReason', d.kotShowReason),
      kotShowGroup: b('kotShowGroup', d.kotShowGroup),
      kotShowSplit: b('kotShowSplit', d.kotShowSplit),
      kotShowBanner: b('kotShowBanner', d.kotShowBanner),
      kotShowServer: b('kotShowServer', d.kotShowServer),
      kotShowPax: b('kotShowPax', d.kotShowPax),
      kotShowCustomer: b('kotShowCustomer', d.kotShowCustomer),
      kotUppercase: b('kotUppercase', d.kotUppercase),
      kotLargeItems: b('kotLargeItems', d.kotLargeItems),
      kotShowMods: b('kotShowMods', d.kotShowMods),
      kotShowNotes: b('kotShowNotes', d.kotShowNotes),
      kotShowTotal: b('kotShowTotal', d.kotShowTotal),
      kotShowOutlet: b('kotShowOutlet', d.kotShowOutlet),
      kotFooter: s('kotFooter', d.kotFooter),
      kotCopies: i('kotCopies', d.kotCopies).clamp(1, 3),
      kotTopLines: i('kotTopLines', d.kotTopLines).clamp(0, maxFeedLines),
      kotBottomLines: i('kotBottomLines', d.kotBottomLines).clamp(0, maxFeedLines),
    );
  }
}
