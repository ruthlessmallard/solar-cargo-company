import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SpaceDriftApp());
}

class SpaceDriftApp extends StatelessWidget {
  const SpaceDriftApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Space Drift', debugShowCheckedModeBanner: false, theme: ThemeData.dark(), home: const GameScreen());
  }
}

class PhysicsSettings {
  double planetMass = 168412.97;
  double planetRadius = 60.0;
  double shipRadius = 14.64;
  double thrustForce = 50.0;
  double rotationSpeed = 2.15;
  double rotationLag = 0.24;
  double drag = 1.0;
  int trajSteps = 524;
  double trajDt = 0.08;
}

final physics = PhysicsSettings();

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late AnimationController _loop;
  Offset shipPos = Offset.zero;
  Offset vel = Offset.zero;
  double angle = -pi/2, rot = -pi/2;
  double throttle = 0, rotInput = 0;
  bool engineOn = false;
  double fuel = 100;
  final planet = Offset.zero;
  Offset cam = Offset.zero;
  double zoom = 0.8;
  bool showSettings = false;
  List<Offset> traj = [];
  List<Offset> orbit = [];
  
  // Enemy ship
  Offset enemyPos = Offset.zero;
  Offset enemyVel = Offset.zero;
  double enemyAngle = -pi/2, enemyRot = -pi/2;
  double enemyThrottle = 0;
  bool enemyActive = false;
  double enemyTimer = 10.0;
  List<Bullet> enemyBullets = [];
  double enemyShootCooldown = 0;
}

class Bullet {
  Offset pos;
  Offset vel;
  Bullet(this.pos, this.vel);

  @override
  void initState() { 
    super.initState(); 
    _reset(); 
    _loop = AnimationController(vsync: this, duration: const Duration(days: 1))..addListener(_update); 
    _loop.forward(); 
  }

  void _reset() {
    shipPos = Offset(physics.planetRadius + 200, 0);
    vel = Offset(0, sqrt(physics.planetMass / shipPos.distance));
    angle = rot = -pi/2;
    fuel = 100;
    _calcTraj(); 
    _calcOrbit();
  }

  void _update() {
    final dt = 1/60;
    setState(() {
      // Player physics
      rot = lerpAngle(rot, angle + rotInput * physics.rotationSpeed * dt, 1 - physics.rotationLag);
      angle = rot;
      if (engineOn && throttle > 0 && fuel > 0) {
        vel += Offset(cos(angle), sin(angle)) * physics.thrustForce * throttle * dt;
        fuel -= throttle * 25 * dt;
        if (fuel < 0) fuel = 0;
      } else {
        fuel = min(fuel + 8 * dt, 100);
      }
      final toP = planet - shipPos;
      final dist = toP.distance;
      if (dist > 10) vel += (toP / dist) * (physics.planetMass / (dist * dist)) * dt;
      vel *= physics.drag;
      shipPos += vel * dt;
      
      // Enemy spawn timer
      if (!enemyActive) {
        enemyTimer -= dt;
        if (enemyTimer <= 0) {
          enemyActive = true;
          enemyPos = Offset(-physics.planetRadius - 300, 0);
          enemyVel = Offset(0, -sqrt(physics.planetMass / enemyPos.distance) * 0.8);
          enemyAngle = enemyRot = pi/2;
        }
      } else {
        // Enemy AI: point at player and thrust occasionally
        final toPlayer = shipPos - enemyPos;
        final targetAngle = atan2(toPlayer.dy, toPlayer.dx);
        enemyRot = lerpAngle(enemyRot, targetAngle, 0.02);
        enemyAngle = enemyRot;
        enemyThrottle = toPlayer.distance > 200 ? 0.3 : 0.0;
        if (enemyThrottle > 0) {
          enemyVel += Offset(cos(enemyAngle), sin(enemyAngle)) * physics.thrustForce * enemyThrottle * dt;
        }
        final toPE = planet - enemyPos;
        final distE = toPE.distance;
        if (distE > 10) enemyVel += (toPE / distE) * (physics.planetMass / (distE * distE)) * dt;
        enemyVel *= physics.drag;
        enemyPos += enemyVel * dt;
        
        // Enemy shooting
        enemyShootCooldown -= dt;
        if (enemyShootCooldown <= 0 && toPlayer.distance < 400) {
          enemyBullets.add(Bullet(
            enemyPos,
            Offset(cos(enemyAngle), sin(enemyAngle)) * 300
          ));
          enemyShootCooldown = 1.5;
        }
        
        // Update bullets
        for (var bullet in enemyBullets) {
          bullet.pos += bullet.vel * dt;
        }
        // Remove off-screen bullets
        enemyBullets.removeWhere((b) => (b.pos - shipPos).distance > 1000);
      }
      
      _calcTraj(); 
      _calcOrbit();
    });
  }

  void _calcTraj() {
    traj.clear();
    var p = shipPos; 
    var v = vel;
    for (int i = 0; i < physics.trajSteps; i++) {
      traj.add(p);
      final tp = planet - p;
      final d = tp.distance;
      if (d > 10) v += (tp / d) * (physics.planetMass / (d * d)) * physics.trajDt;
      p += v * physics.trajDt;
      if (d <= physics.planetRadius) break;
    }
  }

  void _calcOrbit() {
    orbit.clear();
    final energy = vel.distanceSquared / 2 - physics.planetMass / shipPos.distance;
    if (energy >= 0) return;
    final a = -physics.planetMass / (2 * energy);
    final period = 2 * pi * sqrt(a * a * a / physics.planetMass);
    var p = shipPos; 
    var v = vel;
    for (int i = 0; i < 150; i++) {
      orbit.add(p);
      final tp = planet - p;
      final d = tp.distance;
      if (d > 10) v += (tp / d) * (physics.planetMass / (d * d)) * period / 150;
      p += v * period / 150;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, cons) {
      final size = Size(cons.maxWidth, cons.maxHeight);
      final center = Offset(size.width / 2, size.height / 2);
      final dist = (shipPos - planet).distance;
      final targetZoom = (min(size.width, size.height) / ((dist + 200) * 2.5)).clamp(0.15, 3.0);
      zoom = lerp(zoom, targetZoom, 0.05);
      cam = Offset(lerp(cam.dx, shipPos.dx, 0.08), lerp(cam.dy, shipPos.dy, 0.08));

      return Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          CustomPaint(size: size, painter: GamePainter(shipPos, angle, planet, traj, orbit, engineOn && throttle > 0, cam, zoom, center, enemyActive, enemyPos, enemyAngle, enemyThrottle > 0, enemyBullets, enemyTimer)),
          if (showSettings) Positioned.fill(child: _settingsPanel()),
          if (!showSettings) ...[
            Positioned(left: 20, bottom: 20, child: _controls()),
            Positioned(right: 20, bottom: 20, child: _actions()),
            Positioned(top: 20, left: 20, child: _hud()),
            Positioned(top: 20, right: 20, child: GestureDetector(onTap: () => setState(() => showSettings = true), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.white24)), child: const Icon(Icons.settings, color: Colors.white70)))),
          ],
        ]),
      );
    });
  }

  Widget _controls() {
    return Container(width: 150, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white24)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _sliderRow('THRUST', throttle, 0, 1, (v) => setState(() => throttle = v), fuel > 0 ? Colors.orange : Colors.grey, Icons.rocket_launch),
        const SizedBox(height: 8),
        _sliderRow('ROTATE', rotInput, -1, 1, (v) => setState(() => rotInput = v), Colors.cyan, Icons.rotate_right),
      ]));
  }

  Widget _sliderRow(String label, double val, double min, double max, ValueChanged<double> onChanged, Color color, IconData icon) {
    return StatefulBuilder(builder: (ctx, setSt) => Row(children: [
      Icon(icon, color: color, size: 18),
      const SizedBox(width: 6),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('$label ${(val * 100).toInt()}%', style: const TextStyle(fontSize: 9, color: Colors.white70)),
        Slider(value: val, min: min, max: max, onChanged: (v) { setSt(() {}); onChanged(v); }, activeColor: color),
      ])),
    ]));
  }

  Widget _actions() => Column(mainAxisSize: MainAxisSize.min, children: [
    GestureDetector(onTap: () => setState(() => engineOn = !engineOn), child: Container(width: 70, height: 70, margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(shape: BoxShape.circle, color: engineOn && fuel > 0 ? Colors.orange.withOpacity(0.3) : Colors.grey.withOpacity(0.2), border: Border.all(color: engineOn && fuel > 0 ? Colors.orange : Colors.grey, width: 2)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(engineOn ? Icons.local_fire_department : Icons.local_fire_department_outlined, color: engineOn && fuel > 0 ? Colors.orange : Colors.grey, size: 24), Text(engineOn ? 'ON' : 'OFF', style: TextStyle(color: engineOn && fuel > 0 ? Colors.orange : Colors.grey, fontWeight: FontWeight.bold, fontSize: 10))])))),
    GestureDetector(onTap: _reset, child: Container(width: 55, height: 55, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.blue.withOpacity(0.2), border: Border.all(color: Colors.blue, width: 2)), child: const Center(child: Icon(Icons.restart_alt, color: Colors.blue, size: 22)))),
  ]);

  Widget _hud() {
    final alt = (shipPos - planet).distance - physics.planetRadius;
    final v = vel.distance;
    String status = alt < 0 ? 'CRASHED' : v < sqrt(physics.planetMass / max(alt + physics.planetRadius, 1)) * 0.9 ? 'SUB-ORBIT' : v > sqrt(2 * physics.planetMass / max(alt + physics.planetRadius, 1)) ? 'ESCAPE' : 'ORBIT';
    return Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _hudRow('VEL', v.toStringAsFixed(1)),
        _hudRow('ALT', alt.toStringAsFixed(0)),
        _hudRow('STATE', status),
        const SizedBox(height: 6),
        SizedBox(width: 110, height: 6, child: LinearProgressIndicator(value: fuel / 100, backgroundColor: Colors.grey.shade800, valueColor: AlwaysStoppedAnimation(fuel < 20 ? Colors.red : fuel < 50 ? Colors.orange : Colors.green))),
        Text('FUEL ${fuel.toInt()}%', style: const TextStyle(fontSize: 9, color: Colors.white70)),
      ]));
  }

  Widget _hudRow(String k, String v) => Padding(padding: const EdgeInsets.only(bottom: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 40, child: Text(k, style: const TextStyle(fontSize: 10, color: Colors.white54))), Text(v, style: const TextStyle(fontSize: 11, color: Colors.white, fontFamily: 'monospace'))]));

  Widget _settingsPanel() {
    return SafeArea(child: Column(children: [
      Container(padding: const EdgeInsets.all(16), decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white24))), child: Row(children: [
        const Icon(Icons.tune, color: Colors.cyan), const SizedBox(width: 12), const Expanded(child: Text('PHYSICS SETTINGS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        TextButton.icon(onPressed: _reset, icon: const Icon(Icons.restart_alt, size: 16), label: const Text('RESET')),
        TextButton.icon(onPressed: () => setState(() => showSettings = false), icon: const Icon(Icons.close, size: 16), label: const Text('CLOSE')),
      ])),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Wrap(spacing: 12, runSpacing: 12, children: [
        _setSlider('Planet Mass', physics.planetMass, 5000.0, 200000.0, (v) => physics.planetMass = v, Colors.purple, Icons.public),
        _setSlider('Thrust Force', physics.thrustForce, 50.0, 1200.0, (v) => physics.thrustForce = v, Colors.orange, Icons.rocket),
        _setSlider('Rotation Speed', physics.rotationSpeed, 0.5, 8.0, (v) => physics.rotationSpeed = v, Colors.cyan, Icons.rotate_right),
        _setSlider('Rotation Lag', physics.rotationLag, 0.0, 0.95, (v) => physics.rotationLag = v, Colors.yellow, Icons.speed),
        _setSlider('Space Drag', physics.drag, 0.99, 1.0, (v) => physics.drag = v, Colors.blue, Icons.air),
        _setSlider('Planet Radius', physics.planetRadius, 20.0, 150.0, (v) => physics.planetRadius = v, Colors.green, Icons.circle),
        _setSlider('Ship Radius', physics.shipRadius, 5.0, 25.0, (v) => physics.shipRadius = v, Colors.grey, Icons.rocket_launch),
        _setSlider('Traj Steps', physics.trajSteps.toDouble(), 50.0, 800.0, (v) => physics.trajSteps = v.toInt(), Colors.teal, Icons.timeline),
      ]))),
    ]));
  }

  Widget _setSlider(String label, double val, double min, double max, ValueChanged<double> onChanged, Color color, IconData icon) {
    return StatefulBuilder(builder: (ctx, setSt) {
      return Container(
        width: 260, 
        padding: const EdgeInsets.all(12), 
        decoration: BoxDecoration(
          color: Colors.black45, 
          borderRadius: BorderRadius.circular(10), 
          border: Border.all(color: color.withOpacity(0.3))
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          mainAxisSize: MainAxisSize.min, 
          children: [
            Row(children: [
              Icon(icon, color: color, size: 16), 
              const SizedBox(width: 6), 
              Expanded(child: Text(label.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color))), 
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
                decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4)), 
                child: Text(label.contains('Steps') ? val.toInt().toString() : val.toStringAsFixed(2), style: TextStyle(fontSize: 11, color: color, fontFamily: 'monospace'))
              )
            ]),
            Slider(
              value: val, 
              min: min, 
              max: max, 
              onChanged: (v) { setSt(() {}); onChanged(v); }, 
              activeColor: color, 
              inactiveColor: color.withOpacity(0.2)
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: [
                Text(min.toStringAsFixed(min < 1 ? 2 : 0), style: TextStyle(fontSize: 9, color: Colors.white38)),
                Text(max.toStringAsFixed(max > 1000 ? 0 : max < 1 ? 2 : 0), style: TextStyle(fontSize: 9, color: Colors.white38))
              ]
            ),
          ]
        )
      );
    });
  }
}

class GamePainter extends CustomPainter {
  final Offset shipPos; 
  final double angle; 
  final Offset planet; 
  final List<Offset> traj; 
  final List<Offset> orbit; 
  final bool engineOn; 
  final Offset cam; 
  final double zoom; 
  final Offset screenCenter;
  final bool enemyActive;
  final Offset enemyPos;
  final double enemyAngle;
  final bool enemyEngineOn;
  final List<Bullet> enemyBullets;
  final double enemyTimer;
  
  GamePainter(this.shipPos, this.angle, this.planet, this.traj, this.orbit, this.engineOn, this.cam, this.zoom, this.screenCenter, this.enemyActive, this.enemyPos, this.enemyAngle, this.enemyEngineOn, this.enemyBullets, this.enemyTimer);

  @override
  void paint(Canvas c, Size s) {
    c.save();
    c.translate(screenCenter.dx, screenCenter.dy);
    c.scale(zoom);
    c.translate(-cam.dx, -cam.dy);

    final r = Random(42);
    final star = Paint()..color = Colors.white.withOpacity(0.6);
    for (int i = 0; i < 300; i++) {
      c.drawCircle(Offset(r.nextDouble() * 4000 - 2000, r.nextDouble() * 4000 - 2000), r.nextDouble() * 1.5 + 0.5, star);
    }

    if (orbit.length > 2) {
      final oPaint = Paint()..color = Colors.cyan.withOpacity(0.15)..style = PaintingStyle.stroke..strokeWidth = 2 / zoom;
      final path = Path(); 
      path.moveTo(orbit[0].dx, orbit[0].dy);
      for (var p in orbit.skip(1)) path.lineTo(p.dx, p.dy);
      path.close();
      c.drawPath(path, oPaint);
    }

    final gPaint = Paint()..color = Colors.purple.withOpacity(0.08)..style = PaintingStyle.stroke..strokeWidth = 1 / zoom;
    for (double rad = physics.planetRadius + 50; rad < physics.planetRadius + 400; rad += 50) {
      c.drawCircle(planet, rad, gPaint);
    }

    if (traj.length > 1) {
      final tPaint = Paint()..color = Colors.yellow.withOpacity(0.6)..style = PaintingStyle.stroke..strokeWidth = 2 / zoom;
      final path = Path()..moveTo(traj[0].dx, traj[0].dy);
      for (var p in traj.skip(1)) path.lineTo(p.dx, p.dy);
      c.drawPath(path, tPaint);
    }

    final glow = Paint()..color = Colors.blue.shade400.withOpacity(0.3)..style = PaintingStyle.fill;
    final body = Paint()..color = Colors.blue.shade700..style = PaintingStyle.fill;
    final hl = Paint()..color = Colors.blue.shade300.withOpacity(0.4)..style = PaintingStyle.fill;
    c.drawCircle(planet, physics.planetRadius + 10, glow);
    c.drawCircle(planet, physics.planetRadius, body);
    c.drawCircle(planet - const Offset(15, 15), physics.planetRadius * 0.3, hl);

    if (engineOn) {
      final ep = Paint()..color = Colors.orange.withOpacity(0.6 + Random().nextDouble() * 0.4)..style = PaintingStyle.fill;
      final len = 20 + Random().nextDouble() * 15;
      final path = Path()
        ..moveTo(shipPos.dx - cos(angle) * physics.shipRadius, shipPos.dy - sin(angle) * physics.shipRadius)
        ..lineTo(shipPos.dx - cos(angle + 0.3) * (physics.shipRadius + len * 0.5), shipPos.dy - sin(angle + 0.3) * (physics.shipRadius + len * 0.5))
        ..lineTo(shipPos.dx - cos(angle) * (physics.shipRadius + len), shipPos.dy - sin(angle) * (physics.shipRadius + len))
        ..lineTo(shipPos.dx - cos(angle - 0.3) * (physics.shipRadius + len * 0.5), shipPos.dy - sin(angle - 0.3) * (physics.shipRadius + len * 0.5))
        ..close();
      c.drawPath(path, ep);
    }
    
    // Draw enemy ship
    if (enemyActive) {
      final enemyPaint = Paint()..color = Colors.red.shade400..style = PaintingStyle.fill;
      final enemyOutline = Paint()..color = Colors.red.shade200..style = PaintingStyle.stroke..strokeWidth = 2 / zoom;
      final enemyPath = Path()
        ..moveTo(enemyPos.dx + cos(enemyAngle) * physics.shipRadius, enemyPos.dy + sin(enemyAngle) * physics.shipRadius)
        ..lineTo(enemyPos.dx + cos(enemyAngle + 2.5) * physics.shipRadius * 0.7, enemyPos.dy + sin(enemyAngle + 2.5) * physics.shipRadius * 0.7)
        ..lineTo(enemyPos.dx + cos(enemyAngle + pi) * physics.shipRadius * 0.4, enemyPos.dy + sin(enemyAngle + pi) * physics.shipRadius * 0.4)
        ..lineTo(enemyPos.dx + cos(enemyAngle - 2.5) * physics.shipRadius * 0.7, enemyPos.dy + sin(enemyAngle - 2.5) * physics.shipRadius * 0.7)
        ..close();
      c.drawPath(enemyPath, enemyPaint);
      c.drawPath(enemyPath, enemyOutline);
      
      // Enemy engine flame
      if (enemyEngineOn) {
        final eep = Paint()..color = Colors.red.withOpacity(0.6 + Random().nextDouble() * 0.4)..style = PaintingStyle.fill;
        final len = 15 + Random().nextDouble() * 10;
        final flamePath = Path()
          ..moveTo(enemyPos.dx - cos(enemyAngle) * physics.shipRadius, enemyPos.dy - sin(enemyAngle) * physics.shipRadius)
          ..lineTo(enemyPos.dx - cos(enemyAngle + 0.3) * (physics.shipRadius + len * 0.5), enemyPos.dy - sin(enemyAngle + 0.3) * (physics.shipRadius + len * 0.5))
          ..lineTo(enemyPos.dx - cos(enemyAngle) * (physics.shipRadius + len), enemyPos.dy - sin(enemyAngle) * (physics.shipRadius + len))
          ..lineTo(enemyPos.dx - cos(enemyAngle - 0.3) * (physics.shipRadius + len * 0.5), enemyPos.dy - sin(enemyAngle - 0.3) * (physics.shipRadius + len * 0.5))
          ..close();
        c.drawPath(flamePath, eep);
      }
      
      // Draw enemy bullets
      final bulletPaint = Paint()..color = Colors.yellow..style = PaintingStyle.fill;
      for (var bullet in enemyBullets) {
        c.drawCircle(bullet.pos, 3 / zoom, bulletPaint);
      }
    } else {
      // Draw spawn timer
      final timerPaint = Paint()..color = Colors.red.withOpacity(0.3 + 0.7 * (enemyTimer / 10))..style = PaintingStyle.stroke..strokeWidth = 2 / zoom;
      c.drawCircle(planet, physics.planetRadius + 50, timerPaint);
    }

    final sp = Paint()..color = Colors.grey.shade300..style = PaintingStyle.fill;
    final so = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 2 / zoom;
    c.drawCircle(shipPos, physics.shipRadius, sp);
    c.drawCircle(shipPos, physics.shipRadius, so);
    final np = Paint()..color = Colors.cyan..style = PaintingStyle.fill;
    final nose = shipPos + Offset(cos(angle), sin(angle)) * (physics.shipRadius - 3);
    c.drawCircle(nose, 4 / zoom, np);

    c.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}

double lerpAngle(double a, double b, double t) { 
  var d = b - a; 
  while (d > pi) d -= 2 * pi; 
  while (d < -pi) d += 2 * pi; 
  return a + d * t; 
}

double lerp(double a, double b, double t) => a + (b - a) * t;
