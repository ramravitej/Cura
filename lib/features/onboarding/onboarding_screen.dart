import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'engine_choice_screen.dart';

/// AyusAI Onboarding & Welcome screen.
/// Matches the "Your AI Health Coach" design with hero illustration,
/// feature cards, and gradient call to action.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  static const Duration _enterDuration = Duration(milliseconds: 700);
  static const Curve _enterCurve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: const Color(0xFFF2F9F6),
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F9F6),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF7FCFA),
                Color(0xFFF0F8F5),
                Color(0xFFE9F4F0),
              ],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 480),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 8),

                                // Top AyusAI Lotus Logo
                                Center(
                                  child: Image.asset(
                                    'assets/ayus_logo.png',
                                    height: 76,
                                    fit: BoxFit.contain,
                                  ),
                                )
                                    .animate()
                                    .fadeIn(duration: _enterDuration)
                                    .slideY(begin: -0.2, curve: _enterCurve),

                                const SizedBox(height: 16),

                                // Main Headline
                                const Text(
                                  'Your AI Health Coach',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                    color: Color(0xFF093930),
                                  ),
                                )
                                    .animate()
                                    .fadeIn(
                                      duration: _enterDuration,
                                      delay: 150.ms,
                                    )
                                    .slideY(begin: 0.1, curve: _enterCurve),

                                const SizedBox(height: 8),

                                // Subtitle
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    'Guiding your health, wellness, food, activity and medical records — all in one place.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontSize: 14,
                                      height: 1.4,
                                      fontWeight: FontWeight.w400,
                                      color: Color(0xFF4A6F68),
                                    ),
                                  ),
                                )
                                    .animate()
                                    .fadeIn(
                                      duration: _enterDuration,
                                      delay: 250.ms,
                                    )
                                    .slideY(begin: 0.1, curve: _enterCurve),

                                const SizedBox(height: 16),

                                // Hero Illustration with woman & glowing wellness arc
                                Expanded(
                                  child: Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(24),
                                      child: Image.asset(
                                        'assets/ayus_hero.png',
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                )
                                    .animate()
                                    .fadeIn(
                                      duration: _enterDuration,
                                      delay: 350.ms,
                                    )
                                    .scale(
                                      begin: const Offset(0.95, 0.95),
                                      curve: _enterCurve,
                                    ),

                                const SizedBox(height: 16),

                                // Three Feature Cards Row
                                const IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _FeatureCard(
                                          icon: Icons.camera_alt_rounded,
                                          iconColor: Color(0xFF0D946F),
                                          iconBgColor: Color(0xFFE2F7F0),
                                          title: 'Food Scan',
                                          description:
                                              'Analyze meals\nand get insights.',
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: _FeatureCard(
                                          icon: Icons.note_add_rounded,
                                          iconColor: Color(0xFF2563EB),
                                          iconBgColor: Color(0xFFEBF2FF),
                                          title: 'Medical Records',
                                          description:
                                              'Keep your health\ndocuments in one\nsecure place.',
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Expanded(
                                        child: _FeatureCard(
                                          icon: Icons.lightbulb_rounded,
                                          iconColor: Color(0xFFEA580C),
                                          iconBgColor: Color(0xFFFFF2E6),
                                          title: 'Daily Coach',
                                          description:
                                              'Get personalized\nguidance for a\nhealthier you.',
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                                    .animate()
                                    .fadeIn(
                                      duration: _enterDuration,
                                      delay: 450.ms,
                                    )
                                    .slideY(begin: 0.15, curve: _enterCurve),

                                const SizedBox(height: 20),

                                // Bottom CTA "Get Started ->" Button
                                Container(
                                  height: 54,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF0B7B58),
                                        Color(0xFF04533C),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(28),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF0B7B58,
                                        ).withValues(alpha: 0.32),
                                        blurRadius: 16,
                                        offset: const Offset(0, 6),
                                      ),
                                    ],
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(28),
                                      onTap: () => _onGetStarted(context),
                                      child: const Center(
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              'Get Started',
                                              style: TextStyle(
                                                fontFamily: 'PlusJakartaSans',
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            SizedBox(width: 8),
                                            Icon(
                                              Icons.arrow_forward_rounded,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                    .animate()
                                    .fadeIn(
                                      duration: _enterDuration,
                                      delay: 550.ms,
                                    )
                                    .slideY(begin: 0.2, curve: _enterCurve),

                                const SizedBox(height: 12),

                                // "I already have an account Sign in >"
                                Center(
                                  child: GestureDetector(
                                    onTap: () => _onGetStarted(context),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: RichText(
                                        text: const TextSpan(
                                          style: TextStyle(
                                            fontFamily: 'PlusJakartaSans',
                                            fontSize: 13,
                                            color: Color(0xFF64748B),
                                          ),
                                          children: [
                                            TextSpan(
                                              text:
                                                  'I already have an account ',
                                            ),
                                            TextSpan(
                                              text: 'Sign in  ›',
                                              style: TextStyle(
                                                color: Color(0xFF0B7B58),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                    .animate()
                                    .fadeIn(
                                      duration: _enterDuration,
                                      delay: 650.ms,
                                    ),

                                const SizedBox(height: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _onGetStarted(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const EngineChoiceScreen()),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2EEEA),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF093930).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 22,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF093930),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: 10.5,
              height: 1.25,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
