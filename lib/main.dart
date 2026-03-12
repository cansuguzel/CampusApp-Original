import 'package:akilli_kampus_proje/views/main/main_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';

import 'view_models/auth_view_model.dart';
import 'view_models/notification_view_model.dart';

import 'views/auth/login_view.dart';
import 'views/main/home_page.dart';


const bool testMode = false;
const Widget testScreen = HomePage(); 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => NotificationViewModel()),
      ],

      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: testMode
            ? testScreen     
            : const RootRouter(), 
      ),
    );
  }
}

class RootRouter extends StatelessWidget {
  const RootRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, authViewModel, _) {
        if (authViewModel.currentUser == null) {
          return const LoginView();
        }

        final user = authViewModel.currentUser!;

        if (user.role.isEmpty) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

      if (user.role == "admin") {
  return const MainScreen(); 
} else {
  return const MainScreen(); 
}
      },
    );
  }
}




