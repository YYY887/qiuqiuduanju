import 'package:flutter/material.dart';

import '../app/app_layout.dart';
import '../core/core_bridge.dart';
import '../core/models.dart';
import '../downloads/downloads_screen.dart';
import '../library/local_store.dart';
import '../library/saved_library.dart';

class MyScreen extends StatefulWidget {
  const MyScreen({
    super.key,
    required this.repository,
    required this.store,
    required this.active,
    required this.sourceGroups,
    required this.currentGroup,
    required this.onSourceSelected,
    required this.onOpen,
    required this.onContinue,
    required this.onDownload,
    required this.onSort,
    required this.onRefresh,
    required this.onManageSources,
    required this.onProfiles,
    required this.onSettings,
  });

  final AppRepository repository;
  final LocalStore store;
  final bool active;
  final List<SourceGroup> sourceGroups;
  final SourceGroup currentGroup;
  final ValueChanged<SourceGroup> onSourceSelected;
  final ValueChanged<Drama> onOpen;
  final ValueChanged<Drama> onContinue;
  final ValueChanged<Drama>? onDownload;
  final VoidCallback onSort;
  final VoidCallback onRefresh;
  final VoidCallback onManageSources;
  final VoidCallback onProfiles;
  final VoidCallback onSettings;

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  int _section = 0;
  final _visited = <int>{0};
  final _savedPages = <int, Widget>{};
  int? _savedEpoch;

  void _openSection(int section) {
    if (_section == section) return;
    setState(() {
      _section = section;
      _visited.add(section);
    });
  }

  Widget _savedPage(int section) {
    final epoch = widget.store.profileEpoch;
    if (_savedEpoch != epoch) {
      _savedEpoch = epoch;
      _savedPages.clear();
    }
    return _savedPages.putIfAbsent(
      section,
      () => SavedLibrary(
        key: ValueKey('my-saved-$section-$epoch'),
        repository: widget.repository,
        store: widget.store,
        history: section == 2,
        onOpen: widget.onOpen,
        onContinue: widget.onContinue,
        onDownload: widget.onDownload,
      ),
    );
  }

  Future<void> _selectSource() async {
    final selected = await showModalBottomSheet<SourceGroup>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final group in widget.sourceGroups)
              ListTile(
                title: Text(group.name),
                trailing: group.id == widget.currentGroup.id
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.pop(context, group),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) widget.onSourceSelected(selected);
  }

  Widget _entry(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: colors.surfaceContainer.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          minTileHeight: 66,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          leading: Icon(icon, color: colors.primary),
          title: Text(title),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    );
  }

  Widget _overview() {
    final colors = Theme.of(context).colorScheme;
    return CustomScrollView(
      key: const PageStorageKey('my-overview'),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            20,
            MediaQuery.paddingOf(context).top + 22,
            20,
            MediaQuery.paddingOf(context).bottom + 116,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Row(
                children: [
                  CircleAvatar(
                    radius: 29,
                    backgroundColor: colors.primaryContainer,
                    child: Icon(
                      Icons.person_rounded,
                      color: colors.onPrimaryContainer,
                      size: 30,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.store.profile.name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        Text('秋秋短剧 · ${widget.currentGroup.name}'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text('我的内容', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _entry(
                Icons.bookmark_rounded,
                '收藏与追剧',
                '${widget.store.favorites.length} 部已收藏',
                () => _openSection(1),
              ),
              _entry(
                Icons.history_rounded,
                '最近观看',
                '${widget.store.history.length} 条观看记录',
                () => _openSection(2),
              ),
              if (widget.store.canDownload &&
                  widget.repository.supportsDownloads)
                _entry(
                  Icons.download_rounded,
                  '下载管理',
                  '查看下载任务与本地视频',
                  () => _openSection(3),
                ),
              const SizedBox(height: 18),
              Text('内容与设置', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _entry(
                Icons.hub_outlined,
                '切换站源',
                widget.currentGroup.name,
                _selectSource,
              ),
              _entry(Icons.tune_rounded, '排序与筛选', '调整首页显示顺序', widget.onSort),
              _entry(
                Icons.refresh_rounded,
                '更新剧库',
                '手动获取最新内容',
                widget.onRefresh,
              ),
              if (widget.repository.supportsSourceManagement)
                _entry(
                  Icons.source_outlined,
                  '站源管理',
                  '检查连接并管理站源',
                  widget.onManageSources,
                ),
              _entry(
                Icons.people_outline_rounded,
                '用户管理',
                '切换或管理本地用户',
                widget.onProfiles,
              ),
              _entry(
                Icons.settings_outlined,
                '设置与备份',
                '外观、播放和数据设置',
                widget.onSettings,
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '秋秋短剧 ${AppLayout.versionOf(context)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['我的', '收藏与追剧', '最近观看', '下载管理'];
    return PopScope(
      canPop: !widget.active || _section == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.active && _section != 0) _openSection(0);
      },
      child: Column(
        children: [
          if (_section != 0)
            Padding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => _openSection(0),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  Text(
                    titles[_section],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _section,
              children: [
                _overview(),
                _visited.contains(1) ? _savedPage(1) : const SizedBox.shrink(),
                _visited.contains(2) ? _savedPage(2) : const SizedBox.shrink(),
                _visited.contains(3)
                    ? DownloadsScreen(
                        key: ValueKey(
                          'my-downloads-${widget.store.profileEpoch}',
                        ),
                        repository: widget.repository,
                        store: widget.store,
                        embedded: true,
                        active: widget.active && _section == 3,
                      )
                    : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
