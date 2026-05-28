class OrderItem {
  final String name;
  final int price;
  final bool noVegetable;
  final bool isSpecial;
  final String? noodleType;
  final String? eggType;
  final String? note; // เพิ่ม note

  OrderItem({
    required this.name,
    required this.price,
    this.noVegetable = false,
    this.isSpecial = false,
    this.noodleType,
    this.eggType,
    this.note, // เพิ่ม note
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'price': price,
      'noVegetable': noVegetable,
      'isSpecial': isSpecial,
      'noodleType': noodleType,
      'eggType': eggType,
      'note': note,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      name: map['name'] ?? '',
      price: map['price'] ?? 0,
      noVegetable: map['noVegetable'] ?? false,
      isSpecial: map['isSpecial'] ?? false,
      noodleType: map['noodleType'],
      eggType: map['eggType'],
      note: map['note'],
    );
  }
}

