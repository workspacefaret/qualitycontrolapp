import 'package:flutter/material.dart';

import '../home/home_page.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _scannerController;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _glowAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _scannerAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.94,
      end: 1.04,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
      ),
    );

    _glowAnimation = Tween<double>(
      begin: 0.12,
      end: 0.55,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );
    _scannerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    );

    _scannerAnimation = Tween<double>(
      begin: -320,
      end: 720,
    ).animate(
      CurvedAnimation(
        parent: _scannerController,
        curve: Curves.easeInOutCubic,
      ),
    );

    _controller.forward();
    _controller.forward();
    _scannerController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _goToHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const HomePage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/background.jpg',
              fit: BoxFit.cover,
            ),
          ),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.88),
                    const Color(0xFF102027).withOpacity(0.82),
                    Colors.black.withOpacity(0.90),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -80,
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, _) {
                return Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF8BC34A)
                        .withOpacity(_glowAnimation.value),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8BC34A)
                            .withOpacity(_glowAnimation.value),
                        blurRadius: 90,
                        spreadRadius: 20,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: -90,
            left: -70,
            child: AnimatedBuilder(
              animation: _glowAnimation,
              builder: (context, _) {
                return Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF607D8B)
                        .withOpacity(_glowAnimation.value * 0.7),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF607D8B)
                            .withOpacity(_glowAnimation.value),
                        blurRadius: 100,
                        spreadRadius: 28,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          AnimatedBuilder(
            animation: _scannerAnimation,
            builder: (context, _) {
              return Positioned(
                top: _scannerAnimation.value,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 90,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          const Color(0xFF8BC34A).withOpacity(0.10),
                          const Color(0xFF8BC34A).withOpacity(0.32),
                          const Color(0xFF8BC34A).withOpacity(0.10),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1F2A33).withOpacity(0.82),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.42),
                                blurRadius: 36,
                                offset: const Offset(0, 18),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: Colors.white.withOpacity(0.12),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF8BC34A)
                                            .withOpacity(0.22),
                                        blurRadius: 34,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: Image.asset(
                                    'assets/images/logo2.png',
                                    height: 120,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 34),
                              const Text(
                                'QUALITY CONTROL',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.4,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                height: 3,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 84),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8BC34A),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              const SizedBox(height: 22),
                              const Text(
                                'Sistema operacional de control de calidad industrial',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.5,
                                  color: Color(0xFFCFD8DC),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'Producción • Calidad • Trazabilidad',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  letterSpacing: 0.8,
                                  color: Color(0xFF90A4AE),
                                ),
                              ),
                              const SizedBox(height: 42),
                              SizedBox(
                                height: 64,
                                child: ElevatedButton(
                                  onPressed: _goToHome,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF8BC34A),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                  ),
                                  child: const Text(
                                    'INGRESAR',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              const Text(
                                'FARET INNPACK • CONTROL OPERACIONAL',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                  color: Color(0xFF78909C),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
