// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $MenuItemRowsTable extends MenuItemRows
    with TableInfo<$MenuItemRowsTable, MenuItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MenuItemRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'menu_item_rows';
  @override
  VerificationContext validateIntegrity(Insertable<MenuItemRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MenuItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MenuItemRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
    );
  }

  @override
  $MenuItemRowsTable createAlias(String alias) {
    return $MenuItemRowsTable(attachedDatabase, alias);
  }
}

class MenuItemRow extends DataClass implements Insertable<MenuItemRow> {
  final String id;
  final String json;
  const MenuItemRow({required this.id, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['json'] = Variable<String>(json);
    return map;
  }

  MenuItemRowsCompanion toCompanion(bool nullToAbsent) {
    return MenuItemRowsCompanion(
      id: Value(id),
      json: Value(json),
    );
  }

  factory MenuItemRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MenuItemRow(
      id: serializer.fromJson<String>(json['id']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'json': serializer.toJson<String>(json),
    };
  }

  MenuItemRow copyWith({String? id, String? json}) => MenuItemRow(
        id: id ?? this.id,
        json: json ?? this.json,
      );
  MenuItemRow copyWithCompanion(MenuItemRowsCompanion data) {
    return MenuItemRow(
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MenuItemRow(')
          ..write('id: $id, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MenuItemRow && other.id == this.id && other.json == this.json);
}

class MenuItemRowsCompanion extends UpdateCompanion<MenuItemRow> {
  final Value<String> id;
  final Value<String> json;
  final Value<int> rowid;
  const MenuItemRowsCompanion({
    this.id = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MenuItemRowsCompanion.insert({
    required String id,
    required String json,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        json = Value(json);
  static Insertable<MenuItemRow> custom({
    Expression<String>? id,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MenuItemRowsCompanion copyWith(
      {Value<String>? id, Value<String>? json, Value<int>? rowid}) {
    return MenuItemRowsCompanion(
      id: id ?? this.id,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MenuItemRowsCompanion(')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CategoryRowsTable extends CategoryRows
    with TableInfo<$CategoryRowsTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoryRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayOrderMeta =
      const VerificationMeta('displayOrder');
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
      'display_order', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [name, displayOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'category_rows';
  @override
  VerificationContext validateIntegrity(Insertable<CategoryRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('display_order')) {
      context.handle(
          _displayOrderMeta,
          displayOrder.isAcceptableOrUnknown(
              data['display_order']!, _displayOrderMeta));
    } else if (isInserting) {
      context.missing(_displayOrderMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      displayOrder: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}display_order'])!,
    );
  }

  @override
  $CategoryRowsTable createAlias(String alias) {
    return $CategoryRowsTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final String name;
  final int displayOrder;
  const CategoryRow({required this.name, required this.displayOrder});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['display_order'] = Variable<int>(displayOrder);
    return map;
  }

  CategoryRowsCompanion toCompanion(bool nullToAbsent) {
    return CategoryRowsCompanion(
      name: Value(name),
      displayOrder: Value(displayOrder),
    );
  }

  factory CategoryRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      name: serializer.fromJson<String>(json['name']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'displayOrder': serializer.toJson<int>(displayOrder),
    };
  }

  CategoryRow copyWith({String? name, int? displayOrder}) => CategoryRow(
        name: name ?? this.name,
        displayOrder: displayOrder ?? this.displayOrder,
      );
  CategoryRow copyWithCompanion(CategoryRowsCompanion data) {
    return CategoryRow(
      name: data.name.present ? data.name.value : this.name,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('name: $name, ')
          ..write('displayOrder: $displayOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, displayOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.name == this.name &&
          other.displayOrder == this.displayOrder);
}

class CategoryRowsCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> name;
  final Value<int> displayOrder;
  final Value<int> rowid;
  const CategoryRowsCompanion({
    this.name = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoryRowsCompanion.insert({
    required String name,
    required int displayOrder,
    this.rowid = const Value.absent(),
  })  : name = Value(name),
        displayOrder = Value(displayOrder);
  static Insertable<CategoryRow> custom({
    Expression<String>? name,
    Expression<int>? displayOrder,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (displayOrder != null) 'display_order': displayOrder,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoryRowsCompanion copyWith(
      {Value<String>? name, Value<int>? displayOrder, Value<int>? rowid}) {
    return CategoryRowsCompanion(
      name: name ?? this.name,
      displayOrder: displayOrder ?? this.displayOrder,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRowsCompanion(')
          ..write('name: $name, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DiningTableRowsTable extends DiningTableRows
    with TableInfo<$DiningTableRowsTable, DiningTableRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DiningTableRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dining_table_rows';
  @override
  VerificationContext validateIntegrity(Insertable<DiningTableRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DiningTableRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DiningTableRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
    );
  }

  @override
  $DiningTableRowsTable createAlias(String alias) {
    return $DiningTableRowsTable(attachedDatabase, alias);
  }
}

class DiningTableRow extends DataClass implements Insertable<DiningTableRow> {
  final String id;
  final String json;
  const DiningTableRow({required this.id, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['json'] = Variable<String>(json);
    return map;
  }

  DiningTableRowsCompanion toCompanion(bool nullToAbsent) {
    return DiningTableRowsCompanion(
      id: Value(id),
      json: Value(json),
    );
  }

  factory DiningTableRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DiningTableRow(
      id: serializer.fromJson<String>(json['id']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'json': serializer.toJson<String>(json),
    };
  }

  DiningTableRow copyWith({String? id, String? json}) => DiningTableRow(
        id: id ?? this.id,
        json: json ?? this.json,
      );
  DiningTableRow copyWithCompanion(DiningTableRowsCompanion data) {
    return DiningTableRow(
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DiningTableRow(')
          ..write('id: $id, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DiningTableRow &&
          other.id == this.id &&
          other.json == this.json);
}

class DiningTableRowsCompanion extends UpdateCompanion<DiningTableRow> {
  final Value<String> id;
  final Value<String> json;
  final Value<int> rowid;
  const DiningTableRowsCompanion({
    this.id = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DiningTableRowsCompanion.insert({
    required String id,
    required String json,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        json = Value(json);
  static Insertable<DiningTableRow> custom({
    Expression<String>? id,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DiningTableRowsCompanion copyWith(
      {Value<String>? id, Value<String>? json, Value<int>? rowid}) {
    return DiningTableRowsCompanion(
      id: id ?? this.id,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DiningTableRowsCompanion(')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PrinterRowsTable extends PrinterRows
    with TableInfo<$PrinterRowsTable, PrinterRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PrinterRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'printer_rows';
  @override
  VerificationContext validateIntegrity(Insertable<PrinterRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PrinterRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PrinterRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
    );
  }

  @override
  $PrinterRowsTable createAlias(String alias) {
    return $PrinterRowsTable(attachedDatabase, alias);
  }
}

class PrinterRow extends DataClass implements Insertable<PrinterRow> {
  final String id;
  final String json;
  const PrinterRow({required this.id, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['json'] = Variable<String>(json);
    return map;
  }

  PrinterRowsCompanion toCompanion(bool nullToAbsent) {
    return PrinterRowsCompanion(
      id: Value(id),
      json: Value(json),
    );
  }

  factory PrinterRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PrinterRow(
      id: serializer.fromJson<String>(json['id']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'json': serializer.toJson<String>(json),
    };
  }

  PrinterRow copyWith({String? id, String? json}) => PrinterRow(
        id: id ?? this.id,
        json: json ?? this.json,
      );
  PrinterRow copyWithCompanion(PrinterRowsCompanion data) {
    return PrinterRow(
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PrinterRow(')
          ..write('id: $id, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PrinterRow && other.id == this.id && other.json == this.json);
}

class PrinterRowsCompanion extends UpdateCompanion<PrinterRow> {
  final Value<String> id;
  final Value<String> json;
  final Value<int> rowid;
  const PrinterRowsCompanion({
    this.id = const Value.absent(),
    this.json = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PrinterRowsCompanion.insert({
    required String id,
    required String json,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        json = Value(json);
  static Insertable<PrinterRow> custom({
    Expression<String>? id,
    Expression<String>? json,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (json != null) 'json': json,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PrinterRowsCompanion copyWith(
      {Value<String>? id, Value<String>? json, Value<int>? rowid}) {
    return PrinterRowsCompanion(
      id: id ?? this.id,
      json: json ?? this.json,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PrinterRowsCompanion(')
          ..write('id: $id, ')
          ..write('json: $json, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OrderRowsTable extends OrderRows
    with TableInfo<$OrderRowsTable, OrderRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OrderRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'order_rows';
  @override
  VerificationContext validateIntegrity(Insertable<OrderRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OrderRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OrderRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
    );
  }

  @override
  $OrderRowsTable createAlias(String alias) {
    return $OrderRowsTable(attachedDatabase, alias);
  }
}

class OrderRow extends DataClass implements Insertable<OrderRow> {
  final int id;
  final String json;
  const OrderRow({required this.id, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['json'] = Variable<String>(json);
    return map;
  }

  OrderRowsCompanion toCompanion(bool nullToAbsent) {
    return OrderRowsCompanion(
      id: Value(id),
      json: Value(json),
    );
  }

  factory OrderRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OrderRow(
      id: serializer.fromJson<int>(json['id']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'json': serializer.toJson<String>(json),
    };
  }

  OrderRow copyWith({int? id, String? json}) => OrderRow(
        id: id ?? this.id,
        json: json ?? this.json,
      );
  OrderRow copyWithCompanion(OrderRowsCompanion data) {
    return OrderRow(
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OrderRow(')
          ..write('id: $id, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OrderRow && other.id == this.id && other.json == this.json);
}

class OrderRowsCompanion extends UpdateCompanion<OrderRow> {
  final Value<int> id;
  final Value<String> json;
  const OrderRowsCompanion({
    this.id = const Value.absent(),
    this.json = const Value.absent(),
  });
  OrderRowsCompanion.insert({
    this.id = const Value.absent(),
    required String json,
  }) : json = Value(json);
  static Insertable<OrderRow> custom({
    Expression<int>? id,
    Expression<String>? json,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (json != null) 'json': json,
    });
  }

  OrderRowsCompanion copyWith({Value<int>? id, Value<String>? json}) {
    return OrderRowsCompanion(
      id: id ?? this.id,
      json: json ?? this.json,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OrderRowsCompanion(')
          ..write('id: $id, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }
}

class $KotRowsTable extends KotRows with TableInfo<$KotRowsTable, KotRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KotRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _noMeta = const VerificationMeta('no');
  @override
  late final GeneratedColumn<int> no = GeneratedColumn<int>(
      'no', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [no, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'kot_rows';
  @override
  VerificationContext validateIntegrity(Insertable<KotRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('no')) {
      context.handle(_noMeta, no.isAcceptableOrUnknown(data['no']!, _noMeta));
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {no};
  @override
  KotRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KotRow(
      no: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}no'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
    );
  }

  @override
  $KotRowsTable createAlias(String alias) {
    return $KotRowsTable(attachedDatabase, alias);
  }
}

class KotRow extends DataClass implements Insertable<KotRow> {
  final int no;
  final String json;
  const KotRow({required this.no, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['no'] = Variable<int>(no);
    map['json'] = Variable<String>(json);
    return map;
  }

  KotRowsCompanion toCompanion(bool nullToAbsent) {
    return KotRowsCompanion(
      no: Value(no),
      json: Value(json),
    );
  }

  factory KotRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KotRow(
      no: serializer.fromJson<int>(json['no']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'no': serializer.toJson<int>(no),
      'json': serializer.toJson<String>(json),
    };
  }

  KotRow copyWith({int? no, String? json}) => KotRow(
        no: no ?? this.no,
        json: json ?? this.json,
      );
  KotRow copyWithCompanion(KotRowsCompanion data) {
    return KotRow(
      no: data.no.present ? data.no.value : this.no,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KotRow(')
          ..write('no: $no, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(no, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KotRow && other.no == this.no && other.json == this.json);
}

class KotRowsCompanion extends UpdateCompanion<KotRow> {
  final Value<int> no;
  final Value<String> json;
  const KotRowsCompanion({
    this.no = const Value.absent(),
    this.json = const Value.absent(),
  });
  KotRowsCompanion.insert({
    this.no = const Value.absent(),
    required String json,
  }) : json = Value(json);
  static Insertable<KotRow> custom({
    Expression<int>? no,
    Expression<String>? json,
  }) {
    return RawValuesInsertable({
      if (no != null) 'no': no,
      if (json != null) 'json': json,
    });
  }

  KotRowsCompanion copyWith({Value<int>? no, Value<String>? json}) {
    return KotRowsCompanion(
      no: no ?? this.no,
      json: json ?? this.json,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (no.present) {
      map['no'] = Variable<int>(no.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KotRowsCompanion(')
          ..write('no: $no, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }
}

class $HistoryRowsTable extends HistoryRows
    with TableInfo<$HistoryRowsTable, HistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HistoryRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _jsonMeta = const VerificationMeta('json');
  @override
  late final GeneratedColumn<String> json = GeneratedColumn<String>(
      'json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, json];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'history_rows';
  @override
  VerificationContext validateIntegrity(Insertable<HistoryRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('json')) {
      context.handle(
          _jsonMeta, json.isAcceptableOrUnknown(data['json']!, _jsonMeta));
    } else if (isInserting) {
      context.missing(_jsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      json: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}json'])!,
    );
  }

  @override
  $HistoryRowsTable createAlias(String alias) {
    return $HistoryRowsTable(attachedDatabase, alias);
  }
}

class HistoryRow extends DataClass implements Insertable<HistoryRow> {
  final int id;
  final String json;
  const HistoryRow({required this.id, required this.json});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['json'] = Variable<String>(json);
    return map;
  }

  HistoryRowsCompanion toCompanion(bool nullToAbsent) {
    return HistoryRowsCompanion(
      id: Value(id),
      json: Value(json),
    );
  }

  factory HistoryRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryRow(
      id: serializer.fromJson<int>(json['id']),
      json: serializer.fromJson<String>(json['json']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'json': serializer.toJson<String>(json),
    };
  }

  HistoryRow copyWith({int? id, String? json}) => HistoryRow(
        id: id ?? this.id,
        json: json ?? this.json,
      );
  HistoryRow copyWithCompanion(HistoryRowsCompanion data) {
    return HistoryRow(
      id: data.id.present ? data.id.value : this.id,
      json: data.json.present ? data.json.value : this.json,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryRow(')
          ..write('id: $id, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, json);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryRow && other.id == this.id && other.json == this.json);
}

class HistoryRowsCompanion extends UpdateCompanion<HistoryRow> {
  final Value<int> id;
  final Value<String> json;
  const HistoryRowsCompanion({
    this.id = const Value.absent(),
    this.json = const Value.absent(),
  });
  HistoryRowsCompanion.insert({
    this.id = const Value.absent(),
    required String json,
  }) : json = Value(json);
  static Insertable<HistoryRow> custom({
    Expression<int>? id,
    Expression<String>? json,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (json != null) 'json': json,
    });
  }

  HistoryRowsCompanion copyWith({Value<int>? id, Value<String>? json}) {
    return HistoryRowsCompanion(
      id: id ?? this.id,
      json: json ?? this.json,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (json.present) {
      map['json'] = Variable<String>(json.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HistoryRowsCompanion(')
          ..write('id: $id, ')
          ..write('json: $json')
          ..write(')'))
        .toString();
  }
}

class $StockRowsTable extends StockRows
    with TableInfo<$StockRowsTable, StockRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StockRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
      'item_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _qtyMeta = const VerificationMeta('qty');
  @override
  late final GeneratedColumn<int> qty = GeneratedColumn<int>(
      'qty', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [itemId, qty];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stock_rows';
  @override
  VerificationContext validateIntegrity(Insertable<StockRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('item_id')) {
      context.handle(_itemIdMeta,
          itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta));
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('qty')) {
      context.handle(
          _qtyMeta, qty.isAcceptableOrUnknown(data['qty']!, _qtyMeta));
    } else if (isInserting) {
      context.missing(_qtyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {itemId};
  @override
  StockRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StockRow(
      itemId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}item_id'])!,
      qty: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}qty'])!,
    );
  }

  @override
  $StockRowsTable createAlias(String alias) {
    return $StockRowsTable(attachedDatabase, alias);
  }
}

class StockRow extends DataClass implements Insertable<StockRow> {
  final String itemId;
  final int qty;
  const StockRow({required this.itemId, required this.qty});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['item_id'] = Variable<String>(itemId);
    map['qty'] = Variable<int>(qty);
    return map;
  }

  StockRowsCompanion toCompanion(bool nullToAbsent) {
    return StockRowsCompanion(
      itemId: Value(itemId),
      qty: Value(qty),
    );
  }

  factory StockRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StockRow(
      itemId: serializer.fromJson<String>(json['itemId']),
      qty: serializer.fromJson<int>(json['qty']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'itemId': serializer.toJson<String>(itemId),
      'qty': serializer.toJson<int>(qty),
    };
  }

  StockRow copyWith({String? itemId, int? qty}) => StockRow(
        itemId: itemId ?? this.itemId,
        qty: qty ?? this.qty,
      );
  StockRow copyWithCompanion(StockRowsCompanion data) {
    return StockRow(
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      qty: data.qty.present ? data.qty.value : this.qty,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StockRow(')
          ..write('itemId: $itemId, ')
          ..write('qty: $qty')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(itemId, qty);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StockRow &&
          other.itemId == this.itemId &&
          other.qty == this.qty);
}

class StockRowsCompanion extends UpdateCompanion<StockRow> {
  final Value<String> itemId;
  final Value<int> qty;
  final Value<int> rowid;
  const StockRowsCompanion({
    this.itemId = const Value.absent(),
    this.qty = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StockRowsCompanion.insert({
    required String itemId,
    required int qty,
    this.rowid = const Value.absent(),
  })  : itemId = Value(itemId),
        qty = Value(qty);
  static Insertable<StockRow> custom({
    Expression<String>? itemId,
    Expression<int>? qty,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (itemId != null) 'item_id': itemId,
      if (qty != null) 'qty': qty,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StockRowsCompanion copyWith(
      {Value<String>? itemId, Value<int>? qty, Value<int>? rowid}) {
    return StockRowsCompanion(
      itemId: itemId ?? this.itemId,
      qty: qty ?? this.qty,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (qty.present) {
      map['qty'] = Variable<int>(qty.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StockRowsCompanion(')
          ..write('itemId: $itemId, ')
          ..write('qty: $qty, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ItemOffRowsTable extends ItemOffRows
    with TableInfo<$ItemOffRowsTable, ItemOffRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemOffRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'item_off_rows';
  @override
  VerificationContext validateIntegrity(Insertable<ItemOffRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ItemOffRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ItemOffRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $ItemOffRowsTable createAlias(String alias) {
    return $ItemOffRowsTable(attachedDatabase, alias);
  }
}

class ItemOffRow extends DataClass implements Insertable<ItemOffRow> {
  final String id;
  const ItemOffRow({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    return map;
  }

  ItemOffRowsCompanion toCompanion(bool nullToAbsent) {
    return ItemOffRowsCompanion(
      id: Value(id),
    );
  }

  factory ItemOffRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ItemOffRow(
      id: serializer.fromJson<String>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
    };
  }

  ItemOffRow copyWith({String? id}) => ItemOffRow(
        id: id ?? this.id,
      );
  ItemOffRow copyWithCompanion(ItemOffRowsCompanion data) {
    return ItemOffRow(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ItemOffRow(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is ItemOffRow && other.id == this.id);
}

class ItemOffRowsCompanion extends UpdateCompanion<ItemOffRow> {
  final Value<String> id;
  final Value<int> rowid;
  const ItemOffRowsCompanion({
    this.id = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemOffRowsCompanion.insert({
    required String id,
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<ItemOffRow> custom({
    Expression<String>? id,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemOffRowsCompanion copyWith({Value<String>? id, Value<int>? rowid}) {
    return ItemOffRowsCompanion(
      id: id ?? this.id,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemOffRowsCompanion(')
          ..write('id: $id, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CatOffRowsTable extends CatOffRows
    with TableInfo<$CatOffRowsTable, CatOffRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CatOffRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cat_off_rows';
  @override
  VerificationContext validateIntegrity(Insertable<CatOffRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CatOffRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CatOffRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
    );
  }

  @override
  $CatOffRowsTable createAlias(String alias) {
    return $CatOffRowsTable(attachedDatabase, alias);
  }
}

class CatOffRow extends DataClass implements Insertable<CatOffRow> {
  final String id;
  const CatOffRow({required this.id});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    return map;
  }

  CatOffRowsCompanion toCompanion(bool nullToAbsent) {
    return CatOffRowsCompanion(
      id: Value(id),
    );
  }

  factory CatOffRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CatOffRow(
      id: serializer.fromJson<String>(json['id']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
    };
  }

  CatOffRow copyWith({String? id}) => CatOffRow(
        id: id ?? this.id,
      );
  CatOffRow copyWithCompanion(CatOffRowsCompanion data) {
    return CatOffRow(
      id: data.id.present ? data.id.value : this.id,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CatOffRow(')
          ..write('id: $id')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => id.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is CatOffRow && other.id == this.id);
}

class CatOffRowsCompanion extends UpdateCompanion<CatOffRow> {
  final Value<String> id;
  final Value<int> rowid;
  const CatOffRowsCompanion({
    this.id = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CatOffRowsCompanion.insert({
    required String id,
    this.rowid = const Value.absent(),
  }) : id = Value(id);
  static Insertable<CatOffRow> custom({
    Expression<String>? id,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CatOffRowsCompanion copyWith({Value<String>? id, Value<int>? rowid}) {
    return CatOffRowsCompanion(
      id: id ?? this.id,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CatOffRowsCompanion(')
          ..write('id: $id, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsRowsTable extends SettingsRows
    with TableInfo<$SettingsRowsTable, SettingsRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
      'key', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
      'value', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings_rows';
  @override
  VerificationContext validateIntegrity(Insertable<SettingsRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
          _keyMeta, key.isAcceptableOrUnknown(data['key']!, _keyMeta));
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
          _valueMeta, value.isAcceptableOrUnknown(data['value']!, _valueMeta));
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingsRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingsRow(
      key: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}key'])!,
      value: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value'])!,
    );
  }

  @override
  $SettingsRowsTable createAlias(String alias) {
    return $SettingsRowsTable(attachedDatabase, alias);
  }
}

class SettingsRow extends DataClass implements Insertable<SettingsRow> {
  final String key;
  final String value;
  const SettingsRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsRowsCompanion toCompanion(bool nullToAbsent) {
    return SettingsRowsCompanion(
      key: Value(key),
      value: Value(value),
    );
  }

  factory SettingsRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingsRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingsRow copyWith({String? key, String? value}) => SettingsRow(
        key: key ?? this.key,
        value: value ?? this.value,
      );
  SettingsRow copyWithCompanion(SettingsRowsCompanion data) {
    return SettingsRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingsRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsRowsCompanion extends UpdateCompanion<SettingsRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsRowsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsRowsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  })  : key = Value(key),
        value = Value(value);
  static Insertable<SettingsRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsRowsCompanion copyWith(
      {Value<String>? key, Value<String>? value, Value<int>? rowid}) {
    return SettingsRowsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsRowsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MenuItemRowsTable menuItemRows = $MenuItemRowsTable(this);
  late final $CategoryRowsTable categoryRows = $CategoryRowsTable(this);
  late final $DiningTableRowsTable diningTableRows =
      $DiningTableRowsTable(this);
  late final $PrinterRowsTable printerRows = $PrinterRowsTable(this);
  late final $OrderRowsTable orderRows = $OrderRowsTable(this);
  late final $KotRowsTable kotRows = $KotRowsTable(this);
  late final $HistoryRowsTable historyRows = $HistoryRowsTable(this);
  late final $StockRowsTable stockRows = $StockRowsTable(this);
  late final $ItemOffRowsTable itemOffRows = $ItemOffRowsTable(this);
  late final $CatOffRowsTable catOffRows = $CatOffRowsTable(this);
  late final $SettingsRowsTable settingsRows = $SettingsRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        menuItemRows,
        categoryRows,
        diningTableRows,
        printerRows,
        orderRows,
        kotRows,
        historyRows,
        stockRows,
        itemOffRows,
        catOffRows,
        settingsRows
      ];
}

typedef $$MenuItemRowsTableCreateCompanionBuilder = MenuItemRowsCompanion
    Function({
  required String id,
  required String json,
  Value<int> rowid,
});
typedef $$MenuItemRowsTableUpdateCompanionBuilder = MenuItemRowsCompanion
    Function({
  Value<String> id,
  Value<String> json,
  Value<int> rowid,
});

class $$MenuItemRowsTableFilterComposer
    extends Composer<_$AppDatabase, $MenuItemRowsTable> {
  $$MenuItemRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));
}

class $$MenuItemRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $MenuItemRowsTable> {
  $$MenuItemRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));
}

class $$MenuItemRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MenuItemRowsTable> {
  $$MenuItemRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$MenuItemRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MenuItemRowsTable,
    MenuItemRow,
    $$MenuItemRowsTableFilterComposer,
    $$MenuItemRowsTableOrderingComposer,
    $$MenuItemRowsTableAnnotationComposer,
    $$MenuItemRowsTableCreateCompanionBuilder,
    $$MenuItemRowsTableUpdateCompanionBuilder,
    (
      MenuItemRow,
      BaseReferences<_$AppDatabase, $MenuItemRowsTable, MenuItemRow>
    ),
    MenuItemRow,
    PrefetchHooks Function()> {
  $$MenuItemRowsTableTableManager(_$AppDatabase db, $MenuItemRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MenuItemRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MenuItemRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MenuItemRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MenuItemRowsCompanion(
            id: id,
            json: json,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String json,
            Value<int> rowid = const Value.absent(),
          }) =>
              MenuItemRowsCompanion.insert(
            id: id,
            json: json,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$MenuItemRowsTable, MenuItemRow>(table),
                    BaseReferences<_$AppDatabase, $MenuItemRowsTable,
                        MenuItemRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MenuItemRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MenuItemRowsTable,
    MenuItemRow,
    $$MenuItemRowsTableFilterComposer,
    $$MenuItemRowsTableOrderingComposer,
    $$MenuItemRowsTableAnnotationComposer,
    $$MenuItemRowsTableCreateCompanionBuilder,
    $$MenuItemRowsTableUpdateCompanionBuilder,
    (
      MenuItemRow,
      BaseReferences<_$AppDatabase, $MenuItemRowsTable, MenuItemRow>
    ),
    MenuItemRow,
    PrefetchHooks Function()>;
typedef $$CategoryRowsTableCreateCompanionBuilder = CategoryRowsCompanion
    Function({
  required String name,
  required int displayOrder,
  Value<int> rowid,
});
typedef $$CategoryRowsTableUpdateCompanionBuilder = CategoryRowsCompanion
    Function({
  Value<String> name,
  Value<int> displayOrder,
  Value<int> rowid,
});

class $$CategoryRowsTableFilterComposer
    extends Composer<_$AppDatabase, $CategoryRowsTable> {
  $$CategoryRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get displayOrder => $composableBuilder(
      column: $table.displayOrder, builder: (column) => ColumnFilters(column));
}

class $$CategoryRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoryRowsTable> {
  $$CategoryRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get displayOrder => $composableBuilder(
      column: $table.displayOrder,
      builder: (column) => ColumnOrderings(column));
}

class $$CategoryRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoryRowsTable> {
  $$CategoryRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
      column: $table.displayOrder, builder: (column) => column);
}

class $$CategoryRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CategoryRowsTable,
    CategoryRow,
    $$CategoryRowsTableFilterComposer,
    $$CategoryRowsTableOrderingComposer,
    $$CategoryRowsTableAnnotationComposer,
    $$CategoryRowsTableCreateCompanionBuilder,
    $$CategoryRowsTableUpdateCompanionBuilder,
    (
      CategoryRow,
      BaseReferences<_$AppDatabase, $CategoryRowsTable, CategoryRow>
    ),
    CategoryRow,
    PrefetchHooks Function()> {
  $$CategoryRowsTableTableManager(_$AppDatabase db, $CategoryRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoryRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoryRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoryRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> name = const Value.absent(),
            Value<int> displayOrder = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoryRowsCompanion(
            name: name,
            displayOrder: displayOrder,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String name,
            required int displayOrder,
            Value<int> rowid = const Value.absent(),
          }) =>
              CategoryRowsCompanion.insert(
            name: name,
            displayOrder: displayOrder,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CategoryRowsTable, CategoryRow>(table),
                    BaseReferences<_$AppDatabase, $CategoryRowsTable,
                        CategoryRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CategoryRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CategoryRowsTable,
    CategoryRow,
    $$CategoryRowsTableFilterComposer,
    $$CategoryRowsTableOrderingComposer,
    $$CategoryRowsTableAnnotationComposer,
    $$CategoryRowsTableCreateCompanionBuilder,
    $$CategoryRowsTableUpdateCompanionBuilder,
    (
      CategoryRow,
      BaseReferences<_$AppDatabase, $CategoryRowsTable, CategoryRow>
    ),
    CategoryRow,
    PrefetchHooks Function()>;
typedef $$DiningTableRowsTableCreateCompanionBuilder = DiningTableRowsCompanion
    Function({
  required String id,
  required String json,
  Value<int> rowid,
});
typedef $$DiningTableRowsTableUpdateCompanionBuilder = DiningTableRowsCompanion
    Function({
  Value<String> id,
  Value<String> json,
  Value<int> rowid,
});

class $$DiningTableRowsTableFilterComposer
    extends Composer<_$AppDatabase, $DiningTableRowsTable> {
  $$DiningTableRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));
}

class $$DiningTableRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $DiningTableRowsTable> {
  $$DiningTableRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));
}

class $$DiningTableRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DiningTableRowsTable> {
  $$DiningTableRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$DiningTableRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DiningTableRowsTable,
    DiningTableRow,
    $$DiningTableRowsTableFilterComposer,
    $$DiningTableRowsTableOrderingComposer,
    $$DiningTableRowsTableAnnotationComposer,
    $$DiningTableRowsTableCreateCompanionBuilder,
    $$DiningTableRowsTableUpdateCompanionBuilder,
    (
      DiningTableRow,
      BaseReferences<_$AppDatabase, $DiningTableRowsTable, DiningTableRow>
    ),
    DiningTableRow,
    PrefetchHooks Function()> {
  $$DiningTableRowsTableTableManager(
      _$AppDatabase db, $DiningTableRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DiningTableRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DiningTableRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DiningTableRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DiningTableRowsCompanion(
            id: id,
            json: json,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String json,
            Value<int> rowid = const Value.absent(),
          }) =>
              DiningTableRowsCompanion.insert(
            id: id,
            json: json,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$DiningTableRowsTable, DiningTableRow>(table),
                    BaseReferences<_$AppDatabase, $DiningTableRowsTable,
                        DiningTableRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$DiningTableRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DiningTableRowsTable,
    DiningTableRow,
    $$DiningTableRowsTableFilterComposer,
    $$DiningTableRowsTableOrderingComposer,
    $$DiningTableRowsTableAnnotationComposer,
    $$DiningTableRowsTableCreateCompanionBuilder,
    $$DiningTableRowsTableUpdateCompanionBuilder,
    (
      DiningTableRow,
      BaseReferences<_$AppDatabase, $DiningTableRowsTable, DiningTableRow>
    ),
    DiningTableRow,
    PrefetchHooks Function()>;
typedef $$PrinterRowsTableCreateCompanionBuilder = PrinterRowsCompanion
    Function({
  required String id,
  required String json,
  Value<int> rowid,
});
typedef $$PrinterRowsTableUpdateCompanionBuilder = PrinterRowsCompanion
    Function({
  Value<String> id,
  Value<String> json,
  Value<int> rowid,
});

class $$PrinterRowsTableFilterComposer
    extends Composer<_$AppDatabase, $PrinterRowsTable> {
  $$PrinterRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));
}

class $$PrinterRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $PrinterRowsTable> {
  $$PrinterRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));
}

class $$PrinterRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PrinterRowsTable> {
  $$PrinterRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$PrinterRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PrinterRowsTable,
    PrinterRow,
    $$PrinterRowsTableFilterComposer,
    $$PrinterRowsTableOrderingComposer,
    $$PrinterRowsTableAnnotationComposer,
    $$PrinterRowsTableCreateCompanionBuilder,
    $$PrinterRowsTableUpdateCompanionBuilder,
    (PrinterRow, BaseReferences<_$AppDatabase, $PrinterRowsTable, PrinterRow>),
    PrinterRow,
    PrefetchHooks Function()> {
  $$PrinterRowsTableTableManager(_$AppDatabase db, $PrinterRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PrinterRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PrinterRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PrinterRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> json = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PrinterRowsCompanion(
            id: id,
            json: json,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String json,
            Value<int> rowid = const Value.absent(),
          }) =>
              PrinterRowsCompanion.insert(
            id: id,
            json: json,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$PrinterRowsTable, PrinterRow>(table),
                    BaseReferences<_$AppDatabase, $PrinterRowsTable,
                        PrinterRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PrinterRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PrinterRowsTable,
    PrinterRow,
    $$PrinterRowsTableFilterComposer,
    $$PrinterRowsTableOrderingComposer,
    $$PrinterRowsTableAnnotationComposer,
    $$PrinterRowsTableCreateCompanionBuilder,
    $$PrinterRowsTableUpdateCompanionBuilder,
    (PrinterRow, BaseReferences<_$AppDatabase, $PrinterRowsTable, PrinterRow>),
    PrinterRow,
    PrefetchHooks Function()>;
typedef $$OrderRowsTableCreateCompanionBuilder = OrderRowsCompanion Function({
  Value<int> id,
  required String json,
});
typedef $$OrderRowsTableUpdateCompanionBuilder = OrderRowsCompanion Function({
  Value<int> id,
  Value<String> json,
});

class $$OrderRowsTableFilterComposer
    extends Composer<_$AppDatabase, $OrderRowsTable> {
  $$OrderRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));
}

class $$OrderRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $OrderRowsTable> {
  $$OrderRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));
}

class $$OrderRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OrderRowsTable> {
  $$OrderRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$OrderRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OrderRowsTable,
    OrderRow,
    $$OrderRowsTableFilterComposer,
    $$OrderRowsTableOrderingComposer,
    $$OrderRowsTableAnnotationComposer,
    $$OrderRowsTableCreateCompanionBuilder,
    $$OrderRowsTableUpdateCompanionBuilder,
    (OrderRow, BaseReferences<_$AppDatabase, $OrderRowsTable, OrderRow>),
    OrderRow,
    PrefetchHooks Function()> {
  $$OrderRowsTableTableManager(_$AppDatabase db, $OrderRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OrderRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OrderRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OrderRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> json = const Value.absent(),
          }) =>
              OrderRowsCompanion(
            id: id,
            json: json,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String json,
          }) =>
              OrderRowsCompanion.insert(
            id: id,
            json: json,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$OrderRowsTable, OrderRow>(table),
                    BaseReferences<_$AppDatabase, $OrderRowsTable, OrderRow>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OrderRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OrderRowsTable,
    OrderRow,
    $$OrderRowsTableFilterComposer,
    $$OrderRowsTableOrderingComposer,
    $$OrderRowsTableAnnotationComposer,
    $$OrderRowsTableCreateCompanionBuilder,
    $$OrderRowsTableUpdateCompanionBuilder,
    (OrderRow, BaseReferences<_$AppDatabase, $OrderRowsTable, OrderRow>),
    OrderRow,
    PrefetchHooks Function()>;
typedef $$KotRowsTableCreateCompanionBuilder = KotRowsCompanion Function({
  Value<int> no,
  required String json,
});
typedef $$KotRowsTableUpdateCompanionBuilder = KotRowsCompanion Function({
  Value<int> no,
  Value<String> json,
});

class $$KotRowsTableFilterComposer
    extends Composer<_$AppDatabase, $KotRowsTable> {
  $$KotRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get no => $composableBuilder(
      column: $table.no, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));
}

class $$KotRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $KotRowsTable> {
  $$KotRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get no => $composableBuilder(
      column: $table.no, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));
}

class $$KotRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $KotRowsTable> {
  $$KotRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get no =>
      $composableBuilder(column: $table.no, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$KotRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $KotRowsTable,
    KotRow,
    $$KotRowsTableFilterComposer,
    $$KotRowsTableOrderingComposer,
    $$KotRowsTableAnnotationComposer,
    $$KotRowsTableCreateCompanionBuilder,
    $$KotRowsTableUpdateCompanionBuilder,
    (KotRow, BaseReferences<_$AppDatabase, $KotRowsTable, KotRow>),
    KotRow,
    PrefetchHooks Function()> {
  $$KotRowsTableTableManager(_$AppDatabase db, $KotRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KotRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KotRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KotRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> no = const Value.absent(),
            Value<String> json = const Value.absent(),
          }) =>
              KotRowsCompanion(
            no: no,
            json: json,
          ),
          createCompanionCallback: ({
            Value<int> no = const Value.absent(),
            required String json,
          }) =>
              KotRowsCompanion.insert(
            no: no,
            json: json,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$KotRowsTable, KotRow>(table),
                    BaseReferences<_$AppDatabase, $KotRowsTable, KotRow>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$KotRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $KotRowsTable,
    KotRow,
    $$KotRowsTableFilterComposer,
    $$KotRowsTableOrderingComposer,
    $$KotRowsTableAnnotationComposer,
    $$KotRowsTableCreateCompanionBuilder,
    $$KotRowsTableUpdateCompanionBuilder,
    (KotRow, BaseReferences<_$AppDatabase, $KotRowsTable, KotRow>),
    KotRow,
    PrefetchHooks Function()>;
typedef $$HistoryRowsTableCreateCompanionBuilder = HistoryRowsCompanion
    Function({
  Value<int> id,
  required String json,
});
typedef $$HistoryRowsTableUpdateCompanionBuilder = HistoryRowsCompanion
    Function({
  Value<int> id,
  Value<String> json,
});

class $$HistoryRowsTableFilterComposer
    extends Composer<_$AppDatabase, $HistoryRowsTable> {
  $$HistoryRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnFilters(column));
}

class $$HistoryRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $HistoryRowsTable> {
  $$HistoryRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get json => $composableBuilder(
      column: $table.json, builder: (column) => ColumnOrderings(column));
}

class $$HistoryRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HistoryRowsTable> {
  $$HistoryRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get json =>
      $composableBuilder(column: $table.json, builder: (column) => column);
}

class $$HistoryRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $HistoryRowsTable,
    HistoryRow,
    $$HistoryRowsTableFilterComposer,
    $$HistoryRowsTableOrderingComposer,
    $$HistoryRowsTableAnnotationComposer,
    $$HistoryRowsTableCreateCompanionBuilder,
    $$HistoryRowsTableUpdateCompanionBuilder,
    (HistoryRow, BaseReferences<_$AppDatabase, $HistoryRowsTable, HistoryRow>),
    HistoryRow,
    PrefetchHooks Function()> {
  $$HistoryRowsTableTableManager(_$AppDatabase db, $HistoryRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HistoryRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HistoryRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HistoryRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> json = const Value.absent(),
          }) =>
              HistoryRowsCompanion(
            id: id,
            json: json,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String json,
          }) =>
              HistoryRowsCompanion.insert(
            id: id,
            json: json,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$HistoryRowsTable, HistoryRow>(table),
                    BaseReferences<_$AppDatabase, $HistoryRowsTable,
                        HistoryRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$HistoryRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $HistoryRowsTable,
    HistoryRow,
    $$HistoryRowsTableFilterComposer,
    $$HistoryRowsTableOrderingComposer,
    $$HistoryRowsTableAnnotationComposer,
    $$HistoryRowsTableCreateCompanionBuilder,
    $$HistoryRowsTableUpdateCompanionBuilder,
    (HistoryRow, BaseReferences<_$AppDatabase, $HistoryRowsTable, HistoryRow>),
    HistoryRow,
    PrefetchHooks Function()>;
typedef $$StockRowsTableCreateCompanionBuilder = StockRowsCompanion Function({
  required String itemId,
  required int qty,
  Value<int> rowid,
});
typedef $$StockRowsTableUpdateCompanionBuilder = StockRowsCompanion Function({
  Value<String> itemId,
  Value<int> qty,
  Value<int> rowid,
});

class $$StockRowsTableFilterComposer
    extends Composer<_$AppDatabase, $StockRowsTable> {
  $$StockRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get itemId => $composableBuilder(
      column: $table.itemId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get qty => $composableBuilder(
      column: $table.qty, builder: (column) => ColumnFilters(column));
}

class $$StockRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $StockRowsTable> {
  $$StockRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get itemId => $composableBuilder(
      column: $table.itemId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get qty => $composableBuilder(
      column: $table.qty, builder: (column) => ColumnOrderings(column));
}

class $$StockRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StockRowsTable> {
  $$StockRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<int> get qty =>
      $composableBuilder(column: $table.qty, builder: (column) => column);
}

class $$StockRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $StockRowsTable,
    StockRow,
    $$StockRowsTableFilterComposer,
    $$StockRowsTableOrderingComposer,
    $$StockRowsTableAnnotationComposer,
    $$StockRowsTableCreateCompanionBuilder,
    $$StockRowsTableUpdateCompanionBuilder,
    (StockRow, BaseReferences<_$AppDatabase, $StockRowsTable, StockRow>),
    StockRow,
    PrefetchHooks Function()> {
  $$StockRowsTableTableManager(_$AppDatabase db, $StockRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StockRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StockRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StockRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> itemId = const Value.absent(),
            Value<int> qty = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              StockRowsCompanion(
            itemId: itemId,
            qty: qty,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String itemId,
            required int qty,
            Value<int> rowid = const Value.absent(),
          }) =>
              StockRowsCompanion.insert(
            itemId: itemId,
            qty: qty,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$StockRowsTable, StockRow>(table),
                    BaseReferences<_$AppDatabase, $StockRowsTable, StockRow>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$StockRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $StockRowsTable,
    StockRow,
    $$StockRowsTableFilterComposer,
    $$StockRowsTableOrderingComposer,
    $$StockRowsTableAnnotationComposer,
    $$StockRowsTableCreateCompanionBuilder,
    $$StockRowsTableUpdateCompanionBuilder,
    (StockRow, BaseReferences<_$AppDatabase, $StockRowsTable, StockRow>),
    StockRow,
    PrefetchHooks Function()>;
typedef $$ItemOffRowsTableCreateCompanionBuilder = ItemOffRowsCompanion
    Function({
  required String id,
  Value<int> rowid,
});
typedef $$ItemOffRowsTableUpdateCompanionBuilder = ItemOffRowsCompanion
    Function({
  Value<String> id,
  Value<int> rowid,
});

class $$ItemOffRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ItemOffRowsTable> {
  $$ItemOffRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$ItemOffRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ItemOffRowsTable> {
  $$ItemOffRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$ItemOffRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ItemOffRowsTable> {
  $$ItemOffRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$ItemOffRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ItemOffRowsTable,
    ItemOffRow,
    $$ItemOffRowsTableFilterComposer,
    $$ItemOffRowsTableOrderingComposer,
    $$ItemOffRowsTableAnnotationComposer,
    $$ItemOffRowsTableCreateCompanionBuilder,
    $$ItemOffRowsTableUpdateCompanionBuilder,
    (ItemOffRow, BaseReferences<_$AppDatabase, $ItemOffRowsTable, ItemOffRow>),
    ItemOffRow,
    PrefetchHooks Function()> {
  $$ItemOffRowsTableTableManager(_$AppDatabase db, $ItemOffRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemOffRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemOffRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemOffRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ItemOffRowsCompanion(
            id: id,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<int> rowid = const Value.absent(),
          }) =>
              ItemOffRowsCompanion.insert(
            id: id,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$ItemOffRowsTable, ItemOffRow>(table),
                    BaseReferences<_$AppDatabase, $ItemOffRowsTable,
                        ItemOffRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ItemOffRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ItemOffRowsTable,
    ItemOffRow,
    $$ItemOffRowsTableFilterComposer,
    $$ItemOffRowsTableOrderingComposer,
    $$ItemOffRowsTableAnnotationComposer,
    $$ItemOffRowsTableCreateCompanionBuilder,
    $$ItemOffRowsTableUpdateCompanionBuilder,
    (ItemOffRow, BaseReferences<_$AppDatabase, $ItemOffRowsTable, ItemOffRow>),
    ItemOffRow,
    PrefetchHooks Function()>;
typedef $$CatOffRowsTableCreateCompanionBuilder = CatOffRowsCompanion Function({
  required String id,
  Value<int> rowid,
});
typedef $$CatOffRowsTableUpdateCompanionBuilder = CatOffRowsCompanion Function({
  Value<String> id,
  Value<int> rowid,
});

class $$CatOffRowsTableFilterComposer
    extends Composer<_$AppDatabase, $CatOffRowsTable> {
  $$CatOffRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));
}

class $$CatOffRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $CatOffRowsTable> {
  $$CatOffRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));
}

class $$CatOffRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CatOffRowsTable> {
  $$CatOffRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);
}

class $$CatOffRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CatOffRowsTable,
    CatOffRow,
    $$CatOffRowsTableFilterComposer,
    $$CatOffRowsTableOrderingComposer,
    $$CatOffRowsTableAnnotationComposer,
    $$CatOffRowsTableCreateCompanionBuilder,
    $$CatOffRowsTableUpdateCompanionBuilder,
    (CatOffRow, BaseReferences<_$AppDatabase, $CatOffRowsTable, CatOffRow>),
    CatOffRow,
    PrefetchHooks Function()> {
  $$CatOffRowsTableTableManager(_$AppDatabase db, $CatOffRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CatOffRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CatOffRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CatOffRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              CatOffRowsCompanion(
            id: id,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<int> rowid = const Value.absent(),
          }) =>
              CatOffRowsCompanion.insert(
            id: id,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CatOffRowsTable, CatOffRow>(table),
                    BaseReferences<_$AppDatabase, $CatOffRowsTable, CatOffRow>(
                        db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CatOffRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CatOffRowsTable,
    CatOffRow,
    $$CatOffRowsTableFilterComposer,
    $$CatOffRowsTableOrderingComposer,
    $$CatOffRowsTableAnnotationComposer,
    $$CatOffRowsTableCreateCompanionBuilder,
    $$CatOffRowsTableUpdateCompanionBuilder,
    (CatOffRow, BaseReferences<_$AppDatabase, $CatOffRowsTable, CatOffRow>),
    CatOffRow,
    PrefetchHooks Function()>;
typedef $$SettingsRowsTableCreateCompanionBuilder = SettingsRowsCompanion
    Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsRowsTableUpdateCompanionBuilder = SettingsRowsCompanion
    Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsRowsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnFilters(column));
}

class $$SettingsRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
      column: $table.key, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get value => $composableBuilder(
      column: $table.value, builder: (column) => ColumnOrderings(column));
}

class $$SettingsRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsRowsTable> {
  $$SettingsRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsRowsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SettingsRowsTable,
    SettingsRow,
    $$SettingsRowsTableFilterComposer,
    $$SettingsRowsTableOrderingComposer,
    $$SettingsRowsTableAnnotationComposer,
    $$SettingsRowsTableCreateCompanionBuilder,
    $$SettingsRowsTableUpdateCompanionBuilder,
    (
      SettingsRow,
      BaseReferences<_$AppDatabase, $SettingsRowsTable, SettingsRow>
    ),
    SettingsRow,
    PrefetchHooks Function()> {
  $$SettingsRowsTableTableManager(_$AppDatabase db, $SettingsRowsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SettingsRowsCompanion(
            key: key,
            value: value,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) =>
              SettingsRowsCompanion.insert(
            key: key,
            value: value,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$SettingsRowsTable, SettingsRow>(table),
                    BaseReferences<_$AppDatabase, $SettingsRowsTable,
                        SettingsRow>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SettingsRowsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SettingsRowsTable,
    SettingsRow,
    $$SettingsRowsTableFilterComposer,
    $$SettingsRowsTableOrderingComposer,
    $$SettingsRowsTableAnnotationComposer,
    $$SettingsRowsTableCreateCompanionBuilder,
    $$SettingsRowsTableUpdateCompanionBuilder,
    (
      SettingsRow,
      BaseReferences<_$AppDatabase, $SettingsRowsTable, SettingsRow>
    ),
    SettingsRow,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MenuItemRowsTableTableManager get menuItemRows =>
      $$MenuItemRowsTableTableManager(_db, _db.menuItemRows);
  $$CategoryRowsTableTableManager get categoryRows =>
      $$CategoryRowsTableTableManager(_db, _db.categoryRows);
  $$DiningTableRowsTableTableManager get diningTableRows =>
      $$DiningTableRowsTableTableManager(_db, _db.diningTableRows);
  $$PrinterRowsTableTableManager get printerRows =>
      $$PrinterRowsTableTableManager(_db, _db.printerRows);
  $$OrderRowsTableTableManager get orderRows =>
      $$OrderRowsTableTableManager(_db, _db.orderRows);
  $$KotRowsTableTableManager get kotRows =>
      $$KotRowsTableTableManager(_db, _db.kotRows);
  $$HistoryRowsTableTableManager get historyRows =>
      $$HistoryRowsTableTableManager(_db, _db.historyRows);
  $$StockRowsTableTableManager get stockRows =>
      $$StockRowsTableTableManager(_db, _db.stockRows);
  $$ItemOffRowsTableTableManager get itemOffRows =>
      $$ItemOffRowsTableTableManager(_db, _db.itemOffRows);
  $$CatOffRowsTableTableManager get catOffRows =>
      $$CatOffRowsTableTableManager(_db, _db.catOffRows);
  $$SettingsRowsTableTableManager get settingsRows =>
      $$SettingsRowsTableTableManager(_db, _db.settingsRows);
}
