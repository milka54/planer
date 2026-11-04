import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../data/speech_service.dart';

class ThemedBackground extends StatelessWidget {
  final Widget child;
  final String? assetPath;
  final String? filePath;
  final List<Color>? gradientColors;
  final bool dim;

  const ThemedBackground({
    super.key,
    required this.child,
    this.assetPath,
    this.filePath,
    this.gradientColors,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    final file = filePath;
    final asset = assetPath;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (file != null)
          Image.file(
            File(file),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) {
              // Файл недоступен — сразу градиент, без пустого экрана.
              return _GradientBackdrop(colors: gradientColors);
            },
          )
        else if (asset != null)
          Image.asset(
            asset,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, e, ___) {
              debugPrint('bg asset error: $asset → $e');
              return _GradientBackdrop(colors: gradientColors);
            },
          )
        else if (gradientColors != null && gradientColors!.length >= 2)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors!,
              ),
            ),
          )
        else
          const _GradientBackdrop(),
        if (dim)
          Container(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.black.withOpacity(0.42)
                : Colors.black.withOpacity(0.22),
          ),
        child,
      ],
    );
  }
}

class _GradientBackdrop extends StatelessWidget {
  final List<Color>? colors;

  const _GradientBackdrop({this.colors});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = colors != null && colors!.length >= 2
        ? colors!
        : (dark
            ? [
                AppPalette.inkDeep,
                AppPalette.ink.withOpacity(0.95),
                const Color(0xFF1A2748),
              ]
            : [
                AppPalette.paper,
                const Color(0xFFFFF7EC),
                const Color(0xFFEFE6D8),
              ]);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: base,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _GlowCircle(
              size: 220,
              color: AppPalette.accent.withOpacity(dark ? 0.18 : 0.16),
            ),
          ),
          Positioned(
            bottom: -100,
            left: -70,
            child: _GlowCircle(
              size: 260,
              color: AppPalette.sky.withOpacity(dark ? 0.14 : 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final double size;
  final Color color;
  const _GlowCircle({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}

class GlassPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? radius;
  final bool glow;

  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius,
    this.glow = true,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        // Плотнее, чтобы текст читался на любом фоне-картинке.
        color: dark
            ? const Color(0xFF1A2744).withOpacity(0.88)
            : Colors.white.withOpacity(0.94),
        borderRadius: radius ?? BorderRadius.circular(22),
        border: Border.all(
          color: dark
              ? Colors.white.withOpacity(0.16)
              : Colors.white.withOpacity(0.8),
        ),
        boxShadow: [
          if (glow)
            BoxShadow(
              color: Colors.black.withOpacity(dark ? 0.32 : 0.1),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          if (glow && !dark)
            BoxShadow(
              color: AppPalette.accent.withOpacity(0.08),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: AppPalette.accent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withOpacity(0.75),
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.loading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 1),
      duration: const Duration(milliseconds: 120),
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: child,
        );
      },
      child: SizedBox(
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AppPalette.accent.withOpacity(0.35),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FilledButton(
            onPressed: loading ? null : onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.accent,
              foregroundColor: AppPalette.inkDeep,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            child: loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(label),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class NoteChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool filled;

  const NoteChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color.withOpacity(0.22) : color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class BetaBanner extends StatefulWidget {
  final bool compact;
  const BetaBanner({super.key, this.compact = false});

  @override
  State<BetaBanner> createState() => _BetaBannerState();
}

class _BetaBannerState extends State<BetaBanner>
    with SingleTickerProviderStateMixin {
  bool _visible = true;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = 0.55 + 0.45 * _controller.value;
        return Container(
          margin: EdgeInsets.fromLTRB(
            widget.compact ? 16 : 16,
            0,
            widget.compact ? 16 : 16,
            widget.compact ? 8 : 12,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: 14,
            vertical: widget.compact ? 10 : 12,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                AppPalette.accent.withOpacity(0.28 * t + 0.12),
                AppPalette.rose.withOpacity(0.18 * t + 0.10),
              ],
            ),
            border: Border.all(
              color: AppPalette.accent.withOpacity(0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: AppPalette.accent.withOpacity(0.12 * t),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppPalette.accent.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.science_rounded,
                  size: 18,
                  color: AppPalette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BETA · режим тестирования',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: dark ? Colors.white : AppPalette.inkDeep,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Скоро регистрация станет платной.\nУспейте попробовать бесплатно.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.3,
                        color: (dark ? Colors.white : AppPalette.inkDeep)
                            .withOpacity(0.78),
                      ),
                    ),
                  ],
                ),
              ),
              if (!widget.compact)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _visible = false),
                  icon: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: (dark ? Colors.white : AppPalette.inkDeep)
                        .withOpacity(0.55),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class StaggeredFadeIn extends StatelessWidget {
  final int index;
  final Widget child;
  final Duration delayStep;

  const StaggeredFadeIn({
    super.key,
    required this.index,
    required this.child,
    this.delayStep = const Duration(milliseconds: 45),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 380 + index * 40),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) {
        return Opacity(
          opacity: t.clamp(0, 1),
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: Transform.scale(
              scale: 0.96 + 0.04 * t,
              child: child,
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class PulseIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;
  const PulseIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 18,
  });

  @override
  State<PulseIcon> createState() => _PulseIconState();
}

class _PulseIconState extends State<PulseIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final s = 1 + 0.12 * _c.value;
        return Transform.scale(
          scale: s,
          child: Icon(
            widget.icon,
            size: widget.size,
            color: widget.color.withOpacity(0.75 + 0.25 * _c.value),
          ),
        );
      },
    );
  }
}

class ParallaxBackground extends StatelessWidget {
  final Widget child;
  final ScrollController? controller;
  final String? assetPath;
  final String? filePath;
  final double parallax;

  const ParallaxBackground({
    super.key,
    required this.child,
    this.controller,
    this.assetPath,
    this.filePath,
    this.parallax = 0.18,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = assetPath != null || filePath != null;
    if (!hasImage) return child;

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        // rebuild via Listenable below
        return false;
      },
      child: AnimatedBuilder(
        animation: controller ?? const AlwaysStoppedAnimation(0),
        builder: (context, _) {
          final offset = controller?.hasClients == true
              ? controller!.offset
              : 0.0;
          return Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: Offset(0, -offset * parallax),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 1.3,
                  child: filePath != null
                      ? Image.file(
                          File(filePath!),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink(),
                        )
                      : Image.asset(
                          assetPath!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) =>
                              const SizedBox.shrink(),
                        ),
                ),
              ),
              child,
            ],
          );
        },
      ),
    );
  }
}

class SoftIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  const SoftIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
  });

  @override
  State<SoftIconButton> createState() => _SoftIconButtonState();
}

class _SoftIconButtonState extends State<SoftIconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 110),
        child: Tooltip(
          message: widget.tooltip ?? '',
          child: Icon(widget.icon),
        ),
      ),
    );
  }
}

/// Текст с кликабельными ссылками (http/https/www/email).
class LinkifiedText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const LinkifiedText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  static final _linkRe = RegExp(
    r'(?:https?:\/\/|www\.)[^\s<>"\x27]+|[\w.+-]+@[\w-]+\.[A-Za-z]{2,}',
    caseSensitive: false,
  );

  static const _trailingPunct = '.,;:!?)]}>\u00bb\u201d\u2019';

  static String _trimTrailing(String s) {
    var out = s;
    while (out.isNotEmpty && _trailingPunct.contains(out[out.length - 1])) {
      out = out.substring(0, out.length - 1);
    }
    return out;
  }

  static String _targetOf(String raw) {
    final isEmail = !raw.contains('://') && raw.contains('@');
    if (isEmail) return 'mailto:$raw';
    if (raw.toLowerCase().startsWith('www.')) return 'https://$raw';
    return raw;
  }

  Future<void> _open(BuildContext context, String raw) async {
    final target = _targetOf(raw);
    final uri = Uri.tryParse(target);
    if (uri == null) return;
    var ok = false;
    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (ok) return;
    await Clipboard.setData(ClipboardData(text: target));
    if (!context.mounted) return;
    showSnack(context, 'Не удалось открыть ссылку — она скопирована');
  }

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final linkStyle = base.copyWith(
      color: AppPalette.accent,
      decoration: TextDecoration.underline,
      decorationColor: AppPalette.accent.withOpacity(0.55),
      decorationThickness: 1.4,
    );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in _linkRe.allMatches(text)) {
      final raw = _trimTrailing(m.group(0)!);
      if (raw.isEmpty) continue;
      final start = m.start;
      final end = start + raw.length;
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      spans.add(
        TextSpan(
          text: raw,
          style: linkStyle,
          recognizer: TapGestureRecognizer()
            ..onTap = () => _open(context, raw),
        ),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return SelectableText.rich(
      TextSpan(style: base, children: spans),
      textAlign: textAlign,
      maxLines: maxLines,
      // maxLines + SelectableText несовместимы с ellipsis на старых версиях,
      // поэтому overflow прокидываем только если maxLines задан.
      strutStyle: StrutStyle.fromTextStyle(base),
    );
  }
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}

String formatDateRu(DateTime d) {
  const months = [
    'янв', 'фев', 'мар', 'апр', 'май', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String formatDateTimeRu(DateTime d) {
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${formatDateRu(d)}, $hh:$mm';
}

String formatRelative(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'сегодня';
  if (diff == 1) return 'завтра';
  if (diff == -1) return 'вчера';
  return formatDateRu(d);
}

class MagazineTitle extends StatelessWidget {
  final String text;
  final double size;
  const MagazineTitle(this.text, {super.key, this.size = 30});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.8,
        height: 1.08,
        color: Theme.of(context).textTheme.bodyLarge?.color,
      ),
    );
  }
}

double shimmer(double t) => (math.sin(t * math.pi * 2) + 1) / 2;

/// Просмотр фото/тяжёлых медиа — отдельным экраном (не диалогом:
/// тапы по картинке конфликтовали с формой под диалогом).
class ImageViewerScreen extends StatelessWidget {
  final String path;

  const ImageViewerScreen({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          tooltip: 'Закрыть',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 6,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}

/// Переиспользуемая mic-кнопка диктовки для любого TextEditingController:
/// буфер + нарастание текста + закрепление фразы по finalResult.
class DictationSuffix extends StatefulWidget {
  final TextEditingController controller;

  const DictationSuffix({super.key, required this.controller});

  @override
  State<DictationSuffix> createState() => _DictationSuffixState();
}

class _DictationSuffixState extends State<DictationSuffix> {
  bool _active = false;
  String _buf = '';

  Future<void> _toggle() async {
    if (_active) {
      await SpeechService.instance.stop();
      if (mounted) setState(() => _active = false);
      return;
    }
    await SpeechService.instance.stop();
    _buf = widget.controller.text.trim();
    final ok = await SpeechService.instance.start(
      onResult: (text, finalResult) {
        widget.controller.text = _buf.isEmpty ? text : '$_buf $text';
        if (finalResult) _buf = widget.controller.text;
      },
      onStopped: () {
        if (mounted) setState(() => _active = false);
      },
    );
    if (!ok) {
      if (mounted) {
        showSnack(context, 'Голосовой ввод недоступен на этом устройстве');
      }
      return;
    }
    if (mounted) setState(() => _active = true);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Голосовой ввод',
      icon: Icon(
        _active ? Icons.mic_rounded : Icons.mic_none_rounded,
        color: _active ? AppPalette.rose : null,
      ),
      onPressed: _toggle,
    );
  }
}

