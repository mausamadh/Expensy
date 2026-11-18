import 'dart:convert';

import 'transaction_type.dart';

/// One message shape as data: which [senderId] it arrives from, the anchor
/// text that identifies the shape, and the [fields] to slice out. The
/// registry routes by [senderId] and resolves duplicate [id]s by highest
/// [revision]; `isActive = false` retires an id.
class ParserTemplate {
  final String id;
  final String senderId;
  final String serviceName;
  /// Explicit provider country for docs; absent means the registry falls
  /// back to the provider folder name.
  final String? country;
  final List<TemplateAnchor> anchors;
  final List<TemplateField> fields;
  final TransactionType transactionDirection;
  final int revision;
  final bool isBuiltIn;
  final bool isActive;

  const ParserTemplate({
    required this.id,
    required this.senderId,
    required this.serviceName,
    this.country,
    required this.anchors,
    required this.fields,
    required this.transactionDirection,
    this.revision = 1,
    this.isBuiltIn = false,
    this.isActive = true,
  });

  factory ParserTemplate.fromJson(Map<String, dynamic> json) => ParserTemplate(
        id: json['id'] as String,
        senderId: json['senderId'] as String,
        serviceName: json['serviceName'] as String,
        country: json['country'] as String?,
        anchors: (json['anchors'] as List)
            .map((a) => TemplateAnchor.fromJson(a as Map<String, dynamic>))
            .toList(),
        fields: (json['fields'] as List)
            .map((f) => TemplateField.fromJson(f as Map<String, dynamic>))
            .toList(),
        transactionDirection:
            parseTransactionType(json['transactionDirection'] as String?),
        revision: (json['revision'] as int?) ?? 1,
        isBuiltIn: (json['isBuiltIn'] as bool?) ?? false,
        isActive: (json['isActive'] as bool?) ?? true,
      );

  static ParserTemplate decode(String text) =>
      ParserTemplate.fromJson(jsonDecode(text) as Map<String, dynamic>);
}

/// The literal text around a field. A field extracts only when both sides
/// match, so anchors are the template's identity test, not a regex grammar;
/// an empty `textAfter` means the captured value runs to the end of the
/// message.
class TemplateAnchor {
  final String textBefore;
  final String textAfter;

  const TemplateAnchor({required this.textBefore, required this.textAfter});

  factory TemplateAnchor.fromJson(Map<String, dynamic> json) => TemplateAnchor(
        textBefore: json['textBefore'] as String,
        textAfter: json['textAfter'] as String,
      );
}

/// One named slice of the message, found via its [anchor].
class TemplateField {
  final FieldName name;
  final TemplateAnchor anchor;
  final FieldType type;

  const TemplateField({required this.name, required this.anchor, required this.type});

  factory TemplateField.fromJson(Map<String, dynamic> json) => TemplateField(
        name: parseFieldName(json['name'] as String),
        anchor: TemplateAnchor.fromJson(json['anchor'] as Map<String, dynamic>),
        type: parseFieldType(json['type'] as String?),
      );
}

/// Which slice of the message a [TemplateField] captures.
enum FieldName { amount, merchant, reference, balance, fee, date }

FieldName parseFieldName(String s) {
  switch (s.toUpperCase()) {
    case 'AMOUNT':
      return FieldName.amount;
    case 'MERCHANT':
      return FieldName.merchant;
    case 'REFERENCE':
      return FieldName.reference;
    case 'BALANCE':
      return FieldName.balance;
    case 'FEE':
      return FieldName.fee;
    case 'DATE':
      return FieldName.date;
    default:
      throw ArgumentError('Unknown field name: $s');
  }
}

/// Declared intent for the captured slice; the engine interprets by
/// [FieldName], not by this type.
enum FieldType { currency, text, date, number }

FieldType parseFieldType(String? s) {
  switch ((s ?? 'TEXT').toUpperCase()) {
    case 'CURRENCY':
      return FieldType.currency;
    case 'DATE':
      return FieldType.date;
    case 'NUMBER':
      return FieldType.number;
    default:
      return FieldType.text;
  }
}
