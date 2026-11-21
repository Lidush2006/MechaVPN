import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'gear_button_painter.dart';

/// Состояния подключения МехаВПН.
enum ConnectionState { off, starting, connected }

/// Главная кнопка-шестерёнка.
///
/// Цвет и анимация зависят от [state]:
/// - off        → серая #3A3A40, без вращения, почти без свечения
/// - starting   → оранжевая #FF6A00, 1 оборот / 8 с, пульсация 1.2 с
/// - connected  → красная #E10600, 1 оборот / 20 с (холостой ход), пульсация 3 с
///
/// На тап — лёгкая вибрация (HapticFeedback.lightImpact) + callback [onTap].
/// Размер по умолчанию 220px (как в дизайн-спеке).
///
/// Поведение тапа — заглушка: родитель сам решает, что делать
/// (вызвать сервис VPN, переключить состояние и т.д.).
class ConnectionButton extends StatefulWidget {
  const ConnectionButton({
    super.key,
    this.size = 220,
    this.state = ConnectionState.off,
    this.onTap,
  });

  final double size;
  final ConnectionState state;
  final VoidCallback? onTap;

  @override
  State<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends State<ConnectionButton>
    with TickerProviderStateMixin {
  late final AnimationController _rot;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _rot = AnimationController(vsync: this);
    _pulse = AnimationController(vsync: this);
    _applyState(widget.state);
  }

  @override
  void didUpdateWidget(covariant ConnectionButton old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _applyState(widget.state);
  }

  void _applyState(ConnectionState s) {
    switch (s) {
      case ConnectionState.off:
        _rot.stop();
        _pulse.stop();
        _pulse.value = 0;
        break;
      case ConnectionState.starting:
        _rot.duration = const Duration(seconds: 8);
        _rot.repeat();
        _pulse.duration = const Duration(milliseconds: 1200);
        _pulse.repeat(reverse: true);
        break;
      case ConnectionState.connected:
        _rot.duration = const Duration(seconds: 20);
        _rot.repeat();
        _pulse.duration = const Duration(seconds: 3);
        _pulse.repeat(reverse: true);
        break;
    }
  }

  Color get _color => switch (widget.state) {
        ConnectionState.off => const Color(0xFF3A3A40),
        ConnectionState.starting => const Color(0xFFFF6A00),
        ConnectionState.connected => const Color(0xFFE10600),
      };

  double get _glowBase => switch (widget.state) {
        ConnectionState.off => 0.05,
        ConnectionState.starting => 0.55,
        ConnectionState.connected => 0.60,
      };

  @override
  void dispose() {
    _rot.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onTap?.call();
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_rot, _pulse]),
          builder: (context, _) {
            final pulseVal = _pulse.isAnimating ? _pulse.value : 0.0;
            final glow = _glowBase + (1 - _glowBase) * 0.4 * pulseVal;
            return CustomPaint(
              painter: GearButtonPainter(
                color: _color,
                rotation: _rot.value * 2 * pi,
                glow: glow,
              ),
            );
          },
        ),
      ),
    );
  }
}
