// lib/models/user_model.dart

class UserModel {
  final String uid;
  final String email;
  final String name;
  final String unit;
  final String role; // 'user' veya 'admin'
  final Map<String, bool> preferences;

  UserModel({
    required this.uid,
    required this.email,
    required this.name,
    required this.unit,
    required this.role,
    required this.preferences,
  });

 
factory UserModel.fromMap(Map<String, dynamic> map, String id) {
  return UserModel(
    uid: id,
    name: map['name'] ?? '',
    email: map['email'] ?? '',
    role: map['role'] ?? 'user',
    unit: map['unit'] ?? '',
    
    preferences: Map<String, bool>.from(map['preferences'] ?? {
      'health': true,
      'technical': true,
    }),
  );
}
  

  // Firestore'a veri yazmak için
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'name': name,
      'unit': unit,
      'preferences': preferences,
      'role': role,
      'createdAt': DateTime.now().toUtc(),
    };
  }
}