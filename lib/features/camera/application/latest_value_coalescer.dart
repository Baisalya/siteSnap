import 'dart:async';

typedef LatestValueApplier<T> = Future<void> Function(T value);

/// Runs at most one asynchronous update at a time while retaining only the
/// newest value submitted during that update.
///
/// Camera controls can emit many values per second. Serializing every value
/// creates a long native-command backlog, so intermediate values are safely
/// replaced by the latest target instead.
class LatestValueCoalescer<T> {
  _PendingValue<T>? _pending;
  Future<void>? _activeDrain;
  int _generation = 0;

  bool get isBusy => _activeDrain != null || _pending != null;

  void submit(T value, LatestValueApplier<T> apply) {
    _pending = _PendingValue<T>(value, apply);
    _ensureDrain();
  }

  /// Drops any queued intermediate value, waits for the one already in flight,
  /// then applies [value]. This gives capture a single authoritative value
  /// without waiting for an entire gesture history.
  Future<void> flush(T value, LatestValueApplier<T> apply) async {
    final activeDrain = _activeDrain;
    _generation++;
    _pending = null;

    if (activeDrain != null) {
      await activeDrain;
    }
    await apply(value);
  }

  void cancelPending() {
    _generation++;
    _pending = null;
  }

  void _ensureDrain() {
    if (_activeDrain != null) return;

    final generation = _generation;
    final drain = _drain(generation);
    _activeDrain = drain;
    unawaited(drain.whenComplete(() {
      if (!identical(_activeDrain, drain)) return;
      _activeDrain = null;
      if (_pending != null) {
        _ensureDrain();
      }
    }));
  }

  Future<void> _drain(int generation) async {
    while (generation == _generation) {
      final pending = _pending;
      if (pending == null) return;

      _pending = null;
      await pending.apply(pending.value);
    }
  }
}

class _PendingValue<T> {
  const _PendingValue(this.value, this.apply);

  final T value;
  final LatestValueApplier<T> apply;
}
