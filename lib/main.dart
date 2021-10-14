import 'package:centaur/centaur_scene.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  CentaurScene? _scene;

  @override
  void initState() {
    RiveFile.asset('assets/centaur.riv').then((riveFile) {
      setState(() {
        _scene = CentaurScene(riveFile);
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: _scene == null
          ? const SizedBox.shrink()
          : GestureDetector(
              onTapDown: (details) => _scene?.fire(),
              child: MouseRegion(
                onHover: (hoverEvent) {
                  _scene?.cursor = hoverEvent.localPosition;
                },
                child: RawKeyboardListener(
                  autofocus: true,
                  focusNode: FocusNode(),
                  onKey: (RawKeyEvent event) {
                    if (_scene == null) {
                      return;
                    }
                    var modifier = 1;
                    if (event is RawKeyDownEvent) {
                      modifier = -1;
                    }

                    if (event.physicalKey == PhysicalKeyboardKey.keyA) {
                      _scene!.direction += modifier;
                    } else if (event.physicalKey == PhysicalKeyboardKey.keyD) {
                      _scene!.direction -= modifier;
                    }
                  },
                  child: RiveScene(
                    controller: _scene!,
                    fit: BoxFit.contain,
                    alignment: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
    );
  }
}
