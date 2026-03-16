import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'screens/test_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DemoPage(),
    );
  }
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  String result = "아직 호출 안함";

  Future<void> callDemo() async {
    final response = await http.post(
      Uri.parse("http://localhost:8080/demo"),
    );

    if (response.statusCode == 200) {
      setState(() {
        result = response.body;
      });
    } else {
      setState(() {
        result = "에러: ${response.statusCode}";
      });
    }
  }

  void moveTestPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TestPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SpringBoot Test"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              result,
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: callDemo,
              child: const Text("서버 호출"),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: moveTestPage,
              child: const Text("테스트 페이지 이동"),
            ),
          ],
        ),
      ),
    );
  }
}