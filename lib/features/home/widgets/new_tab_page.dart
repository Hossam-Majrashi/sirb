import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../shared/widgets/bounded_page.dart';
import '../services/browser_controller.dart';

class NewTabPage extends StatefulWidget {
  const NewTabPage({super.key, required this.browser});
  final BrowserController browser;
  @override
  State<NewTabPage> createState() => _NewTabPageState();
}

class _NewTabPageState extends State<NewTabPage> {
  final search = TextEditingController();
  final scrollController = ScrollController();
  late final sites = widget.browser.store.mostVisited();
  @override
  void dispose() {
    search.dispose();
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scrollbar(
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        child: BoundedPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Image.asset('assets/icon/icon.png', height: 96),
              const SizedBox(height: 24),
              Text(
                l.appName,
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: search,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: l.search,
                    onPressed: () => widget.browser.navigate(search.text),
                    icon: const Icon(Icons.arrow_forward),
                  ),
                ),
                onSubmitted: (s) => widget.browser.navigate(s),
              ),
              const SizedBox(height: 32),
              Text(
                l.mostVisited,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              FutureBuilder(
                future: sites,
                builder: (context, snapshot) {
                  final items = snapshot.data ?? [];
                  return Column(
                    children: items
                        .map(
                          (item) => ListTile(
                            leading: const Icon(Icons.public),
                            title: Text(
                              (item['title'] as String).isEmpty
                                  ? item['url'] as String
                                  : item['title'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              item['url'] as String,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () =>
                                widget.browser.navigate(item['url'] as String),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
