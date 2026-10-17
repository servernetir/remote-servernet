import 'package:flutter/material.dart';

import '../../common.dart';

/// The INSTRUMENT layer.
///
/// Every machine-readable value — device ID, one-time password, relay address,
/// telemetry — renders on this plate. It stays dark in BOTH themes and is
/// locked to left-to-right.
///
/// Three problems, one rule:
///   * light-mode glass only reaches ~1.07:1 separation, while a dark plate on
///     the light deck gives ~15:1 — so the hero element is MORE legible in the
///     light theme, not less;
///   * it is the app's visual signature and the most screenshotted surface;
///   * being a `Directionality.ltr` island, a Persian user physically cannot
///     get a device ID rendered with Arabic-Indic digits or bidi-reordered.
///
/// Deliberately opaque: no BackdropFilter, no GlassContainer. It usually sits
/// inside a scroller, and blur inside a scroller re-rasterises every frame.
///
/// Inside the plate use plain [EdgeInsets] on purpose — the LTR lock inverts
/// what "start"/"end" mean. Outside it, keep using directional insets.
class InstrumentPlate extends StatelessWidget {
  const InstrumentPlate({
    Key? key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(14, 13, 14, 12),
    this.margin,
  }) : super(key: key);

  final List<Widget> children;
  final EdgeInsets padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [MyTheme.plateTop, MyTheme.plateBottom],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MyTheme.plateLine, width: 1),
        boxShadow: const [
          BoxShadow(
              color: Color(0x57000000), blurRadius: 26, offset: Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            // 2px brand rail on the leading edge. Positioned, not
            // PositionedDirectional: the plate is an LTR island.
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 2,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [MyTheme.snCyan, MyTheme.snViolet],
                  ),
                ),
              ),
            ),
            // 1px inner top specular, the one Apple-glass cue that survives
            // being opaque.
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: 1,
              child: Container(color: MyTheme.plateSpecular),
            ),
            // Lock direction AND isolate the ambient theme. The app-wide
            // inputDecorationTheme is `filled: true` with a light grey fill,
            // which paints a white box behind every TextFormField — on this
            // dark plate that made the ID and password text invisible. A
            // Brightness.dark Theme override fixes the whole subtree at once
            // instead of patching each field.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Theme(
                data: Theme.of(context).copyWith(
                  brightness: Brightness.dark,
                  inputDecorationTheme: const InputDecorationTheme(
                    filled: false,
                    fillColor: Colors.transparent,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  textSelectionTheme: const TextSelectionThemeData(
                    cursorColor: MyTheme.snCyan,
                    selectionColor: Color(0x553B82F6),
                  ),
                ),
                child: DefaultTextStyle(
                  style: const TextStyle(
                    color: MyTheme.plateValue,
                    fontSize: 13,
                    decoration: TextDecoration.none,
                  ),
                  child: IconTheme(
                    data: const IconThemeData(color: MyTheme.plateLabel),
                    child: Padding(
                      padding: padding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: children,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One labelled machine value inside an [InstrumentPlate].
class InstrumentField extends StatelessWidget {
  const InstrumentField({
    Key? key,
    required this.label,
    required this.value,
    this.actions = const [],
    this.accent = false,
    this.bottomGap = 9,
  }) : super(key: key);

  final String label;

  /// Usually a read-only TextFormField wired to a ServerModel controller.
  final Widget value;
  final List<Widget> actions;

  /// Cyan-tinted treatment, used for the one-time password.
  final bool accent;
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: MyTheme.plateLabel,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: .5,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: value),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }

  /// Text style for the value itself — tabular mono so digit groups line up.
  static TextStyle valueStyle({bool accent = false}) => TextStyle(
        fontFamilyFallback: MyTheme.plateMono,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontSize: accent ? 17 : 21,
        fontWeight: FontWeight.w600,
        letterSpacing: accent ? 2.4 : 1.6,
        height: 1.15,
        color: accent ? MyTheme.plateValueAccent : MyTheme.plateValue,
        decoration: TextDecoration.none,
      );
}

/// Small square icon button sized for the plate.
class InstrumentAction extends StatelessWidget {
  const InstrumentAction({
    Key? key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  }) : super(key: key);

  final Widget icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: const Color(0x1FFFFFFF), width: 1),
        ),
        child: Center(
          child: IconTheme(
            data: const IconThemeData(color: Color(0xFFA9B6D0), size: 13),
            child: icon,
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: tooltip == null ? btn : Tooltip(message: tooltip!, child: btn),
    );
  }
}
