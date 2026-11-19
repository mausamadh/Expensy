// lib/domain/certificates/ports/certificate_store.dart
//
// Domain port for the Certificates bounded context (Phase 6, "Slim the
// provider"). The [CertificateViewModel] persists certificates through this
// port; the concrete Drift implementation lives in `adapters/` and is
// injected by the composition root.
//
// Layering: this file lives in `domain/` and imports only `models/` —
// never `database/`, `adapters/`, or `providers/`.

import 'package:finwick/models/models.dart';

abstract class CertificateStore {
  /// All certificates, ordered by creation date (newest first).
  Future<List<Certificate>> getCertificates();

  /// Inserts a certificate.
  Future<void> insertCertificate(Certificate c);

  /// Updates an existing certificate.
  Future<void> updateCertificate(Certificate c);

  /// Deletes a certificate by id.
  Future<void> deleteCertificate(String id);
}
