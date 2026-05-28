import 'order_item.dart';

class QueueItem {
  final String id;
  final String customerName;
  final String phoneNumber;
  final List<OrderItem> orders;
  final DateTime createdAt;
  final String status; // 'waiting', 'called', 'completed'
  final int queueNumber;
  final int tableNumber;

  QueueItem({
    required this.id,
    required this.customerName,
    required this.phoneNumber,
    required this.orders,
    required this.createdAt,
    this.status = 'waiting',
    required this.queueNumber,
    required this.tableNumber,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'customerName': customerName,
      'phoneNumber': phoneNumber,
      'orders': orders.map((order) => order.toMap()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'queueNumber': queueNumber,
      'tableNumber': tableNumber,
    };
  }

  factory QueueItem.fromMap(Map<String, dynamic> map) {
    return QueueItem(
      id: map['id'] ?? '',
      customerName: map['customerName'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      orders: (map['orders'] as List<dynamic>?)
              ?.map((order) => OrderItem.fromMap(order))
              .toList() ??
          [],
      createdAt:
          DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      status: map['status'] ?? 'waiting',
      queueNumber: map['queueNumber'] ?? 0,
      tableNumber: map['tableNumber'] ?? 0,
    );
  }
}


