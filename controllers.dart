import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'order_item.dart';

class PagerTableController {
  int currentTable = 0;
  List<int> waitingTables = [];
  bool tableActive = false;
  DateTime? lastCallTime;
  int callCount = 0;
  final AudioPlayer _audioPlayer = AudioPlayer();

  static const String esp32BaseUrl =
      'http://esp32.local'; // mDNS ไม่ต้องเปลี่ยน IP อีกต่อไป // IP ของ ESP32

  Future<void> callTable(int tableNumber) async {
    if (tableNumber < 1 || tableNumber > 12) return;

    print('DEBUG: PagerTableController.callTable($tableNumber) เริ่มทำงาน');

    currentTable = tableNumber;
    tableActive = true;
    lastCallTime = DateTime.now();
    callCount++;

    print('DEBUG: ตั้งค่า currentTable=$currentTable, tableActive=$tableActive');

    if (!waitingTables.contains(tableNumber)) {
      waitingTables.add(tableNumber);
    }

    await _triggerPager(tableNumber);
    await _playNotificationSound();

    print('DEBUG: กำลังอัปเดต Firestore...');
    await _updateTableStatus();
    print('DEBUG: อัปเดต Firestore เรียบร้อย');
  }

  Future<void> callNextTable() async {
    if (waitingTables.isEmpty) return;

    int nextTable = waitingTables.removeAt(0);
    await callTable(nextTable);
  }

  Future<void> repeatTable() async {
    if (currentTable == 0) return;

    lastCallTime = DateTime.now();
    await _triggerPager(currentTable);
    await _playNotificationSound();
    await _updateTableStatus();
  }

  Future<void> resetTable() async {
    currentTable = 0;
    waitingTables.clear();
    tableActive = false;
    lastCallTime = null;
    callCount = 0;
    await _updateTableStatus();
  }

  Future<void> clearWaitingTables() async {
    waitingTables.clear();
    await _updateTableStatus();
  }

  Future<void> _playNotificationSound() async {
    try {
      await _audioPlayer.play(AssetSource('sounds/notification.mp3'));
    } catch (e) {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _triggerPager(int queueNumber) async {
    try {
      final isWeb = kIsWeb;
      final scheme = Uri.base.scheme;
      final host = Uri.base.host;

      final isHttps = isWeb &&
          (scheme == 'https' ||
              host.contains('.web.app') ||
              host.contains('.firebaseapp.com') ||
              host.contains('project-fire-baseaapp') ||
              (host != 'localhost' && host != '127.0.0.1'));

      print('DEBUG: _triggerPager($queueNumber)');
      print('DEBUG: - kIsWeb: $isWeb');
      print('DEBUG: - scheme: $scheme');
      print('DEBUG: - host: $host');
      print('DEBUG: - isHttps: $isHttps');

      if (isHttps) {
        print(
            'DEBUG: ✅ ใช้ Firestore เพื่อส่งคำสั่งไป ESP32 (HTTPS mode)');
        print('DEBUG: URL: ${Uri.base}');
        await _triggerPagerViaFirestore(queueNumber);
      } else {
        final uri = Uri.parse('$esp32BaseUrl/buzz?id=$queueNumber');
        print('DEBUG: ส่ง HTTP request ไปที่ ESP32: $uri');
        print('DEBUG: Platform: ${kIsWeb ? "Web" : "Mobile"}');

        final res = await http.get(uri, headers: {}).timeout(
              const Duration(seconds: 5),
            );

        print('DEBUG: ESP32 response status: ${res.statusCode}');
        print('DEBUG: ESP32 response body: ${res.body}');

        if (res.statusCode == 200) {
          print(
              'DEBUG: ✅ ESP32 เรียกคิวสำเร็จ (โต๊ะ $queueNumber)');
        } else {
          print(
              'DEBUG: ⚠️ ESP32 response error ${res.statusCode}: ${res.body}');
          debugPrint(
              'ESP32 response ${res.statusCode}: ${res.body}');
        }
      }
    } catch (e, stackTrace) {
      print('DEBUG: ❌ Failed to trigger pager: $e');
      print('DEBUG: Stack trace: $stackTrace');
      debugPrint('Failed to trigger pager: $e');
      debugPrint('Stack trace: $stackTrace');

      String errorMessage = e.toString();
      if (errorMessage.contains('Load failed') ||
          errorMessage.contains('NetworkException') ||
          errorMessage.contains('SocketException') ||
          errorMessage.contains('Failed host lookup') ||
          errorMessage.contains('Mixed Content')) {
        throw Exception(
            'ไม่สามารถเชื่อมต่อ ESP32 ได้\n\n'
            'กรุณาตรวจสอบ:\n'
            '1. โทรศัพท์เชื่อมต่อ WiFi เดียวกับ ESP32\n'
            '2. ปิด Mobile Data และใช้ WiFi เท่านั้น\n'
            '3. ESP32 IP: $esp32BaseUrl\n'
            '4. ทดสอบเปิด: $esp32BaseUrl/status ในเบราว์เซอร์\n\n'
            'หมายเหตุ: แอพ HTTPS ใช้ Firestore เป็นสื่อกลาง\n\n'
            'Error: $e');
      }

      rethrow;
    }
  }

  Future<void> _triggerPagerViaFirestore(int queueNumber) async {
    try {
      print('DEBUG: เขียนคำสั่งลง Firestore สำหรับ ESP32');
      print('DEBUG: Table Number: $queueNumber');

      try {
        final oldCommands = await FirebaseFirestore.instance
            .collection('esp32_commands')
            .where('status', isEqualTo: 'completed')
            .orderBy('createdAt', descending: true)
            .limit(100)
            .get();

        if (oldCommands.docs.length > 5) {
          final toDelete = oldCommands.docs.skip(5);
          final batch = FirebaseFirestore.instance.batch();
          for (var doc in toDelete) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          print(
              'DEBUG: ลบคำสั่งเก่า ${toDelete.length} รายการ');
        }
      } catch (e) {
        print(
            'DEBUG: ⚠️ ไม่สามารถลบคำสั่งเก่าได้: $e (ไม่เป็นไร)');
      }

      try {
        final allPending = await FirebaseFirestore.instance
            .collection('esp32_commands')
            .where('status', isEqualTo: 'pending')
            .get();

        if (allPending.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (var doc in allPending.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          print(
              'DEBUG: ลบคำสั่ง pending เก่าทั้งหมด ${allPending.docs.length} รายการ (เพื่อให้ ESP32 อ่านคำสั่งใหม่ได้แน่นอน)');
        }
      } catch (e) {
        print(
            'DEBUG: ⚠️ ไม่สามารถลบคำสั่ง pending เก่าได้: $e (ไม่เป็นไร)');
      }

      final docRef = await FirebaseFirestore.instance
          .collection('esp32_commands')
          .add({
        'tableNumber': queueNumber,
        'command': 'buzz',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });

      print('DEBUG: ✅ ส่งคำสั่งไป ESP32 ผ่าน Firestore สำเร็จ');
      print('DEBUG: Document ID: ${docRef.id}');
      print('DEBUG: Table Number: $queueNumber');
      print(
          'DEBUG: ESP32 จะอ่านคำสั่งจาก Firestore และเรียก HTTP endpoint เอง');
      print('DEBUG: ตรวจสอบ Firestore collection: esp32_commands');

      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e, stackTrace) {
      print('DEBUG: ❌ Failed to write to Firestore: $e');
      print('DEBUG: Stack trace: $stackTrace');
      throw Exception(
          'ไม่สามารถส่งคำสั่งไป ESP32 ผ่าน Firestore ได้: $e');
    }
  }

  Future<void> _updateTableStatus() async {
    try {
      print(
          'DEBUG: กำลังเขียน Firestore - currentTable: $currentTable, tableActive: $tableActive');

      await FirebaseFirestore.instance
          .collection('pager_queue')
          .doc('status')
          .set({
        'currentTable': currentTable,
        'waitingTables': waitingTables,
        'tableActive': tableActive,
        'lastCallTime': lastCallTime?.toIso8601String(),
        'callCount': callCount,
        'updatedAt': DateTime.now().toIso8601String(),
      });

      print('DEBUG: เขียน Firestore สำเร็จ');
    } catch (e) {
      print('DEBUG: Error updating table status: $e');
      debugPrint('Error updating table status: $e');
    }
  }

  Future<void> loadTableStatus() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('pager_queue')
          .doc('status')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        currentTable = data['currentTable'] ?? 0;
        waitingTables = List<int>.from(data['waitingTables'] ?? []);
        tableActive = data['tableActive'] ?? false;
        callCount = data['callCount'] ?? 0;

        if (data['lastCallTime'] != null) {
          lastCallTime = DateTime.parse(data['lastCallTime']);
        }
      }
    } catch (e) {
      debugPrint('Error loading table status: $e');
    }
  }
}

class OrderController {
  static final OrderController _instance = OrderController._internal();
  factory OrderController() => _instance;
  OrderController._internal();

  final List<OrderItem> _orders = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void addOrder(
    String name,
    int price, {
    bool noVegetable = false,
    bool isSpecial = false,
    String? noodleType,
    String? eggType,
    String? note,
  }) async {
    final orderItem = OrderItem(
      name: name,
      price: price,
      noVegetable: noVegetable,
      isSpecial: isSpecial,
      noodleType: noodleType,
      eggType: eggType,
      note: note,
    );

    _orders.add(orderItem);
    print(
        'Added order to local list: ${orderItem.name}, Total orders: ${_orders.length}');

    try {
      await _firestore.collection('order_details').add(orderItem.toMap());
      print('Order saved to Firestore successfully');
    } catch (e) {
      print('⚠️ Error saving order to Firestore: $e');
      print(
          '⚠️ Order saved locally only (no internet connection)');
    }
  }

  List<OrderItem> get orders => _orders;

  int get total =>
      _orders.fold(0, (sum, item) => sum + item.price);

  void clear() {
    _orders.clear();
  }

  void removeOrderAt(int index) {
    if (index >= 0 && index < _orders.length) {
      _orders.removeAt(index);
      print(
          'Removed order at index $index, Remaining orders: ${_orders.length}');
    }
  }

  Future<List<OrderItem>> loadOrdersFromFirestore() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('order_details')
          .orderBy('timestamp', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        Map<String, dynamic> data =
            doc.data() as Map<String, dynamic>;
        return OrderItem(
          name: data['name'] ?? '',
          price: data['price'] ?? 0,
          noVegetable: data['noVegetable'] ?? false,
          isSpecial: data['isSpecial'] ?? false,
          noodleType: data['noodleType'],
          eggType: data['eggType'],
          note: data['note'],
        );
      }).toList();
    } catch (e) {
      print('Error loading orders from Firestore: $e');
      return [];
    }
  }
}

class QueueController {
  static final QueueController _instance = QueueController._internal();
  factory QueueController() => _instance;
  QueueController._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> addToQueue(
    String customerName,
    String phoneNumber,
    List<OrderItem> orders,
    int tableNumber,
  ) async {
    try {
      print('Starting to add queue for: $customerName');

      try {
        await _firestore.collection('queue').limit(1).get();
        print('Firebase connection is working');
      } catch (e) {
        print('Firebase connection error: $e');
        throw Exception(
            'ไม่สามารถเชื่อมต่อ Firebase ได้: $e');
      }

      final queueNumber = await _getNextQueueNumber();
      print('Got queue number: $queueNumber');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final shortId =
          (timestamp % 1000).toString().padLeft(3, '0');

      final queueItem = QueueItem(
        id: shortId,
        customerName: customerName,
        phoneNumber: phoneNumber,
        orders: orders,
        createdAt: DateTime.now(),
        queueNumber: queueNumber,
        tableNumber: tableNumber,
      );

      print('Creating queue item with ID: ${queueItem.id}');
      print('Queue data: ${queueItem.toMap()}');

      await _firestore
          .collection('queue')
          .doc(queueItem.id)
          .set(queueItem.toMap());
      print('Successfully saved to Firestore');

      final doc = await _firestore
          .collection('queue')
          .doc(queueItem.id)
          .get();
      if (!doc.exists) {
        throw Exception('ข้อมูลไม่ถูกบันทึกใน Firestore');
      }
      print('Verified data exists in Firestore');

      return {
        'id': queueItem.id,
        'queueNumber': queueItem.queueNumber,
      };
    } catch (e) {
      print('Error adding to queue: $e');
      print('Error type: ${e.runtimeType}');
      rethrow;
    }
  }

  Future<int> _getNextQueueNumber() async {
    try {
      print('Getting next queue number from counter...');
      final counterRef =
          _firestore.collection('meta').doc('queue_counter');
      final today = DateTime.now()
          .toIso8601String()
          .split('T')[0];

      return await _firestore
          .runTransaction<int>((transaction) async {
        final snapshot = await transaction.get(counterRef);
        Map<String, dynamic> data = {};

        if (snapshot.exists) {
          data = snapshot.data() as Map<String, dynamic>;
        }

        final lastResetDate = data['lastResetDate'] as String?;
        int current = 0;

        if (lastResetDate != today) {
          print(
              'New day detected, resetting queue counter');
          current = 0;
          data = {
            'current': current,
            'lastResetDate': today,
          };
          transaction.set(counterRef, data);
        } else {
          current = (data['current'] ?? 0) as int;
        }

        final next = current + 1;
        data['current'] = next;
        transaction.update(counterRef, data);
        return next;
      });
    } catch (e) {
      print('Error getting next queue number: $e');
      print('Error type: ${e.runtimeType}');
      return 1;
    }
  }

  Future<void> resetQueueNumber() async {
    try {
      final counterRef =
          _firestore.collection('meta').doc('queue_counter');
      await counterRef.set({'current': 0});
    } catch (e) {
      print('Error resetting queue number: $e');
      rethrow;
    }
  }

  Stream<List<QueueItem>> getQueueStream() {
    return _firestore
        .collection('queue')
        .orderBy('queueNumber')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => QueueItem.fromMap(doc.data()))
            .toList());
  }

  Stream<List<QueueItem>> getQueueStreamByDate(DateTime day) {
    final DateTime startOfDay =
        DateTime(day.year, day.month, day.day);
    final DateTime startOfNextDay =
        startOfDay.add(const Duration(days: 1));

    return _firestore
        .collection('queue')
        .where('createdAt',
            isGreaterThanOrEqualTo:
                startOfDay.toIso8601String())
        .where('createdAt',
            isLessThan: startOfNextDay.toIso8601String())
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => QueueItem.fromMap(doc.data()))
            .toList());
  }

  Future<QueueItem?> getQueueById(String id) async {
    try {
      final doc =
          await _firestore.collection('queue').doc(id).get();
      if (doc.exists) {
        return QueueItem.fromMap(doc.data()!);
      }
      return null;
    } catch (e) {
      print('Error getting queue by ID: $e');
      return null;
    }
  }

  Future<void> callQueue(String id, {int? tableNumber}) async {
    try {
      await _firestore.collection('queue').doc(id).update({
        'status': 'called',
      });

      int pagerNumber = tableNumber ?? 0;
      if (pagerNumber <= 0) {
        final doc =
            await _firestore.collection('queue').doc(id).get();
        if (doc.exists) {
          pagerNumber =
              (doc.data()?['tableNumber'] ?? 0) as int;
        }
      }

      if (pagerNumber > 0) {
        await PagerTableController().callTable(pagerNumber);
      }
    } catch (e) {
      print('Error calling queue: $e');
      rethrow;
    }
  }

  Future<void> completeQueue(String id) async {
    try {
      await _firestore.collection('queue').doc(id).update({
        'status': 'completed',
      });
    } catch (e) {
      print('Error completing queue: $e');
      rethrow;
    }
  }

  Future<void> deleteQueue(String id) async {
    try {
      await _firestore.collection('queue').doc(id).delete();
    } catch (e) {
      print('Error deleting queue: $e');
      rethrow;
    }
  }
}

class AppState {
  AppState._internal();
  static final AppState _instance = AppState._internal();
  factory AppState() => _instance;

  String? selectedTableNumber;

  void setSelectedTable(String? table) {
    selectedTableNumber =
        table?.trim().isEmpty == true ? null : table?.trim();
  }
}

