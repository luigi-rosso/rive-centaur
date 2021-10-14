import 'dart:math';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:rive/rive.dart';
import 'package:rive/math.dart';
import 'package:rive/components.dart';

class CentaurScene extends RiveSceneController with ChangeNotifier {
  final RiveFile file;

  final Artboard character;
  final Artboard arrow;
  final Artboard apple;
  final Artboard background;

  late Node _target;
  late TransformComponent _characterRoot;
  late TransformComponent _arrowLocation;
  late StateMachineController _motionMachine;
  late SMITrigger _fireInput;
  late SMINumber _moveInput;

  final Set<_ArrowInstance> arrows = {};
  final Set<_AppleInstance> apples = {};

  double _currentMoveSpeed = 0;
  double _characterX = 0;
  double _characterDirection = 1;
  Offset cursor = Offset.zero;
  int _direction = 0;
  int get direction => _direction;
  set direction(int value) => _direction = value.clamp(-1, 1);
  final Mat2D _viewTransform = Mat2D();
  final Mat2D _inverseviewTransform = Mat2D();

  static const moveSpeed = 100;
  static const arrowSpeed = 3000;

  static const minApples = 1;
  static const maxApples = 5;
  static const appleRadius = 40;
  static const appleRadiusSquared = appleRadius * appleRadius;

  CentaurScene(this.file)
      : character = file.artboardByName('Character')!,
        arrow = file.artboardByName('Arrow')!,
        apple = file.artboardByName('Apple')!,
        background = file.artboardByName('Background_tile')!.instance() {
    // background doesn't animate, just set it up once.
    background.advance(0);

    // Mark the arrow as not needing framing, makes it easier to align instances
    // in world space.
    arrow.frameOrigin = false;

    _target = character.component('Look')!;
    _characterRoot = character.component('Character')!;
    _arrowLocation = character.component('ArrowLocation')!;
    _motionMachine = character.stateMachineByName('Motion')!;
    character.addController(_motionMachine);
    _fireInput = _motionMachine.findSMI('Fire');
    _moveInput = _motionMachine.findSMI('Move');
  }

  @override
  bool advance(double elapsedSeconds) {
    var targetMoveSpeed = _direction == 0
        ? 0
        : _direction > 0
            ? moveSpeed
            : -moveSpeed;
    _currentMoveSpeed +=
        (targetMoveSpeed - _currentMoveSpeed) * min(1, elapsedSeconds * 10);
    _characterX += elapsedSeconds * _currentMoveSpeed;

    bool spawnMoreApples = false;
    for (final apple in apples.toList(growable: false)) {
      apple.artboard.advance(elapsedSeconds);
      if (apple.isDone) {
        apples.remove(apple);
        spawnMoreApples = true;
      }
    }
    if (spawnMoreApples) {
      _spawnApples();
    }
    // Drive all the arrows forward.
    for (final arrow in arrows.toList(growable: false)) {
      // See if we hit any apple
      for (final apple in apples) {
        if (Vec2D.squaredDistance(apple.center, arrow.translation) <
            appleRadiusSquared) {
          apple.explode.fire();
        }
      }
      arrow.time += elapsedSeconds;

      Vec2D.scaleAndAdd(arrow.translation, arrow.translation, arrow.heading,
          elapsedSeconds * arrowSpeed);
      // Pull the arrow downwards.
      arrow.heading[1] += elapsedSeconds;
      Vec2D.normalize(arrow.heading, arrow.heading);
      if (arrow.time > 2) {
        arrows.remove(arrow);
      } else {
        arrow.artboard.advance(elapsedSeconds);
      }
    }

    // Get the cursor into scene space.
    var sceneCursor = Vec2D.transformMat2D(
        Vec2D(), Vec2D.fromValues(cursor.dx, cursor.dy), _inverseviewTransform);

    // Check if we should invert the character's direction by comparing
    // the world location of the cursor to the world location of the
    // character (need to compensate by character movement, characterX).
    _characterDirection =
        _characterRoot.worldTransform[4] < sceneCursor[0] - _characterX
            ? 1
            : -1;
    _characterRoot.scaleX = _characterDirection;

    // Set the move direction on the state machine.
    _moveInput.value = direction * _characterDirection;

    // Place the target at the cursor.
    // Get the parent world transform of the target "look" node.
    var targetParentWorld = _target.parentWorldTransform;
    Mat2D inverseTargetWorld = Mat2D();
    if (Mat2D.invert(inverseTargetWorld, targetParentWorld)) {
      _target.translation = Vec2D.transformMat2D(
          Vec2D(),
          Vec2D.fromValues(sceneCursor[0] - _characterX, sceneCursor[1]),
          inverseTargetWorld);
    }
    character.advance(elapsedSeconds);

    _spawnApples();

    return true;
  }

  void fire() {
    _fireInput.fire();
    // Assumes world scale of the arrow in each artboard matches.
    arrows.add(
      _ArrowInstance(
        artboard: arrow.instance(),
        transform: _arrowLocation.worldTransform,
        characterX: _characterX,
      ),
    );
  }

  @override
  void draw(Canvas canvas, Mat2D viewTransform) {
    /// Make a copy of it so advance can use the latest view transform.
    if (!Mat2D.areEqual(_viewTransform, viewTransform)) {
      Mat2D.copy(_viewTransform, viewTransform);
      Mat2D.invert(_inverseviewTransform, _viewTransform);
    }
    canvas.drawColor(const Color(0xFF6F8C9B), BlendMode.srcOver);
    canvas.save();
    canvas.scale(1.3);
    canvas.translate(0, -140);
    background.draw(canvas);
    canvas.translate(background.width - 1, 0);
    background.draw(canvas);
    canvas.translate(background.width - 1, 0);
    background.draw(canvas);
    canvas.restore();

    canvas.save();
    canvas.translate(_characterX, 0);
    character.draw(canvas);
    canvas.restore();

    for (final apple in apples) {
      canvas.save();
      canvas.translate(apple.translation[0], apple.translation[1]);
      apple.artboard.draw(canvas);
      canvas.restore();
    }

    for (final arrow in arrows) {
      canvas.save();
      canvas.translate(arrow.translation[0], arrow.translation[1]);
      canvas.rotate(atan2(arrow.heading[1], arrow.heading[0]));
      arrow.artboard.draw(canvas);
      canvas.restore();
    }
  }

  void _spawnApples() {
    var random = Random();
    var count = (random.nextDouble() * (maxApples - minApples)) + minApples;
    while (apples.length < count) {
      apples.add(_AppleInstance(apple));
    }
  }

  @override
  ChangeNotifier get redraw => this;

  @override
  Size get size => Size(character.width * 3, character.height);
}

class _AppleInstance {
  late Artboard artboard;
  late SMITrigger explode;
  late Vec2D translation;
  late Vec2D center;
  bool _isDone = false;
  bool get isDone => _isDone;
  _AppleInstance(Artboard apple) {
    var appleMachine =
        apple.stateMachineByName('Apple', onChange: _onStateChange);

    assert(appleMachine != null);

    explode = appleMachine!.findSMI('Explode');

    var random = Random();
    translation = Vec2D.fromValues(
        -apple.width + random.nextDouble() * apple.width * 3,
        -apple.height - random.nextDouble() * apple.height);

    artboard = apple.instance();
    artboard.addController(appleMachine);
    artboard.advance(0);

    // Store the center of the apple to use it for hit detection with arrows.
    TransformComponent appleCenter = artboard.component('Apple_flying');
    center = Vec2D.add(Vec2D(), translation, appleCenter.worldTranslation);
  }

  void _onStateChange(String layer, String? state) {
    if (state == 'ExitState') {
      _isDone = true;
    }
  }
}

class _ArrowInstance {
  final Artboard artboard;
  late Vec2D translation;
  late Vec2D heading;
  double time = 0;

  _ArrowInstance({
    required this.artboard,
    required Mat2D transform,
    required double characterX,
  }) {
    translation = Vec2D.fromValues(transform[4] + characterX, transform[5]);
    heading = Vec2D.fromValues(transform[0], transform[1]);
    // Immediately advance it so the hierarchy is in correct state for first
    // frame draw.
    artboard.advance(0);
  }
}
