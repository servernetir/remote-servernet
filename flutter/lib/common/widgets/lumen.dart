// LUMEN — light as the material.
//
// Every primitive of the design language lives here. No other file gets a
// private copy: the whole point of a travelling specular rim is that every
// sheet in the product gathers light the same way, and two implementations
// drift apart within a week.
//
// THE THREE-DEPTH RULE — the one non-negotiable invariant. Every surface is
// exactly one of:
//    LumenSheet      a LIT PLANE       — gathers light at the reading entry
//    InstrumentPlate an EMISSIVE SLAB  — see common/widgets/instrument_plate.dart
//    LumenWell       a RECESSED HOLE   — light does not reach in
// There is no fourth material, and every control that receives input lives in
// a well.
//
// RENDER BUDGET: nothing in this file creates a BackdropFilter, an ImageFilter,
// a MaskFilter or a saveLayer. The app is allowed exactly three live blurs
// (title bar, operator rail, connect command bar) and all three already exist.
// Everything here is paint: gradients, one stroked RRect with a shader, radial
// blooms, 1px ColoredBox lines, one negative-spread BoxShadow per surface.
//
// PER-SURFACE CEILINGS, enforced in review: <= 1 BoxShadow (blurRadius <= 22
// in-page, <= 44 modal), <= 1 RadialGradient bloom, <= 1 CustomPaint, and no
// Opacity over a large subtree (that allocates an offscreen buffer) — use
// per-widget colour alpha instead.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../common.dart';

// ---------------------------------------------------------------------------
// 1.1  HELPERS
// ---------------------------------------------------------------------------

/// The lit corner. MIRRORS with language: a specular rim is a LIGHTING cue, and
/// if it stayed physically top-left under fa the panel's brightest corner would
/// land at the reading *exit* and the surface would read backwards.
///
/// MyTheme.snGradient stays ABSOLUTE — that is brand identity, a different job.
Alignment lumenLit(BuildContext c) =>
    const AlignmentDirectional(-1.0, -1.0).resolve(Directionality.of(c));

/// The shade corner: where a dark sheet picks up deck bounce and a light sheet
/// terminates as an ink hairline.
Alignment lumenShade(BuildContext c) =>
    const AlignmentDirectional(1.0, 1.0).resolve(Directionality.of(c));

/// letterSpacing separates Arabic/Persian letterforms and breaks their joins,
/// so it returns 0 under RTL. Turkish is LTR and correctly keeps it.
/// NEVER set letterSpacing except through this.
double lumenLetterSpacing(BuildContext c, double v) =>
    Directionality.of(c) == TextDirection.rtl ? 0.0 : v;

bool lumenDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

bool lumenRtl(BuildContext c) => Directionality.of(c) == TextDirection.rtl;

/// Windows users do set "show animations off", and this ships to Windows.
/// Every duration in this design goes through here so there is one place to
/// audit. maybeOf: a primitive must not assume a MediaQuery ancestor.
Duration lumenDur(BuildContext c, int ms) =>
    (MediaQuery.maybeOf(c)?.disableAnimations ?? false)
        ? Duration.zero
        : Duration(milliseconds: ms);

/// Material chevrons do NOT auto-mirror. Explicit, never Transform.
IconData lumenChevron(BuildContext c) =>
    lumenRtl(c) ? Icons.chevron_left : Icons.chevron_right;

// ---------------------------------------------------------------------------
// 1.2  LumenRimPainter — THE SIGNATURE
// ---------------------------------------------------------------------------

/// One 1px stroke on every sheet, brightness travelling from the lit corner to
/// the shade corner, polarity REVERSED between themes.
///
/// This is the difference between current Apple glass and 2021 glassmorphism.
/// 2021 glassmorphism is uniform-alpha-white + a uniform 1px border. Apple's
/// current material is an edge phenomenon: the sheet gathers light at one
/// corner, dies along the run, and in a light environment its far edge
/// TERMINATES AS A SHADOW LINE rather than a highlight.
///
/// Never a uniform `Border.all` on a LUMEN sheet — a uniform stroke is the
/// clearest tell of a glassmorphism template.
class LumenRimPainter extends CustomPainter {
  const LumenRimPainter({
    required this.radius,
    required this.dark,
    required this.lit,
    required this.shade,
    this.width = 1.0,
  });

  final double radius;
  final bool dark;
  final Alignment lit;
  final Alignment shade;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(
      Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width),
      Radius.circular(math.max(0, radius - width / 2)),
    );
    final shader = LinearGradient(
      begin: lit,
      end: shade,
      colors: dark
          // 56% white at the lit corner -> 17% -> 4% -> back UP to 12%:
          // the deck bouncing light onto the far edge.
          ? const [
              Color(0x8FFFFFFF),
              Color(0x2BFFFFFF),
              Color(0x0AFFFFFF),
              Color(0x1FFFFFFF),
            ]
          // 95% white -> 45% -> THROUGH ZERO into a 7% then 15% ink hairline.
          // A light-theme glass edge terminates as a shadow line, not a
          // highlight. This is the single detail no template produces.
          : const [
              Color(0xF2FFFFFF),
              Color(0x73FFFFFF),
              Color(0x120F172A),
              Color(0x260F172A),
            ],
      stops: const [0.0, 0.26, 0.60, 1.0],
    ).createShader(Offset.zero & size);
    canvas.drawRRect(
      r,
      Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(LumenRimPainter oldDelegate) =>
      oldDelegate.radius != radius ||
      oldDelegate.dark != dark ||
      oldDelegate.lit != lit ||
      oldDelegate.width != width;
}

// ---------------------------------------------------------------------------
// 1.3  LumenSheet — the lit plane
// ---------------------------------------------------------------------------

enum LumenElevation { page, modal }

/// A lit plane. Paint order inside is load-bearing: fill, then the single
/// bloom, then the rim, then content — so the rim can never dim text and the
/// bloom can never wash it out.
class LumenSheet extends StatelessWidget {
  const LumenSheet({
    Key? key,
    required this.child,
    this.onGlass = true,
    this.elevation = LumenElevation.page,
    this.radius = MyTheme.snRadiusLg,
    this.margin,
    this.padding,
    this.bloom,
    this.width,
  }) : super(key: key);

  final Widget child;

  /// True when the sheet sits on an already-blurred FRAME surface (the operator
  /// rail). False when it sits over the raw aurora or a modal scrim.
  final bool onGlass;
  final LumenElevation elevation;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// A single Positioned* radial-gradient child. Max ONE per sheet.
  final Widget? bloom;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final dark = lumenDark(context);
    final lit = lumenLit(context);
    final shade = lumenShade(context);

    // FILL. In DARK the job is to LIFT the sheet off an already-dark frame; in
    // LIGHT the job is to STOP the aurora reaching the panel. Two different
    // jobs, opposite treatments — which is why these are not one ramp with an
    // inverted alpha.
    final List<Color> fill = onGlass
        ? (dark
            ? const [Color(0x1FFFFFFF), Color(0x0AFFFFFF)] // 12% -> 4% white
            : const [Color(0xF7FFFFFF), Color(0xD6FFFFFF)]) // 97% -> 84% white
        : (dark
            ? const [Color(0xF20C1120), Color(0xFA080B16)]
            : const [Color(0xFFFFFFFF), Color(0xF7F4F7FD)]);

    // Exactly one shadow per surface, negative spread ALWAYS: that keeps it a
    // seat under the sheet rather than a halo around it.
    final BoxShadow shadow = elevation == LumenElevation.modal
        ? (dark
            ? const BoxShadow(
                color: Color(0x73000000),
                blurRadius: 44,
                spreadRadius: -10,
                offset: Offset(0, 18))
            : const BoxShadow(
                color: Color(0x240F172A),
                blurRadius: 40,
                spreadRadius: -10,
                offset: Offset(0, 16)))
        : (dark
            ? const BoxShadow(
                color: Color(0x4D000000),
                blurRadius: 18,
                spreadRadius: -6,
                offset: Offset(0, 6))
            : const BoxShadow(
                color: Color(0x0F0F172A),
                blurRadius: 16,
                spreadRadius: -6,
                offset: Offset(0, 5)));

    return Container(
      margin: margin,
      width: width,
      // Clip.none: the contact hairline lives 1px BELOW the sheet.
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // CONTACT HAIRLINE — depth from light, not from a halo. Inset 10 on
          // both sides so it reads as contact with the surface underneath,
          // not as a border belonging to the sheet.
          PositionedDirectional(
            start: 10,
            end: 10,
            bottom: -1,
            height: 1,
            child: IgnorePointer(
              child: ColoredBox(
                color: dark ? const Color(0x38000000) : const Color(0x120F172A),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [shadow],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: lit, end: shade, colors: fill),
                        ),
                      ),
                    ),
                  ),
                  bloom ?? const SizedBox.shrink(),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: LumenRimPainter(
                            radius: radius, dark: dark, lit: lit, shade: shade),
                      ),
                    ),
                  ),
                  Padding(
                    padding: padding ?? EdgeInsets.zero,
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1.4  LumenWell — the recess
// ---------------------------------------------------------------------------

/// A hole in a sheet. ALWAYS darker than its host, with the specular order
/// inverted: a dark line at the top (light does not reach in) and a bright one
/// at the bottom (light returns off the near lip). That two-line inversion is
/// the entire recess illusion and costs two ColoredBoxes.
///
/// The lines use plain left/right, NOT directional: a full-width horizontal
/// line has no handedness, so there is nothing to mirror.
class LumenWell extends StatelessWidget {
  const LumenWell({Key? key, required this.children, this.radius = 12})
      : super(key: key);

  final List<Widget> children;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = lumenDark(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: dark ? const Color(0x33000000) : const Color(0x0A0F172A),
              ),
            ),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: children),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: IgnorePointer(
              child: ColoredBox(
                color: dark ? const Color(0x24000000) : const Color(0x140F172A),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 1,
            child: IgnorePointer(
              child: ColoredBox(
                color: dark ? const Color(0x0FFFFFFF) : const Color(0xB8FFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1.5  LumenLamp — the panel-title lamp
// ---------------------------------------------------------------------------

/// A 7px core inside an 18px static halo. Cyan = inbound, blue = outbound; two
/// colours carry the whole direction cue, which is cheaper and more legible
/// than an icon at 11px across three locales.
///
/// DELIBERATELY NOT ANIMATED. _PulseDot in desktop_home_page.dart stays the
/// home page's only ticker; a second one buys nothing and costs a frame budget.
class LumenLamp extends StatelessWidget {
  const LumenLamp({Key? key, required this.color}) : super(key: key);

  final Color color;

  @override
  Widget build(BuildContext context) {
    final dark = lumenDark(context);
    return IgnorePointer(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                stops: const [0, 1],
                colors: [
                  color.withOpacity(dark ? .38 : .30),
                  color.withOpacity(0),
                ],
              ),
            ),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1.6  LumenSwitch — the toggle
// ---------------------------------------------------------------------------

/// Material's Switch is not used anywhere in this design: MyTheme.switchTheme()
/// only zeroes the splash radius, the rest is stock Android, and it is the
/// second clearest template tell after a uniform border.
///
/// The accent glows from BENEATH the sheet (the internal bloom) — it is not a
/// coloured pill. Thumb, track and bloom share one 180ms duration so the switch
/// reads as one object moving.
class LumenSwitch extends StatelessWidget {
  const LumenSwitch({
    Key? key,
    required this.on,
    required this.accent,
    this.onChanged,
  }) : super(key: key);

  final bool on;
  final Color accent;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = lumenDark(context);
    final d = lumenDur(context, 180);

    final track = AnimatedContainer(
      duration: d,
      curve: MyTheme.snEase,
      width: 40,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        gradient: on
            ? LinearGradient(
                begin: lumenLit(context),
                end: lumenShade(context),
                colors: [accent.withOpacity(.95), accent.withOpacity(.60)],
              )
            : null,
        color: on
            ? null
            : (dark ? const Color(0x1FFFFFFF) : const Color(0x120F172A)),
        border: Border.all(
          color: on ? accent.withOpacity(.55) : MyTheme.line2(context),
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // INTERNAL BLOOM — the LUMEN cue. Rides with the thumb, 4px proud of
          // it on every side, which is why the Stack does not clip.
          //
          // All offsets below are in the track's INNER box (38x20): Border.all
          // insets the Stack by its 1px width, so the spec's outer-space 2/20
          // becomes 1/19 here.
          AnimatedPositionedDirectional(
            duration: d,
            curve: MyTheme.snEase,
            start: on ? 15 : -3,
            top: -3,
            child: AnimatedOpacity(
              duration: d,
              curve: MyTheme.snEase,
              opacity: on ? 1 : 0,
              child: IgnorePointer(
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accent.withOpacity(.30),
                        accent.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // `start` mirrors under fa for free. No Transform, ever.
          AnimatedPositionedDirectional(
            duration: d,
            curve: MyTheme.snEase,
            start: on ? 19 : 1,
            top: 1,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: on
                    ? Colors.white
                    : (dark ? const Color(0xFF9AA6BE) : Colors.white),
                boxShadow: [
                  on
                      ? const BoxShadow(
                          color: Color(0x59000000),
                          blurRadius: 5,
                          offset: Offset(0, 1))
                      : const BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 3,
                          offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // 44px hit target and Tab focus come free from the InkWell.
    return InkWell(
      customBorder: const StadiumBorder(),
      onTap: onChanged == null ? null : () => onChanged!(!on),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(child: track),
      ),
    );
  }
}

// NOTE: §1.7 LumenGlyphCell is intentionally absent from this file. It needs
// MyTheme.advisory(context) — the snAmber / snAmberInk token pair being added
// to common.dart — and it is consumed only by Hero A's access row. Whoever
// lands that token appends it here; it must NOT be re-implemented privately in
// desktop_home_page.dart.
