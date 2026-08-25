import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../features/incident/domain/entities/incident.dart';

class FirebaseIncidentRemoteDataSource {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  Future<Incident> upload(Incident i) async {
    final ref = _storage.ref('incidents/${i.id}.jpg');
    await ref.putFile(File(i.imagePath));
    final url = await ref.getDownloadURL();
    await _firestore.collection('ocorrencias').doc(i.id).set({
      'id': i.id,
      'imagemUrl': url,
      'categoria': i.category,
      'lat': i.latitude,
      'lng': i.longitude,
      'timestamp': Timestamp.fromDate(i.createdAt),
      'status': 'pendente_aprovacao',
      'metadata': {'origem': 'mobile'},
    });
    return i.copyWith(imageUrl: url);
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
