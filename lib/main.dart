import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:confetti/confetti.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';

void main() {
  runApp(const IgniteListApp());
}

class IgniteListApp extends StatelessWidget {
  const IgniteListApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IgniteList',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.orange,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const TodoListPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TodoItem {
  final String id;
  String text;
  bool isCompleted;
  DateTime createdAt;
  int consecutiveDays; // 连续完成天数
  DateTime? lastCompletedDate; // 上次完成日期
  int totalCompletedDays; // 累计已完成天数

  TodoItem({
    required this.id,
    required this.text,
    this.isCompleted = false,
    required this.createdAt,
    this.consecutiveDays = 0,
    this.lastCompletedDate,
    this.totalCompletedDays = 0,
  });

  // 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
      'consecutiveDays': consecutiveDays,
      'lastCompletedDate': lastCompletedDate?.toIso8601String(),
      'totalCompletedDays': totalCompletedDays,
    };
  }

  // 从 JSON 创建
  factory TodoItem.fromJson(Map<String, dynamic> json) {
    return TodoItem(
      id: json['id'] as String,
      text: json['text'] as String,
      isCompleted: json['isCompleted'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      consecutiveDays: json['consecutiveDays'] as int? ?? 0,
      lastCompletedDate: json['lastCompletedDate'] != null
          ? DateTime.parse(json['lastCompletedDate'] as String)
          : null,
      totalCompletedDays: json['totalCompletedDays'] as int? ?? 0,
    );
  }
}

class TodoListPage extends StatefulWidget {
  const TodoListPage({super.key});

  @override
  State<TodoListPage> createState() => _TodoListPageState();
}

class _TodoListPageState extends State<TodoListPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final List<TodoItem> _todos = [];
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _editTextController = TextEditingController();
  final FocusNode _editFocusNode = FocusNode();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _editingTodoId; // 正在编辑的待办项 ID
  bool _showCelebration = false;
  late ConfettiController _confettiController;
  late AnimationController _celebrationController;
  late AnimationController _scaleController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _bounceAnimation;
  String? _completedTodoId;
  int _completedConsecutiveDays = 0; // 当前完成的连续天数
  Timer? _dailyResetTimer;
  String? _selectedVoiceFolder; // 当前选择的语音文件夹
  final List<String> _voiceFolders = ['aqua', 'mea', '冬雪莲', '松冈修造']; // 可用的语音文件夹列表

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _scaleController,
        curve: Curves.elasticOut,
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeIn,
      ),
    );

    _bounceAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 0.4,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 0.6,
      ),
    ]).animate(_scaleController);

    // 注册应用生命周期监听
    WidgetsBinding.instance.addObserver(this);

    // 加载保存的待办事项，并在需要时重置
    _loadTodos().then((_) => _checkAndResetDaily());

    // 加载保存的语音选择
    _loadVoiceSelection();

    // 启动定时器，每分钟检查一次日期变化
    _startDailyResetTimer();
  }

  @override
  void dispose() {
    // 取消应用生命周期监听
    WidgetsBinding.instance.removeObserver(this);
    // 停止定时器
    _stopDailyResetTimer();
    _textController.dispose();
    _editTextController.dispose();
    _editFocusNode.dispose();
    _audioPlayer.dispose();
    _confettiController.dispose();
    _celebrationController.dispose();
    _scaleController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  // 应用生命周期变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // 应用从后台恢复时，立即检查日期变化
      _checkAndResetDaily();
      // 重新启动定时器
      _startDailyResetTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // 应用进入后台时，停止定时器以节省资源
      _stopDailyResetTimer();
    }
  }

  // 启动每日重置定时器
  void _startDailyResetTimer() {
    _stopDailyResetTimer(); // 先停止旧的定时器
    // 每分钟检查一次日期变化
    _dailyResetTimer = Timer.periodic(
      const Duration(minutes: 1),
      (timer) {
        _checkAndResetDaily();
      },
    );
  }

  // 停止每日重置定时器
  void _stopDailyResetTimer() {
    _dailyResetTimer?.cancel();
    _dailyResetTimer = null;
  }

  void _addTodo() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _todos.insert(0, TodoItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        createdAt: DateTime.now(),
      ));
    });
    _textController.clear();
    _saveTodos();
  }

  Future<void> _completeTodo(String id) async {
    final todoIndex = _todos.indexWhere((todo) => todo.id == id);
    if (todoIndex == -1) return;

    final todo = _todos[todoIndex];
    final now = DateTime.now();
    final today = _getLogicalDate(now);

    // 如果今天已经完成过，不重复处理
    if (todo.isCompleted && todo.lastCompletedDate != null) {
      // 使用逻辑日期来判断上次完成的日期
      final lastLogicalDate = _getLogicalDateFromCompletion(todo.lastCompletedDate!);
      if (lastLogicalDate.year == today.year &&
          lastLogicalDate.month == today.month &&
          lastLogicalDate.day == today.day) {
        // 今天已经完成过，不重复处理
        return;
      }
    }

    // 计算新的连续完成天数
    int newConsecutiveDays = 1;
    if (todo.lastCompletedDate != null) {
      // 使用逻辑日期来判断上次完成的日期
      final lastLogicalDate = _getLogicalDateFromCompletion(todo.lastCompletedDate!);
      final yesterday = today.subtract(const Duration(days: 1));
      
      // 比较逻辑日期
      if (lastLogicalDate.year == yesterday.year &&
          lastLogicalDate.month == yesterday.month &&
          lastLogicalDate.day == yesterday.day) {
        // 昨天完成过，连续天数+1
        newConsecutiveDays = todo.consecutiveDays + 1;
      } else if (lastLogicalDate.isBefore(yesterday)) {
        // 中断了，重新开始
        newConsecutiveDays = 1;
      } else {
        // 今天已经完成过（理论上不会到这里，但保险起见）
        newConsecutiveDays = todo.consecutiveDays;
      }
    }

    // 计算累计已完成天数（如果今天还没完成过，则+1）
    int newTotalCompletedDays = todo.totalCompletedDays;
    if (todo.lastCompletedDate == null) {
      // 从未完成过，累计天数+1
      newTotalCompletedDays = todo.totalCompletedDays + 1;
    } else {
      // 使用逻辑日期来判断上次完成的日期
      final lastLogicalDate = _getLogicalDateFromCompletion(todo.lastCompletedDate!);
      // 如果上次完成的逻辑日期不是今天，则累计天数+1
      if (lastLogicalDate.year != today.year ||
          lastLogicalDate.month != today.month ||
          lastLogicalDate.day != today.day) {
        newTotalCompletedDays = todo.totalCompletedDays + 1;
      }
    }

    setState(() {
      todo.isCompleted = true;
      todo.consecutiveDays = newConsecutiveDays;
      todo.totalCompletedDays = newTotalCompletedDays;
      todo.lastCompletedDate = now;
      _completedTodoId = id;
      _completedConsecutiveDays = newConsecutiveDays;
      
      // 将完成的待办事项移动到列表底部
      _todos.removeAt(todoIndex);
      _todos.add(todo);
    });

    // 保存状态
    _saveTodos();

    // 播放音效
    _playSuccessSound();

    // 先启动动画，再显示庆祝弹窗
    _confettiController.play();
    _scaleController.forward(from: 0);
    _fadeController.forward(from: 0);
    _celebrationController.forward(from: 0);
    
    // 延迟一帧再显示，确保动画值已初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _showCelebration = true;
        });
      }
    });

    // 不再自动隐藏，等待用户点击屏幕
  }

  void _deleteTodo(String id) {
    setState(() {
      _todos.removeWhere((todo) => todo.id == id);
    });
    _saveTodos();
  }

  // 开始编辑待办项文本
  void _startEditingTodo(String id, String currentText) {
    setState(() {
      _editingTodoId = id;
      _editTextController.text = currentText;
    });
    // 请求焦点并将光标移动到文本末尾
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _editFocusNode.requestFocus();
      final textLength = _editTextController.text.length;
      _editTextController.selection = TextSelection(
        baseOffset: textLength,
        extentOffset: textLength,
      );
    });
  }

  // 完成编辑待办项文本（保存）
  void _finishEditingTodo(String id) {
    final newText = _editTextController.text.trim();
    if (newText.isNotEmpty) {
      setState(() {
        final todoIndex = _todos.indexWhere((todo) => todo.id == id);
        if (todoIndex != -1) {
          _todos[todoIndex].text = newText;
        }
        _editingTodoId = null;
        _editTextController.clear();
      });
      _saveTodos();
    }
    _editFocusNode.unfocus();
  }

  // 取消编辑（放弃修改）
  void _cancelEditingTodo() {
    if (_editingTodoId != null) {
      setState(() {
        _editingTodoId = null;
        _editTextController.clear();
      });
      _editFocusNode.unfocus();
    }
  }

  // 保存待办事项到本地存储
  Future<void> _saveTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todosJson = _todos.map((todo) => todo.toJson()).toList();
      await prefs.setString('todos', jsonEncode(todosJson));
    } catch (e) {
      // 保存失败时静默处理
      debugPrint('保存待办事项失败: $e');
    }
  }

  // 从本地存储加载待办事项
  Future<void> _loadTodos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todosJsonString = prefs.getString('todos');
      if (todosJsonString != null) {
        final List<dynamic> todosJson = jsonDecode(todosJsonString);
        setState(() {
          _todos.clear();
          _todos.addAll(
            todosJson.map((json) => TodoItem.fromJson(json as Map<String, dynamic>)),
          );
        });
      }
    } catch (e) {
      // 加载失败时静默处理
      debugPrint('加载待办事项失败: $e');
    }
  }

  // 获取逻辑日期（如果当前时间在0:00-4:00之间，返回前一天的日期，否则返回当天）
  DateTime _getLogicalDate(DateTime now) {
    if (now.hour < 4) {
      // 如果当前时间在0:00-4:00之间，算作前一天
      final yesterday = now.subtract(const Duration(days: 1));
      return DateTime(yesterday.year, yesterday.month, yesterday.day);
    } else {
      // 否则算作当天
      return DateTime(now.year, now.month, now.day);
    }
  }

  // 从完成日期获取逻辑日期（用于判断历史完成日期属于哪一天）
  DateTime _getLogicalDateFromCompletion(DateTime completionDate) {
    return _getLogicalDate(completionDate);
  }

  // 检查并重置每日待办事项
  Future<void> _checkAndResetDaily() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final today = _getLogicalDate(now);
      
      // 获取上次重置的日期
      final lastResetDateString = prefs.getString('lastResetDate');
      DateTime? lastResetDate;
      
      if (lastResetDateString != null) {
        lastResetDate = DateTime.parse(lastResetDateString);
        lastResetDate = DateTime(lastResetDate.year, lastResetDate.month, lastResetDate.day);
      }

      // 如果今天与上次重置日期不同，说明已经过了4点，需要重置
      if (lastResetDate == null || lastResetDate.isBefore(today)) {
        bool hasReset = false;
        setState(() {
          for (var todo in _todos) {
            if (todo.isCompleted) {
              todo.isCompleted = false;
              // 检查是否连续完成：如果昨天完成过，连续天数保持不变；否则重置为0
              if (todo.lastCompletedDate != null) {
                // 使用逻辑日期来判断上次完成的日期
                final lastLogicalDate = _getLogicalDateFromCompletion(todo.lastCompletedDate!);
                final yesterday = today.subtract(const Duration(days: 1));
                // 如果上次完成的逻辑日期不是昨天，说明中断了，重置连续天数
                if (lastLogicalDate.year != yesterday.year ||
                    lastLogicalDate.month != yesterday.month ||
                    lastLogicalDate.day != yesterday.day) {
                  todo.consecutiveDays = 0;
                }
                // 注意：如果昨天完成过，连续天数保持不变，等待今天完成时再增加
              } else {
                // 没有完成记录，重置连续天数
                todo.consecutiveDays = 0;
              }
              hasReset = true;
            }
          }
        });

        // 保存重置后的状态
        if (hasReset) {
          await _saveTodos();
        }

        // 更新上次重置日期为今天（使用逻辑日期）
        await prefs.setString('lastResetDate', today.toIso8601String());
        
        debugPrint('每日重置完成: ${_todos.where((t) => !t.isCompleted).length} 个待办事项待完成');
      }
    } catch (e) {
      debugPrint('每日重置检查失败: $e');
    }
  }

  Future<void> _playSuccessSound() async {
    // 如果选择了静音（_selectedVoiceFolder 为 null 或空字符串），不播放任何音频
    if (_selectedVoiceFolder == null || _selectedVoiceFolder!.isEmpty) {
      return;
    }

    try {
      // 从选中的文件夹随机播放
      final soundFile = await _getRandomSoundFromFolder(_selectedVoiceFolder!);
      if (soundFile != null) {
        await _audioPlayer.play(AssetSource('sounds/$_selectedVoiceFolder/$soundFile'));
      }
    } catch (e) {
      // 静默处理，动画效果仍然会显示
      debugPrint('播放音效失败: $e');
    }
  }

  // 从指定文件夹获取随机音频文件名
  Future<String?> _getRandomSoundFromFolder(String folderName) async {
    // 定义每个文件夹的音频文件列表
    final Map<String, List<String>> folderSounds = {
      'aqua': [
        'iloveyou.mp3',
        'rua.mp3',
        '余裕余裕.mp3',
        '呀吼.mp3',
        '太好了洋葱.mp3',
        '完璧完璧.mp3',
        '尖叫.mp3',
        '理解理解.mp3',
      ],
      'mea': [
        'ikuzo.mp3',
        'kimo.mp3',
        'sodayo.mp3',
        'yatta.mp3',
        '吵死了.mp3',
        '啊啊啊啊.mp3',
        '要上了.mp3',
      ],
      '冬雪莲': [
        '我受不了了.mp3',
        '我急死了.mp3',
      ],
      '松冈修造': [
        'dekiru.mp3',
        'nevergiveup.mp3',
        '别放弃.mp3',
        '富士山.mp3',
        '第一名.mp3',
      ],
    };

    final sounds = folderSounds[folderName];
    if (sounds == null || sounds.isEmpty) {
      return null;
    }

    // 随机选择一个音频文件
    final random = math.Random();
    return sounds[random.nextInt(sounds.length)];
  }

  // 加载保存的语音选择
  Future<void> _loadVoiceSelection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedFolder = prefs.getString('selectedVoiceFolder');
      if (savedFolder != null) {
        // 如果是空字符串，表示选择了静音
        if (savedFolder.isEmpty) {
          setState(() {
            _selectedVoiceFolder = '';
          });
        } else if (_voiceFolders.contains(savedFolder)) {
          setState(() {
            _selectedVoiceFolder = savedFolder;
          });
        }
      } else {
        // 如果没有保存的选择，默认选择 aqua
        setState(() {
          _selectedVoiceFolder = 'aqua';
        });
        await _saveVoiceSelection('aqua');
      }
    } catch (e) {
      debugPrint('加载语音选择失败: $e');
      // 如果加载失败，也默认选择 aqua
    setState(() {
        _selectedVoiceFolder = 'aqua';
      });
    }
  }

  // 保存语音选择
  Future<void> _saveVoiceSelection(String folderName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selectedVoiceFolder', folderName);
    } catch (e) {
      debugPrint('保存语音选择失败: $e');
    }
  }

  // 显示语音选择对话框
  Future<void> _showVoiceSelectionDialog() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择语音包'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 添加"静音"选项
                ListTile(
                  title: const Text('🔇 静音（不播放音效）'),
                  leading: Radio<String>(
                    value: '',
                    groupValue: _selectedVoiceFolder ?? '',
                    onChanged: (value) {
                      Navigator.of(context).pop(value);
                    },
                  ),
                  onTap: () {
                    Navigator.of(context).pop('');
                  },
                ),
                const Divider(),
                // 语音文件夹选项
                ..._voiceFolders.map((folder) {
                  return ListTile(
                    title: Text(folder),
                    leading: Radio<String>(
                      value: folder,
                      groupValue: _selectedVoiceFolder ?? '',
                      onChanged: (value) {
                        Navigator.of(context).pop(value);
                      },
                    ),
                    onTap: () {
                      Navigator.of(context).pop(folder);
                    },
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    if (selected != null) {
      setState(() {
        _selectedVoiceFolder = selected.isEmpty ? null : selected;
      });
      await _saveVoiceSelection(selected);
      
      // 如果选择的不是静音，立即播放一个随机音频作为预览
      if (selected.isNotEmpty) {
        try {
          final soundFile = await _getRandomSoundFromFolder(selected);
          if (soundFile != null) {
            await _audioPlayer.play(AssetSource('sounds/$selected/$soundFile'));
          }
        } catch (e) {
          debugPrint('播放预览音效失败: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final completedCount = _todos.where((todo) => todo.isCompleted).length;
    final totalCount = _todos.length;

    return GestureDetector(
      onTap: () {
        // 点击外部区域取消编辑（放弃修改）
        if (_editingTodoId != null) {
          _cancelEditingTodo();
        }
      },
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        body: Stack(
        children: [
          // 主内容
          Column(
            children: [
              // 顶部标题区域
              Container(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                decoration: const BoxDecoration(
                  color: Color(0xFF4DD0E1), // 水蓝色
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'IgniteList',
                                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                totalCount > 0
                                    ? '已完成 $completedCount / $totalCount'
                                    : '开始你的每日待办吧！',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Colors.white70,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        // 语音选择区域
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '选择语音包：',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _showVoiceSelectionDialog,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white, width: 1.5),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                _selectedVoiceFolder != null && _selectedVoiceFolder!.isNotEmpty
                                    ? _selectedVoiceFolder!
                                    : '静音',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 输入框
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[100],
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        decoration: InputDecoration(
                          hintText: '添加新的待办事项...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onSubmitted: (_) => _addTodo(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _addTodo,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        backgroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: const Icon(Icons.add, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // 待办列表
              Expanded(
                child: _todos.isEmpty
                    ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 80,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '还没有待办事项',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '添加一个开始吧！',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ReorderableListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _todos.length,
                        buildDefaultDragHandles: false,
                        onReorder: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) {
                              newIndex -= 1;
                            }
                            final item = _todos.removeAt(oldIndex);
                            _todos.insert(newIndex, item);
                          });
                          _saveTodos();
                        },
                        itemBuilder: (context, index) {
                          final todo = _todos[index];
                          return _buildTodoItem(todo, index);
                        },
                      ),
              ),
            ],
          ),

          // 庆祝动画覆盖层
          if (_showCelebration)
            GestureDetector(
              onTap: () {
                // 点击屏幕任意地方关闭庆祝弹窗
                setState(() {
                  _showCelebration = false;
                  _completedTodoId = null;
                  _completedConsecutiveDays = 0;
                });
                _scaleController.reset();
                _fadeController.reset();
                _celebrationController.reset();
                _confettiController.stop();
              },
              child: Stack(
                children: [
                  // 彩纸动画（从顶部和底部发射）
                  Align(
                    alignment: Alignment.topCenter,
                    child: ConfettiWidget(
                      confettiController: _confettiController,
                      blastDirection: math.pi / 2, // 向下
                      maxBlastForce: 5,
                      minBlastForce: 2,
                      emissionFrequency: 0.05,
                      numberOfParticles: 20,
                      gravity: 0.1,
                      colors: const [
                        Colors.orange,
                        Colors.amber,
                        Colors.red,
                        Colors.yellow,
                        Colors.deepOrange,
                      ],
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ConfettiWidget(
                      confettiController: _confettiController,
                      blastDirection: -math.pi / 2, // 向上
                      maxBlastForce: 5,
                      minBlastForce: 2,
                      emissionFrequency: 0.05,
                      numberOfParticles: 20,
                      gravity: 0.1,
                      colors: const [
                        Colors.orange,
                        Colors.amber,
                        Colors.red,
                        Colors.yellow,
                        Colors.deepOrange,
                      ],
                    ),
                  ),
                  // 中心内容
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _scaleAnimation,
                      _fadeAnimation,
                      _bounceAnimation,
                      _celebrationController,
                    ]),
                    builder: (context, child) {
                      return Opacity(
                        opacity: _fadeAnimation.value,
                        child: Container(
                          color: Colors.black.withOpacity(0.3 * _fadeAnimation.value),
                          child: Center(
                            child: Transform.scale(
                              scale: math.max(0.1, _bounceAnimation.value),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 50,
                                  vertical: 40,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(30),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.orange.withOpacity(0.9 * _scaleAnimation.value),
                                      blurRadius: math.max(0.0, 60 * _scaleAnimation.value),
                                      spreadRadius: math.max(0.0, 15 * _scaleAnimation.value),
                                    ),
                                    BoxShadow(
                                      color: Colors.amber.withOpacity(0.6 * _scaleAnimation.value),
                                      blurRadius: math.max(0.0, 100 * _scaleAnimation.value),
                                      spreadRadius: math.max(0.0, 25 * _scaleAnimation.value),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 庆祝图标
                                    Container(
                                      padding: const EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.withOpacity(0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.celebration,
                                        size: math.max(1.0, 80 * _bounceAnimation.value),
                                        color: Colors.orange,
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                    // 主标题
                                    Text(
                                      _completedConsecutiveDays > 1
                                          ? '🎉 $_completedConsecutiveDays连胜！🎉'
                                          : '🎉 太棒了！🎉',
                                      style: TextStyle(
                                        fontSize: math.max(1.0, 32 * _bounceAnimation.value),
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange,
                                        shadows: [
                                          Shadow(
                                            color: Colors.orange.withOpacity(0.5),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    // 副标题
                                    Text(
                                      _completedConsecutiveDays > 1
                                          ? '连续完成 $_completedConsecutiveDays 天！'
                                          : '你做得很好！',
                                      style: TextStyle(
                                        fontSize: math.max(1.0, 18 * _bounceAnimation.value),
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // 鼓励文字
            Text(
                                      _completedConsecutiveDays > 1
                                          ? '继续保持这个势头！'
                                          : '继续加油！',
                                      style: TextStyle(
                                        fontSize: math.max(1.0, 16 * _bounceAnimation.value),
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
            ),
          ],
        ),
              ),
        ],
      ),
      ),
    );
  }

  Widget _buildTodoItem(TodoItem todo, int index) {
    final isCompleted = todo.isCompleted;
    final isAnimating = _completedTodoId == todo.id && _showCelebration;

    return AnimatedContainer(
      key: ValueKey(todo.id),
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isCompleted ? Colors.green[50] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCompleted ? Colors.green : Colors.grey[300]!,
          width: isCompleted ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: GestureDetector(
          onTap: () => _completeTodo(todo.id),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? Colors.green : Colors.grey[300],
              border: Border.all(
                color: isCompleted ? Colors.green : Colors.grey[400]!,
                width: 2,
              ),
            ),
            child: isCompleted
                ? const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 20,
                  )
                : null,
          ),
        ),
        title: _editingTodoId == todo.id
            ? GestureDetector(
                onTap: () {}, // 阻止事件冒泡到外部
                child: TextField(
                  controller: _editTextController,
                  focusNode: _editFocusNode,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              )
            : GestureDetector(
                onTap: () => _startEditingTodo(todo.id, todo.text),
                child: Text(
                  todo.text,
                  style: TextStyle(
                    decoration: isCompleted ? TextDecoration.lineThrough : null,
                    color: isCompleted ? Colors.grey[600] : Colors.black87,
                    fontSize: 16,
                  ),
                ),
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 编辑模式下显示保存按钮
            if (_editingTodoId == todo.id)
              IconButton(
                icon: Icon(Icons.check, color: Colors.green[600]),
                onPressed: () => _finishEditingTodo(todo.id),
                tooltip: '保存',
              )
            else ...[
              // 显示连续完成天数
              if (todo.consecutiveDays > 0)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.orange.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${todo.consecutiveDays}连胜！',
                    style: TextStyle(
                      color: Colors.orange[700],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              // 显示累计已完成天数
              if (todo.totalCompletedDays > 0)
                Container(
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.blue.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '生涯累计：${todo.totalCompletedDays}',
                    style: TextStyle(
                      color: Colors.blue[700],
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              // 删除按钮
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red[300]),
                onPressed: () => _deleteTodo(todo.id),
              ),
              // 拖拽按钮
              ReorderableDragStartListener(
                index: index,
                child: Icon(
                  Icons.drag_handle,
                  color: Colors.grey[400],
                  size: 24,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
