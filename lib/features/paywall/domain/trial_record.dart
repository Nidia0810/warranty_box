class TrialRecord {
  const TrialRecord({required this.startedAt, required this.lastSeenAt});
  static const duration = Duration(days: 7);
  final DateTime? startedAt;
  final DateTime lastSeenAt;

  DateTime? get expiresAt => startedAt?.add(duration);

  DateTime effectiveNow(DateTime now) =>
      now.toUtc().isBefore(lastSeenAt) ? lastSeenAt : now.toUtc();

  bool isActive(DateTime now) => startedAt != null &&
      !effectiveNow(now).isBefore(startedAt!) &&
      effectiveNow(now).isBefore(expiresAt!);

  int daysRemaining(DateTime now) {
    if (!isActive(now)) return 0;
    return (expiresAt!.difference(effectiveNow(now)).inMicroseconds /
        Duration.microsecondsPerDay).ceil();
  }
}

abstract interface class TrialStore {
  Future<TrialRecord?> read();
  Future<void> write(TrialRecord record);
}
