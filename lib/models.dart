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

class Variant {
  final String name;
  final double price;
  const Variant(this.name, this.price);

  @override
  bool operator ==(Object other) => other is Variant && name == other.name && price == other.price;
  @override
  int get hashCode => Object.hash(name, price);

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
  factory Variant.fromJson(Map<String, dynamic> j) => Variant(j['name'] as String, (j['price'] as num).toDouble());
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
      listEquals(kitchenNotes, other.kitchenNotes);

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
    double? unitPrice,
  })  : addons = addons ?? [],
        unitPrice = unitPrice ?? _resolveUnit(item, variant, addons ?? []);

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
  double get total => unit * qty;
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
        unitPrice: (j['unitPrice'] as num).toDouble(),
      );
}

class Kot {
  final int no;
  final int orderId;
  final DateTime at;
  final List<OrderLine> lines;
  Kot(this.no, this.orderId, this.at, this.lines);

  KotStage get stage {
    if (lines.every((l) => l.state == LineState.served)) return KotStage.done;
    if (lines.every((l) => l.state.index >= LineState.ready.index)) return KotStage.ready;
    if (lines.any((l) => l.state != LineState.queued)) return KotStage.preparing;
    return KotStage.fresh;
  }

  Map<String, dynamic> toJson() =>
      {'no': no, 'orderId': orderId, 'at': at.toIso8601String(), 'lines': lines.map((l) => l.toJson()).toList()};

  factory Kot.fromJson(Map<String, dynamic> j) => Kot(
        j['no'] as int,
        j['orderId'] as int,
        DateTime.parse(j['at'] as String),
        (j['lines'] as List? ?? []).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

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
  int pax;
  bool billed = false;
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
  int get itemCount => lines.fold<int>(0, (a, l) => a + l.qty);
  bool get isPaid => payNote.startsWith('Paid');

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
        'dispatched': dispatched,
        'rider': rider,
        'server': server,
        'payNote': payNote,
        'lines': lines.map((l) => l.toJson()).toList(),
        'payments': payments.map((p) => p.toJson()).toList(),
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
      ..dispatched = j['dispatched'] as bool? ?? false
      ..rider = j['rider'] as String?;
    o.lines.addAll((j['lines'] as List? ?? []).map((e) => OrderLine.fromJson(e as Map<String, dynamic>)));
    o.payments.addAll((j['payments'] as List? ?? []).map((e) => Payment.fromJson(e as Map<String, dynamic>)));
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

/// A configured KOT/bill printer. Connection I/O is not wired up yet (see [Store.testPrint]) —
/// this models the setup a real ESC/POS transport (USB / Bluetooth SPP / raw LAN socket) will
/// eventually be built against, one per [conn] type.
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
