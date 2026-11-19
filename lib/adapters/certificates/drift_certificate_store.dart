// lib/adapters/certificates/drift_certificate_store.dart
//
// Drift-backed read+write adapter for the Certificates bounded context
// (Phase 6). Thin wrapper over the existing AppDatabase methods — no SQL
// changes.

import 'package:finwick/database/app_database.dart';
import 'package:finwick/domain/certificates/ports/certificate_store.dart';
import 'package:finwick/models/models.dart';

class DriftCertificateStore implements CertificateStore {
  const DriftCertificateStore();

  @override
  Future<List<Certificate>> getCertificates() =>
      AppDatabase.instance.getCertificates();

  @override
  Future<void> insertCertificate(Certificate c) =>
      AppDatabase.instance.insertCertificate(c);

  @override
  Future<void> updateCertificate(Certificate c) =>
      AppDatabase.instance.updateCertificate(c);

  @override
  Future<void> deleteCertificate(String id) =>
      AppDatabase.instance.deleteCertificate(id);
}
