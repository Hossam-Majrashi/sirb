enum SearchEngine {
  duckduckgo('https://duckduckgo.com/');

  const SearchEngine(this.endpoint);
  final String endpoint;
  Uri search(String text) =>
      Uri.parse(endpoint).replace(queryParameters: {'q': text});
}
