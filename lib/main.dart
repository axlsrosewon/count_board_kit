import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ad_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  unawaited(MobileAds.instance.initialize());
  runApp(const CountBoardApp());
}

class CountBoardApp extends StatelessWidget {
  const CountBoardApp({super.key, this.showAds = true});

  final bool showAds;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Count Board Kit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff246b60),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xfff6f4ee),
        useMaterial3: true,
      ),
      home: CountBoardHome(showAds: showAds),
    );
  }
}

class CountBoardHome extends StatefulWidget {
  const CountBoardHome({super.key, required this.showAds});

  final bool showAds;

  @override
  State<CountBoardHome> createState() => _CountBoardHomeState();
}

class _CountBoardHomeState extends State<CountBoardHome> {
  static const _storageKey = 'count_board_items_v1';
  final _numberFormat = NumberFormat.decimalPattern();

  BannerAd? _bannerAd;
  bool _bannerLoaded = false;
  bool _loading = true;
  List<CounterItem> _items = [];

  int get _total => _items.fold(0, (sum, item) => sum + item.count);

  int get _completedGoals {
    return _items
        .where((item) => item.goal > 0 && item.count >= item.goal)
        .length;
  }

  @override
  void initState() {
    super.initState();
    _loadItems();
    if (widget.showAds) _loadBannerAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey);
    final loaded = stored
        ?.map((value) => CounterItem.fromJson(jsonDecode(value)))
        .whereType<CounterItem>()
        .toList();
    setState(() {
      _items = loaded == null || loaded.isEmpty
          ? CounterItem.starterItems()
          : loaded;
      _loading = false;
    });
  }

  Future<void> _saveItems() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      _items.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  void _loadBannerAd() {
    final ad = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _bannerLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _bannerLoaded = false);
        },
      ),
    );
    _bannerAd = ad;
    ad.load();
  }

  Future<void> _changeCount(CounterItem item, int delta) async {
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index == -1) return;
    final next = (_items[index].count + delta).clamp(0, 999999);
    setState(() {
      _items[index] = _items[index].copyWith(
        count: next,
        updatedAt: DateTime.now(),
      );
    });
    await _saveItems();
    HapticFeedback.selectionClick();
  }

  Future<void> _resetItem(CounterItem item) async {
    final index = _items.indexWhere((candidate) => candidate.id == item.id);
    if (index == -1) return;
    setState(() {
      _items[index] = _items[index].copyWith(
        count: 0,
        updatedAt: DateTime.now(),
      );
    });
    await _saveItems();
  }

  Future<void> _deleteItem(CounterItem item) async {
    setState(() => _items.removeWhere((candidate) => candidate.id == item.id));
    await _saveItems();
  }

  Future<void> _upsertItem({CounterItem? existing}) async {
    final result = await showModalBottomSheet<CounterItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => CounterEditor(existing: existing),
    );
    if (result == null) return;
    setState(() {
      final index = _items.indexWhere((item) => item.id == result.id);
      if (index == -1) {
        _items.insert(0, result);
      } else {
        _items[index] = result;
      }
    });
    await _saveItems();
  }

  Future<void> _shareBoard() async {
    final lines = [
      'Count Board Kit summary',
      'Total: $_total',
      'Updated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
      '',
      ..._items.map((item) {
        final goal = item.goal > 0 ? ' / ${item.goal}' : '';
        return '${item.name}: ${item.count}$goal';
      }),
    ];
    await SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _Header(
                      total: _numberFormat.format(_total),
                      itemCount: _items.length,
                      completedGoals: _completedGoals,
                      onAdd: () => _upsertItem(),
                      onShare: _items.isEmpty ? null : _shareBoard,
                    ),
                  ),
                  if (_loading)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyState(onAdd: () => _upsertItem()),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      sliver: SliverList.separated(
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return CounterCard(
                            item: item,
                            countLabel: _numberFormat.format(item.count),
                            onIncrement: () => _changeCount(item, 1),
                            onDecrement: () => _changeCount(item, -1),
                            onAddFive: () => _changeCount(item, 5),
                            onEdit: () => _upsertItem(existing: item),
                            onReset: () => _resetItem(item),
                            onDelete: () => _deleteItem(item),
                          );
                        },
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemCount: _items.length,
                      ),
                    ),
                ],
              ),
            ),
            if (_bannerLoaded && _bannerAd != null)
              SizedBox(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                child: AdWidget(ad: _bannerAd!),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.itemCount,
    required this.completedGoals,
    required this.onAdd,
    required this.onShare,
  });

  final String total;
  final int itemCount;
  final int completedGoals;
  final VoidCallback onAdd;
  final VoidCallback? onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Count Board Kit',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Share board',
                onPressed: onShare,
                icon: const Icon(Icons.ios_share_rounded),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'Add counter',
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xff193f3a),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total counted',
                  style: TextStyle(
                    color: Color(0xffb8ccc7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  total,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetricChip(label: '$itemCount counters'),
                    _MetricChip(label: '$completedGoals goals met'),
                    const _MetricChip(label: 'Saved locally'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xffd7ece6),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class CounterCard extends StatelessWidget {
  const CounterCard({
    super.key,
    required this.item,
    required this.countLabel,
    required this.onIncrement,
    required this.onDecrement,
    required this.onAddFive,
    required this.onEdit,
    required this.onReset,
    required this.onDelete,
  });

  final CounterItem item;
  final String countLabel;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onAddFive;
  final VoidCallback onEdit;
  final VoidCallback onReset;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final progress = item.goal <= 0
        ? null
        : (item.count / item.goal).clamp(0.0, 1.0);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 46,
                  decoration: BoxDecoration(
                    color: item.color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (item.note.isNotEmpty)
                        Text(
                          item.note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Counter options',
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'reset') onReset();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'reset', child: Text('Reset')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    countLabel,
                    style: const TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _CountButton(
                  tooltip: 'Subtract one',
                  icon: Icons.remove_rounded,
                  onPressed: item.count == 0 ? null : onDecrement,
                ),
                const SizedBox(width: 8),
                _CountButton(
                  tooltip: 'Add one',
                  icon: Icons.add_rounded,
                  onPressed: onIncrement,
                  filled: true,
                ),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: onAddFive, child: const Text('+5')),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                color: item.color,
                backgroundColor: item.color.withAlpha(45),
              ),
              const SizedBox(height: 6),
              Text(
                '${item.count} of ${item.goal} target',
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountButton extends StatelessWidget {
  const _CountButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Icon(icon);
    return SizedBox.square(
      dimension: 48,
      child: filled
          ? IconButton.filled(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: child,
            )
          : IconButton.outlined(
              tooltip: tooltip,
              onPressed: onPressed,
              icon: child,
            ),
    );
  }
}

class CounterEditor extends StatefulWidget {
  const CounterEditor({super.key, this.existing});

  final CounterItem? existing;

  @override
  State<CounterEditor> createState() => _CounterEditorState();
}

class _CounterEditorState extends State<CounterEditor> {
  late final TextEditingController _nameController;
  late final TextEditingController _noteController;
  late final TextEditingController _goalController;
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _nameController = TextEditingController(text: item?.name ?? '');
    _noteController = TextEditingController(text: item?.note ?? '');
    _goalController = TextEditingController(
      text: item == null || item.goal == 0 ? '' : '${item.goal}',
    );
    _selectedColor = item?.color ?? CounterItem.palette.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    final existing = widget.existing;
    final goal = int.tryParse(_goalController.text.trim()) ?? 0;
    final item = CounterItem(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      note: _noteController.text.trim(),
      count: existing?.count ?? 0,
      goal: goal.clamp(0, 999999),
      colorValue: _selectedColor.toARGB32(),
      updatedAt: DateTime.now(),
    );
    Navigator.of(context).pop(item);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? 'New counter' : 'Edit counter',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _noteController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _goalController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Goal'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: CounterItem.palette.map((color) {
              final selected = color.toARGB32() == _selectedColor.toARGB32();
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => _selectedColor = color),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? Colors.black : Colors.white,
                      width: selected ? 3 : 2,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save counter'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.checklist_rtl_rounded,
              size: 64,
              color: Color(0xff246b60),
            ),
            const SizedBox(height: 12),
            const Text(
              'No counters yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Create boards for inventory, attendance, tasks, stock checks, or event counts.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add counter'),
            ),
          ],
        ),
      ),
    );
  }
}

class CounterItem {
  const CounterItem({
    required this.id,
    required this.name,
    required this.note,
    required this.count,
    required this.goal,
    required this.colorValue,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String note;
  final int count;
  final int goal;
  final int colorValue;
  final DateTime updatedAt;

  Color get color => Color(colorValue);

  CounterItem copyWith({
    String? name,
    String? note,
    int? count,
    int? goal,
    int? colorValue,
    DateTime? updatedAt,
  }) {
    return CounterItem(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      count: count ?? this.count,
      goal: goal ?? this.goal,
      colorValue: colorValue ?? this.colorValue,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'note': note,
      'count': count,
      'goal': goal,
      'colorValue': colorValue,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static CounterItem? fromJson(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return CounterItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Counter',
      note: json['note'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      goal: json['goal'] as int? ?? 0,
      colorValue: json['colorValue'] as int? ?? palette.first.toARGB32(),
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static List<CounterItem> starterItems() {
    final now = DateTime.now();
    return [
      CounterItem(
        id: 'starter-stock',
        name: 'Stock check',
        note: 'Tap as each item is verified',
        count: 12,
        goal: 40,
        colorValue: palette[0].toARGB32(),
        updatedAt: now,
      ),
      CounterItem(
        id: 'starter-attendance',
        name: 'Attendance',
        note: 'Door count for the current session',
        count: 8,
        goal: 0,
        colorValue: palette[2].toARGB32(),
        updatedAt: now,
      ),
      CounterItem(
        id: 'starter-packed',
        name: 'Packed boxes',
        note: 'Shipping batch',
        count: 5,
        goal: 24,
        colorValue: palette[4].toARGB32(),
        updatedAt: now,
      ),
    ];
  }

  static const palette = [
    Color(0xff246b60),
    Color(0xffbf5b45),
    Color(0xff385f96),
    Color(0xff8057a5),
    Color(0xff9d7a1f),
    Color(0xff3b7a33),
  ];
}
