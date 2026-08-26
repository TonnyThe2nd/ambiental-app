import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../features/incident/domain/entities/incident.dart';

class FirebaseIncidentRemoteDataSource {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  Future<Incident> upload(Incident i) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Autenticação Firebase indisponível.');
    }
    await _firestore.collection('ocorrencias').doc(i.id).set({
      'id': i.id,
      'categoria': i.category,
      'lat': i.latitude,
      'lng': i.longitude,
      'timestamp': Timestamp.fromDate(i.createdAt),
      'status': 'pendente_aprovacao',
      'userId': uid,
      'metadata': {'origem': 'mobile', 'fotoMantidaNoDispositivo': true},
    });
    return i;
  }

  Stream<List<Incident>> watch() => _firestore
      .collection('ocorrencias')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((d) {
          final m = d.data();
          return Incident(
            id: d.id,
            imagePath: '',
            imageUrl: m['imagemUrl'] as String?,
            category: m['categoria'] as String,
            latitude: (m['lat'] as num).toDouble(),
            longitude: (m['lng'] as num).toDouble(),
            createdAt: (m['timestamp'] as Timestamp).toDate(),
            status: IncidentStatus.synced,
          );
        }).toList(),
      );
}
