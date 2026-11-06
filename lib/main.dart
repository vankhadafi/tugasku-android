import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await NotificationService.init();
  runApp(const TugasKuApp());
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(initializationSettings);

    // Request permissions for Android 13+
    final androidImplementation =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();
    }
  }

  static Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    final tz.TZDateTime scheduledTZ =
        tz.TZDateTime.from(scheduledDate, tz.local);

    if (scheduledTZ.isBefore(tz.TZDateTime.now(tz.local))) {
      return;
    }

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'tugasku_deadline_channel',
      'Pengingat Deadline Tugas',
      channelDescription: 'Notifikasi pengingat sebelum batas waktu tugas habis',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTZ,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      // Fallback if exact alarm not granted
      await _notificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledTZ,
        platformDetails,
        androidScheduleMode: AndroidScheduleMode.inexact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  static Future<void> cancelNotification(int id) async {
    await _notificationsPlugin.cancel(id);
  }
}

class Task {
  String id;
  int notifId;
  String subject;
  String title;
  String priority;
  String type;
  DateTime deadline;
  String notes;
  bool completed;

  Task({
    required this.id,
    required this.notifId,
    required this.subject,
    required this.title,
    required this.priority,
    required this.type,
    required this.deadline,
    this.notes = '',
    this.completed = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'notifId': notifId,
        'subject': subject,
        'title': title,
        'priority': priority,
        'type': type,
        'deadline': deadline.toIso8601String(),
        'notes': notes,
        'completed': completed,
      };

  factory Task.fromMap(Map<String, dynamic> map) => Task(
        id: map['id'],
        notifId: map['notifId'] ?? 0,
        subject: map['subject'],
        title: map['title'],
        priority: map['priority'],
        type: map['type'],
        deadline: DateTime.parse(map['deadline']),
        notes: map['notes'] ?? '',
        completed: map['completed'] ?? false,
      );
}

class TugasKuApp extends StatelessWidget {
  const TugasKuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TugasKu',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF090D16),
        primaryColor: const Color(0xFF6366F1),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFF8B5CF6),
          surface: Color(0xFF131B2E),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF131B2E),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            side: BorderSide(color: Color(0x1FFFFFFF), width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Task> tasks = [];
  String filter = 'all'; // all, urgent, completed
  String searchQuery = '';
  final TextEditingController searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('tugasku_tasks');
    if (data != null) {
      final List decoded = jsonDecode(data);
      setState(() {
        tasks = decoded.map((e) => Task.fromMap(e)).toList();
      });
    } else {
      // Dummy starter data
      final now = DateTime.now();
      tasks = [
        Task(
          id: const Uuid().v4(),
          notifId: 101,
          subject: 'Rekayasa Perangkat Lunak',
          title: 'Laporan SRS Bab 1-3 & Diagram UML',
          priority: 'Tinggi',
          type: 'Kelompok',
          deadline: now.add(const Duration(hours: 5)),
          notes: 'Format PDF IEEE standard, upload ke portal kuliah.',
        ),
        Task(
          id: const Uuid().v4(),
          notifId: 102,
          subject: 'Basis Data Lanjut',
          title: 'Optimasi Query Indexing & Stored Procedure',
          priority: 'Sedang',
          type: 'Praktikum',
          deadline: now.add(const Duration(days: 2)),
          notes: 'Simpan file .sql di GitHub repo praktikum.',
        ),
      ];
      _saveTasks();
    }
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(tasks.map((e) => e.toMap()).toList());
    await prefs.setString('tugasku_tasks', encoded);
  }

  void _addOrUpdateTask(Task task, {bool isEdit = false}) {
    setState(() {
      if (isEdit) {
        final index = tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          tasks[index] = task;
        }
      } else {
        tasks.insert(0, task);
      }
    });
    _saveTasks();

    // Jadwalkan notifikasi 1 jam sebelum deadline jika belum selesai
    if (!task.completed) {
      final notifTime = task.deadline.subtract(const Duration(hours: 1));
      NotificationService.scheduleNotification(
        id: task.notifId,
        title: '⏰ Pengingat Deadline: ${task.subject}',
        body: '${task.title} jatuh tempo 1 jam lagi!',
        scheduledDate: notifTime,
      );
    }
  }

  void _deleteTask(Task task) {
    NotificationService.cancelNotification(task.notifId);
    setState(() {
      tasks.removeWhere((t) => t.id == task.id);
    });
    _saveTasks();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Tugas berhasil dihapus'),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _toggleComplete(Task task) {
    setState(() {
      task.completed = !task.completed;
      if (task.completed) {
        NotificationService.cancelNotification(task.notifId);
      }
    });
    _saveTasks();
  }

  void _showFormModal({Task? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF101626),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => TaskFormSheet(
        task: existing,
        onSubmit: (savedTask) {
          _addOrUpdateTask(savedTask, isEdit: existing != null);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final filteredTasks = tasks.where((t) {
      final matchQuery = t.subject.toLowerCase().contains(searchQuery) ||
          t.title.toLowerCase().contains(searchQuery);
      if (!matchQuery) return false;

      if (filter == 'urgent') {
        final diff = t.deadline.difference(now);
        return !t.completed && diff.inHours <= 24 && !diff.isNegative;
      }
      if (filter == 'completed') {
        return t.completed;
      }
      return true;
    }).toList();

    filteredTasks.sort((a, b) {
      if (a.completed != b.completed) return a.completed ? 1 : -1;
      return a.deadline.compareTo(b.deadline);
    });

    final urgentCount = tasks.where((t) {
      final diff = t.deadline.difference(now);
      return !t.completed && diff.inHours <= 24 && !diff.isNegative;
    }).length;

    final completedCount = tasks.where((t) => t.completed).length;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.8, -0.9),
            radius: 1.2,
            colors: [Color(0xFF1E1B4B), Color(0xFF090D16)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // Header
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFFA855F7)],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.4),
                                  blurRadius: 15,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.school, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'TugasKu',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                'Campus Deadline Tracker',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => _showFormModal(),
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.all(12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.add, color: Colors.white, size: 22),
                      ),
                    ],
                  ),
                ),
              ),

              // Summary Stats Row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Total',
                          value: tasks.length.toString(),
                          color: const Color(0xFF6366F1),
                          icon: Icons.assignment_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          title: 'Mendesak',
                          value: urgentCount.toString(),
                          color: const Color(0xFFF59E0B),
                          icon: Icons.timer_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          title: 'Tuntas',
                          value: completedCount.toString(),
                          color: const Color(0xFF10B981),
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: TextField(
                      controller: searchCtrl,
                      onChanged: (val) {
                        setState(() {
                          searchQuery = val.toLowerCase().trim();
                        });
                      },
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Cari matkul atau tugas...',
                        hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, color: Colors.white54, size: 16),
                                onPressed: () {
                                  searchCtrl.clear();
                                  setState(() => searchQuery = '');
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              ),

              // Filter Tabs
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Row(
                    children: [
                      _FilterTab(
                        label: 'Semua',
                        isActive: filter == 'all',
                        onTap: () => setState(() => filter = 'all'),
                      ),
                      const SizedBox(width: 8),
                      _FilterTab(
                        label: 'Mendesak',
                        isActive: filter == 'urgent',
                        onTap: () => setState(() => filter = 'urgent'),
                      ),
                      const SizedBox(width: 8),
                      _FilterTab(
                        label: 'Selesai',
                        isActive: filter == 'completed',
                        onTap: () => setState(() => filter = 'completed'),
                      ),
                    ],
                  ),
                ),
              ),

              // Task List or Empty
              if (filteredTasks.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Text('🎉', style: TextStyle(fontSize: 44)),
                        SizedBox(height: 12),
                        Text(
                          'Tidak ada tugas di kategori ini',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Tekan tombol + di atas untuk tambah baru',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 80),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final task = filteredTasks[index];
                        return _TaskCard(
                          task: task,
                          onToggle: () => _toggleComplete(task),
                          onEdit: () => _showFormModal(existing: task),
                          onDelete: () => _deleteTask(task),
                        );
                      },
                      childCount: filteredTasks.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
              ),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? const Color(0xFF6366F1) : const Color(0xFF131B2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? const Color(0xFF6366F1) : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : const Color(0xFF94A3B8),
          ),
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskCard({
    required this.task,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final diff = task.deadline.difference(now);
    final isPast = diff.isNegative;
    final isUrgent = !task.completed && diff.inHours <= 24 && !isPast;

    Color priorityColor = const Color(0xFF3B82F6);
    if (task.priority == 'Tinggi') priorityColor = const Color(0xFFEF4444);
    if (task.priority == 'Sedang') priorityColor = const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131B2E).withOpacity(task.completed ? 0.4 : 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isUrgent
              ? const Color(0xFFF59E0B).withOpacity(0.4)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: priorityColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    '${task.priority} • ${task.type}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: priorityColor,
                    ),
                  ),
                ),
                if (task.completed)
                  const Text(
                    '✓ Tuntas',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF10B981),
                    ),
                  )
                else if (isPast)
                  const Text(
                    'Lewat Deadline!',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF4444),
                    ),
                  )
                else if (isUrgent)
                  Text(
                    '${diff.inHours} jam lagi',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF59E0B),
                    ),
                  )
                else
                  Text(
                    '${diff.inDays} hari lagi',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              task.subject,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF818CF8),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              task.title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: task.completed ? Colors.white38 : Colors.white,
                decoration: task.completed ? TextDecoration.lineThrough : null,
              ),
            ),
            if (task.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF090D16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  task.notes,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.event, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd MMM yyyy, HH:mm').format(task.deadline),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        task.completed ? Icons.undo : Icons.check_circle,
                        color: task.completed ? Colors.white54 : const Color(0xFF10B981),
                        size: 20,
                      ),
                      onPressed: onToggle,
                      tooltip: task.completed ? 'Batal Selesai' : 'Tandai Selesai',
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
                      onPressed: onEdit,
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                      onPressed: onDelete,
                      tooltip: 'Hapus',
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TaskFormSheet extends StatefulWidget {
  final Task? task;
  final Function(Task) onSubmit;

  const TaskFormSheet({super.key, this.task, required this.onSubmit});

  @override
  State<TaskFormSheet> createState() => _TaskFormSheetState();
}

class _TaskFormSheetState extends State<TaskFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _subjectCtrl;
  late TextEditingController _titleCtrl;
  late TextEditingController _notesCtrl;
  String _priority = 'Sedang';
  String _type = 'Individu';
  DateTime _deadline = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _subjectCtrl = TextEditingController(text: widget.task?.subject ?? '');
    _titleCtrl = TextEditingController(text: widget.task?.title ?? '');
    _notesCtrl = TextEditingController(text: widget.task?.notes ?? '');
    if (widget.task != null) {
      _priority = widget.task!.priority;
      _type = widget.task!.type;
      _deadline = widget.task!.deadline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.task != null ? 'Edit Tugas Kuliah' : 'Tambah Tugas Baru',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subjectCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _inputDecoration('Mata Kuliah', 'Contoh: Algoritma'),
                validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: _inputDecoration('Judul Tugas', 'Contoh: Makalah Studi Kasus'),
                validator: (v) => v!.isEmpty ? 'Wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _priority,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Prioritas', ''),
                      items: ['Tinggi', 'Sedang', 'Rendah'].map((e) {
                        return DropdownMenuItem(value: e, child: Text(e));
                      }).toList(),
                      onChanged: (val) => setState(() => _priority = val!),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _type,
                      dropdownColor: const Color(0xFF1E293B),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: _inputDecoration('Tipe', ''),
                      items: ['Individu', 'Kelompok', 'Praktikum', 'Kuis'].map((e) {
                        return DropdownMenuItem(value: e, child: Text(e));
                      }).toList(),
                      onChanged: (val) => setState(() => _type = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _deadline,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (pickedDate != null) {
                    final pickedTime = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(_deadline),
                    );
                    if (pickedTime != null) {
                      setState(() {
                        _deadline = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090D16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Deadline', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            DateFormat('dd MMM yyyy, HH:mm').format(_deadline),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const Icon(Icons.calendar_today, color: Color(0xFF818CF8), size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: _inputDecoration('Catatan Tambahan', 'Format file, link submission...'),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      final task = Task(
                        id: widget.task?.id ?? const Uuid().v4(),
                        notifId: widget.task?.notifId ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
                        subject: _subjectCtrl.text.trim(),
                        title: _titleCtrl.text.trim(),
                        priority: _priority,
                        type: _type,
                        deadline: _deadline,
                        notes: _notesCtrl.text.trim(),
                        completed: widget.task?.completed ?? false,
                      );
                      widget.onSubmit(task);
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Simpan Tugas', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 12),
      filled: true,
      fillColor: const Color(0xFF090D16),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF6366F1))),
    );
  }
}
