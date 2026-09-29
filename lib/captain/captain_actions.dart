import 'package:flutter/widgets.dart';

import '../link/captain_link.dart';
import '../models.dart';
import '../store.dart';
import '../widgets/common.dart';

/// Which order a captain screen is working on. Captain screens hold a
/// reference, not the [Order] object: on a paired phone the local copy is
/// replaced by every snapshot from the POS.
class OrderRef {
  final String? tableId, partyKey;
  final int? orderId;
  const OrderRef.party(String this.tableId, String this.partyKey) : orderId = null;
  const OrderRef.order(int this.orderId)
      : tableId = null,
        partyKey = null;
  const OrderRef.newTakeaway()
      : tableId = null,
        partyKey = null,
        orderId = null;
  bool get dineIn => tableId != null;
}

class SentKot {
  final int orderId;
  final List<int> kots;
  final String label;
  const SentKot(this.orderId, this.kots, this.label);
}

/// Everything a captain can change. On a paired phone each call is a request
/// to the main POS over the Wi-Fi ([RemoteCaptainActions]); in the one-device
/// demo launcher it changes the shared Store directly ([LocalCaptainActions]).
/// Failures throw [LinkError] with a message for the captain.
abstract class CaptainActions {
  String get name;
  bool get canAct;
  Future<String> seat(TableModel t, int pax);
  Future<void> setPax(TableModel t, Party p, int pax);
  Future<void> freeParty(TableModel t, Party p);
  Future<SentKot> sendKot(OrderRef ref, List<OrderLine> lines, {String customer = '', String phone = ''});
  Future<void> requestBill(Order o);
  Future<String?> reopen(Order o);
  Future<void> updateCustomer(Order o, String customer, String phone);

  static CaptainActions of(BuildContext context) {
    final link = CaptainLinkScope.read(context);
    return link != null ? RemoteCaptainActions(link) : LocalCaptainActions(StoreScope.read(context));
  }

  /// The captain's own order, or a blank one until the first KOT creates it.
  static Order resolve(Store s, OrderRef ref, {int? orderId, required Order Function() blank}) {
    if (ref.dineIn) {
      for (final o in s.orders) {
        if (o.tableId == ref.tableId && o.partyKey == ref.partyKey) return o;
      }
      return blank();
    }
    final id = orderId ?? ref.orderId;
    if (id != null) {
      final o = s.orderById(id);
      if (o != null) return o;
    }
    return blank();
  }
}

class RemoteCaptainActions implements CaptainActions {
  final CaptainLink link;
  RemoteCaptainActions(this.link);

  @override
  String get name => link.captainName.isEmpty ? 'Captain' : link.captainName;
  @override
  bool get canAct => link.online;

  @override
  Future<String> seat(TableModel t, int pax) async => (await link.call('seat', {'table': t.id, 'pax': pax}))['party'] as String;
  @override
  Future<void> setPax(TableModel t, Party p, int pax) => link.call('setPax', {'table': t.id, 'party': p.key, 'pax': pax});
  @override
  Future<void> freeParty(TableModel t, Party p) => link.call('freeParty', {'table': t.id, 'party': p.key});

  @override
  Future<SentKot> sendKot(OrderRef ref, List<OrderLine> lines, {String customer = '', String phone = ''}) async {
    final r = await link.call('sendKot', {
      // One id per send, so a retry after a lost reply can't print twice.
      'req': '${DateTime.now().microsecondsSinceEpoch}-${lines.length}',
      if (ref.dineIn) ...{'table': ref.tableId, 'party': ref.partyKey},
      if (!ref.dineIn && ref.orderId != null) 'orderId': ref.orderId,
      'customer': customer,
      'phone': phone,
      'lines': [
        for (final l in lines)
          {'itemId': l.item.id, 'itemName': l.item.name, 'variant': l.variant, 'addons': l.addons, 'qty': l.qty, 'note': l.note}
      ],
    });
    return SentKot((r['orderId'] as num).toInt(), [for (final k in r['kots'] as List) (k as num).toInt()], r['label'] as String? ?? '');
  }

  @override
  Future<void> requestBill(Order o) => link.call('requestBill', {'orderId': o.id});
  @override
  Future<String?> reopen(Order o) async => (await link.call('reopen', {'orderId': o.id}))['voided'] as String?;
  @override
  Future<void> updateCustomer(Order o, String customer, String phone) =>
      link.call('updateCustomer', {'orderId': o.id, 'customer': customer, 'phone': phone});
}

/// The launcher demo: captain and POS in one app sharing one Store.
class LocalCaptainActions implements CaptainActions {
  final Store s;
  LocalCaptainActions(this.s);

  @override
  String get name => 'Captain';
  @override
  bool get canAct => true;

  @override
  Future<String> seat(TableModel t, int pax) async {
    if (pax > t.free) throw LinkError('Only ${t.free} free seats on ${t.id}');
    return s.seatParty(t, pax).key;
  }

  @override
  Future<void> setPax(TableModel t, Party p, int pax) async {
    if (!s.setPax(t, p, pax)) throw LinkError('No free seats on ${t.id}');
  }

  @override
  Future<void> freeParty(TableModel t, Party p) async {
    if (!s.freeParty(t, p)) throw LinkError('This party has items');
  }

  @override
  Future<SentKot> sendKot(OrderRef ref, List<OrderLine> lines, {String customer = '', String phone = ''}) async {
    Order o;
    if (ref.dineIn) {
      final t = s.table(ref.tableId!);
      final p = s.party(t.id, ref.partyKey!) ?? (throw LinkError('That party is no longer seated'));
      o = s.ensurePartyOrder(t, p, server: name);
    } else {
      o = (ref.orderId == null ? null : s.orderById(ref.orderId!)) ?? s.draft(OrderType.takeaway, server: name);
      o
        ..customer = customer
        ..phone = phone;
    }
    if (o.billed) throw LinkError('Bill printed · reopen it first');
    final ks = s.sendKot(o, lines);
    return SentKot(o.id, [for (final k in ks) k.no], s.labelOf(o));
  }

  @override
  Future<void> requestBill(Order o) async => s.requestBill(o, name);
  @override
  Future<String?> reopen(Order o) async => s.reopen(o);
  @override
  Future<void> updateCustomer(Order o, String customer, String phone) async {
    o
      ..customer = customer
      ..phone = phone;
    s.touch();
  }
}
