class UpdateStorage {
  Future<void> clean() async {}
  Future<String> save(Stream<List<int>> bytes, String expectedHash) async =>
      throw UnsupportedError('Atualização disponível apenas no Android.');
}
