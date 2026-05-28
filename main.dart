import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:uni_links/uni_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
// import 'package:firebase_analytics/firebase_analytics.dart';
import 'firebase_options.dart';

import 'controllers.dart';
import 'models.dart';
import 'order_item.dart';
import 'screens/order_screen.dart';

void main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
      debugPrint('FlutterError: \\n${details.exceptionAsString()}');
      if (details.stack != null) {
        debugPrint(details.stack.toString());
      }
    };

    ErrorWidget.builder = (FlutterErrorDetails details) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 40),
                  const SizedBox(height: 12),
                  const Text('เกิดข้อผิดพลาด', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    details.exceptionAsString(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    };

    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      debugPrint('Firebase initialized successfully');
    } catch (e, st) {
      debugPrint('Error initializing Firebase: $e');
      debugPrint(st.toString());
    }

    runApp(const NoodleOrderApp());
  }, (error, stack) {
    debugPrint('Uncaught zone error: $error');
    debugPrint(stack.toString());
  });
}

// ------------------------- APP STATE ---------------------------
class AppState {
  AppState._internal();
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;

  String? selectedTableNumber;

  void setSelectedTable(String? table) {
    selectedTableNumber = table?.trim().isEmpty == true ? null : table?.trim();
  }
}
// ------------------------- APP ------------------------------
class NoodleOrderApp extends StatelessWidget {
  const NoodleOrderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ร้านก๋วยเตี๋ยวบังดิส',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        scaffoldBackgroundColor: Colors.orange.shade50,
      ),
      home: const OrderScreen(),
      routes: {
        '/pager_control': (context) => const PagerControlScreen(),
      },
    );
  }
}

// -------------------- SUMMARY SCREEN ------------------------
class SummaryScreen extends StatefulWidget {
  const SummaryScreen({super.key});

  @override
  State<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends State<SummaryScreen> {
  bool _showAdminActions = false;
  Timer? _adminActionTimer;
  bool _isProcessing = false; // ป้องกันการกดซ้ำ
  Timer? _ordersRefreshTimer;
  int _lastOrdersCount = 0;
  int _lastTotal = 0;

  @override
  void initState() {
    super.initState();
    final orders = OrderController().orders;
    _lastOrdersCount = orders.length;
    _lastTotal = OrderController().total;

    // คอนโทรลเลอร์เป็น singleton แต่ไม่ได้ notify UI โดยตรง
    // ทำให้หน้าสรุปออเดอร์ต้องรีเฟรชเมื่อข้อมูลเปลี่ยน (เช่น สั่งเพิ่ม/ลบ)
    _ordersRefreshTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      final currentCount = OrderController().orders.length;
      final currentTotal = OrderController().total;
      if (currentCount != _lastOrdersCount || currentTotal != _lastTotal) {
        setState(() {
          _lastOrdersCount = currentCount;
          _lastTotal = currentTotal;
        });
      }
    });
  }

  @override
  void dispose() {
    _adminActionTimer?.cancel();
    _ordersRefreshTimer?.cancel();
    super.dispose();
  }

  // Simple PIN check for admin access
  Future<void> _promptAdminAccess(BuildContext context) async {
    final TextEditingController pinController = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ใส่รหัสพนักงาน'),
        content: TextField(
          controller: pinController,
          decoration: const InputDecoration(
            labelText: 'PIN',
            border: OutlineInputBorder(),
          ),
          obscureText: true,
          keyboardType: TextInputType.number,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              // TODO: replace with secure check or Firebase Auth/Remote Config
              if (pinController.text.trim() == '2468') {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN ไม่ถูกต้อง')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('ยืนยัน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      // เปิดปุ่มแอดมินชั่วคราว 3 นาที
      _adminActionTimer?.cancel();
      setState(() {
        _showAdminActions = true;
      });
      _adminActionTimer = Timer(const Duration(minutes: 3), () {
        if (mounted) {
          setState(() {
            _showAdminActions = false;
          });
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('โหมดพนักงานบนหน้าสรุปเปิด 3 นาที (ปุ่มลับถูกเปิด)'),
          duration: Duration(seconds: 3),
        ),
      );

      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const StaffQueueScreen()),
      );
    }
  }
  void _showQueueDialog(BuildContext context) async {
    // ป้องกันการกดซ้ำ
    if (_isProcessing) {
      return;
    }

    final TextEditingController tableNumberController = TextEditingController();

    // Use scanned table if available
    final preset = AppState().selectedTableNumber;
    if (preset != null && preset.isNotEmpty) {
      await _processQueueWithTable(context, preset);
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🪑 หมายเลขโต๊ะ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('กรุณากรอกหมายเลขโต๊ะของคุณ'),
            const SizedBox(height: 16),
            TextField(
              controller: tableNumberController,
              decoration: const InputDecoration(
                labelText: 'หมายเลขโต๊ะ',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.table_restaurant),
                hintText: 'เช่น 1, 2, 3, A1, B2',
              ),
              keyboardType: TextInputType.text,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (tableNumberController.text.trim().isNotEmpty) {
                Navigator.pop(context, tableNumberController.text.trim());
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('กรุณากรอกหมายเลขโต๊ะ'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('ยืนยัน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null) {
      await _processQueueWithTable(context, result);
    }
  }

  Future<void> _processQueueWithTable(BuildContext context, String table) async {
    // ป้องกันการกดซ้ำ
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    // แสดง loading dialog ทันที
    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('กำลังเรียกคิว...'),
                ],
              ),
            ),
          ),
        ),
      );
    }

    try {
      print('Starting queue process for table: $table');
      final currentOrders = OrderController().orders;
      print('Current orders count: ${currentOrders.length}');
      
      List<OrderItem> ordersToQueue = currentOrders;
      if (ordersToQueue.isEmpty) {
        print('No orders in local list, creating sample order');
        ordersToQueue = [
          OrderItem(
            name: 'ก๋วยเตี๋ยวชุดที่2 สด เปื่อย ปีก',
            price: 70,
            noVegetable: false,
            isSpecial: false,
            noodleType: 'หมี่ขาว',
          ),
        ];
      }
      
      final queueResult = await QueueController().addToQueue(
        'โต๊ะ $table',
        'โต๊ะ $table',
        ordersToQueue,
        int.parse(table),
      );

      print('Queue result: $queueResult');
      final queueId = queueResult['id'];
      final queueNumber = queueResult['queueNumber'];

      OrderController().clear();
      AppState().setSelectedTable(null);

      // ปิด loading dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      // แสดง dialog สำเร็จทันที
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('🎉 รับคิวเรียบร้อย!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('หมายเลขคิวของคุณคือ'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.deepOrange,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$queueNumber',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'กรุณารอเรียกคิว\nหรือดูสถานะได้ที่หน้าถัดไป',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'หมายเลขคิว: $queueId',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CustomerQueueScreen(queueId: queueId),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
                child: const Text('ดูสถานะคิว'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('Error in queue process: $e');
      
      // ปิด loading dialog ถ้ายังเปิดอยู่
      if (context.mounted) {
        try {
          Navigator.pop(context);
        } catch (_) {
          // ถ้าไม่มี dialog ให้เปิดอยู่ก็ไม่เป็นไร
        }
      }
      
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('❌ เกิดข้อผิดพลาด'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('ไม่สามารถเรียกคิวได้'),
                const SizedBox(height: 16),
                Text(
                  'ข้อผิดพลาด: $e',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'กรุณาตรวจสอบ:\n1. การเชื่อมต่ออินเทอร์เน็ต\n2. การตั้งค่า Firebase\n3. Firestore Rules',
                  style: TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }
    } finally {
      // Reset flag เมื่อเสร็จหรือเกิด error
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showDeleteSingleOrderDialog(BuildContext context, int index, OrderItem order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ ลบรายการ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('คุณต้องการลบรายการนี้หรือไม่?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ราคา: ${order.price} บาท',
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '⚠️ การลบรายการไม่สามารถยกเลิกได้',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              OrderController().removeOrderAt(index);
              Navigator.pop(context);
              setState(() {}); // รีเฟรช UI
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('🗑️ ลบ "${order.name}" เรียบร้อยแล้ว'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('ลบรายการ'),
          ),
        ],
      ),
    );
  }

  void _showDeleteOrderDialog(BuildContext context) {
    final orders = OrderController().orders;
    
    if (orders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ไม่มีออเดอร์ให้ลบ'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🗑️ ลบออเดอร์ทั้งหมด'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('คุณต้องการลบออเดอร์ทั้งหมดหรือไม่?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'จำนวนออเดอร์: ${orders.length} รายการ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ยอดรวม: ${OrderController().total} บาท',
                    style: const TextStyle(color: Colors.deepOrange),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '⚠️ การลบออเดอร์ไม่สามารถยกเลิกได้',
              style: TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              OrderController().clear();
              Navigator.pop(context);
              Navigator.pop(context); // กลับไปหน้าหลัก
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🗑️ ลบออเดอร์ทั้งหมดเรียบร้อยแล้ว'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('ลบทั้งหมด'),
          ),
        ],
      ),
    );
  }

  void _showQueueStatusDialog(BuildContext context) {
    final TextEditingController queueIdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📱 ดูสถานะคิว'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('กรุณากรอกหมายเลขคิวที่คุณได้รับ'),
            const SizedBox(height: 16),
            TextField(
              controller: queueIdController,
              decoration: const InputDecoration(
                labelText: 'หมายเลขคิว',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.queue),
                hintText: 'เช่น 1234567890',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (queueIdController.text.trim().isNotEmpty) {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CustomerQueueScreen(
                      queueId: queueIdController.text.trim(),
                    ),
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('กรุณากรอกหมายเลขคิว'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('ดูสถานะ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String _orderDetailText(OrderItem order) {
    final note = order.note?.trim() ?? '';
    final hasNote = note.isNotEmpty;

    // เมนูน้ำ: ไม่มีข้อมูล noodleType และไม่เลือกพิเศษ/ไม่ใส่ผัก/ไม่มีไข่
    if (order.noodleType == null &&
        order.noVegetable == false &&
        order.isSpecial == false &&
        (order.eggType == null || order.eggType!.trim().isEmpty)) {
      return hasNote ? 'หมายเหตุ: $note' : '';
    }

    // เมนูก๋วยเตี๋ยว
    if (order.noodleType != null) {
      return '${order.isSpecial ? 'พิเศษ' : 'ธรรมดา'} / '
          '${order.noVegetable ? 'ไม่ใส่ผัก' : 'ใส่ผัก'}'
          ' / เส้น: ${order.noodleType}'
          '${hasNote ? '\nหมายเหตุ: $note' : ''}';
    }

    // เมนูข้าว
    final eggText = (order.eggType != null && order.eggType!.trim().isNotEmpty)
        ? ' / ${order.eggType!.trim()}'
        : '';

    return '${order.isSpecial ? 'พิเศษ' : 'ธรรมดา'}$eggText'
        '${hasNote ? '\nหมายเหตุ: $note' : ''}';
  }

  @override
  Widget build(BuildContext context) {
    final orders = OrderController().orders;
    final total = OrderController().total;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onDoubleTap: () => _promptAdminAccess(context),
          child: const Text('🧾 สรุปออเดอร์'),
        ),
        actions: _showAdminActions
            ? [
                IconButton(
                  icon: const Icon(Icons.visibility),
                  tooltip: 'ดูสถานะคิว',
                  onPressed: () => _showQueueStatusDialog(context),
                ),
                IconButton(
                  icon: const Icon(Icons.cloud_download),
                  tooltip: 'โหลดออเดอร์จาก Firebase',
                  onPressed: () async {
                    try {
                      List<OrderItem> firestoreOrders = await OrderController().loadOrdersFromFirestore();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('โหลดข้อมูล ${firestoreOrders.length} รายการจาก Firebase')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                      );
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever),
                  tooltip: 'ล้างออเดอร์',
                  onPressed: () {
                    OrderController().clear();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('🗑️ ล้างออเดอร์เรียบร้อยแล้วครับ'),
                    ));
                  },
                ),
              ]
            : [],
      ),
      body: orders.isEmpty
          ? const Center(
              child: Text(
                'ยังไม่มีออเดอร์ในขณะนี้ครับ',
                style: TextStyle(fontSize: 20),
              ),
            )
          : ListView(
              children: [
                ...orders.asMap().entries.map((entry) {
                  final index = entry.key;
                  final order = entry.value;
                  final detailText = _orderDetailText(order);

                  return ListTile(
                    leading: const Icon(Icons.fastfood),
                    title: Text(order.name),
                    subtitle: detailText.isEmpty
                        ? null
                        : Text(
                            detailText,
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${order.price} บาท'),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'ลบรายการนี้',
                          onPressed: () =>
                              _showDeleteSingleOrderDialog(context, index, order),
                        ),
                      ],
                    ),
                  );
                }),
                const Divider(thickness: 2),
                ListTile(
                  title: const Text(
                    'รวมทั้งหมด',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Text(
                    '$total บาท',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.deepOrange,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      // ปุ่มลบออเดอร์ทั้งหมด
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _showDeleteOrderDialog(context),
                          icon: const Icon(Icons.delete_sweep, color: Colors.white),
                          label: const Text(
                            'ลบออเดอร์ทั้งหมด',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // ปุ่มเรียกคิว
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : () => _showQueueDialog(context),
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Icon(Icons.queue, color: Colors.white),
                          label: Text(
                            _isProcessing ? 'กำลังเรียกคิว...' : 'เรียกคิว',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepOrange,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

// ------------------- VEGETABLE OPTION ------------------------
class VegetableOptionScreen extends StatefulWidget {
  final String name;
  final bool isRice;
  const VegetableOptionScreen({super.key, required this.name, this.isRice = false});

  @override
  State<VegetableOptionScreen> createState() => _VegetableOptionScreenState();
}

class _VegetableOptionScreenState extends State<VegetableOptionScreen> {
  bool _isSpecial = false;
  String _eggType = '';
  bool? _noVegetable = false;
  String _selectedNoodle = 'เส้นเล็ก';

  final List<String> _noodleOptions = [
    'เส้นเล็ก',
    'เส้นใหญ่',
    'หมี่ขาว',
    'บะหมี่เหลือง',
    'มาม่า',
    'มาม่ามาเลย์',
  ];

  final TextEditingController _noteController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('รายละเอียด: ${widget.name}')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('กรุณาเลือกตัวเลือกเพิ่มเติม:', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 20),
              if (widget.isRice) ...[
                // สำหรับข้าว
                const Text('ขนาด', style: TextStyle(fontWeight: FontWeight.bold)),
                CheckboxListTile(
                  title: const Text('พิเศษ'),
                  value: _isSpecial,
                  onChanged: (value) => setState(() => _isSpecial = value!),
                  secondary: const Icon(Icons.star),
                ),
                const SizedBox(height: 10),
                const Text('ไข่', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<String>(
                  title: const Text('ไข่ดาว'),
                  value: 'ไข่ดาว',
                  groupValue: _eggType,
                  onChanged: (value) => setState(() => _eggType = value!),
                  secondary: const Icon(Icons.egg),
                ),
                RadioListTile<String>(
                  title: const Text('ไข่เจียว'),
                  value: 'ไข่เจียว',
                  groupValue: _eggType,
                  onChanged: (value) => setState(() => _eggType = value!),
                  secondary: const Icon(Icons.egg_alt),
                ),
                RadioListTile<String>(
                  title: const Text('ไม่ใส่ไข่'),
                  value: '',
                  groupValue: _eggType,
                  onChanged: (value) => setState(() => _eggType = value!),
                  secondary: const Icon(Icons.no_food),
                ),
              ] else ...[
                // สำหรับก๋วยเตี๋ยว
                const Text('ผัก', style: TextStyle(fontWeight: FontWeight.bold)),
                RadioListTile<bool>(
                  title: const Text('ใส่ผัก'),
                  value: false,
                  groupValue: _noVegetable,
                  onChanged: (value) => setState(() => _noVegetable = value),
                  secondary: const Icon(Icons.eco),
                ),
                RadioListTile<bool>(
                  title: const Text('ไม่ใส่ผัก'),
                  value: true,
                  groupValue: _noVegetable,
                  onChanged: (value) => setState(() => _noVegetable = value),
                  secondary: const Icon(Icons.no_food),
                ),
                const SizedBox(height: 10),
                const Text('ขนาด', style: TextStyle(fontWeight: FontWeight.bold)),
                CheckboxListTile(
                  title: const Text('พิเศษ'),
                  value: _isSpecial,
                  onChanged: (value) => setState(() => _isSpecial = value!),
                  secondary: const Icon(Icons.star),
                ),
                const SizedBox(height: 10),
                const Text('ประเภทเส้น', style: TextStyle(fontWeight: FontWeight.bold)),
                ..._noodleOptions.map((noodle) => RadioListTile<String>(
                      title: Text(noodle),
                      value: noodle,
                      groupValue: _selectedNoodle,
                      onChanged: (value) {
                        setState(() {
                          _selectedNoodle = value!;
                        });
                      },
                      secondary: const Icon(Icons.ramen_dining),
                    )),
              ],
              const SizedBox(height: 10),
              const Text('หมายเหตุ (ถ้ามี)', style: TextStyle(fontWeight: FontWeight.bold)),
              TextField(
                controller: _noteController,
                decoration: const InputDecoration(
                  hintText: 'เช่น ไม่ใส่พริก, ขอช้อนเพิ่ม ฯลฯ',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 30),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context, {
                      'noVegetable': _noVegetable,
                      'isSpecial': _isSpecial,
                      'selectedNoodle': widget.isRice ? null : _selectedNoodle,
                      'eggType': widget.isRice ? _eggType : null,
                      'note': _noteController.text, // ส่งโน๊ตกลับ
                    });
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('ยืนยันการเลือก'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

}

// -------------------- STAFF QUEUE SCREEN -------------------------
class StaffQueueScreen extends StatefulWidget {
  const StaffQueueScreen({super.key});

  @override
  State<StaffQueueScreen> createState() => _StaffQueueScreenState();
}

class _StaffQueueScreenState extends State<StaffQueueScreen> {
  Timer? _timer;
  StreamController<DateTime> _timeController = StreamController<DateTime>.broadcast();
  DateTime _selectedDate = DateTime.now();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _startTimer();
    _checkAndResetForNewDay();
  }

  // ตรวจสอบและรีเซทสำหรับวันใหม่
  Future<void> _checkAndResetForNewDay() async {
    try {
      final counterRef = _firestore.collection('meta').doc('queue_counter');
      final today = DateTime.now().toIso8601String().split('T')[0];
      
      final snapshot = await counterRef.get();
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final lastResetDate = data['lastResetDate'] as String?;
        
        if (lastResetDate != today) {
          // วันใหม่ - แสดงข้อความแจ้งเตือน
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('📅 ตรวจพบวันใหม่! กดปุ่มรีเซทเพื่อเริ่มคิวที่ 1'),
                duration: const Duration(seconds: 5),
                backgroundColor: Colors.orange,
                action: SnackBarAction(
                  label: 'รีเซท',
                  textColor: Colors.white,
                  onPressed: () async {
                    // รีเซทคิว
                    final queueSnapshot = await _firestore.collection('queue').get();
                    for (var doc in queueSnapshot.docs) {
                      await doc.reference.delete();
                    }
                    await QueueController().resetQueueNumber();
                    setState(() {});
                  },
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Error checking new day: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timeController.close();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _timeController.add(DateTime.now());
        setState(() {
          // Force rebuild to update timer widgets
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('📞 ระบบเรียกคิว - พนักงาน'),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2023, 1, 1),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() {
                      _selectedDate = picked;
                    });
                  }
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.calendar_today, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'รีเฟรชข้อมูล',
            onPressed: () {
              setState(() {
                // Force rebuild to refresh data
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🔄 รีเฟรชข้อมูลแล้ว'),
                  duration: Duration(seconds: 1),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'รีเซทคิวเป็น 1 (วันใหม่)',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('รีเซทคิววันใหม่'),
                  content: const Text('ต้องการรีเซทหมายเลขคิวกลับเป็น 1 สำหรับวันใหม่หรือไม่?\n\nคิวเก่าทั้งหมดจะถูกลบ'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('ยกเลิก'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                      child: const Text('ยืนยัน', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              );
              
              if (confirmed == true) {
                try {
                  // ลบคิวเก่าทั้งหมด
                  final queueSnapshot = await _firestore.collection('queue').get();
                  for (var doc in queueSnapshot.docs) {
                    await doc.reference.delete();
                  }
                  
                  // รีเซทหมายเลขคิว
                  await QueueController().resetQueueNumber();
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ รีเซทคิววันใหม่เรียบร้อย (เริ่มที่ 1)'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('เกิดข้อผิดพลาด: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<List<QueueItem>>(
        stream: QueueController().getQueueStreamByDate(_selectedDate),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('เกิดข้อผิดพลาด: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('กลับ'),
                  ),
                ],
              ),
            );
          }

          final queues = snapshot.data ?? [];
          final waitingQueues = queues.where((q) => q.status == 'waiting').toList();
          final calledQueues = queues.where((q) => q.status == 'called').toList();
          final completedQueues = queues.where((q) => q.status == 'completed').toList();

          return DefaultTabController(
            length: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // สถิติ
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatCard('รอเรียก', waitingQueues.length, Colors.orange),
                          _buildStatCard('กำลังเรียก', calledQueues.length, Colors.blue),
                          _buildStatCard('ทั้งหมด', queues.length, Colors.green),
                        ],
                      ),
                    ),
                  ),
                ),

                // แท็บเปลี่ยนสถานะ (ไม่ต้องเลื่อนลงไปกด)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TabBar(
                    labelColor: Colors.deepOrange,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.deepOrange,
                    tabs: const [
                      Tab(text: 'รอเรียก'),
                      Tab(text: 'กำลังเรียก'),
                      Tab(text: 'เสร็จสิ้น'),
                    ],
                  ),
                ),

                Expanded(
                  child: TabBarView(
                    children: [
                      // รอเรียก
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildQueueColumn(
                          context,
                          'รอเรียก',
                          waitingQueues,
                          'waiting',
                        ),
                      ),
                      // กำลังเรียก
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildQueueColumn(
                          context,
                          'กำลังเรียก',
                          calledQueues,
                          'called',
                        ),
                      ),
                      // เสร็จสิ้น
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: _buildQueueColumn(
                          context,
                          'เสร็จสิ้น',
                          completedQueues,
                          'completed',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(title, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildQueueColumn(
    BuildContext context,
    String title,
    List<QueueItem> queues,
    String status,
  ) {
    final Color sectionColor =
        status == 'waiting' ? Colors.orange : (status == 'called' ? Colors.blue : Colors.green);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: sectionColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sectionColor.withOpacity(0.45)),
              ),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: sectionColor,
                ),
              ),
            ),
            const SizedBox(height: 10),
            if (queues.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Text(
                  'ไม่มีคิว',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  // เผื่อให้คอลัมน์กว้างพอสำหรับปุ่ม (สไตล์ excel)
                  constraints: BoxConstraints(
                    minWidth: MediaQuery.of(context).size.width,
                  ),
                  child: DataTable(
                    headingRowHeight: 40,
                    dataRowMinHeight: 48,
                    dividerThickness: 1,
                    columnSpacing: 18,
                    border: TableBorder.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                    headingRowColor:
                        MaterialStateProperty.all(Colors.grey.shade200),
                    columns: const [
                      DataColumn(label: Text('คิว')),
                      DataColumn(label: Text('โต๊ะ')),
                      DataColumn(label: Text('เวลา')),
                      DataColumn(label: Text('รายการอาหาร')),
                      DataColumn(label: Text('การทำงาน')),
                    ],
                    rows: queues.map((queue) {
                      return DataRow(
                        cells: [
                          DataCell(Text('${queue.queueNumber}')),
                          DataCell(Text('${queue.tableNumber}')),
                          DataCell(
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(queue.createdAt),
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                _buildTimerWidget(queue.createdAt),
                              ],
                            ),
                          ),
                          DataCell(
                            _buildOrdersCell(queue),
                          ),
                          DataCell(
                            _buildQueueActionButtons(
                              context: context,
                              queue: queue,
                              status: status,
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrdersCell(QueueItem queue) {
    if (queue.orders.isEmpty) {
      return const Text('-');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final order in queue.orders) ...[
          Text(
            '• ${order.name} - ${order.price} บาท',
            style: const TextStyle(fontSize: 13),
            softWrap: true,
          ),
          if (order.note != null &&
              order.note!.isNotEmpty &&
              order.note!.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 2),
              child: Text(
                'หมายเหตุ: ${order.note!.trim()}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontStyle: FontStyle.italic,
                ),
                softWrap: true,
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildQueueActionButtons({
    required BuildContext context,
    required QueueItem queue,
    required String status,
  }) {
    final List<Widget> buttons = [];

    if (status == 'waiting') {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _callQueue(context, queue),
          icon: const Icon(Icons.call, size: 18),
          label: const Text('เรียกโต๊ะ'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      );

      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _editQueue(context, queue),
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('แก้ไข'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      );

      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _completeQueue(context, queue),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('เสร็จสิ้น'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      );
    } else if (status == 'called') {
      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _repeatCallQueue(context, queue),
          icon: const Icon(Icons.replay, size: 18),
          label: const Text('เรียกซ้ำ'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      );

      buttons.add(
        ElevatedButton.icon(
          onPressed: () => _completeQueue(context, queue),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('เสร็จสิ้น'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
        ),
      );
    } else {
      buttons.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.12),
            border: Border.all(color: Colors.green.withOpacity(0.55)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'เสร็จสิ้น',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.start,
      children: buttons,
    );
  }

  Widget _buildQueueCard(BuildContext context, QueueItem queue, String status) {
    Color statusColor =
        status == 'waiting' ? Colors.orange : (status == 'called' ? Colors.blue : Colors.green);
    String statusText =
        status == 'waiting' ? 'รอเรียก' : (status == 'called' ? 'กำลังเรียก' : 'เสร็จสิ้น');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'โต๊ะที่ ${queue.tableNumber}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '👤 โต๊ะที่ ${queue.tableNumber}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text('📱 โต๊ะที่ ${queue.tableNumber}'),
            const SizedBox(height: 8),
             Row(
               children: [
                 Icon(Icons.access_time, color: Colors.grey, size: 16),
                 const SizedBox(width: 4),
                 Text(
                   '🕐 ${_formatTime(queue.createdAt)}',
                   style: const TextStyle(color: Colors.grey),
                 ),
                 const SizedBox(width: 16),
                 _buildTimerWidget(queue.createdAt),
               ],
             ),
            const SizedBox(height: 12),
            const Text('รายการอาหาร:', style: TextStyle(fontWeight: FontWeight.bold)),
            ...queue.orders.map((order) => Padding(
              padding: const EdgeInsets.only(left: 8, top: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ${order.name} - ${order.price} บาท'),
                  if (order.note != null && order.note!.isNotEmpty && order.note!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 2),
                      child: Text(
                        '📝 ${order.note}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            )),
            const SizedBox(height: 12),
            Row(
              children: [
                if (status == 'waiting') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _callQueue(context, queue),
                      icon: const Icon(Icons.call),
                      label: const Text('เรียกโต๊ะ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (status == 'called') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _repeatCallQueue(context, queue),
                      icon: const Icon(Icons.replay),
                      label: const Text('เรียกซ้ำ'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (status != 'completed') ...[
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _completeQueue(context, queue),
                      icon: const Icon(Icons.check),
                      label: const Text('เสร็จสิ้น'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                if (status == 'waiting')
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _editQueue(context, queue),
                      icon: const Icon(Icons.edit),
                      label: const Text('แก้ไข'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _callQueue(BuildContext context, QueueItem queue) async {
    try {
      print('DEBUG: ========== เริ่มเรียกโต๊ะ ${queue.tableNumber} ==========');
      print('DEBUG: Queue ID: ${queue.id}');
      print('DEBUG: Table Number: ${queue.tableNumber}');
      print('DEBUG: Platform: ${kIsWeb ? "Web" : "Mobile"}');
      print('DEBUG: URL: ${Uri.base}');

      // อัปเดตสถานะคิวและสั่งรีเลย์ในที่เดียว
      await QueueController().callQueue(
        queue.id,
        tableNumber: queue.tableNumber,
      );
      print('DEBUG: ✅ QueueController เรียบร้อย');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📞 เรียกโต๊ะที่ ${queue.tableNumber} แล้ว'),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('DEBUG: Error = $e');
      // แสดง error message เฉพาะ ESP32 พร้อมคำแนะนำ
      String errorMsg = e.toString();
      String displayMsg = '⚠️ ไม่สามารถเชื่อมต่อ ESP32 ได้\n\n';

      if (errorMsg.contains('ไม่สามารถเชื่อมต่อ ESP32 ได้')) {
        displayMsg = errorMsg;
      } else {
        displayMsg += 'กรุณาตรวจสอบ:\n';
        displayMsg += '1. โทรศัพท์เชื่อมต่อ WiFi เดียวกับ ESP32\n';
        displayMsg += '2. ปิด Mobile Data และใช้ WiFi เท่านั้น\n';
        displayMsg += '3. ESP32 IP: ${PagerTableController.esp32BaseUrl}\n';
        displayMsg += '\nError: $e';
      }

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('ไม่สามารถเชื่อมต่อ ESP32'),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(displayMsg),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ตกลง'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  // แสดง URL ให้ผู้ใช้เปิดในเบราว์เซอร์
                  final testUrl = '${PagerTableController.esp32BaseUrl}/status';
                  if (kIsWeb) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('เปิด URL นี้ในแท็บใหม่: $testUrl'),
                        duration: const Duration(seconds: 5),
                        action: SnackBarAction(
                          label: 'คัดลอก',
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: testUrl));
                          },
                        ),
                      ),
                    );
                  } else {
                    Clipboard.setData(ClipboardData(text: testUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('คัดลอก URL แล้ว กรุณาเปิดในเบราว์เซอร์'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  }
                },
                child: const Text('ทดสอบการเชื่อมต่อ'),
              ),
            ],
          ),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _repeatCallQueue(BuildContext context, QueueItem queue) async {
    try {
      print('DEBUG: เรียกซ้ำโต๊ะ ${queue.tableNumber}');
      
      // สั่งรีเลย์โดยตรงผ่าน PagerTableController (ไม่เปลี่ยนสถานะคิว)
      await PagerTableController().callTable(queue.tableNumber);
      print('DEBUG: PagerTableController เรียบร้อย');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('📞 เรียกซ้ำโต๊ะที่ ${queue.tableNumber} แล้ว'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      print('DEBUG: Error = $e');
      String errorMsg = e.toString();
      String displayMsg = '⚠️ ไม่สามารถเชื่อมต่อ ESP32 ได้\n\n';

      if (errorMsg.contains('ไม่สามารถเชื่อมต่อ ESP32 ได้')) {
        displayMsg = errorMsg;
      } else {
        displayMsg += 'กรุณาตรวจสอบ:\n';
        displayMsg += '1. ESP32 เชื่อมต่อ WiFi และออนไลน์\n';
        displayMsg += '2. ESP32 อ่านคำสั่งจาก Firestore ได้\n';
        displayMsg += '3. ตรวจสอบ Firestore collection: esp32_commands\n';
        displayMsg += '\nError: $e';
      }

      if (context.mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange),
                SizedBox(width: 8),
                Text('ไม่สามารถเรียกซ้ำได้'),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(displayMsg),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _completeQueue(BuildContext context, QueueItem queue) async {
    try {
      await QueueController().completeQueue(queue.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ โต๊ะที่ ${queue.tableNumber} เสร็จสิ้นแล้ว'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _editQueue(BuildContext context, QueueItem queue) async {
    // แสดงรายการอาหารในคิวและให้แก้ไขได้
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('แก้ไขโต๊ะที่ ${queue.tableNumber}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('โต๊ะ: ${queue.tableNumber}'),
              Text('โต๊ะ: ${queue.tableNumber}'),
              const SizedBox(height: 16),
              const Text('รายการอาหาร:', style: TextStyle(fontWeight: FontWeight.bold)),
              ...queue.orders.asMap().entries.map((entry) {
                final index = entry.key;
                final order = entry.value;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${order.name} - ${order.price} บาท'),
                        if (order.note != null && order.note!.isNotEmpty)
                          Text('📝 ${order.note}', 
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, {'action': 'delete', 'index': index}),
                              child: const Text('ลบรายการ', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, {'action': 'delete_all'}),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบคิวทั้งหมด', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null) {
      if (result['action'] == 'delete_all') {
        // ลบคิวทั้งหมด
        try {
          await QueueController().deleteQueue(queue.id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🗑️ ลบโต๊ะที่ ${queue.tableNumber} แล้ว'),
              backgroundColor: Colors.orange,
            ),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('เกิดข้อผิดพลาด: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else if (result['action'] == 'delete' && result['index'] != null) {
        // ลบรายการอาหารเฉพาะรายการ
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ ฟีเจอร์ลบรายการเฉพาะยังไม่พร้อมใช้งาน'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _deleteQueue(BuildContext context, QueueItem queue) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบโต๊ะที่ ${queue.tableNumber} หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await QueueController().deleteQueue(queue.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🗑️ ลบโต๊ะที่ ${queue.tableNumber} แล้ว'),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาด: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTimerWidget(DateTime queueCreatedAt) {
    return StreamBuilder<DateTime>(
      stream: _timeController.stream,
      initialData: DateTime.now(),
      builder: (context, snapshot) {
        final now = snapshot.data ?? DateTime.now();
        final elapsed = now.difference(queueCreatedAt);
        final totalDuration = const Duration(minutes: 15);
        
        if (elapsed < totalDuration) {
          final remaining = totalDuration - elapsed;
          final isNearEnd = remaining.inMinutes < 5;
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isNearEnd ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isNearEnd ? Colors.red : Colors.orange,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer,
                  size: 14,
                  color: isNearEnd ? Colors.red : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  _formatDuration(remaining),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isNearEnd ? Colors.red : Colors.orange,
                  ),
                ),
              ],
            ),
          );
        } else {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.grey,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.timer_off,
                  size: 14,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Text(
                  'หมดเวลา',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }
}

// -------------------- TABLE QR SCREEN ---------------------------
class TableQrScreen extends StatefulWidget {
  const TableQrScreen({super.key});

  @override
  State<TableQrScreen> createState() => _TableQrScreenState();
}

class _TableQrScreenState extends State<TableQrScreen> {
  late TextEditingController _hostController;
  late TextEditingController _portController;

  @override
  void initState() {
    super.initState();
    final isLocalHost = Uri.base.host == 'localhost' || Uri.base.host == '127.0.0.1';
    final defaultHost = isLocalHost ? '' : Uri.base.host;
    final defaultPort = Uri.base.hasPort ? Uri.base.port.toString() : '8080';
    _hostController = TextEditingController(text: defaultHost);
    _portController = TextEditingController(text: defaultPort);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  String _buildOrigin() {
    if (!kIsWeb) {
      return 'myapp://table';
    }
    String host = _hostController.text.trim();
    final port = _portController.text.trim();
    if (host.isEmpty) {
      return '';
    }
    if (host.startsWith('http://') || host.startsWith('https://')) {
      return host;
    }
    if (port.isEmpty) {
      return 'https://$host';
    }
    return 'http://$host:$port';
  }

  @override
  Widget build(BuildContext context) {
    final List<int> tableNumbers = List<int>.generate(12, (index) => index + 1);
    final origin = _buildOrigin();
    return Scaffold(
      appBar: AppBar(
        title: const Text('QR โต๊ะลูกค้า (1-12)'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            if (kIsWeb) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _hostController,
                      decoration: const InputDecoration(
                        labelText: 'Host/IP ของเครื่องเซิร์ฟเวอร์ (เช่น 192.168.1.20)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _portController,
                      decoration: const InputDecoration(
                        labelText: 'พอร์ต',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => setState(() {}),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                    child: const Text('อัปเดต', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (origin.isEmpty)
                const Text('กรุณากรอก Host/IP ของคอมพิวเตอร์ เช่น 192.168.1.20 แล้วกด อัปเดต',
                    style: TextStyle(color: Colors.red)),
            ],
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.9,
                ),
                itemCount: tableNumbers.length,
                itemBuilder: (context, index) {
                  final table = tableNumbers[index];
                  String qrData;
                  if (kIsWeb) {
                    qrData = origin.isEmpty ? '' : '$origin/?table=$table';
                  } else {
                    qrData = 'myapp://table/$table';
                  }
                  return Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'โต๊ะ $table',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Center(
                              child: qrData.isEmpty
                                  ? const Text('กรอก Host/IP ก่อน', style: TextStyle(color: Colors.grey))
                                  : QrImageView(
                                      data: qrData,
                                      version: QrVersions.auto,
                                      size: 180,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(qrData.isEmpty ? '-' : qrData,
                              style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------- SCAN TABLE SCREEN -------------------------
class ScanTableScreen extends StatefulWidget {
  const ScanTableScreen({super.key});

  @override
  State<ScanTableScreen> createState() => _ScanTableScreenState();
}

class _ScanTableScreenState extends State<ScanTableScreen> {
  bool _handled = false;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final codes = capture.barcodes;
    if (codes.isEmpty) return;
    final raw = codes.first.rawValue;
    if (raw == null) return;

    // Accept formats: table:1 or myapp://table/1
    String? table;
    if (raw.startsWith('table:')) {
      table = raw.substring('table:'.length);
    } else if (raw.contains('/table/')) {
      final parts = raw.split('/table/');
      if (parts.length > 1) {
        table = parts.last;
      }
    }

    if (table != null && table.trim().isNotEmpty) {
      _handled = true;
      AppState().setSelectedTable(table);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เลือกโต๊ะ: $table')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('สแกนคิวอาร์โต๊ะ'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          const Text('สแกน QR บนโต๊ะ เพื่อเลือกหมายเลขโต๊ะอัตโนมัติ'),
          const SizedBox(height: 12),
          Expanded(
            child: MobileScanner(
              onDetect: _onDetect,
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------- CUSTOMER QUEUE SCREEN ----------------------
class CustomerQueueScreen extends StatefulWidget {
  final String queueId;
  
  const CustomerQueueScreen({super.key, required this.queueId});

  @override
  State<CustomerQueueScreen> createState() => _CustomerQueueScreenState();
}

class _CustomerQueueScreenState extends State<CustomerQueueScreen> {
  Timer? _timer;
  Duration _remainingTime = const Duration(minutes: 15);
  bool _isTimerActive = true;
  DateTime? _queueStartTime;

  @override
  void initState() {
    super.initState();
    _initializeTimer();
    _startTimer();
  }

  void _initializeTimer() async {
    try {
      // ดึงข้อมูลคิวจาก Firebase เพื่อใช้เวลาที่สร้างคิว
      final queueData = await QueueController().getQueueById(widget.queueId);
      if (queueData != null) {
        _queueStartTime = queueData.createdAt;
        _calculateRemainingTime();
      } else {
        // หากไม่พบข้อมูล ให้ใช้เวลาปัจจุบัน
        _queueStartTime = DateTime.now();
        _calculateRemainingTime();
      }
    } catch (e) {
      print('Error getting queue data: $e');
      // หากเกิดข้อผิดพลาด ให้ใช้เวลาปัจจุบัน
      _queueStartTime = DateTime.now();
      _calculateRemainingTime();
    }
  }

  void _calculateRemainingTime() {
    if (_queueStartTime != null) {
      final elapsed = DateTime.now().difference(_queueStartTime!);
      final totalDuration = const Duration(minutes: 15);
      
      if (elapsed < totalDuration) {
        _remainingTime = totalDuration - elapsed;
        _isTimerActive = true;
      } else {
        _remainingTime = Duration.zero;
        _isTimerActive = false;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && _queueStartTime != null) {
        setState(() {
          // คำนวณเวลาที่ผ่านไปจากเวลาที่สร้างคิว
          final elapsed = DateTime.now().difference(_queueStartTime!);
          final totalDuration = const Duration(minutes: 15);
          
          if (elapsed < totalDuration) {
            _remainingTime = totalDuration - elapsed;
            _isTimerActive = true;
          } else {
            _remainingTime = Duration.zero;
            _isTimerActive = false;
            timer.cancel();
          }
        });
      }
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📱 สถานะคิวของฉัน'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<QueueItem?>(
        future: QueueController().getQueueById(widget.queueId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('ไม่พบข้อมูลคิว'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('กลับ'),
                  ),
                ],
              ),
            );
          }

          final queue = snapshot.data!;
          return _buildQueueStatus(context, queue);
        },
      ),
    );
  }

  Widget _buildQueueStatus(BuildContext context, QueueItem queue) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (queue.status) {
      case 'waiting':
        statusColor = Colors.orange;
        statusText = 'รอเรียก';
        statusIcon = Icons.access_time;
        break;
      case 'called':
        statusColor = Colors.blue;
        statusText = 'กำลังเรียก';
        statusIcon = Icons.call;
        break;
      case 'completed':
        statusColor = Colors.green;
        statusText = 'เสร็จสิ้น';
        statusIcon = Icons.check_circle;
        break;
      default:
        statusColor = Colors.grey;
        statusText = 'ไม่ทราบสถานะ';
        statusIcon = Icons.help;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
           // หมายเลขคิว
           Container(
             width: double.infinity,
             padding: const EdgeInsets.all(16),
             decoration: BoxDecoration(
               color: statusColor.withOpacity(0.1),
               borderRadius: BorderRadius.circular(16),
               border: Border.all(color: statusColor, width: 2),
             ),
             child: Column(
               children: [
                 Icon(statusIcon, size: 48, color: statusColor),
                 const SizedBox(height: 16),
                 Text(
                   'โต๊ะที่ ${queue.tableNumber}',
                   style: TextStyle(
                     fontSize: 32,
                     fontWeight: FontWeight.bold,
                     color: statusColor,
                   ),
                 ),
                 const SizedBox(height: 8),
                 Text(
                   'หมายเลขคิว: ${queue.id}',
                   style: TextStyle(
                     fontSize: 14,
                     color: statusColor.withOpacity(0.8),
                   ),
                 ),
                 const SizedBox(height: 8),
                 Container(
                   padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                   decoration: BoxDecoration(
                     color: statusColor,
                     borderRadius: BorderRadius.circular(20),
                   ),
                   child: Text(
                     statusText,
                     style: const TextStyle(
                       color: Colors.white,
                       fontWeight: FontWeight.bold,
                       fontSize: 16,
                     ),
                   ),
                 ),
                 const SizedBox(height: 12),
                 // เวลาถอยหลัง
                 Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: _isTimerActive 
                         ? (_remainingTime.inMinutes < 5 ? Colors.red.withOpacity(0.1) : Colors.orange.withOpacity(0.1))
                         : Colors.grey.withOpacity(0.1),
                     borderRadius: BorderRadius.circular(12),
                     border: Border.all(
                       color: _isTimerActive 
                           ? (_remainingTime.inMinutes < 5 ? Colors.red : Colors.orange)
                           : Colors.grey,
                       width: 2,
                     ),
                   ),
                   child: Column(
                     children: [
                       Icon(
                         _isTimerActive ? Icons.timer : Icons.timer_off,
                         size: 24,
                         color: _isTimerActive 
                             ? (_remainingTime.inMinutes < 5 ? Colors.red : Colors.orange)
                             : Colors.grey,
                       ),
                       const SizedBox(height: 8),
                       Text(
                         _isTimerActive ? 'เวลาที่เหลือ' : 'หมดเวลาแล้ว',
                         style: TextStyle(
                           fontSize: 14,
                           color: _isTimerActive 
                               ? (_remainingTime.inMinutes < 5 ? Colors.red : Colors.orange)
                               : Colors.grey,
                           fontWeight: FontWeight.w500,
                         ),
                       ),
                       const SizedBox(height: 4),
                       Text(
                         _formatDuration(_remainingTime),
                         style: TextStyle(
                           fontSize: 24,
                           fontWeight: FontWeight.bold,
                           color: _isTimerActive 
                               ? (_remainingTime.inMinutes < 5 ? Colors.red : Colors.orange)
                               : Colors.grey,
                         ),
                       ),
                       if (_isTimerActive && _remainingTime.inMinutes < 5)
                         const Padding(
                           padding: EdgeInsets.only(top: 8),
                           child: Text(
                             '⚠️ ใกล้หมดเวลาแล้ว!',
                             style: TextStyle(
                               fontSize: 12,
                               color: Colors.red,
                               fontWeight: FontWeight.bold,
                             ),
                           ),
                         ),
                       if (!_isTimerActive)
                         Padding(
                           padding: const EdgeInsets.only(top: 8),
                           child: ElevatedButton.icon(
                             onPressed: () {
                               setState(() {
                                 _queueStartTime = DateTime.now();
                                 _remainingTime = const Duration(minutes: 15);
                                 _isTimerActive = true;
                                 _startTimer();
                               });
                             },
                             icon: const Icon(Icons.refresh, size: 16),
                             label: const Text('รีเซ็ตเวลา'),
                             style: ElevatedButton.styleFrom(
                               backgroundColor: Colors.deepOrange,
                               foregroundColor: Colors.white,
                               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                             ),
                           ),
                         ),
                     ],
                   ),
                 ),
               ],
             ),
           ),
          const SizedBox(height: 16),

          // ข้อมูลลูกค้า
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ข้อมูลลูกค้า',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.person, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Text('โต๊ะที่ ${queue.tableNumber}', style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.phone, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Text('โต๊ะที่ ${queue.tableNumber}', style: const TextStyle(fontSize: 16)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.access_time, color: Colors.deepOrange),
                      const SizedBox(width: 8),
                      Text(
                        'สั่งเมื่อ ${_formatDateTime(queue.createdAt)}',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // รายการอาหาร
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'รายการอาหาร',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  ...queue.orders.map((order) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(order.name),
                            ),
                            Text('${order.price} บาท'),
                          ],
                        ),
                        if (order.note != null && order.note!.isNotEmpty && order.note!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, left: 8),
                            child: Text(
                              '📝 ${order.note}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'รวมทั้งหมด',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${queue.orders.fold(0, (sum, order) => sum + order.price)} บาท',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.deepOrange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
           ),
           const SizedBox(height: 16),

           // ปุ่มกลับ
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              label: const Text('กลับ'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

// ---------------------- MENU DETAIL SCREEN -----------------------
class MenuDetailScreen extends StatelessWidget {
  final String name;
  final int price;
  final String image;

  const MenuDetailScreen({
    super.key,
    required this.name,
    required this.price,
    required this.image,
  });

  void orderNoodle(BuildContext context) async {
    final Map<String, bool>? options = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VegetableOptionScreen(name: name),
      ),
    );

    if (options != null) {
      OrderController().addOrder(
        name,
        price,
        noVegetable: options['noVegetable']!,
        isSpecial: options['isSpecial']!,
      );
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '📦 รับออเดอร์: $name (${options['isSpecial']! ? 'พิเศษ' : 'ธรรมดา'} / ${options['noVegetable']! ? 'ไม่ใส่ผัก' : 'ใส่ผัก'})',
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('รายละเอียดเมนู')),  
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Image.network(image, width: 120, height: 120),
            const SizedBox(height: 20),
            Text(name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('ราคา $price บาท', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () => orderNoodle(context),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('สั่งเมนูนี้'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
                ),
              ],
            ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showQueueDialog(context),
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.queue, color: Colors.white),
        label: const Text(
          'เรียกคิว',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }


  void _showQueueDialog(BuildContext context) async {
    final TextEditingController tableNumberController = TextEditingController();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('🪑 หมายเลขโต๊ะ'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('กรุณากรอกหมายเลขโต๊ะของคุณ'),
            const SizedBox(height: 16),
            TextField(
              controller: tableNumberController,
              decoration: const InputDecoration(
                labelText: 'หมายเลขโต๊ะ',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.table_restaurant),
                hintText: 'เช่น 1, 2, 3, A1, B2',
              ),
              keyboardType: TextInputType.text,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () {
              if (tableNumberController.text.trim().isNotEmpty) {
                Navigator.pop(context, tableNumberController.text.trim());
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('กรุณากรอกหมายเลขโต๊ะ'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('ยืนยัน', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        print('Starting queue process for table: $result');
        final currentOrders = OrderController().orders;
        print('Current orders count: ${currentOrders.length}');
        
        // หากไม่มีออเดอร์ใน local list ให้สร้างออเดอร์ตัวอย่าง
        List<OrderItem> ordersToQueue = currentOrders;
        if (ordersToQueue.isEmpty) {
          print('No orders in local list, creating sample order');
          ordersToQueue = [
            OrderItem(
              name: 'ก๋วยเตี๋ยวชุดที่2 สด เปื่อย ปีก',
              price: 70,
              noVegetable: false,
              isSpecial: false,
              noodleType: 'หมี่ขาว',
            ),
          ];
        }
        
        final queueResult = await QueueController().addToQueue(
          'โต๊ะ $result',
          'โต๊ะ $result',
          ordersToQueue,
          int.parse(result),
        );

        print('Queue result: $queueResult');
        final queueId = queueResult['id'];
        final queueNumber = queueResult['queueNumber'];

        // ล้างออเดอร์หลังจากเพิ่มคิวแล้ว
        OrderController().clear();

        // แสดงผลลัพธ์
        if (context.mounted) {
          // แสดง dialog หมายเลขคิว
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('🎉 รับคิวเรียบร้อย!'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('หมายเลขคิวของคุณคือ'),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$queueNumber',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'กรุณารอเรียกคิว\nหรือดูสถานะได้ที่หน้าถัดไป',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'หมายเลขคิว: $queueId',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context); // ปิด dialog
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CustomerQueueScreen(queueId: queueId),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ดูสถานะคิว'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        print('Error in queue process: $e');
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('❌ เกิดข้อผิดพลาด'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('ไม่สามารถเรียกคิวได้'),
                  const SizedBox(height: 16),
                  Text(
                    'ข้อผิดพลาด: $e',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'กรุณาตรวจสอบ:\n1. การเชื่อมต่ออินเทอร์เน็ต\n2. การตั้งค่า Firebase\n3. Firestore Rules',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ตกลง'),
                ),
              ],
            ),
          );
        }
      }
    }
  }
}

// --------------------- PAGER CONTROL SCREEN -------------------------
class PagerControlScreen extends StatefulWidget {
  const PagerControlScreen({super.key});

  @override
  State<PagerControlScreen> createState() => _PagerControlScreenState();
}

class _PagerControlScreenState extends State<PagerControlScreen> {
  final PagerTableController _controller = PagerTableController();
  StreamSubscription? _queueSubscription;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTableStatus();
    _startListening();
  }

  @override
  void dispose() {
    _queueSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTableStatus() async {
    await _controller.loadTableStatus();
    setState(() {
      _isLoading = false;
    });
  }

  void _startListening() {
    _queueSubscription = FirebaseFirestore.instance
        .collection('pager_queue')
        .doc('status')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data()!;
        setState(() {
          _controller.currentTable = data['currentTable'] ?? 0;
          _controller.waitingTables = List<int>.from(data['waitingTables'] ?? []);
          _controller.tableActive = data['tableActive'] ?? false;
          _controller.callCount = data['callCount'] ?? 0;
          
          if (data['lastCallTime'] != null) {
            _controller.lastCallTime = DateTime.parse(data['lastCallTime']);
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🎮 ควบคุมระบบคิวผ่านเพจเจอร์'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _loadTableStatus,
            icon: const Icon(Icons.refresh),
            tooltip: 'รีเฟรชข้อมูล',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 20),
                  _buildQueueControls(),
                  const SizedBox(height: 20),
                  _buildWaitingQueue(),
                  const SizedBox(height: 20),
                  _buildStatistics(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _controller.tableActive ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: _controller.tableActive ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'สถานะระบบโต๊ะ',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'โต๊ะปัจจุบัน',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      _controller.currentTable == 0 ? 'ไม่มี' : 'โต๊ะที่ ${_controller.currentTable}',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: _controller.currentTable == 0 ? Colors.grey : Colors.deepOrange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'โต๊ะที่รอ',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '${_controller.waitingTables.length} โต๊ะ',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (_controller.lastCallTime != null) ...[
              const SizedBox(height: 8),
              Text(
                'เรียกล่าสุด: ${_formatTime(_controller.lastCallTime!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildQueueControls() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🎮 ควบคุมคิว',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildControlButton(
                  'เรียกโต๊ะถัดไป',
                  Icons.skip_next,
                  Colors.blue,
                  _controller.waitingTables.isNotEmpty ? _controller.callNextTable : null,
                ),
                _buildControlButton(
                  'เรียกโต๊ะซ้ำ',
                  Icons.replay,
                  Colors.orange,
                  _controller.currentTable > 0 ? _controller.repeatTable : null,
                ),
                _buildControlButton(
                  'รีเซ็ตโต๊ะ',
                  Icons.refresh,
                  Colors.red,
                  _controller.resetTable,
                ),
                _buildControlButton(
                  'ล้างโต๊ะที่รอ',
                  Icons.clear_all,
                  Colors.purple,
                  _controller.waitingTables.isNotEmpty ? _controller.clearWaitingTables : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runAction(String label, Future<void> Function() action) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label สำเร็จ'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label ล้มเหลว: $e'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildControlButton(String label, IconData icon, Color color, Future<void> Function()? onPressed) {
    return SizedBox(
      width: 150,
      child: ElevatedButton.icon(
        onPressed: onPressed == null ? null : () => _runAction(label, onPressed),
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildWaitingQueue() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⏳ โต๊ะที่รอ (${_controller.waitingTables.length} โต๊ะ)',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_controller.waitingTables.isEmpty)
              const Text(
                'ไม่มีโต๊ะที่รอ',
                style: TextStyle(color: Colors.grey),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _controller.waitingTables.map((tableNumber) {
                  return GestureDetector(
                    onTap: () => _runAction('เรียกโต๊ะ $tableNumber', () => _controller.callTable(tableNumber)),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Text(
                        'โต๊ะที่ $tableNumber',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatistics() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '📊 สถิติการใช้งาน',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('เรียกโต๊ะทั้งหมด', '${_controller.callCount} ครั้ง', Icons.call),
                _buildStatItem('โต๊ะที่รอ', '${_controller.waitingTables.length} โต๊ะ', Icons.table_restaurant),
                _buildStatItem('สถานะ', _controller.tableActive ? 'ใช้งาน' : 'หยุด', Icons.power),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.deepOrange, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.deepOrange,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}