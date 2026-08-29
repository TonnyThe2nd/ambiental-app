import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../app/app_initializer.dart';
import '../../domain/usecases/create_incident_use_case.dart';

class IncidentFormPage extends StatefulWidget {
  const IncidentFormPage({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<IncidentFormPage> createState() => _IncidentFormPageState();
}

class _IncidentFormPageState extends State<IncidentFormPage> {
  String? imagePath;
  String category = 'alagamento';
  bool loading = false;
  Future<void> _capture() async {
    final path = await widget.dependencies.camera.capturePhoto();
    if (mounted && path != null) setState(() => imagePath = path);
  }

  Future<void> _save() async {
    if (imagePath == null) {
      _message('Capture uma foto antes de salvar.');
      return;
    }
    setState(() => loading = true);
    try {
      final place = await widget.dependencies.location.current();
      final user = widget.dependencies.auth.currentUser!;
      await CreateIncidentUseCase(widget.dependencies.repository)(
        imagePath: imagePath!,
        category: category,
        latitude: place.latitude,
        longitude: place.longitude,
        reportedById: user.id,
        reportedByName: user.name,
      );
      final synced = await widget.dependencies.sync.synchronize();
      if (mounted) {
        _message(
          synced > 0
              ? 'Ocorrência sincronizada.'
              : 'Ocorrência salva na fila local.',
        );
      }
    } catch (error) {
      if (mounted) _message(error.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _message(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nova ocorrência'),
          Text(
            'Ajude a cuidar da sua cidade',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: Color(0xFF667C75),
            ),
          ),
        ],
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        GestureDetector(
          onTap: loading ? null : _capture,
          child: Container(
            height: 230,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: const Color(0xFFE4F1ED),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFCFE3DC)),
            ),
            child: imagePath == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white,
                        child: Icon(
                          Icons.add_a_photo_outlined,
                          color: Color(0xFF176B5B),
                          size: 28,
                        ),
                      ),
                      SizedBox(height: 14),
                      Text(
                        'Adicione uma foto',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF18332D),
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Toque para abrir a câmera',
                        style: TextStyle(color: Color(0xFF667C75)),
                      ),
                    ],
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(File(imagePath!), fit: BoxFit.cover),
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.refresh,
                                color: Colors.white,
                                size: 17,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Trocar foto',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'Tipo de ocorrência',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF18332D),
          ),
        ),
        const SizedBox(height: 9),
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: const ['alagamento', 'poluicao', 'lixo', 'outro']
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(_categoryLabel(item)),
                ),
              )
              .toList(),
          onChanged: loading
              ? null
              : (value) => setState(() => category = value!),
        ),
        const SizedBox(height: 14),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined, color: Color(0xFF2A806F)),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Localização automática',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'As coordenadas serão incluídas ao enviar.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF667C75),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.check_circle, color: Color(0xFF57A78D)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: loading ? null : _save,
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.send_rounded),
          label: Text(loading ? 'Salvando...' : 'Salvar e sincronizar'),
        ),
      ],
    ),
  );
}

String _categoryLabel(String category) => switch (category) {
  'alagamento' => 'Alagamento',
  'poluicao' => 'Poluição',
  'lixo' => 'Descarte de lixo',
  _ => 'Outro',
};
