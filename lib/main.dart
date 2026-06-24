import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// TWEAKABLE CONSTANTS
// =============================================================================

const double GRAVITY_STRENGTH = 800.0;      // Gravity pull multiplier
const double THRUST_FORCE = 400.0;          // Thrust acceleration
const double ROTATION_SPEED = 3.0;          // Base rotation speed (radians/sec)
const double ROTATION_LAG = 0.15;           // Rotation momentum lag (0-1, higher = more lag)
const double DRAG_FACTOR = 0.995;           // Velocity decay per frame (0-1)
const double PLANET_RADIUS = 60.0;          // Planet size
const double SHIP_RADIUS = 12.0;            // Ship size
const double PROJECTILE_SPEED = 500.0;      // Bullet speed
const double PROJECTILE_LIFETIME = 2.0;     // Seconds before bullet despawns

// =============================================================================
// MAIN ENTRY
// =============================================================================

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SpaceDriftApp());
}

class SpaceDriftApp extends StatelessWidget {
  const SpaceDriftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Space Drift',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const GameScreen(),
    );
  }
}

// =============================================================================
// GAME SCREEN
// =============================================================================

class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late AnimationController _gameLoop;
  
  // Ship state
  Offset shipPosition = const Offset(200, 300);
  Offset velocity = Offset.zero;
  double facingAngle = -pi / 2;  // Pointing up
  double currentRotation = -pi / 2;
  
  // Controls
  double throttle = 0.0;  // 0 to 1
  double rotationInput = 0.0;  // -1 to 1
  bool engineOn = false;
  
  // Projectiles
  List<Projectile> projectiles = [];
  
  // Planet position (center of screen, set in layout)
  Offset planetCenter = Offset.zero;
  
  @override
  void initState() {
    super.initState();
    _gameLoop = AnimationController(
      vsync: this,
      duration: const Duration(days: 1),
    )..addListener(_update);
    _gameLoop.forward();
  }
  
  @override
  void dispose() {
    _gameLoop.dispose();
    super.dispose();
  }
  
  void _update() {
    final dt = 1 / 60;  // Assume 60fps
    
    if (planetCenter == Offset.zero) return;
    
    setState(() {
      // Rotation with momentum lag
      final targetRotation = facingAngle + rotationInput * ROTATION_SPEED * dt;
      currentRotation = lerpAngle(currentRotation, targetRotation, 1 - ROTATION_LAG);
      facingAngle = currentRotation;
      
      // Thrust
      if (engineOn && throttle > 0) {
        final thrustVector = Offset(
          cos(facingAngle) * THRUST_FORCE * throttle * dt,
          sin(facingAngle) * THRUST_FORCE * throttle * dt,
        );
        velocity += thrustVector;
      }
      
      // Gravity
      final toPlanet = planetCenter - shipPosition;
      final distance = toPlanet.distance;
      if (distance > PLANET_RADIUS + SHIP_RADIUS) {
        final gravityDir = toPlanet / distance;
        final gravityForce = GRAVITY_STRENGTH / (distance * distance);
        velocity += gravityDir * gravityForce * dt;
      }
      
      // Apply drag
      velocity *= DRAG_FACTOR;
      
      // Update position
      shipPosition += velocity * dt;
      
      // Update projectiles
      for (var i = projectiles.length - 1; i >= 0; i--) {
        projectiles[i].update(dt);
        if (projectiles[i].lifetime <= 0) {
          projectiles.removeAt(i);
        }
      }
    });
  }
  
  void _fire() {
    setState(() {
      final bulletVel = Offset(
        cos(facingAngle) * PROJECTILE_SPEED,
        sin(facingAngle) * PROJECTILE_SPEED,
      );
      projectiles.add(Projectile(
        position: shipPosition + Offset(cos(facingAngle), sin(facingAngle)) * (SHIP_RADIUS + 5),
        velocity: velocity + bulletVel,
      ));
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        planetCenter = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
        
        // Initialize ship position if at default
        if (shipPosition == const Offset(200, 300)) {
          shipPosition = Offset(
            constraints.maxWidth * 0.2,
            constraints.maxHeight / 2,
          );
        }
        
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Game canvas
              CustomPaint(
                size: Size(constraints.maxWidth, constraints.maxHeight),
                painter: GamePainter(
                  planetCenter: planetCenter,
                  shipPosition: shipPosition,
                  shipAngle: facingAngle,
                  projectiles: projectiles,
                  engineOn: engineOn && throttle > 0,
                ),
              ),
              
              // Left controls (sliders)
              Positioned(
                left: 20,
                bottom: 20,
                child: Container(
                  width: 120,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Throttle slider
                      Row(
                        children: [
                          const Icon(Icons.rocket_launch, color: Colors.orange, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'THRUST ${(throttle * 100).toInt()}%',
                                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                                ),
                                Slider(
                                  value: throttle,
                                  min: 0,
                                  max: 1,
                                  onChanged: (v) => setState(() => throttle = v),
                                  activeColor: Colors.orange,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Rotation slider
                      Row(
                        children: [
                          const Icon(Icons.rotate_right, color: Colors.cyan, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ROTATE ${(rotationInput * 100).toInt()}%',
                                  style: const TextStyle(fontSize: 10, color: Colors.white70),
                                ),
                                Slider(
                                  value: rotationInput,
                                  min: -1,
                                  max: 1,
                                  onChanged: (v) => setState(() => rotationInput = v),
                                  activeColor: Colors.cyan,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              // Right controls (buttons)
              Positioned(
                right: 20,
                bottom: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fire button
                    GestureDetector(
                      onTapDown: (_) => _fire(),
                      child: Container(
                        width: 80,
                        height: 80,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red.withOpacity(0.3),
                          border: Border.all(color: Colors.red, width: 2),
                        ),
                        child: const Center(
                          child: Text(
                            'FIRE',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Engine toggle
                    GestureDetector(
                      onTap: () => setState(() => engineOn = !engineOn),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: engineOn ? Colors.green.withOpacity(0.3) : Colors.grey.withOpacity(0.2),
                          border: Border.all(
                            color: engineOn ? Colors.green : Colors.grey,
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            engineOn ? 'ON' : 'OFF',
                            style: TextStyle(
                              color: engineOn ? Colors.green : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // HUD
              Positioned(
                top: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VEL: ${velocity.distance.toStringAsFixed(1)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                      ),
                      Text(
                        'ALT: ${(shipPosition - planetCenter).distance.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// =============================================================================
// PROJECTILE CLASS
// =============================================================================

class Projectile {
  Offset position;
  Offset velocity;
  double lifetime;
  
  Projectile({
    required this.position,
    required this.velocity,
  }) : lifetime = PROJECTILE_LIFETIME;
  
  void update(double dt) {
    position += velocity * dt;
    lifetime -= dt;
  }
}

// =============================================================================
// GAME PAINTER
// =============================================================================

class GamePainter extends CustomPainter {
  final Offset planetCenter;
  final Offset shipPosition;
  final double shipAngle;
  final List<Projectile> projectiles;
  final bool engineOn;
  
  GamePainter({
    required this.planetCenter,
    required this.shipPosition,
    required this.shipAngle,
    required this.projectiles,
    required this.engineOn,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    // Draw starfield
    final random = Random(42);
    final starPaint = Paint()..color = Colors.white.withOpacity(0.5);
    for (var i = 0; i < 100; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = random.nextDouble() * 1.5 + 0.5;
      canvas.drawCircle(Offset(x, y), r, starPaint);
    }
    
    // Draw gravity well indicator (subtle ring)
    final gravityPaint = Paint()
      ..color = Colors.purple.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = 100.0; r < 400; r += 50) {
      canvas.drawCircle(planetCenter, PLANET_RADIUS + r, gravityPaint);
    }
    
    // Draw planet
    final planetPaint = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.fill;
    final planetGlowPaint = Paint()
      ..color = Colors.blue.shade400.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(planetCenter, PLANET_RADIUS + 10, planetGlowPaint);
    canvas.drawCircle(planetCenter, PLANET_RADIUS, planetPaint);
    
    // Planet highlight
    final highlightPaint = Paint()
      ..color = Colors.blue.shade300.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      planetCenter - const Offset(15, 15),
      PLANET_RADIUS * 0.3,
      highlightPaint,
    );
    
    // Draw ship
    _drawShip(canvas);
    
    // Draw projectiles
    final bulletPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
    for (final p in projectiles) {
      canvas.drawCircle(p.position, 3, bulletPaint);
    }
  }
  
  void _drawShip(Canvas canvas) {
    // Engine exhaust
    if (engineOn) {
      final exhaustPaint = Paint()
        ..color = Colors.orange.withOpacity(0.6 + Random().nextDouble() * 0.4)
        ..style = PaintingStyle.fill;
      
      final exhaustLength = 20 + Random().nextDouble() * 15;
      final exhaustPath = Path()
        ..moveTo(
          shipPosition.dx - cos(shipAngle) * SHIP_RADIUS,
          shipPosition.dy - sin(shipAngle) * SHIP_RADIUS,
        )
        ..lineTo(
          shipPosition.dx - cos(shipAngle + 0.3) * (SHIP_RADIUS + exhaustLength * 0.5),
          shipPosition.dy - sin(shipAngle + 0.3) * (SHIP_RADIUS + exhaustLength * 0.5),
        )
        ..lineTo(
          shipPosition.dx - cos(shipAngle) * (SHIP_RADIUS + exhaustLength),
          shipPosition.dy - sin(shipAngle) * (SHIP_RADIUS + exhaustLength),
        )
        ..lineTo(
          shipPosition.dx - cos(shipAngle - 0.3) * (SHIP_RADIUS + exhaustLength * 0.5),
          shipPosition.dy - sin(shipAngle - 0.3) * (SHIP_RADIUS + exhaustLength * 0.5),
        )
        ..close();
      
      canvas.drawPath(exhaustPath, exhaustPaint);
    }
    
    // Ship body
    final shipPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;
    final shipOutlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawCircle(shipPosition, SHIP_RADIUS, shipPaint);
    canvas.drawCircle(shipPosition, SHIP_RADIUS, shipOutlinePaint);
    
    // Direction indicator (nose)
    final nosePaint = Paint()
      ..color = Colors.cyan
      ..style = PaintingStyle.fill;
    final nosePos = shipPosition + Offset(cos(shipAngle), sin(shipAngle)) * (SHIP_RADIUS - 3);
    canvas.drawCircle(nosePos, 4, nosePaint);
    
    // Rotation indicator
    final indicatorPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawArc(
      Rect.fromCenter(center: shipPosition, width: SHIP_RADIUS * 2.5, height: SHIP_RADIUS * 2.5),
      shipAngle - pi / 6,
      pi / 3,
      false,
      indicatorPaint,
    );
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// =============================================================================
// UTILITIES
// =============================================================================

double lerpAngle(double a, double b, double t) {
  var delta = b - a;
  while (delta > pi) delta -= 2 * pi;
  while (delta < -pi) delta += 2 * pi;
  return a + delta * t;
}