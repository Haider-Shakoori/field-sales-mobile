/// Record-level sync state for locally stored entities.
///
/// Batch 6 ships the core states below (`pending`, `syncing`, `synced`,
/// `failed`); `conflict` arrives with the Batch 12 sync engine. States are
/// stored as lowercase strings in SQLite so they are forwards-compatible.
enum SyncStatus {
  pending,
  syncing,
  synced,
  failed,
  conflict;

  static SyncStatus from(String? value) => SyncStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => SyncStatus.pending,
  );
}

/// Device-level connectivity as surfaced by the local network probes.
enum NetworkState {
  online,
  offline,
  limited;

  static NetworkState from(String? value) => NetworkState.values.firstWhere(
    (s) => s.name == value,
    orElse: () => NetworkState.offline,
  );
}
