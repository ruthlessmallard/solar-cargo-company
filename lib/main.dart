import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// =============================================================================
// PHYSICS SETTINGS - Mutable, live-tunable
// =============================================================================

class PhysicsSettings {
  double gravityStrength = 800.0;
  double thrustForce = 400.0;
  double rotationSpeed = 3.0;
  double rotationLag = 0.15;
  double dragFactor = 0.995;
  double planetRadius = 60.0;
  double shipRadius = 12.0;
  double projectileSpeed = 500.0;
  double projectileLifetime = 2.0;
  double minZoom = 0.3;
  double maxZoom = 2.0;
  double zoomPadding = 150.0;
  double zoomSmoothing = 0.05;
}

// Global settings instance
final physics = PhysicsSettings();

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
  double facingAngle = -pi / 2;
  double currentRotation = -pi / 2;
  
  // Controls
  double throttle = 0.0;
  double rotationInput = 0.0;
  bool engineOn = false;
  
  // Projectiles
  List<Projectile> projectiles = [];
  
  // Planet position
  final Offset planetCenter = Offset.zero;
  
  // Camera state
  Offset cameraPosition = Offset.zero;
  double cameraZoom = 1.0;
  
  // Settings panel
  bool showSettings = false;
  
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
  
  void _resetShip() {
    setState(() {
      shipPosition = Offset(physics.planetRadius + 150, 0);
      velocity = Offset.zero;
      facingAngle = -pi / 2;
      currentRotation = -pi / 2;
      projectiles.clear();
    });
  }
  
  void _update() {
    final dt = 1 / 60;
    
    setState(() {
      // Rotation with momentum lag
      final targetRotation = facingAngle + rotationInput * physics.rotationSpeed * dt;
      currentRotation = lerpAngle(currentRotation, targetRotation, 1 - physics.rotationLag);
      facingAngle = currentRotation;
      
      // Thrust
      if (engineOn && throttle > 0) {
        final thrustVector = Offset(
          cos(facingAngle) * physics.thrustForce * throttle * dt,
          sin(facingAngle) * physics.thrustForce * throttle * dt,
        );
        velocity += thrustVector;
      }
      
      // Gravity - simplified model for gameplay feel
      final toPlanet = planetCenter - shipPosition;
      final distance = toPlanet.distance;
      if (distance > physics.planetRadius) {
        final gravityDir = toPlanet / distance;
        // Linear gravity for better gameplay feel (inverse-square is too weak at distance)
        final gravityForce = physics.gravityStrength * dt / (distance * 0.5);
        velocity += gravityDir * gravityForce;
      }
      
      // Apply drag
      velocity *= physics.dragFactor;
      
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
        cos(facingAngle) * physics.projectileSpeed,
        sin(facingAngle) * physics.projectileSpeed,
      );
      projectiles.add(Projectile(
        position: shipPosition + Offset(cos(facingAngle), sin(facingAngle)) * (physics.shipRadius + 5),
        velocity: velocity + bulletVel,
      ));
    });
  }
  
  double _calculateZoom(Size screenSize, double distanceToPlanet) {
    final minDimension = min(screenSize.width, screenSize.height);
    final requiredView = (distanceToPlanet + physics.planetRadius + physics.zoomPadding) * 2;
    final targetZoom = minDimension / requiredView;
    return targetZoom.clamp(physics.minZoom, physics.maxZoom);
  }
  
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = Size(constraints.maxWidth, constraints.maxHeight);
        final screenCenter = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
        
        if (shipPosition == const Offset(200, 300)) {
          shipPosition = Offset(physics.planetRadius + 150, 0);
        }
        
        final targetCamera = shipPosition;
        final distanceToPlanet = (shipPosition - planetCenter).distance;
        final targetZoom = _calculateZoom(screenSize, distanceToPlanet);
        
        cameraPosition = Offset(
          lerp(cameraPosition.dx, targetCamera.dx, 0.1),
          lerp(cameraPosition.dy, targetCamera.dy, 0.1),
        );
        cameraZoom = lerp(cameraZoom, targetZoom, physics.zoomSmoothing);
        
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // Game canvas
              CustomPaint(
                size: screenSize,
                painter: GamePainter(
                  planetCenter: planetCenter,
                  shipPosition: shipPosition,
                  shipAngle: facingAngle,
                  projectiles: projectiles,
                  engineOn: engineOn && throttle > 0,
                  cameraPosition: cameraPosition,
                  cameraZoom: cameraZoom,
                  screenCenter: screenCenter,
                ),
              ),
              
              // Settings panel
              if (showSettings)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.85),
                    child: _buildSettingsPanel(),
                  ),
                ),
              
              // Left controls (sliders)
              if (!showSettings)
                Positioned(
                  left: 20,
                  bottom: 20,
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
              if (!showSettings)
                Positioned(
                  right: 20,
                  bottom: 20,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
              if (!showSettings)
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
                        Text(
                          'ZOOM: ${cameraZoom.toStringAsFixed(2)}x',
                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // Settings button
              if (!showSettings)
                Positioned(
                  top: 20,
                  right: 20,
                  child: GestureDetector(
                    onTap: () => setState(() => showSettings = true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Icon(Icons.settings, color: Colors.white70),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildSettingsPanel() {
    return SafeArea(
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.cyan),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'PHYSICS SETTINGS',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _resetShip,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('RESET SHIP'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => setState(() => showSettings = false),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('CLOSE'),
                ),
              ],
            ),
          ),
          
          // Settings grid
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildSliderCard(
                    'Gravity Strength',
                    physics.gravityStrength,
                    100,
                    5000,
                    (v) => setState(() => physics.gravityStrength = v),
                    icon: Icons.public,
                    color: Colors.purple,
                  ),
                  _buildSliderCard(
                    'Thrust Force',
                    physics.thrustForce,
                    50,
                    2000,
                    (v) => setState(() => physics.thrustForce = v),
                    icon: Icons.rocket,
                    color: Colors.orange,
                  ),
                  _buildSliderCard(
                    'Rotation Speed',
                    physics.rotationSpeed,
                    0.5,
                    10,
                    (v) => setState(() => physics.rotationSpeed = v),
                    icon: Icons.rotate_right,
                    color: Colors.cyan,
                  ),
                  _buildSliderCard(
                    'Rotation Lag',
                    physics.rotationLag,
                    0,
                    0.95,
                    (v) => setState(() => physics.rotationLag = v),
                    icon: Icons.speed,
                    color: Colors.yellow,
                  ),
                  _buildSliderCard(
                    'Drag Factor',
                    physics.dragFactor,
                    0.9,
                    1.0,
                    (v) => setState(() => physics.dragFactor = v),
                    icon: Icons.air,
                    color: Colors.blue,
                  ),
                  _buildSliderCard(
                    'Planet Radius',
                    physics.planetRadius,
                    20,
                    200,
                    (v) => setState(() => physics.planetRadius = v),
                    icon: Icons.circle,
                    color: Colors.green,
                  ),
                  _buildSliderCard(
                    'Ship Radius',
                    physics.shipRadius,
                    5,
                    30,
                    (v) => setState(() => physics.shipRadius = v),
                    icon: Icons.rocket_launch,
                    color: Colors.grey,
                  ),
                  _buildSliderCard(
                    'Zoom Smoothing',
                    physics.zoomSmoothing,
                    0.01,
                    0.5,
                    (v) => setState(() => physics.zoomSmoothing = v),
                    icon: Icons.zoom_in,
                    color: Colors.teal,
                  ),
                  _buildSliderCard(
                    'Min Zoom',
                    physics.minZoom,
                    0.1,
                    1.0,
                    (v) => setState(() => physics.minZoom = v),
                    icon: Icons.zoom_out,
                    color: Colors.indigo,
                  ),
                  _buildSliderCard(
                    'Max Zoom',
                    physics.maxZoom,
                    1.0,
                    5.0,
                    (v) => setState(() => physics.maxZoom = v),
                    icon: Icons.zoom_in_map,
                    color: Colors.pink,
                  ),
                  _buildSliderCard(
                    'Zoom Padding',
                    physics.zoomPadding,
                    50,
                    500,
                    (v) => setState(() => physics.zoomPadding = v),
                    icon: Icons.padding,
                    color: Colors.amber,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSliderCard(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged, {
    required IconData icon,
    required Color color,
  }) {
    return Container(
      width: 280,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  value.toStringAsFixed(value < 1 ? 3 : 1),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
            activeColor: color,
            inactiveColor: color.withOpacity(0.2),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                min.toStringAsFixed(min < 1 ? 2 : 0),
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
              Text(
                max.toStringAsFixed(max < 1 ? 2 : 0),
                style: TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ],
          ),
        ],
      ),
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
  }) : lifetime = physics.projectileLifetime;
  
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
  final Offset cameraPosition;
  final double cameraZoom;
  final Offset screenCenter;
  
  GamePainter({
    required this.planetCenter,
    required this.shipPosition,
    required this.shipAngle,
    required this.projectiles,
    required this.engineOn,
    required this.cameraPosition,
    required this.cameraZoom,
    required this.screenCenter,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    
    canvas.translate(screenCenter.dx, screenCenter.dy);
    canvas.scale(cameraZoom);
    canvas.translate(-cameraPosition.dx, -cameraPosition.dy);
    
    // Draw starfield
    final random = Random(42);
    final starPaint = Paint()..color = Colors.white.withOpacity(0.5);
    for (var i = 0; i < 200; i++) {
      final x = (random.nextDouble() * 4000 - 2000);
      final y = (random.nextDouble() * 4000 - 2000);
      final r = random.nextDouble() * 1.5 + 0.5;
      canvas.drawCircle(Offset(x, y), r / cameraZoom, starPaint);
    }
    
    // Draw gravity well indicator
    final gravityPaint = Paint()
      ..color = Colors.purple.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var r = 100.0; r < 400; r += 50) {
      canvas.drawCircle(planetCenter, physics.planetRadius + r, gravityPaint);
    }
    
    // Draw planet
    final planetPaint = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.fill;
    final planetGlowPaint = Paint()
      ..color = Colors.blue.shade400.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(planetCenter, physics.planetRadius + 10, planetGlowPaint);
    canvas.drawCircle(planetCenter, physics.planetRadius, planetPaint);
    
    final highlightPaint = Paint()
      ..color = Colors.blue.shade300.withOpacity(0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      planetCenter - const Offset(15, 15),
      physics.planetRadius * 0.3,
      highlightPaint,
    );
    
    // Draw ship
    _drawShip(canvas);
    
    // Draw projectiles
    final bulletPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;
    for (final p in projectiles) {
      canvas.drawCircle(p.position, 3 / cameraZoom, bulletPaint);
    }
    
    canvas.restore();
  }
  
  void _drawShip(Canvas canvas) {
    if (engineOn) {
      final exhaustPaint = Paint()
        ..color = Colors.orange.withOpacity(0.6 + Random().nextDouble() * 0.4)
        ..style = PaintingStyle.fill;
      
      final exhaustLength = 20 + Random().nextDouble() * 15;
      final exhaustPath = Path()
        ..moveTo(
          shipPosition.dx - cos(shipAngle) * physics.shipRadius,
          shipPosition.dy - sin(shipAngle) * physics.shipRadius,
        )
        ..lineTo(
          shipPosition.dx - cos(shipAngle + 0.3) * (physics.shipRadius + exhaustLength * 0.5),
          shipPosition.dy - sin(shipAngle + 0.3) * (physics.shipRadius + exhaustLength * 0.5),
        )
        ..lineTo(
          shipPosition.dx - cos(shipAngle) * (physics.shipRadius + exhaustLength),
          shipPosition.dy - sin(shipAngle) * (physics.shipRadius + exhaustLength),
        )
        ..lineTo(
          shipPosition.dx - cos(shipAngle - 0.3) * (physics.shipRadius + exhaustLength * 0.5),
          shipPosition.dy - sin(shipAngle - 0.3) * (physics.shipRadius + exhaustLength * 0.5),
        )
        ..close();
      
      canvas.drawPath(exhaustPath, exhaustPaint);
    }
    
    final shipPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;
    final shipOutlinePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 / cameraZoom;
    
    canvas.drawCircle(shipPosition, physics.shipRadius, shipPaint);
    canvas.drawCircle(shipPosition, physics.shipRadius, shipOutlinePaint);
    
    final nosePaint = Paint()
      ..color = Colors.cyan
      ..style = PaintingStyle.fill;
    final nosePos = shipPosition + Offset(cos(shipAngle), sin(shipAngle)) * (physics.shipRadius - 3);
    canvas.drawCircle(nosePos, 4 / cameraZoom, nosePaint);
    
    final indicatorPaint = Paint()
      ..color = Colors.white.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1 / cameraZoom;
    canvas.drawArc(
      Rect.fromCenter(center: shipPosition, width: physics.shipRadius * 2.5, height: physics.shipRadius * 2.5),
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

double lerp(double a, double b, double t) {
  return a + (b - a) * t;
}
