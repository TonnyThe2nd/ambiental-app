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
      await CreateIncidentUseCase(widget.dependencies.repository)(
        imagePath: imagePath!,
        category: category,
        latitude: place.latitude,
        longitude: place.longitude,
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
    appBar: AppBar(title: const Text('Nova ocorrência')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (imagePath == null)
          const Placeholder(fallbackHeight: 220)
        else
          Image.file(File(imagePath!), height: 220, fit: BoxFit.cover),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: loading ? null : _capture,
          icon: const Icon(Icons.camera_alt),
          label: const Text('Abrir câmera'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: category,
          decoration: const InputDecoration(labelText: 'Categoria'),
          items: const ['alagamento', 'poluicao', 'lixo', 'outro']
              .map((item) => DropdownMenuItem(value: item, child: Text(item)))
              .toList(),
          onChanged: loading
              ? null
              : (value) => setState(() => category = value!),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: loading ? null : _save,
          child: Text(loading ? 'Salvando...' : 'Salvar e sincronizar'),
        ),
      ],
    ),
  );
}
