import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/rate_us_service.dart';

/// A premium, emotionally engaging "Rate Us" dialog with Lottie animations.
class RateUsDialog extends StatefulWidget {
  const RateUsDialog({super.key});

  @override
  State<RateUsDialog> createState() => _RateUsDialogState();
}

class _RateUsDialogState extends State<RateUsDialog> with TickerProviderStateMixin {
  int _selectedRating = 0;
  bool _isRatingSent = false;
  late final AnimationController _entranceController;
  late final AnimationController _pulseController;
  late final AnimationController _confettiController;

  static const String _playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.baishalya.surveycam';

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _pulseController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _launchURL() async {
    final Uri url = Uri.parse(_playStoreUrl);
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      debugPrint('Could not launch $_playStoreUrl');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(
        parent: _entranceController,
        curve: Curves.elasticOut,
      ),
      child: FadeTransition(
        opacity: _entranceController,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Main Dialog Container
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withAlpha(230), // ~0.9 opacity
                          const Color(0xFFFFF0F5).withAlpha(204), // ~0.8 opacity
                        ],
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: Colors.white.withAlpha(128), // ~0.5 opacity
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pink.withAlpha(26), // ~0.1 opacity
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 40),
                        
                        // Heartwarming Text
                        Text(
                          'Enjoying SurveyCam?',
                          style: GoogleFonts.quicksand(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.pink[800],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Your support means the world to us ❤️\nThis app stays free because of amazing users like you ✨',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.quicksand(
                            fontSize: 15,
                            color: Colors.grey[700],
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        
                        const SizedBox(height: 24),
                        
                        // Interactive Stars
                        _buildStarRating(),
                        
                        const SizedBox(height: 32),
                        
                        // Action Buttons
                        _buildActionButtons(),
                        
                        const SizedBox(height: 12),
                        
                        // "No Thanks" Option
                        TextButton(
                          onPressed: () async {
                            final navigator = Navigator.of(context);
                            await RateUsService.markAsDontShow();
                            if (mounted) navigator.pop();
                          },
                          child: Text(
                            "No Thanks",
                            style: GoogleFonts.quicksand(
                              color: Colors.grey[400],
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Cute Mascot (Lottie)
              Positioned(
                top: -80,
                left: 0,
                right: 0,
                child: Center(
                  child: ScaleTransition(
                    scale: Tween(begin: 1.0, end: 1.05).animate(
                      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                    ),
                    child: SizedBox(
                      height: 160,
                      width: 160,
                      child: Lottie.asset(
                        'Assets/lottie/photographing_cat.json',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              
              // Confetti Layer
              if (_isRatingSent)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Lottie.asset(
                      'Assets/lottie/like.json',
                      controller: _confettiController,
                      onLoaded: (composition) {
                        _confettiController.duration = composition.duration;
                        _confettiController.forward();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStarRating() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedRating = index + 1;
            });
          },
          child: TweenAnimationBuilder(
            tween: Tween<double>(begin: 1, end: _selectedRating > index ? 1.2 : 1.0),
            duration: const Duration(milliseconds: 300),
            builder: (context, scale, child) {
              return Transform.scale(
                scale: scale,
                child: Icon(
                  index < _selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: index < _selectedRating ? Colors.amber : Colors.grey[300],
                  size: 48,
                ),
              );
            },
          ),
        );
      }),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Rate Now Button
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () async {
              if (_selectedRating == 0) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a star rating first!')),
                  );
                }
                return;
              }
              
              final navigator = Navigator.of(context);
              setState(() => _isRatingSent = true);
              await RateUsService.markAsRated();
              
              // Delay slightly for confetti effect
              await Future.delayed(const Duration(milliseconds: 1000));
              if (mounted) {
                navigator.pop();
                await _launchURL();
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _selectedRating > 0 ? Colors.pink[400] : Colors.grey[300],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Rate Now ⭐',
                  style: GoogleFonts.quicksand(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Maybe Later Button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: OutlinedButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              await RateUsService.remindLater();
              if (mounted) navigator.pop();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.pink[300],
              side: BorderSide(color: Colors.pink[100]!, width: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'Maybe Later 🥺',
              style: GoogleFonts.quicksand(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
