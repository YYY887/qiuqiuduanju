import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_layout.dart';
import '../app/app_bottom_navigation.dart';
import '../core/core_bridge.dart';
import '../catalog/catalog_filters.dart';
import '../catalog/catalog_browser.dart';
import '../catalog/catalog_sort.dart';
import '../catalog/catalog_sort_sheet.dart';
import '../catalog/recommendations_screen.dart';
import '../catalog/rankings_screen.dart';
import 'detail_screen.dart';
import '../playback/playback_launch_screen.dart';
import '../downloads/downloads_screen.dart';
import '../library/local_store.dart';
import '../lan/lan_screen.dart';
import '../core/models.dart';
import 'remote_widgets.dart';
import 'widgets.dart';
import 'vip_icon.dart';
import '../settings/settings_screen.dart';
import '../settings/profiles_screen.dart';
import '../catalog/search_input.dart';
import '../catalog/sources_screen.dart';
import '../downloads/batch_download_screen.dart';
import '../downloads/batch_downloads.dart';
import 'drama_actions.dart';
import 'mobile_discovery_sections.dart';
import '../catalog/library_updater.dart';
import '../library/saved_library.dart';
import 'my_screen.dart';
import 'app_gradient_background.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository, required this.store});
  final AppRepository repository;
  final LocalStore store;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const _recommendationCategory = 'app:recommendations';
  static const _catalogBatchSize = 36;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;
  late SourceSite _source;
  bool _allSources = false;
  List<Drama> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _generation = 0;
  int _tab = 0;
  bool _sourceUnlockInProgress = false;
  String _submittedQuery = '';
  final _categorySelections = <String, String>{};
  final _categorySnapshots = <String, (List<Drama>, bool, int)>{};
  final _loadedCategoryGroups = <String>{};
  int? _categorySnapshotEpoch;
  late final CatalogBrowser _browser;
  bool _searchVisible = false;
  bool _categoriesLoading = false;
  String? _categoriesError;
  int _categoryGeneration = 0;
  late final LibraryUpdater _updater;
  final _changedSources = <String>{};
  final _selectedDramas = <String, Drama>{};
  Timer? _cacheRefreshTimer;
  bool _refreshingUpdatedCache = false;
  bool _selectionMode = false;
  bool _showRecommendations = false;
  double? _categoryDragDistanceValue;
  double get _categoryDragDistance => _categoryDragDistanceValue ?? 0;
  set _categoryDragDistance(double value) => _categoryDragDistanceValue = value;
  double? _categoryTransitionDirectionValue;
  double get _categoryTransitionDirection =>
      _categoryTransitionDirectionValue ?? 1;
  set _categoryTransitionDirection(double value) =>
      _categoryTransitionDirectionValue = value;
  AnimationController? _categoryTransitionControllerValue;
  AnimationController get _categoryTransitionController =>
      _categoryTransitionControllerValue ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
        value: 1,
      );
  ValueNotifier<double>? _categorySwipeOffsetValue;
  ValueNotifier<double> get _categorySwipeOffset =>
      _categorySwipeOffsetValue ??= ValueNotifier<double>(0);
  ValueNotifier<String?>? _categorySwipeTargetValue;
  ValueNotifier<String?> get _categorySwipeTargetNotifier =>
      _categorySwipeTargetValue ??= ValueNotifier<String?>(null);
  String? get _categorySwipeTarget => _categorySwipeTargetValue?.value;
  set _categorySwipeTarget(String? value) =>
      _categorySwipeTargetNotifier.value = value;
  ValueNotifier<String?>? _categorySwipeHighlightValue;
  ValueNotifier<String?> get _categorySwipeHighlightNotifier =>
      _categorySwipeHighlightValue ??= ValueNotifier<String?>(null);
  String? get _categorySwipeHighlight => _categorySwipeHighlightValue?.value;
  set _categorySwipeHighlight(String? value) =>
      _categorySwipeHighlightNotifier.value = value;
  double? _categorySwipeStartValue;
  double? _categorySwipeEndValue;
  bool? _categorySwipeSettlingValue;
  int? _categorySwipeGenerationValue;
  int get _categorySwipeGeneration => _categorySwipeGenerationValue ?? 0;
  set _categorySwipeGeneration(int value) =>
      _categorySwipeGenerationValue = value;
  bool _catalogLoadScheduled = false;
  int _renderLimit = _catalogBatchSize;
  List<Drama>? _visibleSource;
  List<Drama>? _visibleCache;
  (String, String, String, bool, bool, CatalogSort, String, int, String)?
  _visibleFingerprint;
  final _visitedTabs = <int>{0};
  Widget? _rankingsTab;
  int? _rankingsEpoch;
  Widget? _catalogTab;
  bool _catalogTabDirty = true;
  (double, double, int)? _catalogTabLayout;

  @override
  void setState(VoidCallback fn) {
    _catalogTabDirty = true;
    super.setState(fn);
  }

  void _storeChanged() {
    _catalogTabDirty = true;
    if (_categorySnapshotEpoch != widget.store.profileEpoch) {
      _categorySnapshotEpoch = widget.store.profileEpoch;
      _categorySnapshots.clear();
      _loadedCategoryGroups.clear();
      _rankingsTab = null;
    }
  }

  List<SourceGroup> get _sourceGroups {
    final groups = SourceGroup.fromSources(widget.store.sources);
    return [
      if (groups.length > 1) SourceGroup('all', '全部站源', widget.store.sources),
      ...groups,
    ];
  }

  SourceGroup get _group =>
      _sourceGroups
          .where((group) => group.id == (_allSources ? 'all' : _source.groupId))
          .firstOrNull ??
      SourceGroup(_source.groupId, _source.groupName, [_source]);
  bool get _onlineSearch => _group.sources.any((source) => source.onlineSearch);
  bool get _searchSuggestions =>
      _group.sources.any((source) => source.searchSuggestions);
  String get _searchHint {
    final online = _group.sources
        .where((source) => source.onlineSearch)
        .toList();
    if (online.isEmpty) {
      return '筛选本机已更新剧库';
    }
    final names = online.map((source) => source.name).join('、');
    return online.length == _group.sources.length
        ? '搜索$names'
        : '搜索$names及本机剧库';
  }

  String get _category => _categorySelections[_group.id] ?? '';
  String _categorySnapshotKey(String category) =>
      '${_group.id}|$category|${widget.store.profileEpoch}';

  void _rememberCategory() {
    if (_showRecommendations ||
        _search.text.trim().isNotEmpty ||
        _submittedQuery.isNotEmpty ||
        _items.isEmpty) {
      return;
    }
    final key = _categorySnapshotKey(_category);
    _categorySnapshots.remove(key);
    _categorySnapshots[key] = (_items, _hasMore, _renderLimit);
    if (_categorySnapshots.length > 12) {
      _categorySnapshots.remove(_categorySnapshots.keys.first);
    }
  }

  List<CatalogCategory> get _categories => _browser.categories(_group);
  String get _displayCategory =>
      _showRecommendations ? _recommendationCategory : _category;
  List<CatalogCategory> get _displayCategories => [
    CatalogCategory.all,
    if (_group.id == 'hongguo')
      const CatalogCategory(_recommendationCategory, '推荐'),
    ..._categories.where((entry) => entry.id.isNotEmpty),
  ];

  Future<void> _loadCategories({
    bool force = false,
    bool cacheOnly = false,
  }) async {
    final generation = ++_categoryGeneration;
    final group = _group;
    setState(() {
      _categoriesLoading = true;
      _categoriesError = null;
    });
    final error = await _browser.loadCategories(
      group,
      force: force,
      cacheOnly: cacheOnly,
    );
    if (!mounted ||
        generation != _categoryGeneration ||
        group.id != _group.id) {
      return;
    }
    setState(() {
      _categoriesLoading = false;
      _categoriesError = error;
    });
    if (error == null) _loadedCategoryGroups.add(group.id);
    if (!_showRecommendations &&
        _category.isNotEmpty &&
        !_categories.any((entry) => entry.id == _category)) {
      _changeCategory('');
    }
  }

  Future<void> _refreshCatalog() async {
    _categorySnapshots.clear();
    _loadedCategoryGroups.remove(_group.id);
    if (widget.repository.supportsSourceManagement) {
      if (_group.sources.any((source) => _updater.busy(source.id))) return;
      _pauseCatalog();
      await _updater.update(_group.sources);
      return;
    }
    await _loadCategories(force: true);
    if (mounted) await _load(force: true);
  }

  void _updateChanged() {
    if (mounted) setState(() {});
  }

  void _catalogUpdated(String source) {
    if (!mounted) return;
    _categorySnapshots.clear();
    _changedSources.add(source);
    _cacheRefreshTimer?.cancel();
    _cacheRefreshTimer = Timer(const Duration(milliseconds: 100), () {
      unawaited(_reloadUpdatedCache());
    });
  }

  Future<void> _reloadUpdatedCache() async {
    if (_refreshingUpdatedCache) return;
    _refreshingUpdatedCache = true;
    final epoch = widget.store.profileEpoch;
    try {
      while (mounted &&
          _changedSources.isNotEmpty &&
          epoch == widget.store.profileEpoch) {
        final sources = Set.of(_changedSources);
        _changedSources.clear();
        final updates = <String, Drama>{};
        for (final source in sources) {
          if (!widget.store.allowsSource(source)) continue;
          try {
            final cached = await widget.repository.cached(source);
            for (final drama in cached.items) {
              if (widget.store.allowsSource(drama.source)) {
                updates[drama.id] = drama;
              }
            }
          } catch (error) {
            if (mounted && epoch == widget.store.profileEpoch) {
              setState(() => _error = '更新后读取缓存失败：$error');
            }
          }
        }
        if (!mounted || epoch != widget.store.profileEpoch) return;
        _browser.updateDramas(updates.values);
        setState(() {
          _items = [
            for (final item in _items)
              updates[item.id] == null ? item : item.merge(updates[item.id]!),
          ];
          for (final id in _selectedDramas.keys.toList()) {
            if (updates[id] != null) {
              _selectedDramas[id] = _selectedDramas[id]!.merge(updates[id]!);
            }
          }
        });
        await saveUserChange(
          context,
          () => widget.store.refreshDramas(updates.values),
        );
        if (!mounted || epoch != widget.store.profileEpoch) return;
        if (_group.sources.any((source) => sources.contains(source.id))) {
          await _loadCategories(cacheOnly: true);
          if (mounted &&
              !_loading &&
              !_loadingMore &&
              (!_onlineSearch || _search.text.trim().isEmpty)) {
            await _load(cacheOnly: true);
          }
        }
      }
    } finally {
      _refreshingUpdatedCache = false;
    }
  }

  Future<void> _changeGroup(SourceGroup group) async {
    if (_group.id == group.id || _sourceUnlockInProgress) return;
    _sourceUnlockInProgress = true;
    try {
      if (!await _unlockSourceSwitch() || !mounted) return;
      if (!widget.store.allowsSource(group.sources.first.id)) return;
      _changeSource(group.sources.first, allSources: group.id == 'all');
    } finally {
      _sourceUnlockInProgress = false;
    }
  }

  Future<bool> _unlockSourceSwitch() async {
    if (widget.store.sourceSwitchUnlocked) return true;
    var password = '';
    var incorrect = false;
    final route = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          void submit() {
            if (password.trim() == '987654321') {
              Navigator.pop(dialogContext, true);
            } else {
              update(() => incorrect = true);
            }
          }

          return AlertDialog(
            title: const Text('切换站源'),
            content: TextField(
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              onChanged: (value) {
                password = value;
                if (incorrect) update(() => incorrect = false);
              },
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: '请输入切换密码',
                errorText: incorrect ? '密码不正确' : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(onPressed: submit, child: const Text('确认')),
            ],
          );
        },
      ),
    );
    final accepted = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(route);
    if (accepted != true || !mounted) return false;
    await route.completed;
    if (!mounted) return false;
    try {
      await widget.store.unlockSourceSwitch();
      return mounted && widget.store.sourceSwitchUnlocked;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存站源解锁状态失败：$error')));
      }
      return false;
    }
  }

  void _openWatchHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('最近观看')),
          body: SavedLibrary(
            repository: widget.repository,
            store: widget.store,
            history: true,
            onOpen: _openDrama,
            onContinue: (drama) => _openDrama(drama, resume: true),
            onDownload:
                widget.store.canDownload && widget.repository.supportsDownloads
                ? (drama) => _openDrama(drama, download: true)
                : null,
          ),
        ),
      ),
    );
  }

  void _clearCategorySwipe() {
    if (_categorySwipeTarget == null &&
        _categorySwipeSettlingValue != true &&
        (_categorySwipeOffsetValue?.value ?? 0) == 0) {
      return;
    }
    _categorySwipeGeneration++;
    _categoryTransitionController.stop();
    _categorySwipeSettlingValue = false;
    _categorySwipeOffsetValue?.value = 0;
    _categorySwipeTarget = null;
    _categorySwipeHighlight = null;
  }

  void _changeCategory(String category, {bool animate = true}) {
    final cancelSwipe =
        animate &&
        (_categorySwipeTarget != null || _categorySwipeSettlingValue == true);
    if (cancelSwipe) _clearCategorySwipe();
    final categories = _displayCategories;
    final previousIndex = categories.indexWhere(
      (entry) => entry.id == _displayCategory,
    );
    final nextIndex = categories.indexWhere((entry) => entry.id == category);
    if (previousIndex >= 0 && nextIndex >= 0 && previousIndex != nextIndex) {
      _categoryTransitionDirection = nextIndex > previousIndex ? 1 : -1;
    }
    if (category == _recommendationCategory && _group.id == 'hongguo') {
      if (_showRecommendations) {
        return;
      }
      _rememberCategory();
      _pauseCatalog();
      setState(() {
        _showRecommendations = true;
        _selectionMode = false;
        _selectedDramas.clear();
        _search.clear();
        _searchVisible = false;
        _submittedQuery = '';
      });
      if (animate) _categoryTransitionController.forward(from: 0);
      return;
    }
    if (_category == category && !_showRecommendations) {
      return;
    }
    _rememberCategory();
    final snapshot = _categorySnapshots[_categorySnapshotKey(category)];
    _debounce?.cancel();
    if (snapshot != null) {
      _generation++;
      unawaited(_browser.cancel());
    }
    setState(() {
      _showRecommendations = false;
      _selectionMode = false;
      _selectedDramas.clear();
      _categorySelections[_group.id] = category;
      if (_onlineSearch) {
        _search.clear();
        _submittedQuery = '';
      }
      _items = snapshot?.$1 ?? [];
      _renderLimit = snapshot?.$3 ?? _catalogBatchSize;
      _hasMore = snapshot?.$2 ?? true;
      _loading = snapshot == null;
      _loadingMore = false;
      _error = null;
    });
    if (animate) _categoryTransitionController.forward(from: 0);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (snapshot == null) _load(useCache: true);
  }

  void _swipeCategory(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final distance = _categoryDragDistance;
    _categoryDragDistance = 0;
    if (velocity.abs() < 240 && distance.abs() < 56) return;
    final categories = _displayCategories;
    final index = categories.indexWhere(
      (entry) => entry.id == _displayCategory,
    );
    final forward = velocity.abs() >= 240 ? velocity < 0 : distance < 0;
    final next = index + (forward ? 1 : -1);
    if (next >= 0 && next < categories.length) {
      _changeCategory(categories[next].id);
    }
  }

  void _startMobileCategorySwipe() {
    _categorySwipeGeneration++;
    _categoryTransitionController.stop();
    _categorySwipeSettlingValue = false;
    _categorySwipeOffset.value = 0;
    _categorySwipeTarget = null;
    _categorySwipeHighlight = null;
  }

  void _updateMobileCategorySwipe(DragUpdateDetails details, double width) {
    final delta = details.primaryDelta ?? 0;
    if (delta == 0 || width <= 0) return;
    final proposed = (_categorySwipeOffset.value + delta)
        .clamp(-width, width)
        .toDouble();
    final categories = _displayCategories;
    final index = categories.indexWhere(
      (entry) => entry.id == _displayCategory,
    );
    final next = index + (proposed < 0 ? 1 : -1);
    final target = proposed == 0 || next < 0 || next >= categories.length
        ? null
        : categories[next].id;
    final offset = target == null ? proposed * .18 : proposed;
    final highlight = target != null && offset.abs() >= width * .5
        ? target
        : null;
    _categorySwipeOffset.value = offset;
    if (target != _categorySwipeTarget) _categorySwipeTarget = target;
    if (highlight != _categorySwipeHighlight) {
      _categorySwipeHighlight = highlight;
    }
  }

  void _endMobileCategorySwipe(DragEndDetails details, double width) {
    final offset = _categorySwipeOffset.value;
    final target = _categorySwipeTarget;
    final velocity = details.primaryVelocity ?? 0;
    final completes =
        target != null &&
        (offset.abs() >= width * .5 ||
            velocity.abs() >= 650 && velocity.sign == offset.sign);
    _categorySwipeStartValue = offset;
    _categorySwipeEndValue = completes ? (offset < 0 ? -width : width) : 0;
    _categorySwipeSettlingValue = true;
    final generation = ++_categorySwipeGeneration;
    _categoryTransitionController.forward(from: 0).whenCompleteOrCancel(() {
      if (!mounted || generation != _categorySwipeGeneration) return;
      _categorySwipeSettlingValue = false;
      _categorySwipeOffset.value = 0;
      _categorySwipeTarget = null;
      _categorySwipeHighlight = null;
      if (completes && target != null) {
        _changeCategory(target, animate: false);
      }
    });
  }

  Widget _mobileCategoryPreview(String category, double width) {
    final name =
        _displayCategories
            .where((entry) => entry.id == category)
            .firstOrNull
            ?.name ??
        category;
    final snapshot = _categorySnapshots[_categorySnapshotKey(category)];
    final items =
        snapshot?.$1
            .where(
              (drama) =>
                  widget.store.allowsSource(drama.source) &&
                  !(_hideVip && drama.source == 'huangdou' && drama.vip),
            )
            .take(24)
            .toList(growable: false) ??
        const <Drama>[];
    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text('正在加载剧集'),
          ],
        ),
      );
    }
    final padding = width < 600 ? 16.0 : 24.0;
    final showTrending =
        !_selectionMode && (_onlineSearch || _search.text.trim().isEmpty);
    return IgnorePointer(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          if (showTrending)
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(padding, 16, padding, 12),
                    child: Text(
                      '近期热播',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TrendingDramaRow(
                    dramas: items.take(8).toList(growable: false),
                    repository: widget.repository,
                    onOpen: _openDrama,
                  ),
                ],
              ),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padding, 20, padding, 16),
              child: Text(
                showTrending ? '更多短剧' : name,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: padding),
            sliver: SliverGrid(
              gridDelegate: dramaGridDelegate(context, width - 2 * padding),
              delegate: SliverChildBuilderDelegate(
                (_, index) => _catalogTile(items[index]),
                childCount: items.length,
                addAutomaticKeepAlives: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileCategorySwipeFrame(Widget content, double width) {
    return ValueListenableBuilder<String?>(
      valueListenable: _categorySwipeTargetNotifier,
      child: RepaintBoundary(child: content),
      builder: (context, target, currentPage) {
        final preview = target == null
            ? null
            : RepaintBoundary(child: _mobileCategoryPreview(target, width));
        final categories = _displayCategories;
        final currentIndex = categories.indexWhere(
          (entry) => entry.id == _displayCategory,
        );
        final targetIndex = categories.indexWhere(
          (entry) => entry.id == target,
        );
        final previewFromRight = targetIndex > currentIndex;
        return AnimatedBuilder(
          animation: Listenable.merge([
            _categorySwipeOffset,
            _categoryTransitionController,
          ]),
          child: currentPage,
          builder: (context, current) {
            final progress = Curves.easeOutCubic.transform(
              _categoryTransitionController.value,
            );
            final offset = _categorySwipeSettlingValue == true
                ? (_categorySwipeStartValue ?? 0) +
                      ((_categorySwipeEndValue ?? 0) -
                              (_categorySwipeStartValue ?? 0)) *
                          progress
                : _categorySwipeOffset.value;
            return ClipRect(
              child: Stack(
                children: [
                  if (preview != null)
                    Positioned.fill(
                      child: Transform.translate(
                        offset: Offset(
                          offset + (previewFromRight ? width : -width),
                          0,
                        ),
                        child: preview,
                      ),
                    ),
                  Positioned.fill(
                    child: Transform.translate(
                      offset: Offset(offset, 0),
                      child: current,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _toggleSearch() {
    if (AppLayout.isTelevision(context)) {
      _televisionSearch();
      return;
    }
    if (_showRecommendations) _changeCategory('');
    final hadQuery = _search.text.isNotEmpty;
    setState(() {
      _searchVisible = !_searchVisible;
      if (!_searchVisible) _search.clear();
    });
    if (!_searchVisible && hadQuery) _searchChanged('');
  }

  void _openRankings() {
    _pauseCatalog();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RankingsScreen(
          repository: widget.repository,
          store: widget.store,
          initialGroup: _group.id,
        ),
      ),
    );
  }

  Future<void> _manageSources() async {
    final before = widget.store.sources.map((source) => source.id).join(',');
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SourcesScreen(
          repository: widget.repository,
          store: widget.store,
          initialSource: _source.id,
        ),
      ),
    );
    if (!mounted) return;
    final after = widget.store.sources.map((source) => source.id).join(',');
    if (before != after) {
      _categorySnapshots.clear();
      _loadedCategoryGroups.clear();
      await _loadCategories();
      if (mounted && (!_onlineSearch || _submittedQuery.isEmpty)) {
        await _load(useCache: true);
      }
    }
  }

  Future<void> _chooseDisplayMode() async {
    final selection = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('界面模式'),
        children: [
          RadioGroup<String>(
            groupValue: widget.store.displayMode,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final mode in const {
                  'auto': '自动识别设备',
                  'television': '电视 / 遥控器',
                  'standard': '手机 / 电脑',
                }.entries)
                  RadioListTile<String>(
                    value: mode.key,
                    autofocus: mode.key == widget.store.displayMode,
                    title: Text(mode.value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selection != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setDisplayMode(selection),
      );
    }
  }

  Future<void> _televisionSearch() async {
    final query = await showDialog<String>(
      context: context,
      builder: (_) => TelevisionSearchDialog(
        initialValue: _search.text,
        title: _group.id == 'all'
            ? '搜索已开放站源'
            : _onlineSearch
            ? '搜索${_group.name}短剧'
            : '筛选当前已加载短剧',
        recentSearches: widget.store.recentSearches,
        onCancel: () => unawaited(widget.repository.cancelSuggestions()),
        suggestions: _searchSuggestions ? widget.repository.suggestions : null,
      ),
    );
    if (query != null && mounted) {
      _submitSearch(query);
    }
  }

  void _televisionBack() {
    if (_selectionMode) {
      _cancelSelection();
    } else if (_tab != 0) {
      setState(() => _tab = 0);
    } else if (_search.text.isNotEmpty) {
      _search.clear();
      _searchChanged('');
    }
  }

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_storeChanged);
    _categorySnapshotEpoch = widget.store.profileEpoch;
    _scroll.addListener(_onCatalogScroll);
    _source = SourceSite.byId(widget.store.source);
    _allSources = widget.store.catalogView.allSources;
    _browser = CatalogBrowser(widget.repository);
    _updater = LibraryUpdater(
      widget.repository,
      widget.store,
      onCatalogChanged: _catalogUpdated,
    )..addListener(_updateChanged);
    _updater.startWatching();
    widget.repository.catalogUpdates.addListener(_metadataChanged);
    if (widget.store.sources.isNotEmpty) {
      _load(useCache: true);
      _loadCategories();
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_storeChanged);
    _updater.removeListener(_updateChanged);
    _updater.dispose();
    _cacheRefreshTimer?.cancel();
    widget.repository.catalogUpdates.removeListener(_metadataChanged);
    _generation++;
    _categoryGeneration++;
    unawaited(_browser.cancel());
    unawaited(widget.repository.cancelSuggestions());
    _debounce?.cancel();
    _search.dispose();
    _scroll.removeListener(_onCatalogScroll);
    _scroll.dispose();
    _categoryTransitionControllerValue?.dispose();
    _categorySwipeOffsetValue?.dispose();
    _categorySwipeTargetValue?.dispose();
    _categorySwipeHighlightValue?.dispose();
    super.dispose();
  }

  void _onCatalogScroll() {
    if (!mounted ||
        _tab != 0 ||
        _showRecommendations ||
        _loading ||
        _loadingMore ||
        !_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final threshold = (position.viewportDimension * 1.5).clamp(320.0, 900.0);
    if (position.extentAfter > threshold || _catalogLoadScheduled) return;
    _catalogLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _catalogLoadScheduled = false;
      if (!mounted ||
          _tab != 0 ||
          _showRecommendations ||
          _loading ||
          _loadingMore ||
          !_scroll.hasClients) {
        return;
      }
      final mobile =
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS;
      if (!mobile &&
          !AppLayout.isTelevision(context) &&
          _renderLimit < _visible.length) {
        setState(() => _renderLimit += _catalogBatchSize);
      } else if (_hasMore) {
        unawaited(_load(more: true));
      }
    });
  }

  bool _onCatalogScrollNotification(ScrollNotification notification) {
    if (notification is OverscrollNotification &&
        notification.metrics.axis == Axis.vertical &&
        notification.overscroll > 0) {
      _onCatalogScroll();
    }
    return false;
  }

  void _metadataChanged() {
    final drama = widget.repository.catalogUpdates.latest;
    if (!mounted || drama == null || !widget.store.allowsSource(drama.source)) {
      return;
    }
    _browser.updateDrama(drama);
    setState(() {
      _items = [
        for (final item in _items)
          item.id == drama.id ? item.merge(drama) : item,
      ];
    });
    unawaited(saveUserChange(context, () => widget.store.refreshDrama(drama)));
  }

  Future<void> _load({
    bool more = false,
    bool useCache = false,
    bool force = false,
    bool cacheOnly = false,
  }) async {
    if (_showRecommendations) return;
    if (more && (_loading || _loadingMore || !_hasMore)) return;
    final generation = ++_generation;
    final group = _group;
    final query = _onlineSearch ? _search.text.trim() : '';
    setState(() {
      _error = null;
      if (query.isNotEmpty) _categorySelections[group.id] = '';
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _loadingMore = false;
        if (query != _submittedQuery) {
          _items = [];
          _renderLimit = _catalogBatchSize;
        }
      }
    });
    void accept(CatalogPage result, {bool cached = false}) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = result.items;
        _hasMore = result.hasMore;
        _submittedQuery = query;
        _loading = cached && !result.fresh;
        _loadingMore = false;
        _error = result.warning.isEmpty ? null : result.warning;
      });
      _rememberCategory();
      unawaited(
        saveUserChange(context, () => widget.store.refreshDramas(result.items)),
      );
    }

    try {
      final result = await _browser.load(
        group,
        category: _category,
        query: query,
        more: more,
        useCache: useCache,
        force: force,
        cacheOnly: cacheOnly,
        onCached: (result) => accept(result, cached: true),
      );
      accept(result);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _changeSource(SourceSite source, {bool allSources = false}) {
    if (_source.id == source.id && _allSources == allSources) {
      return;
    }
    _clearCategorySwipe();
    _rememberCategory();
    (List<Drama>, bool, int)? snapshot;
    _debounce?.cancel();
    _search.clear();
    setState(() {
      _showRecommendations = false;
      _selectionMode = false;
      _selectedDramas.clear();
      _source = source;
      _allSources = allSources;
      snapshot = _categorySnapshots[_categorySnapshotKey(_category)];
      _items = snapshot?.$1 ?? [];
      _renderLimit = snapshot?.$3 ?? _catalogBatchSize;
      _hasMore = snapshot?.$2 ?? true;
      _loading = false;
      _loadingMore = false;
      _submittedQuery = '';
      _error = null;
    });
    if (snapshot != null) {
      _generation++;
      unawaited(_browser.cancel());
    }
    unawaited(
      saveUserChange(
        context,
        () => widget.store.setCatalogSource(source.id, allSources: allSources),
      ),
    );
    if (_scroll.hasClients) {
      _scroll.jumpTo(0);
    }
    if (snapshot == null) _load(useCache: true);
    if (!_loadedCategoryGroups.contains(_group.id)) _loadCategories();
  }

  void _searchChanged(String query) {
    _debounce?.cancel();
    _selectionMode = false;
    _selectedDramas.clear();
    if (_onlineSearch && (_loading || _loadingMore)) {
      _generation++;
      unawaited(_browser.cancel());
      _loading = _loadingMore = false;
    }
    setState(() => _renderLimit = _catalogBatchSize);
    if (_onlineSearch && query.trim().isEmpty) {
      _debounce = Timer(const Duration(milliseconds: 300), () => _load());
    }
  }

  void _submitSearch(String query) {
    if (_showRecommendations) {
      _showRecommendations = false;
      _categorySelections[_group.id] = '';
    }
    _selectionMode = false;
    _selectedDramas.clear();
    _search.text = query.trim();
    _debounce?.cancel();
    if (_search.text.isNotEmpty) {
      unawaited(
        saveUserChange(
          context,
          () => widget.store.rememberSearch(_search.text),
        ),
      );
    }
    if (_onlineSearch) {
      _load();
    } else {
      setState(() => _renderLimit = _catalogBatchSize);
    }
  }

  Future<void> _chooseCatalogView() async {
    final selected = await chooseCatalogView(context, widget.store.catalogView);
    if (selected != null && mounted) {
      await saveUserChange(
        context,
        () => widget.store.setCatalogView(selected),
      );
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _openDrama(Drama drama, {bool resume = false, bool download = false}) {
    _pauseCatalog();
    if (!AppLayout.isTelevision(context) &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DetailScreen(
            drama: drama,
            repository: widget.repository,
            store: widget.store,
            resumeOnOpen: resume,
            downloadOnOpen: download,
          ),
        ),
      );
      return;
    }
    if (download) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DetailScreen(
            drama: drama,
            repository: widget.repository,
            store: widget.store,
            downloadOnOpen: true,
          ),
        ),
      );
      return;
    }
    unawaited(
      openPlaybackDirectly(
        context,
        drama: drama,
        repository: widget.repository,
        store: widget.store,
      ),
    );
  }

  void _changeTab(int tab) {
    if (_tab == tab) return;
    _clearCategorySwipe();
    if (_selectionMode) _catalogTabDirty = true;
    super.setState(() {
      _tab = tab;
      _visitedTabs.add(tab);
      _selectionMode = false;
      _selectedDramas.clear();
    });
  }

  void _cancelSelection() => setState(() {
    _selectionMode = false;
    _selectedDramas.clear();
  });

  void _selectDrama(Drama drama) {
    if (!widget.store.canDownload ||
        !widget.repository.supportsDownloads ||
        !widget.store.allowsSource(drama.source)) {
      return;
    }
    if (!_selectedDramas.containsKey(drama.id) &&
        _selectedDramas.length >= BatchDownloads.maxDramas) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('一次最多选择 50 部短剧，请分批下载')));
      return;
    }
    setState(() {
      _selectionMode = true;
      if (_selectedDramas.remove(drama.id) == null) {
        _selectedDramas[drama.id] = drama;
      }
    });
  }

  void _downloadSelected() {
    if (!widget.store.canDownload || _selectedDramas.isEmpty) return;
    _pauseCatalog();
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BatchDownloadScreen(
          repository: widget.repository,
          store: widget.store,
          dramas: _selectedDramas.values.toList(),
        ),
      ),
    );
  }

  void _dramaActions(Drama drama) => showDramaActions(
    context,
    drama: drama,
    store: widget.store,
    onContinue: () => _openDrama(drama, resume: true),
    onDownload: widget.repository.supportsDownloads && widget.store.canDownload
        ? () => _openDrama(drama, download: true)
        : null,
    onSelect: widget.repository.supportsDownloads && widget.store.canDownload
        ? () => _selectDrama(drama)
        : null,
  );

  Widget _catalogTile(
    Drama drama, {
    FocusNode? focusNode,
    VoidCallback? onFocus,
  }) {
    final following = widget.store.following(drama.id);
    final canSelect =
        widget.store.canDownload && widget.repository.supportsDownloads;
    return DramaTile(
      key: ValueKey(drama.id),
      drama: drama,
      repository: widget.repository,
      focusNode: focusNode,
      onFocus: onFocus,
      onTap: () => _selectionMode ? _selectDrama(drama) : _openDrama(drama),
      onLongPress: canSelect ? () => _selectDrama(drama) : null,
      onMore: () => _dramaActions(drama),
      actions: DramaActionButton(
        drama: drama,
        onPressed: () => _dramaActions(drama),
      ),
      selected: _selectionMode ? _selectedDramas.containsKey(drama.id) : null,
      badge: following == null
          ? null
          : '${following.status.label}${following.hasUpdates ? ' · ${following.updateLabel}' : ''}',
    );
  }

  void _pauseCatalog() {
    _debounce?.cancel();
    _generation++;
    unawaited(_browser.cancel());
    unawaited(widget.repository.cancelSuggestions());
    setState(() {
      _loading = false;
      _loadingMore = false;
    });
  }

  bool get _supportsVipFilter =>
      _group.sources.any((source) => source.id == 'huangdou');
  bool get _hideVip => _supportsVipFilter && widget.store.hideVip;

  List<Drama> get _visible {
    final query = _search.text.trim().toLowerCase();
    final view = widget.store.catalogView;
    final fingerprint = (
      _group.id,
      _category,
      query,
      _hideVip,
      _onlineSearch,
      view.sort,
      view.release,
      widget.store.profileEpoch,
      widget.store.sources.map((source) => source.id).join(','),
    );
    if (identical(_visibleSource, _items) &&
        _visibleFingerprint == fingerprint &&
        _visibleCache != null) {
      return _visibleCache!;
    }
    final result = sortCatalog(
      _items.where((drama) {
        if (!widget.store.allowsSource(drama.source)) return false;
        if (_category.startsWith('local:') &&
            categoryName(drama.category) != _category.substring(6)) {
          return false;
        }
        if (_hideVip && drama.source == 'huangdou' && drama.vip) {
          return false;
        }
        return _onlineSearch ||
            query.isEmpty ||
            matchesDramaQuery(drama, query);
      }),
      view,
    );
    _visibleSource = _items;
    _visibleFingerprint = fingerprint;
    _visibleCache = result;
    return result;
  }

  Widget _phoneBody(BoxConstraints constraints) {
    final layout = (
      constraints.maxWidth,
      constraints.maxHeight,
      widget.store.profileEpoch,
    );
    if (_catalogTabLayout != layout) {
      _catalogTabLayout = layout;
      _catalogTabDirty = true;
    }
    if (_catalogTab == null || _tab == 0 && _catalogTabDirty) {
      _catalogTab = widget.store.sources.isEmpty
          ? const StatusPanel(title: '暂无可用站源', message: '请联系管理员为当前用户开放站源。')
          : _catalog(selectionInBody: false);
      _catalogTabDirty = false;
    }
    final epoch = widget.store.profileEpoch;
    if (_visitedTabs.contains(1) &&
        (_rankingsTab == null || _rankingsEpoch != epoch)) {
      _rankingsEpoch = epoch;
      _rankingsTab = RankingsScreen(
        key: ValueKey('main-rankings-$epoch'),
        repository: widget.repository,
        store: widget.store,
        initialGroup: _group.id,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        _animatedTab(0, _catalogTab!),
        _animatedTab(1, _rankingsTab ?? const SizedBox.shrink()),
        _animatedTab(
          2,
          _visitedTabs.contains(2)
              ? MyScreen(
                  key: ValueKey('main-my-$epoch'),
                  repository: widget.repository,
                  store: widget.store,
                  active: _tab == 2,
                  sourceGroups: _sourceGroups,
                  currentGroup: _group,
                  onSourceSelected: (group) => unawaited(_changeGroup(group)),
                  onOpen: _openDrama,
                  onContinue: (drama) => _openDrama(drama, resume: true),
                  onDownload:
                      widget.store.canDownload &&
                          widget.repository.supportsDownloads
                      ? (drama) => _openDrama(drama, download: true)
                      : null,
                  onSort: () => unawaited(_chooseCatalogView()),
                  onRefresh: () => unawaited(_refreshCatalog()),
                  onManageSources: () => unawaited(_manageSources()),
                  onProfiles: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ProfilesScreen(store: widget.store),
                    ),
                  ),
                  onSettings: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => SettingsScreen(
                        repository: widget.repository,
                        store: widget.store,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _animatedTab(int tab, Widget child) {
    final active = (_tab <= 2 ? _tab : 2) == tab;
    return IgnorePointer(
      ignoring: !active,
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        child: AnimatedSlide(
          offset: active ? Offset.zero : const Offset(0, .018),
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          child: TickerMode(enabled: active, child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final television = AppLayout.isTelevision(context);
        final phone =
            !television &&
            (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.iOS);
        final desktop =
            constraints.maxWidth >= 840 &&
            (defaultTargetPlatform == TargetPlatform.windows ||
                defaultTargetPlatform == TargetPlatform.macOS ||
                defaultTargetPlatform == TargetPlatform.linux);
        final body = phone
            ? _phoneBody(constraints)
            : _tab == 0
            ? widget.store.sources.isEmpty
                  ? const StatusPanel(
                      title: '暂无可用站源',
                      message: '请联系管理员为当前用户开放站源。',
                    )
                  : _catalog(selectionInBody: desktop || television)
            : _tab == 3
            ? DownloadsScreen(
                repository: widget.repository,
                store: widget.store,
                embedded: true,
              )
            : SavedLibrary(
                key: ValueKey('saved-tab-$_tab'),
                repository: widget.repository,
                store: widget.store,
                history: _tab == 2,
                onOpen: _openDrama,
                onContinue: (drama) => _openDrama(drama, resume: true),
                onDownload:
                    widget.repository.supportsDownloads &&
                        widget.store.canDownload
                    ? (drama) => _openDrama(drama, download: true)
                    : null,
              );
        final scaffold = Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: !desktop && !television && !_selectionMode,
          appBar: phone && !_selectionMode
              ? null
              : _buildAppBar(
                  phone: phone,
                  television: television,
                  width: constraints.maxWidth,
                ),
          body: Stack(
            children: [
              if (phone)
                const Positioned.fill(
                  child: RepaintBoundary(child: AppGradientBackground()),
                ),
              SafeArea(
                top: false,
                bottom: desktop || television || _selectionMode,
                child: Row(
                  children: [
                    if (television) ...[
                      SizedBox(
                        width: 164,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 24, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final entry in [
                                (Icons.explore_rounded, '发现'),
                                (Icons.bookmark_rounded, '追剧'),
                                (Icons.history_rounded, '最近观看'),
                                if (widget.store.canDownload)
                                  (Icons.download_rounded, '下载'),
                              ].indexed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 14),
                                  child: RemoteButton(
                                    key: ValueKey('tv-nav-${entry.$1}'),
                                    label: entry.$2.$2,
                                    icon: entry.$2.$1,
                                    selected: _tab == entry.$1,
                                    autofocus: entry.$1 == 0,
                                    onPressed: () => _changeTab(entry.$1),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                    ] else if (desktop) ...[
                      NavigationRail(
                        selectedIndex: _tab,
                        onDestinationSelected: _changeTab,
                        labelType: NavigationRailLabelType.all,
                        groupAlignment: -.8,
                        destinations: [
                          NavigationRailDestination(
                            icon: Icon(Icons.explore_outlined),
                            selectedIcon: Icon(Icons.explore),
                            label: Text('发现'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.bookmark_border_rounded),
                            selectedIcon: Icon(Icons.bookmark_rounded),
                            label: Text('追剧'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.history_rounded),
                            label: Text('最近观看'),
                          ),
                          if (widget.store.canDownload)
                            NavigationRailDestination(
                              icon: Icon(Icons.download_outlined),
                              selectedIcon: Icon(Icons.download_rounded),
                              label: Text('下载'),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1, thickness: 1),
                    ],
                    Expanded(child: body),
                  ],
                ),
              ),
              if (!desktop && !television && !_selectionMode)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: MediaQuery.paddingOf(context).bottom + 8,
                  child: AppBottomNavigation(
                    selectedIndex: _tab <= 2 ? _tab : 2,
                    onDestinationSelected: _changeTab,
                    destinations: [
                      NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: '首页',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.leaderboard_outlined),
                        selectedIcon: Icon(Icons.leaderboard_rounded),
                        label: '榜单',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.person_outline_rounded),
                        selectedIcon: Icon(Icons.person_rounded),
                        label: '我的',
                      ),
                    ],
                  ),
                ),
            ],
          ),
          bottomNavigationBar: desktop || television
              ? null
              : _selectionMode
              ? _selectionBar()
              : null,
        );
        if (!television && !_selectionMode) return scaffold;
        return PopScope(
          canPop:
              !_selectionMode &&
              (!television || _tab == 0 && _search.text.isEmpty),
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _televisionBack();
          },
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(context).maybePop(),
              const SingleActivator(LogicalKeyboardKey.goBack): () =>
                  Navigator.of(context).maybePop(),
            },
            child: scaffold,
          ),
        );
      },
    ),
  );

  PreferredSizeWidget _buildAppBar({
    required bool phone,
    required bool television,
    required double width,
  }) => AppBar(
    backgroundColor:
        phone && _tab == 0 && Theme.of(context).brightness == Brightness.dark
        ? Colors.transparent
        : null,
    flexibleSpace:
        phone && _tab == 0 && Theme.of(context).brightness == Brightness.dark
        ? const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF173626), Color(0xFF25482C)],
              ),
            ),
          )
        : null,
    toolbarHeight: television
        ? 64
        : phone && _tab == 0
        ? 46
        : null,
    titleSpacing: 12,
    title: _selectionMode
        ? const Text('选择短剧', maxLines: 1, overflow: TextOverflow.ellipsis)
        : _tab == 0
        ? PopupMenuButton<SourceGroup>(
            key: const ValueKey('source-switch'),
            tooltip: '切换站源',
            enabled: _sourceGroups.length > 1,
            onSelected: (group) => unawaited(_changeGroup(group)),
            itemBuilder: (_) => [
              for (final group in _sourceGroups)
                PopupMenuItem(
                  value: group,
                  child: Row(
                    children: [
                      Expanded(child: Text(group.name)),
                      if (group.id == _group.id)
                        const Icon(Icons.check_rounded, size: 20),
                    ],
                  ),
                ),
            ],
            child: SizedBox(
              height: 48,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _group.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (_sourceGroups.length > 1)
                    const Icon(Icons.expand_more_rounded),
                ],
              ),
            ),
          )
        : const Text(appName),
    actions: [
      if (_selectionMode) ...[
        TextButton(
          key: const ValueKey('clear-catalog-selection'),
          onPressed: _selectedDramas.isEmpty
              ? null
              : () => setState(_selectedDramas.clear),
          child: const Text('清空'),
        ),
        TextButton(
          key: const ValueKey('cancel-catalog-selection'),
          onPressed: _cancelSelection,
          child: const Text('取消'),
        ),
      ] else ...[
        if (_tab == 1)
          IconButton(
            key: const ValueKey('follow-lan-sync'),
            tooltip: '追剧同步',
            onPressed: () => openLanSync(context),
            icon: const Icon(Icons.sync_rounded),
          ),
        if (_tab == 0) ...[
          if (!_showRecommendations)
            IconButton(
              tooltip: '排序与筛选 · ${widget.store.catalogView.sort.label}',
              onPressed: _chooseCatalogView,
              color:
                  widget.store.catalogView.sort != CatalogSort.source ||
                      widget.store.catalogView.release.isNotEmpty
                  ? Theme.of(context).colorScheme.primary
                  : null,
              icon: const Icon(Icons.sort_rounded),
            ),
          IconButton(
            key: const ValueKey('open-rankings'),
            tooltip: '榜单',
            onPressed: widget.store.sources.isEmpty ? null : _openRankings,
            icon: const Icon(Icons.leaderboard_outlined),
          ),
          if (!_showRecommendations &&
              widget.store.canDownload &&
              widget.repository.supportsDownloads)
            IconButton(
              key: const ValueKey('select-catalog-dramas'),
              tooltip: '多选下载',
              onPressed: () => setState(() => _selectionMode = true),
              icon: const Icon(Icons.checklist_rounded),
            ),
          IconButton(
            key: const ValueKey('toggle-search'),
            tooltip: phone
                ? (_searchVisible ? '收起最近搜索' : '最近搜索')
                : (_searchVisible ? '收起搜索' : '搜索'),
            icon: Icon(
              phone
                  ? Icons.history_rounded
                  : _searchVisible
                  ? Icons.search_off_rounded
                  : Icons.search_rounded,
            ),
            onPressed: _toggleSearch,
          ),
        ],
        if (_tab == 0 && !_showRecommendations && width >= 400)
          RefreshAction(
            key: const ValueKey('catalog-refresh'),
            loading:
                _loading ||
                _loadingMore ||
                _categoriesLoading ||
                _group.sources.any((source) => _updater.busy(source.id)),
            tooltip: '更新剧库',
            onPressed: widget.store.sources.isEmpty ? null : _refreshCatalog,
          ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (value) {
            if (value == 'update') {
              _refreshCatalog();
            } else if (value == 'sources') {
              _manageSources();
            } else if (value == 'settings') {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    repository: widget.repository,
                    store: widget.store,
                  ),
                ),
              );
            } else if (value == 'users') {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ProfilesScreen(store: widget.store),
                ),
              );
            } else if (value == 'display') {
              _chooseDisplayMode();
            } else if (value == 'about') {
              showAboutDialog(
                context: context,
                applicationName: appName,
                applicationVersion: AppLayout.versionOf(context),
                applicationIcon: const Icon(
                  Icons.play_circle_filled_rounded,
                  size: 48,
                  color: Color(0xFFFF765F),
                ),
                children: [const Text('独立运行，打开即可浏览和播放。观看记录与追剧收藏保存在当前设备。')],
              );
            }
          },
          itemBuilder: (_) => [
            if (_tab == 0 && !_showRecommendations && width < 400)
              PopupMenuItem(
                value: 'update',
                enabled:
                    widget.store.sources.isNotEmpty &&
                    !_group.sources.any((source) => _updater.busy(source.id)),
                child: const Text('更新剧库'),
              ),
            if (widget.repository.supportsSourceManagement)
              const PopupMenuItem(value: 'sources', child: Text('站源管理')),
            const PopupMenuItem(value: 'users', child: Text('用户管理')),
            const PopupMenuItem(value: 'settings', child: Text('设置与备份')),
            const PopupMenuItem(value: 'display', child: Text('界面模式')),
            const PopupMenuItem(value: 'about', child: Text('关于$appName')),
          ],
        ),
      ],
      const SizedBox(width: 8),
    ],
  );

  Widget _catalog({required bool selectionInBody}) {
    final items = _visible;
    final television = AppLayout.isTelevision(context);
    final mobileDiscovery =
        !television &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final displayedItems = television || mobileDiscovery
        ? items
        : items.take(_renderLimit).toList(growable: false);
    final hasHiddenItems = displayedItems.length < items.length;
    final showTrending =
        mobileDiscovery &&
        !_selectionMode &&
        !_showRecommendations &&
        _search.text.trim().isEmpty &&
        displayedItems.isNotEmpty;
    final sectionTitle = showTrending
        ? '更多短剧'
        : _search.text.trim().isNotEmpty
        ? '搜索结果'
        : _displayCategory.isEmpty
        ? '发现好剧'
        : _displayCategories
                  .where((category) => category.id == _displayCategory)
                  .firstOrNull
                  ?.name ??
              '发现好剧';
    final header = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if ((_searchVisible || mobileDiscovery) && !television)
          ColoredBox(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Theme(
                      data: Theme.of(context).copyWith(
                        inputDecorationTheme: Theme.of(context)
                            .inputDecorationTheme
                            .copyWith(
                              fillColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHigh,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(28),
                                borderSide: BorderSide.none,
                              ),
                            ),
                      ),
                      child: SearchInput(
                        key: ValueKey('search-${_group.id}'),
                        controller: _search,
                        autofocus: _searchVisible,
                        hint: _searchHint,
                        suggestions: _searchSuggestions
                            ? widget.repository.suggestions
                            : null,
                        onChanged: _searchChanged,
                        onCancel: () =>
                            unawaited(widget.repository.cancelSuggestions()),
                        onSearch: _submitSearch,
                      ),
                    ),
                  ),
                  if (mobileDiscovery) ...[
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      key: const ValueKey('open-watch-history'),
                      tooltip: '历史记录',
                      onPressed: _openWatchHistory,
                      icon: const Icon(Icons.history_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (_searchVisible &&
            _search.text.trim().isEmpty &&
            widget.store.recentSearches.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final query in widget.store.recentSearches)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              avatar: const Icon(
                                Icons.history_rounded,
                                size: 16,
                              ),
                              label: Text(query),
                              onPressed: () => _submitSearch(query),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '清空最近搜索',
                  onPressed: () =>
                      saveUserChange(context, widget.store.clearRecentSearches),
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                ),
              ],
            ),
          ),
        ValueListenableBuilder<String?>(
          valueListenable: _categorySwipeHighlightNotifier,
          builder: (context, highlighted, _) => CatalogFilters(
            key: ValueKey('filters-${_group.id}'),
            categories: _displayCategories,
            category: mobileDiscovery
                ? highlighted ?? _displayCategory
                : _displayCategory,
            error: _categoriesError,
            onCategory: _changeCategory,
            onRetry: () => _loadCategories(force: true),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_supportsVipFilter)
                  IconButton(
                    tooltip: widget.store.hideVip ? 'VIP：隐藏' : 'VIP：显示',
                    onPressed: () => saveUserChange(
                      context,
                      () => widget.store.setHideVip(!widget.store.hideVip),
                    ),
                    icon: VipIcon(hidden: widget.store.hideVip),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
    if (mobileDiscovery && !_showRecommendations) {
      return _mobileCatalog(
        header: header,
        items: items,
        displayedItems: displayedItems,
        showTrending: showTrending,
        sectionTitle: sectionTitle,
        hasHiddenItems: hasHiddenItems,
      );
    }
    return Column(
      children: [
        mobileDiscovery
            ? SafeArea(top: true, bottom: false, child: header)
            : header,
        if (_showRecommendations)
          Expanded(
            child: mobileDiscovery
                ? LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      onHorizontalDragStart: (_) => _startMobileCategorySwipe(),
                      onHorizontalDragUpdate: (details) =>
                          _updateMobileCategorySwipe(
                            details,
                            constraints.maxWidth,
                          ),
                      onHorizontalDragEnd: (details) => _endMobileCategorySwipe(
                        details,
                        constraints.maxWidth,
                      ),
                      onHorizontalDragCancel: () => _endMobileCategorySwipe(
                        DragEndDetails(),
                        constraints.maxWidth,
                      ),
                      child: _mobileCategorySwipeFrame(
                        RecommendationsScreen(
                          repository: widget.repository,
                          store: widget.store,
                          embedded: true,
                        ),
                        constraints.maxWidth,
                      ),
                    ),
                  )
                : GestureDetector(
                    onHorizontalDragStart: (_) => _categoryDragDistance = 0,
                    onHorizontalDragUpdate: (details) =>
                        _categoryDragDistance += details.primaryDelta ?? 0,
                    onHorizontalDragEnd: television ? null : _swipeCategory,
                    child: _categoryTransition(
                      RecommendationsScreen(
                        repository: widget.repository,
                        store: widget.store,
                        embedded: true,
                      ),
                    ),
                  ),
          )
        else ...[
          if (_loading && _items.isNotEmpty)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: television ? null : _swipeCategory,
              child: _loading && _items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 18),
                          Text('正在加载剧集'),
                        ],
                      ),
                    )
                  : _items.isEmpty && _error != null
                  ? StatusPanel(
                      title: '暂时无法加载',
                      message: _error!,
                      onRetry: () => _load(force: true),
                      secondaryAction:
                          widget.repository.supportsSourceManagement
                          ? TextButton(
                              onPressed: _manageSources,
                              child: const Text('站源诊断'),
                            )
                          : null,
                      icon: Icons.wifi_off_rounded,
                    )
                  : items.isEmpty
                  ? StatusPanel(
                      title: '没有找到匹配的短剧',
                      message: _hasMore
                          ? '继续下滑会自动尝试下一页。'
                          : _hideVip
                          ? '可以换个搜索词，或显示 VIP 内容。'
                          : widget.store.sources.length > 1
                          ? '可以换个搜索词或切换站源。'
                          : '可以换个搜索词，或刷新后重试。',
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (television) {
                          return _televisionGrid(
                            items,
                            constraints.maxWidth,
                            key:
                                'catalog-${_group.id}-$_category-$_submittedQuery',
                            controller: _scroll,
                            footer: Padding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : _hasMore
                                    ? RemoteButton(
                                        label: '加载更多',
                                        icon: Icons.expand_more,
                                        onPressed: () => _load(more: true),
                                      )
                                    : const Text('已经看到这里的全部剧集'),
                              ),
                            ),
                          );
                        }
                        final padding = constraints.maxWidth < 600
                            ? 16.0
                            : 24.0;
                        return RefreshIndicator(
                          onRefresh: _refreshCatalog,
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _onCatalogScrollNotification,
                            child: CustomScrollView(
                              controller: _scroll,
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                if (showTrending)
                                  SliverToBoxAdapter(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            padding,
                                            16,
                                            padding,
                                            12,
                                          ),
                                          child: Text(
                                            '近期热播',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        TrendingDramaRow(
                                          dramas: displayedItems
                                              .take(8)
                                              .toList(growable: false),
                                          repository: widget.repository,
                                          onOpen: _openDrama,
                                        ),
                                      ],
                                    ),
                                  ),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      padding,
                                      20,
                                      padding,
                                      16,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            sectionTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                  letterSpacing: -.3,
                                                ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          '已加载 ${items.length} 部',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                    padding,
                                    0,
                                    padding,
                                    16,
                                  ),
                                  sliver: SliverGrid(
                                    gridDelegate: dramaGridDelegate(
                                      context,
                                      constraints.maxWidth - 2 * padding,
                                    ),
                                    delegate: SliverChildBuilderDelegate(
                                      (_, index) =>
                                          _catalogTile(displayedItems[index]),
                                      childCount: displayedItems.length,
                                    ),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.only(bottom: 24),
                                    child: Center(
                                      child: _loadingMore
                                          ? const CircularProgressIndicator()
                                          : hasHiddenItems || _hasMore
                                          ? const Text('继续下滑加载更多')
                                          : Text(
                                              '已经看到这里的全部剧集',
                                              style: TextStyle(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                                fontSize: 12,
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          if (_selectionMode && selectionInBody)
            _selectionBar(safeBottom: false),
        ],
      ],
    );
  }

  Widget _categoryTransition(Widget content) {
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return content;
    }
    return AnimatedBuilder(
      animation: _categoryTransitionController,
      child: content,
      builder: (context, child) => FractionalTranslation(
        translation: Offset(
          (1 -
                  Curves.easeOutCubic.transform(
                    _categoryTransitionController.value,
                  )) *
              _categoryTransitionDirection *
              .08,
          0,
        ),
        child: child,
      ),
    );
  }

  Widget _mobileCatalog({
    required Widget header,
    required List<Drama> items,
    required List<Drama> displayedItems,
    required bool showTrending,
    required String sectionTitle,
    required bool hasHiddenItems,
  }) {
    Widget? status;
    if (_loading && _items.isEmpty) {
      status = const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 18),
            Text('正在加载剧集'),
          ],
        ),
      );
    } else if (_items.isEmpty && _error != null) {
      status = StatusPanel(
        title: '暂时无法加载',
        message: _error!,
        onRetry: () => _load(force: true),
        secondaryAction: widget.repository.supportsSourceManagement
            ? TextButton(onPressed: _manageSources, child: const Text('站源诊断'))
            : null,
        icon: Icons.wifi_off_rounded,
      );
    } else if (items.isEmpty) {
      status = StatusPanel(
        title: '没有找到匹配的短剧',
        message: _hasMore
            ? '继续下滑会自动尝试下一页。'
            : _hideVip
            ? '可以换个搜索词，或显示 VIP 内容。'
            : widget.store.sources.length > 1
            ? '可以换个搜索词或切换站源。'
            : '可以换个搜索词，或刷新后重试。',
      );
    }
    final width = MediaQuery.sizeOf(context).width;
    final padding = width < 600 ? 16.0 : 24.0;
    return Column(
      children: [
        SafeArea(top: true, bottom: false, child: header),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => GestureDetector(
              onHorizontalDragStart: (_) => _startMobileCategorySwipe(),
              onHorizontalDragUpdate: (details) =>
                  _updateMobileCategorySwipe(details, constraints.maxWidth),
              onHorizontalDragEnd: (details) =>
                  _endMobileCategorySwipe(details, constraints.maxWidth),
              onHorizontalDragCancel: () => _endMobileCategorySwipe(
                DragEndDetails(),
                constraints.maxWidth,
              ),
              child: _mobileCategorySwipeFrame(
                RefreshIndicator(
                  onRefresh: _refreshCatalog,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onCatalogScrollNotification,
                    child: CustomScrollView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      cacheExtent: 500,
                      slivers: [
                        if (_loading && _items.isNotEmpty)
                          const SliverToBoxAdapter(
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (status != null)
                          SliverFillRemaining(
                            hasScrollBody: false,
                            child: status,
                          )
                        else ...[
                          if (showTrending)
                            SliverToBoxAdapter(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      padding,
                                      16,
                                      padding,
                                      12,
                                    ),
                                    child: Text(
                                      '近期热播',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  TrendingDramaRow(
                                    dramas: displayedItems
                                        .take(8)
                                        .toList(growable: false),
                                    repository: widget.repository,
                                    onOpen: _openDrama,
                                  ),
                                ],
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                padding,
                                20,
                                padding,
                                16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      sectionTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    '已加载 ${items.length} 部',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              padding,
                              0,
                              padding,
                              16,
                            ),
                            sliver: SliverGrid(
                              gridDelegate: dramaGridDelegate(
                                context,
                                width - 2 * padding,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (_, index) =>
                                    _catalogTile(displayedItems[index]),
                                childCount: displayedItems.length,
                                addAutomaticKeepAlives: false,
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 24),
                              child: Center(
                                child: _loadingMore
                                    ? const CircularProgressIndicator()
                                    : hasHiddenItems || _hasMore
                                    ? const Text('继续下滑加载更多')
                                    : Text(
                                        '已经看到这里的全部剧集',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          SliverToBoxAdapter(
                            child: SizedBox(
                              height:
                                  MediaQuery.paddingOf(context).bottom + 112,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                constraints.maxWidth,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _selectionBar({bool safeBottom = true}) {
    final theme = Theme.of(context);
    final count = _selectedDramas.length;
    return Material(
      color: theme.colorScheme.surface,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: safeBottom,
          minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final summary = Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      count == 0 ? '点选要下载的短剧' : '已选 $count 部',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      count == 0
                          ? '最多 ${BatchDownloads.maxDramas} 部'
                          : '下一步选择分集和画质',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
              final next = FilledButton(
                key: const ValueKey('download-selected-dramas'),
                onPressed: count == 0 ? null : _downloadSelected,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(96, 48),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                child: const Text('下一步'),
              );
              if (constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(14) > 21) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [summary, const SizedBox(height: 12), next],
                );
              }
              return Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 16),
                  next,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _televisionGrid(
    List<Drama> items,
    double width, {
    required String key,
    ScrollController? controller,
    Widget? footer,
  }) {
    final columns = ((width - 36) / 150).floor().clamp(1, 8);
    final tileWidth = (width - 36 - (columns - 1) * 14) / columns;
    return RemoteGrid(
      key: ValueKey('tv-grid-$key'),
      itemKeys: items.map((item) => item.id).toList(),
      columns: columns,
      itemExtent: DramaTile.extentFor(context, tileWidth - 14) + 14,
      controller: controller,
      footer: footer,
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 18),
      itemBuilder: (_, index, node, onFocus) =>
          _catalogTile(items[index], focusNode: node, onFocus: onFocus),
    );
  }
}
