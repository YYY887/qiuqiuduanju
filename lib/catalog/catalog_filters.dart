import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/app_layout.dart';
import '../core/models.dart';
import '../ui/remote_widgets.dart';

class CatalogFilters extends StatefulWidget {
  const CatalogFilters({
    super.key,
    required this.categories,
    required this.category,
    required this.onCategory,
    required this.onRetry,
    this.error,
    this.trailing,
  });

  final List<CatalogCategory> categories;
  final String category;
  final String? error;
  final ValueChanged<String> onCategory;
  final VoidCallback onRetry;
  final Widget? trailing;

  @override
  State<CatalogFilters> createState() => _CatalogFiltersState();
}

class _CatalogFiltersState extends State<CatalogFilters> {
  final _anchors = <String, GlobalKey>{};
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CatalogFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.category != widget.category) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final anchor = _anchors[widget.category]?.currentContext;
        if (mounted && anchor != null) {
          Scrollable.ensureVisible(
            anchor,
            alignment: .4,
            duration: const Duration(milliseconds: 180),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final television = AppLayout.isTelevision(context);
    final colors = Theme.of(context).colorScheme;
    final phone =
        !television &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final mobileDark = phone && Theme.of(context).brightness == Brightness.dark;
    final accent = phone
        ? colors.primary
        : Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFB4E06D)
        : const Color(0xFF386B27);
    final idleColor = phone
        ? mobileDark
              ? const Color(0xFFE6C5B6)
              : const Color(0xFF68483D)
        : colors.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: phone ? Colors.transparent : colors.surfaceContainerLow,
        border: phone
            ? null
            : Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        height: television
            ? 64
            : max(58, MediaQuery.textScalerOf(context).scale(14) + 34),
        child: Row(
          children: [
            Expanded(
              child: television
                  ? SingleChildScrollView(
                      key: const ValueKey('catalog-categories'),
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          for (final entry in widget.categories)
                            Padding(
                              key: _anchors.putIfAbsent(
                                entry.id,
                                GlobalKey.new,
                              ),
                              padding: const EdgeInsets.only(right: 6),
                              child: RemoteButton(
                                key: ValueKey('category-${entry.id}'),
                                label: entry.name,
                                selected: entry.id == widget.category,
                                onPressed: () => widget.onCategory(entry.id),
                              ),
                            ),
                        ],
                      ),
                    )
                  : ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: const {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.stylus,
                          PointerDeviceKind.trackpad,
                        },
                      ),
                      child: SingleChildScrollView(
                        key: const ValueKey('catalog-categories'),
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            for (final entry in widget.categories)
                              Padding(
                                key: _anchors.putIfAbsent(
                                  entry.id,
                                  GlobalKey.new,
                                ),
                                padding: const EdgeInsets.only(right: 18),
                                child: InkWell(
                                  key: ValueKey('category-${entry.id}'),
                                  onTap: () => widget.onCategory(entry.id),
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 2,
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          entry.name,
                                          style: TextStyle(
                                            color: entry.id == widget.category
                                                ? accent
                                                : idleColor,
                                            fontSize: 14,
                                            fontWeight:
                                                entry.id == widget.category
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          width: 20,
                                          height: 3,
                                          decoration: BoxDecoration(
                                            color: entry.id == widget.category
                                                ? accent
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (widget.error != null)
              IconButton(
                tooltip: widget.error,
                onPressed: widget.onRetry,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            if (widget.trailing != null) widget.trailing!,
          ],
        ),
      ),
    );
  }
}
