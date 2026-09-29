import 'package:flutter/foundation.dart';

enum OrderType { dineIn, takeaway, delivery }

extension OrderTypeLabel on OrderType {
  String get label => switch (this) {
        OrderType.dineIn => 'Dine in',
        OrderType.takeaway => 'Takeaway',
        OrderType.delivery => 'Delivery',
      };
}

enum LineState { queued, preparing, ready, served }

extension LineStateLabel on LineState {
  String get label => switch (this) {
        LineState.queued => 'Queued',
        LineState.preparing => 'Preparing',
        LineState.ready => 'Ready',
        LineState.served => 'Served',
      };
}

enum OrderStage { placed, preparing, ready, served, outForDelivery, billing }

extension OrderStageLabel on OrderStage {
  String get label => switch (this) {
        OrderStage.placed => 'Placed',
        OrderStage.preparing => 'Preparing',
        OrderStage.ready => 'Ready',
        OrderStage.served => 'Served',
        OrderStage.outForDelivery => 'Out for delivery',
        OrderStage.billing => 'Billing',
      };
}

enum KotStage { fresh, preparing, ready, done }
/// A kitchen section (Grill, Bread, Drinks…) from the backoffice `kot_groups`.
/// Each group gets its own KOT; which printer(s) it prints on is set per device.
class KotGroup {
  final String id, code, name;
  final int order;
  const KotGroup(this.id, this.code, this.name, this.order);

  Map<String, dynamic> toJson() => {'id': id, 'code': code, 'name': name, 'order': order};
  factory KotGroup.fromJson(Map<String, dynamic> j) =>
      KotGroup(j['id'] as String, j['code'] as String? ?? '', j['name'] as String, j['order'] as int? ?? 0);
}

class Variant {
  final String name;
  final double price;
  /// KOT group for this size, overriding the product's own group.
  final String? kotGroup;
  const Variant(this.name, this.price, {this.kotGroup});

  @override
  bool operator ==(Object other) => other is Variant && name == other.name && price == other.price && kotGroup == other.kotGroup;
  @override
  int get hashCode => Object.hash(name, price, kotGroup);

  Map<String, dynamic> toJson() => {'name': name, 'price': price, 'kotGroup': kotGroup};
  factory Variant.fromJson(Map<String, dynamic> j) =>
      Variant(j['name'] as String, (j['price'] as num).toDouble(), kotGroup: j['kotGroup'] as String?);
}

class Addon {
  final String name;
  final double price;
  const Addon(this.name, this.price);

  @override
  bool operator ==(Object other) => other is Addon && name == other.name && price == other.price;
  @override
  int get hashCode => Object.hash(name, price);

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
  factory Addon.fromJson(Map<String, dynamic> j) => Addon(j['name'] as String, (j['price'] as num).toDouble());
}

class MenuItem {
  final String id, code, cat, name, desc;
  final double price;
  final bool veg, bestseller;
  final List<Variant> variants;
  final List<Addon> addons;
  /// Per-item quick-tap kitchen note presets (e.g. "Dry", "Juicy" for a grilled item),
  /// configured on the product in the backoffice — not a global list.
  final List<String> kitchenNotes;
  /// KOT group id from `product_kot_groups`; null = no group (prints on the counter printer unless routed).
  final String? kotGroup;
  const MenuItem({
    required this.id,
    required this.code,
    required this.cat,
    required this.name,
    required this.price,
    this.veg = false,
    this.desc = '',
    this.bestseller = false,
    this.variants = const [],
    this.addons = const [],
    this.kitchenNotes = const [],
    this.kotGroup,
  });

  bool get customizable => variants.isNotEmpty || addons.isNotEmpty;
  double get fromPrice => variants.isNotEmpty ? variants.first.price : price;
  String get initials {
    final w = name.split(RegExp(r'\s+'));
    return (w.length == 1 ? w.first.substring(0, 2) : '${w[0][0]}${w[1][0]}').toUpperCase();
  }

  String get searchInitials =>
      name.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w[0]).join();

  @override
  bool operator ==(Object other) =>
      other is MenuItem &&
      id == other.id &&
      code == other.code &&
      cat == other.cat &&
      name == other.name &&
      desc == other.desc &&
      price == other.price &&
      veg == other.veg &&
      bestseller == other.bestseller &&
      listEquals(variants, other.variants) &&
      listEquals(addons, other.addons) &&
      listEquals(kitchenNotes, other.kitchenNotes) &&
      kotGroup == other.kotGroup;

  @override
  int get hashCode => Object.hash(id, code, cat, name, desc, price, veg, bestseller);

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'cat': cat,
        'name': name,
        'desc': desc,
        'price': price,
        'veg': veg,
        'bestseller': bestseller,
        'variants': variants.map((v) => v.toJson()).toList(),
        'addons': addons.map((a) => a.toJson()).toList(),
        'kitchenNotes': kitchenNotes,
        'kotGroup': kotGroup,
      };

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id: j['id'] as String,
        code: j['code'] as String,
        cat: j['cat'] as String,
        name: j['name'] as String,
        desc: j['desc'] as String? ?? '',
        price: (j['price'] as num).toDouble(),
        veg: j['veg'] as bool? ?? false,
        bestseller: j['bestseller'] as bool? ?? false,
        variants: (j['variants'] as List? ?? []).map((e) => Variant.fromJson(e as Map<String, dynamic>)).toList(),
        addons: (j['addons'] as List? ?? []).map((e) => Addon.fromJson(e as Map<String, dynamic>)).toList(),
        kitchenNotes: (j['kitchenNotes'] as List? ?? []).map((e) => e as String).toList(),
        kotGroup: j['kotGroup'] as String?,
      );
}

class OrderLine {
  final MenuItem item;
  String? variant;
  List<String> addons;
  int qty;
  String note;
  LineState state;
  int? kotNo;
  /// Units of [qty] cancelled after being sent to the kitchen. [qty] stays the
  /// ordered quantity so history keeps "ordered 4, cancelled 1, remaining 3".
  int cancelledQty;
  /// KOT group this line was routed to, frozen when the line is created so a later
  /// menu change can't re-route a reprint or cancellation of an old item.
  final String? kotGroup;
  /// The per-unit price at the moment this line was created — captured once, never
  /// recomputed from [item], so a later menu price change can't reprice a past order.
  final double unitPrice;

  OrderLine({
    required this.item,
    this.variant,
    List<String>? addons,
    this.qty = 1,
    this.note = '',
    this.state = LineState.queued,
    this.kotNo,
    this.cancelledQty = 0,
    String? kotGroup,
    double? unitPrice,
  })  : addons = addons ?? [],
        kotGroup = kotGroup ?? _resolveGroup(item, variant),
        unitPrice = unitPrice ?? _resolveUnit(item, variant, addons ?? []);

  static String? _resolveGroup(MenuItem item, String? variant) {
    for (final v in item.variants) {
      if (v.name == variant && v.kotGroup != null) return v.kotGroup;
    }
    return item.kotGroup;
  }

  static double _resolveUnit(MenuItem item, String? variant, List<String> addons) {
    double b = item.price;
    if (variant != null) {
      for (final v in item.variants) {
        if (v.name == variant) b = v.price;
      }
    }
    for (final a in addons) {
      for (final x in item.addons) {
        if (x.name == a) b += x.price;
      }
    }
    return b;
  }

  double get unit => unitPrice;
  int get activeQty => qty - cancelledQty;
  double get total => unit * activeQty;
  String get optText => [if (variant != null) variant!, ...addons.map((a) => '+ $a')].join(' · ');
  List<String> get mods => [if (variant != null) '> $variant', ...addons.map((a) => '+ $a')];

  bool sameConfig(OrderLine o) =>
      o.item.id == item.id && o.variant == variant && setEquals(o.addons.toSet(), addons.toSet()) && o.note == note;

  OrderLine copy() => OrderLine(
      item: item,
      variant: variant,
      addons: [...addons],
      qty: qty,
      note: note,
      state: state,
      kotNo: kotNo,
      cancelledQty: cancelledQty,
      kotGroup: kotGroup,
      unitPrice: unitPrice);

  /// A frozen snapshot — [item] is reconstructed from stored fields, not looked up in the
  /// live menu, so a deleted/renamed product can't break loading a historical order.
  Map<String, dynamic> toJson() => {
        'itemId': item.id,
        'itemCode': item.code,
        'itemCat': item.cat,
        'itemName': item.name,
        'itemVeg': item.veg,
        'variant': variant,
        'addons': addons,
        'qty': qty,
        'note': note,
        'state': state.name,
        'kotNo': kotNo,
        'cancelledQty': cancelledQty,
        'kotGroup': kotGroup,
        'unitPrice': unitPrice,
      };

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        item: MenuItem(
          id: j['itemId'] as String,
          code: j['itemCode'] as String? ?? '',
          cat: j['itemCat'] as String? ?? '',
          name: j['itemName'] as String,
          price: (j['unitPrice'] as num).toDouble(),
          veg: j['itemVeg'] as bool? ?? false,
        ),
        variant: j['variant'] as String?,
        addons: (j['addons'] as List? ?? []).map((e) => e as String).toList(),
        qty: j['qty'] as int? ?? 1,
        note: j['note'] as String? ?? '',
        state: LineState.values.byName(j['state'] as String),
        kotNo: j['kotNo'] as int?,
        cancelledQty: j['cancelledQty'] as int? ?? 0,
        kotGroup: j['kotGroup'] as String?,
        unitPrice: (j['unitPrice'] as num).toDouble(),
      );
}

enum KotKind { order, cancel, modify }

class Kot {
  final int no;
  final int orderId;
  final DateTime at;
  /// Items the kitchen should make. Shared with the order's own lines, so kitchen
  /// progress and later cancellations show up here too.
  final List<OrderLine> lines;
  /// Items the kitchen should stop making: frozen snapshots, `qty` = units cancelled.
  final List<OrderLine> voided;
  final String reason;
  final String by;
  /// KOT group this ticket is for (null = items with no group).
  final String? group;
  /// Numbers of every KOT sent in the same go (this one included), in print
  /// order, so each ticket can say "1 of 3" and name the others.
  final List<int> batch;
  Kot(this.no, this.orderId, this.at, this.lines,
      {List<OrderLine>? voided, this.reason = '', this.by = '', this.group, List<int>? batch})
      : voided = voided ?? [],
        batch = batch ?? [];

  /// No voided lines: a normal KOT. Only voided: a cancellation. Both: an edited item.
  KotKind get kind => voided.isEmpty ? KotKind.order : (lines.isEmpty ? KotKind.cancel : KotKind.modify);

  KotStage get stage {
    final live = lines.where((l) => l.activeQty > 0);
    if (live.every((l) => l.state == LineState.served)) return KotStage.done;
    if (live.every((l) => l.state.index >= LineState.ready.index)) return KotStage.ready;
    if (live.any((l) => l.state != LineState.queued)) return KotStage.preparing;
    return KotStage.fresh;
  }

  Map<String, dynamic> toJson() => {
        'no': no,
        'orderId': orderId,
        'at': at.toIso8601String(),
        'lines': lines.map((l) => l.toJson()).toList(),
        'voided': voided.map((l) => l.toJson()).toList(),
        'reason': reason,
        'by': by,
        'group': group,
        'batch': batch,
      };

  factory Kot.fromJson(Map<String, dynamic> j) => Kot(
        j['no'] as int,
        j['orderId'] as int,
        DateTime.parse(j['at'] as String),
        (j['lines'] as List? ?? []).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
        voided: (j['voided'] as List? ?? []).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
        reason: j['reason'] as String? ?? '',
        by: j['by'] as String? ?? '',
        group: j['group'] as String?,
        batch: (j['batch'] as List? ?? []).cast<int>(),
      );
}

/// Audit record of units cancelled from a sent line. Kept on the order so it
/// survives into history with who, what, why and which cancellation KOT.
class ItemCancellation {
  final String itemName, optText, reason, by;
  final int qty, kotNo;
  final double unitPrice;
  final DateTime at;
  const ItemCancellation(
      {required this.itemName,
      required this.optText,
      required this.qty,
      required this.unitPrice,
      required this.reason,
      required this.by,
      required this.kotNo,
      required this.at});

  Map<String, dynamic> toJson() => {
        'itemName': itemName,
        'optText': optText,
        'qty': qty,
        'unitPrice': unitPrice,
        'reason': reason,
        'by': by,
        'kotNo': kotNo,
        'at': at.toIso8601String(),
      };

  factory ItemCancellation.fromJson(Map<String, dynamic> j) => ItemCancellation(
        itemName: j['itemName'] as String,
        optText: j['optText'] as String? ?? '',
        qty: j['qty'] as int,
        unitPrice: (j['unitPrice'] as num).toDouble(),
        reason: j['reason'] as String? ?? '',
        by: j['by'] as String? ?? '',
        kotNo: j['kotNo'] as int,
        at: DateTime.parse(j['at'] as String),
      );
}

/// Default reasons offered when cancelling an item; the outlet can't edit these
/// locally yet (backoffice `cancellation_reasons` is not synced).
const defaultCancelReasons = [
  'Customer changed mind',
  'Wrong item entered',
  'Out of stock',
  'Kitchen unable to prepare',
  'Duplicate order',
  'Captain mistake',
  'Other',
];

class Payment {
  final String method; // Cash / UPI
  final double amount;
  final double tendered;
  const Payment(this.method, this.amount, [this.tendered = 0]);
  double get change => method == 'Cash' && tendered > amount ? tendered - amount : 0;

  Map<String, dynamic> toJson() => {'method': method, 'amount': amount, 'tendered': tendered};
  factory Payment.fromJson(Map<String, dynamic> j) =>
      Payment(j['method'] as String, (j['amount'] as num).toDouble(), (j['tendered'] as num?)?.toDouble() ?? 0);
}

class Order {
  int id;
  final OrderType type;
  final String? tableId;
  final String? partyKey;
  String token;
  String customer, phone, address;
  final DateTime at;
  final List<OrderLine> lines = [];
  final List<Payment> payments = [];
  final List<ItemCancellation> cancellations = [];
  int pax;
  bool billed = false;
  /// When the current bill was printed (null before billing, or for bills
  /// printed before this was tracked).
  DateTime? billedAt;
  /// Whole order voided (every item cancelled); kept in history for audit.
  bool voided = false;
  String? billNo;
  bool dispatched = false;
  String? rider;
  String server;
  String payNote;

  Order({
    required this.id,
    required this.type,
    this.tableId,
    this.partyKey,
    this.token = '',
    this.customer = '',
    this.phone = '',
    this.address = '',
    DateTime? at,
    this.pax = 1,
    this.server = '',
    this.payNote = 'Unpaid',
  }) : at = at ?? DateTime.now();

  double get subtotal => lines.fold<double>(0, (a, l) => a + l.total);
  double get tax => subtotal * 0.05;
  double get fee => type == OrderType.delivery ? 40 : 0;
  double get raw => subtotal + tax + fee;
  double get total => raw.roundToDouble();
  /// Lines with anything left after cancellations.
  List<OrderLine> get liveLines => lines.where((l) => l.activeQty > 0).toList();
  int get itemCount => lines.fold<int>(0, (a, l) => a + l.activeQty);
  double get paid => payments.fold<double>(0, (a, p) => a + p.amount);
  /// Paid in full: taken up front (takeaway "Pay now") or marked paid.
  bool get isPaid => payNote.startsWith('Paid') || (payments.isNotEmpty && paid >= total - .005);

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'tableId': tableId,
        'partyKey': partyKey,
        'token': token,
        'customer': customer,
        'phone': phone,
        'address': address,
        'at': at.toIso8601String(),
        'pax': pax,
        'billed': billed,
        'billNo': billNo,
        'billedAt': billedAt?.toIso8601String(),
        'dispatched': dispatched,
        'rider': rider,
        'server': server,
        'payNote': payNote,
        'lines': lines.map((l) => l.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
        'cancellations': cancellations.map((c) => c.toJson()).toList(),
        'voided': voided,
      };

  factory Order.fromJson(Map<String, dynamic> j) {
    final o = Order(
      id: j['id'] as int,
      type: OrderType.values.byName(j['type'] as String),
      tableId: j['tableId'] as String?,
      partyKey: j['partyKey'] as String?,
      token: j['token'] as String? ?? '',
      customer: j['customer'] as String? ?? '',
      phone: j['phone'] as String? ?? '',
      address: j['address'] as String? ?? '',
      at: DateTime.parse(j['at'] as String),
      pax: j['pax'] as int? ?? 1,
      server: j['server'] as String? ?? '',
      payNote: j['payNote'] as String? ?? 'Unpaid',
    )
      ..billed = j['billed'] as bool? ?? false
      ..billNo = j['billNo'] as String?
      ..billedAt = DateTime.tryParse(j['billedAt'] as String? ?? '')
      ..dispatched = j['dispatched'] as bool? ?? false
      ..rider = j['rider'] as String?
      ..voided = j['voided'] as bool? ?? false;
    o.lines.addAll((j['lines'] as List? ?? []).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)));
    o.payments.addAll((j['payments'] as List? ?? []).map((e) => Payment.fromJson(e as Map<String, dynamic>)));
    o.cancellations
        .addAll((j['cancellations'] as List? ?? []).map((e) => ItemCancellation.fromJson(e as Map<String, dynamic>)));
    return o;
  }
}

class Party {
  final String key;
  int pax;
  final DateTime seatedAt;
  int? orderId;
  Party(this.key, this.pax, {DateTime? seatedAt, this.orderId}) : seatedAt = seatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {'key': key, 'pax': pax, 'seatedAt': seatedAt.toIso8601String(), 'orderId': orderId};
  factory Party.fromJson(Map<String, dynamic> j) => Party(j['key'] as String, j['pax'] as int,
      seatedAt: DateTime.parse(j['seatedAt'] as String), orderId: j['orderId'] as int?);
}

class MenuSyncResult {
  final int added, updated, removed;
  final DateTime at;
  MenuSyncResult({required this.added, required this.updated, this.removed = 0, required this.at});
  int get changed => added + updated + removed;
}

enum PrinterConn { usb, bluetooth, lan }

extension PrinterConnLabel on PrinterConn {
  String get label => switch (this) {
        PrinterConn.usb => 'USB',
        PrinterConn.bluetooth => 'Bluetooth',
        PrinterConn.lan => 'Network (LAN)',
      };
}

/// A configured KOT/bill printer, reached over USB / Bluetooth (Classic or BLE) / raw LAN
/// socket depending on [conn] (see [Store.testPrint]).
class PosPrinter {
  String id;
  String name;
  PrinterConn conn;
  String station;
  bool forBill;
  bool forKot;
  String? ip;
  int port;
  String? btAddress;
  String? usbIdentifier;
  DateTime? lastTestAt;
  bool? lastTestOk;

  PosPrinter({
    required this.id,
    required this.name,
    required this.conn,
    this.station = '',
    this.forBill = false,
    this.forKot = false,
    this.ip,
    this.port = 9100,
    this.btAddress,
    this.usbIdentifier,
    this.lastTestAt,
    this.lastTestOk,
  });

  String get connSummary => switch (conn) {
        PrinterConn.lan => '${ip?.isNotEmpty == true ? ip : '—'}:$port',
        PrinterConn.bluetooth => btAddress?.isNotEmpty == true ? btAddress! : 'Not paired',
        PrinterConn.usb => usbIdentifier?.isNotEmpty == true ? usbIdentifier! : 'Not selected',
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'conn': conn.name,
        'station': station,
        'forBill': forBill,
        'forKot': forKot,
        'ip': ip,
        'port': port,
        'btAddress': btAddress,
        'usbIdentifier': usbIdentifier,
        'lastTestAt': lastTestAt?.toIso8601String(),
        'lastTestOk': lastTestOk,
      };

  factory PosPrinter.fromJson(Map<String, dynamic> j) => PosPrinter(
        id: j['id'] as String,
        name: j['name'] as String,
        conn: PrinterConn.values.byName(j['conn'] as String),
        station: j['station'] as String? ?? '',
        forBill: j['forBill'] as bool? ?? false,
        forKot: j['forKot'] as bool? ?? false,
        ip: j['ip'] as String?,
        port: j['port'] as int? ?? 9100,
        btAddress: j['btAddress'] as String?,
        usbIdentifier: j['usbIdentifier'] as String?,
        lastTestAt: j['lastTestAt'] == null ? null : DateTime.tryParse(j['lastTestAt'] as String),
        lastTestOk: j['lastTestOk'] as bool?,
      );
}

class TableModel {
  final String id;
  String floor;
  int seats, w, h;
  String? reservedFor;
  final List<Party> parties = [];
  TableModel(this.id, this.floor, this.seats, {this.w = 1, this.h = 1, this.reservedFor});
  int get used => parties.fold<int>(0, (a, p) => a + p.pax);
  int get free => seats - used;

  Map<String, dynamic> toJson() => {
        'id': id,
        'floor': floor,
        'seats': seats,
        'w': w,
        'h': h,
        'parties': parties.map((p) => p.toJson()).toList(),
      };
  factory TableModel.fromJson(Map<String, dynamic> j) {
    final t = TableModel(
      j['id'] as String,
      j['floor'] as String,
      j['seats'] as int,
      w: j['w'] as int? ?? 1,
      h: j['h'] as int? ?? 1,
    );
    t.parties.addAll((j['parties'] as List? ?? []).map((e) => Party.fromJson(e as Map<String, dynamic>)));
    return t;
  }
}

enum PrinterHealth { unknown, checking, online, offline }

/// Last known reachability of a printer (see Store.checkPrinters).
class PrinterStatus {
  final PrinterHealth health;
  final String? error;
  final DateTime? at;
  const PrinterStatus(this.health, {this.error, this.at});
}
