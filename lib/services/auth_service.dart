import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _userCollection = 'users';

  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
    required String unit,
  }) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = userCredential.user;

      if (user != null) {
        UserModel newUser = UserModel(
          uid: user.uid,
          email: email,
          name: name,
          unit: unit,
          role: 'user',
          preferences: {
            'health': true,
            'technical': true,
          },
        );
        await _firestore.collection(_userCollection).doc(user.uid).set(newUser.toMap());
        return newUser;
      }
    } on FirebaseAuthException {
      rethrow;
    }
    return null;
  }

  Future<UserModel?> signIn({required String email, required String password}) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = userCredential.user;

      if (user != null) {
        DocumentSnapshot doc = await _firestore.collection(_userCollection).doc(user.uid).get();

        if (!doc.exists) {
          await Future.delayed(const Duration(milliseconds: 700));
          doc = await _firestore.collection(_userCollection).doc(user.uid).get();
        }

        if (doc.exists) {
          return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        } else {
          throw Exception('Kullanıcı bilgisi Firestore\'da bulunamadı.');
        }
      }
    } on FirebaseAuthException {
      rethrow;
    } catch (e) {
      rethrow;
    }
    return null;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<void> resetPassword({required String email}) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  Future<UserModel?> getUserModelFromFirestore(String uid) async {
    DocumentSnapshot doc = await _firestore.collection(_userCollection).doc(uid).get();

    if (doc.exists) {
      return UserModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    } else {
      throw Exception('Kullanıcı rol bilgisi Firestore\'da bulunamadı (Oturum kontrolü).');
    }
  }
}