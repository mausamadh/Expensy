/// Base class for typed identifiers.
///
/// Wrapping raw strings in named types lets the compiler catch
/// cross-entity mixups (e.g. passing an [AccountId] where a
/// [TransactionId] is expected) without changing the stored shape.
class TypedId {
  final String value;

  const TypedId(this.value);

  @override
  bool operator ==(Object other) => other is TypedId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

class AccountId extends TypedId {
  const AccountId(super.value);
}

class TransactionId extends TypedId {
  const TransactionId(super.value);
}

class CategoryId extends TypedId {
  const CategoryId(super.value);
}

class BudgetId extends TypedId {
  const BudgetId(super.value);
}

class RecurringId extends TypedId {
  const RecurringId(super.value);
}

class SmsInboxItemId extends TypedId {
  const SmsInboxItemId(super.value);
}
