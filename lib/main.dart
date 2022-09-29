import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:test_app/download.dart';

const debug = true;
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterDownloader.initialize(
      debug: debug // optional: set false to disable printing logs to console
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        iconTheme: IconThemeData(
          color: Colors.black
        ),
        appBarTheme: AppBarTheme(
          color: Colors.orange.shade200,
          elevation: 0.0,
        ),
        primarySwatch: Colors.blue,
      ),
      home: Download(
        platform : platform
      ),
    );
  }
}
