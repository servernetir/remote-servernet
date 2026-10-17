import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import '../../models/state_model.dart';
import 'lumen.dart';

// ===========================================================================
// THE ACCESS CONSOLE — the operator's permissions control.
//
// Three things live here:
//   * the advisory-amber token pair, derived locally (see below);
//   * LumenGlyphCell, the 20x18 state glyph lumen.dart deliberately left out
//     because it needs that token;
//   * the pinned rail row (PermissionsAccessRow) and the sheet it opens.
//
// RENDER BUDGET. Nothing here creates a BackdropFilter, an ImageFilter, a
// MaskFilter or a saveLayer. The app stays at exactly three live blurs — title
// bar, operator rail, connect command bar — none of which this file touches.
//
// The console is deliberately NOT frosted: it opens over a full-screen scrim
// that has already flattened the aurora, so a blur would cost a full render
// pass for a change nobody can see. Being blur-free is also precisely what lets
// it legally hold a SingleChildScrollView. Do not "just add a frosted scrim"
// and do not reuse GlassContainer for this sheet.
// ===========================================================================

// ------------------------------------------------------------------ tokens --

/// Advisory amber, DERIVED LOCALLY ON PURPOSE.
///
/// #FBBF24 is already hardcoded three times in desktop_home_page's
/// buildInstallCard; this names it. [snAmberInk] exists because #FBBF24 on a
/// near-white sheet measures ~1.7:1 — a 2px advisory bar drawn in it is
/// invisible, and light is the shipped default theme. #B45309 measures ~4.9:1
/// on white.
///
/// common.dart's token block was frozen for this change, so these are top-level
/// here instead of MyTheme.snAmber / snAmberInk / MyTheme.advisory(). When that
/// block is unfrozen, move all three there verbatim and move [LumenGlyphCell]
/// into lumen.dart, which is where its own closing note asks for it.
const Color snAmber = Color(0xFFFBBF24); // dark:  ~9.8:1 on snBg
const Color snAmberInk = Color(0xFFB45309); // light: ~4.9:1 on white

Color lumenAdvisory(BuildContext c) => lumenDark(c) ? snAmber : snAmberInk;

// -------------------------------------------------------------- glyph cell --

/// The 20x18 state glyph used by the rail readout — LUMEN §1.7.
///
/// A revoked glyph is struck AT THE BASE, not diagonally: one ColoredBox, no
/// CustomPainter, and a horizontal line has no handedness so there is nothing
/// to mirror.
class LumenGlyphCell extends StatelessWidget {
  const LumenGlyphCell({
    Key? key,
    required this.icon,
    required this.on,
    required this.accent,
    this.tooltip,
  }) : super(key: key);

  final IconData icon;
  final bool on;
  final Color accent;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final cell = SizedBox(
      width: 20,
      height: 18,
      child: Stack(
        children: [
          Center(
            child: Icon(icon,
                size: 13, color: on ? accent : MyTheme.textDim(context)),
          ),
          if (!on)
            Positioned(
              left: 1,
              right: 1,
              bottom: 0,
              height: 1.5,
              child: ColoredBox(color: lumenAdvisory(context)),
            ),
        ],
      ),
    );
    return tooltip == null
        ? cell
        : Tooltip(
            waitDuration: const Duration(milliseconds: 300),
            message: tooltip!,
            child: cell);
  }
}

// ===========================================================================
// STATE — the load-bearing part
// ===========================================================================

/// Descending blast radius. This ORDER is shared by the rail readout and the
/// sheet, so the two can never look like different facts.
const List<String> kSnAccessKeys = [
  kOptionEnableKeyboard,
  kOptionEnableClipboard,
  kOptionEnableFileTransfer,
  kOptionEnableAudio,
];

class _SnPerm {
  const _SnPerm(this.key, this.accent, this.icon, this.titleKey);

  final String key;
  final Color accent;
  final IconData icon;
  final String titleKey;
}

/// One brand token per row, which ties the rows to the aurora behind them.
const List<_SnPerm> _snPerms = [
  _SnPerm(kOptionEnableKeyboard, MyTheme.snBlue, Icons.keyboard,
      'Enable keyboard/mouse'),
  _SnPerm(kOptionEnableClipboard, MyTheme.snCyan, Icons.content_paste,
      'Enable clipboard'),
  _SnPerm(kOptionEnableFileTransfer, MyTheme.snViolet, Icons.folder_outlined,
      'Enable file transfer'),
  _SnPerm(kOptionEnableAudio, MyTheme.snGreen, Icons.volume_up_outlined,
      'Enable audio'),
];

/// The fa string carries a LEADING SPACE (" فعالسازی ماوس/صفحه کلید" in
/// src/lang/fa.rs). Trim at the display site.
String snPermTitle(String titleKey) => translate(titleKey).trim();

String snAccessMode() => bind.mainGetOptionSync(key: kOptionAccessMode);

/// kOptionAccessMode OVERRIDES all four booleans server-side — 'full' forces
/// every capability on, 'view' forces every one off. This is exactly what the
/// settings page's Safety tab models with its `fakeValue`. A permissions sheet
/// without the mode segment would let an operator turn keyboard off and watch
/// nothing happen, which is why the segment is a correctness requirement and
/// not scope creep.
bool? snAccessForced() {
  final m = snAccessMode();
  if (m == 'full') return true;
  if (m == 'view') return false;
  return null;
}

/// READ PATH. The option store is the single source of truth.
///
/// NOT ServerModel.inputOk/clipboardOk/fileOk/audioOk: those four mirrors are
/// written only by checkAndroidPermission() — whose sole caller is the mobile
/// server page — and by changeStatue(). On Windows they therefore all read
/// `false` while the underlying options are ENABLED, because option2bool makes
/// any `enable-*` key true unless its value is literally "N". A UI rendering
/// the mirrors would show a fresh install as fully locked down when it is in
/// fact fully open. ServerModel.syncIncomingPermissions() exists to stop the
/// mirrors lying; the values still come from here.
bool snPermOn(String key) => mainGetBoolOptionSync(key);

bool snPermEffective(String key) => snAccessForced() ?? snPermOn(key);

/// common.dart's `isOptionFixed` declares no return type, so it statically
/// resolves to `dynamic Function(String)` and cannot be passed to `.any`.
bool snOptionFixed(String key) => isOptionFixed(key) == true;

bool snAccessAnyFixed() =>
    snOptionFixed(kOptionAccessMode) || kSnAccessKeys.any(snOptionFixed);

/// Three EXISTING translation keys, zero new strings. Shared by the footer chip
/// and the rail glyph so they can never disagree.
String snAccessModeWord() {
  final n = kSnAccessKeys.where(snPermEffective).length;
  if (n == 4) return translate('Full Access');
  if (n == 0) return translate('Screen Share');
  return translate('Custom');
}

/// Cheap change detector for the home page's existing 1s tick — five sync
/// config reads per second, against the two that tick already does.
String snAccessSignature() {
  final b = StringBuffer(snAccessMode());
  for (final k in kSnAccessKeys) {
    b.write('|');
    b.write(snPermOn(k));
  }
  return b.toString();
}

// ===========================================================================
// THE RAIL ROW — pinned, third row of Hero A's well
// ===========================================================================

/// The permissions control's entry point, and its at-a-glance readout.
///
/// It lives in the identity block because inbound permissions belong to the
/// machine being controlled. Being pinned — outside the notice-stack scroller —
/// it is always one click away and can carry hover paint for free.
///
/// It reads through [Consumer] so the ChangeNotifierProvider.value(gFFI
/// .serverModel) that buildLeftPane already wraps around the whole rail keeps
/// driving its rebuilds. The home page's 1s signature check covers writes made
/// from the settings page's Safety tab in another window.
class PermissionsAccessRow extends StatefulWidget {
  const PermissionsAccessRow({Key? key, this.compact = false})
      : super(key: key);

  final bool compact;

  @override
  State<PermissionsAccessRow> createState() => _PermissionsAccessRowState();
}

class _PermissionsAccessRowState extends State<PermissionsAccessRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    // The model is the ChangeNotifier the rail listens to; the VALUES come from
    // the option store (see snPermOn). Consuming it here is what makes a write
    // through ServerModel.setIncomingPermission repaint this row.
    return Consumer<ServerModel>(builder: (context, model, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final dark = lumenDark(context);
    final compact = widget.compact;
    final onCount = kSnAccessKeys.where(snPermEffective).length;

    // An EXPOSURE meter, not a threat meter: more access = more exposure.
    final IconData stateIcon;
    final Color stateColor;
    if (onCount == 4) {
      stateIcon = Icons.lock_open_outlined;
      stateColor = lumenAdvisory(context); // wide open IS the advisory state
    } else if (onCount == 0) {
      stateIcon = Icons.lock_outline;
      stateColor = MyTheme.snGreen; // view-only is the tightest state
    } else {
      stateIcon = Icons.shield_outlined;
      stateColor = MyTheme.snBlue;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: showPermissionsSheet,
          child: AnimatedContainer(
            duration: lumenDur(context, 140),
            curve: MyTheme.snEase,
            height: compact ? 36 : 48,
            padding: const EdgeInsetsDirectional.fromSTEB(10, 0, 8, 0),
            color: _hover
                ? (dark ? const Color(0x0FFFFFFF) : const Color(0x0F0F172A))
                : Colors.transparent,
            child: Row(
              children: [
                Icon(stateIcon, size: 18, color: stateColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        translate('Permissions'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          color: MyTheme.textMain(context),
                        ),
                      ),
                      if (!compact) const SizedBox(height: 2),
                      // FOUR-GLYPH READOUT: revocation stays visible from the
                      // rail with the sheet CLOSED, which no modal-only design
                      // achieves. Each glyph carries its own Tooltip, which is
                      // why there is deliberately no row-level Tooltip to
                      // conflict with it.
                      if (!compact)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final p in _snPerms)
                              Padding(
                                padding: EdgeInsetsDirectional.only(
                                    end: p.key == kSnAccessKeys.last ? 0 : 4),
                                child: LumenGlyphCell(
                                  icon: p.icon,
                                  on: snPermEffective(p.key),
                                  accent: p.accent,
                                  tooltip: snPermTitle(p.titleKey),
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (snAccessAnyFixed())
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: Icon(Icons.lock_outline,
                        size: 12, color: MyTheme.textDim(context)),
                  ),
                Icon(lumenChevron(context),
                    size: 16, color: MyTheme.textDim(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// THE SHEET
// ===========================================================================

OverlayEntry? _accessEntry;

/// Opens the access console.
///
/// It inserts its own OverlayEntry rather than going through
/// gFFI.dialogManager.show, because `DialogBuilder` (common.dart:884) is typed
/// to return a `CustomAlertDialog` and an arbitrary sheet cannot be passed to
/// it. Everything the manager would have supplied is reproduced here: the same
/// scrim colours, click-mask dismiss, and a single-instance guard doing the job
/// of its tag dedupe.
void showPermissionsSheet() {
  if (!(isDesktop || isWebDesktop)) return;
  final overlayState = globalKey.currentState?.overlay;
  if (overlayState == null) return;
  if (_accessEntry != null) return;

  late final OverlayEntry entry;
  void close() {
    if (_accessEntry != entry) return;
    _accessEntry = null;
    entry.remove();
  }

  entry = OverlayEntry(builder: (context) {
    final light = Theme.of(context).brightness == Brightness.light;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: close,
            child: ColoredBox(color: light ? Colors.black12 : Colors.black45),
          ),
        ),
        // Emerges from the rail, on the same side as its trigger, in BOTH
        // directions: centerStart resolves to the left edge in en/tr and the
        // right edge in fa, which is where the rail is. Never centerEnd — that
        // lands opposite the trigger under exactly one of the two.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            // Absorbs taps that land on the sheet's own empty areas so they do
            // not fall through to the dismiss scrim. Child gestures still win
            // the arena.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: _AccessConsole(close: close),
            ),
          ),
        ),
      ],
    );
  });
  _accessEntry = entry;
  overlayState.insert(entry);
}

class _AccessConsole extends StatefulWidget {
  const _AccessConsole({Key? key, required this.close}) : super(key: key);

  final VoidCallback close;

  @override
  State<_AccessConsole> createState() => _AccessConsoleState();
}

class _AccessConsoleState extends State<_AccessConsole>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entry = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 220));
  final FocusScopeNode _scopeNode = FocusScopeNode();

  @override
  void initState() {
    super.initState();
    // RE-READ ON OPEN. The settings page's Safety tab writes the same five
    // options and the two surfaces are not subscribed to each other, so an
    // operator with that tab open in another window can leave this sheet
    // stale. Re-reading costs one frame and closes the hole.
    gFFI.serverModel.syncIncomingPermissions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entry.duration = lumenDur(context, 220);
      _entry.forward();
      if (!_scopeNode.hasFocus) _scopeNode.requestFocus();
    });
  }

  @override
  void dispose() {
    // Self-healing guard: if the overlay is torn down without close() running
    // (reloadCurrentWindow, hot reload), the single-instance latch would
    // otherwise stay set and the sheet could never reopen.
    _accessEntry = null;
    _entry.dispose();
    _scopeNode.dispose();
    super.dispose();
  }

  Future<void> _setPermission(String key, bool value) async {
    // The ONE write path. Never toggleInput/toggleClipboard/toggleFile/
    // toggleAudio: those are Android-shaped — toggleInput() with an unseeded
    // _inputOk opens showInputWarnAlert, the accessibility dialog.
    await gFFI.serverModel.setIncomingPermission(key, value);
    if (mounted) setState(() {});
  }

  Future<void> _setMode(String value) async {
    await bind.mainSetOption(key: kOptionAccessMode, value: value);
    gFFI.serverModel.syncIncomingPermissions();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // No window minimumSize is set anywhere in main.dart, so both clamps are
    // mandatory rather than polish.
    final w = math.min(372.0, media.size.width - 24);
    // 40 title bar + 28 status line + breathing room.
    final maxH = math.min(media.size.height - 92, 560.0);

    return FocusScope(
      node: _scopeNode,
      autofocus: true,
      // CustomAlertDialog's keyboard contract, on the non-deprecated callback:
      // escape closes, tab traverses, and both report handled so a focused
      // TextField cannot throw on escape.
      onKeyEvent: (node, event) {
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          if (event is KeyDownEvent) widget.close();
          return KeyEventResult.handled;
        } else if (event.logicalKey == LogicalKeyboardKey.tab) {
          if (event is KeyDownEvent) _scopeNode.nextFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: _entry,
        builder: (context, child) {
          final t = MyTheme.snEase.transform(_entry.value);
          return Opacity(
            opacity: t,
            child: FractionalTranslation(
              // Slides out of the rail from the START edge in both directions.
              // -0.045 * 372 is ~17px, so no reduced-motion escape hatch is
              // needed beyond lumenDur.
              translation: Offset((lumenRtl(context) ? .045 : -.045) * (1 - t), 0),
              child: child,
            ),
          );
        },
        // Overlay entries have NO Material ancestor. Without this every InkWell
        // in the sheet silently no-ops.
        child: Material(
          type: MaterialType.transparency,
          child: ChangeNotifierProvider.value(
            value: gFFI.serverModel,
            child: Consumer<ServerModel>(
              builder: (context, model, _) => ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxH),
                child: _sheet(context, w),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheet(BuildContext context, double w) {
    final dark = lumenDark(context);
    return LumenSheet(
      onGlass: false,
      elevation: LumenElevation.modal,
      radius: MyTheme.snRadiusLg,
      width: w,
      padding: EdgeInsets.zero,
      // Violet, top-trailing, to distinguish the console from the blue/cyan
      // heroes it floats over.
      bloom: PositionedDirectional(
        end: -50,
        top: -60,
        width: 250,
        height: 190,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                stops: const [0, .5, 1],
                colors: [
                  MyTheme.snViolet.withOpacity(dark ? .20 : .12),
                  MyTheme.snViolet.withOpacity(dark ? .07 : .04),
                  MyTheme.snViolet.withOpacity(0),
                ],
              ),
            ),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          _fullBleedLine(context),
          _segment(context),
          _fullBleedLine(context),
          // Legal only because there is no BackdropFilter anywhere in this
          // sheet's ancestry.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _banner(context),
                  for (final p in _snPerms) _row(context, p),
                ],
              ),
            ),
          ),
          _fullBleedLine(context),
          _footer(context),
        ],
      ),
    );
  }

  Widget _fullBleedLine(BuildContext context) =>
      Container(height: 1, color: MyTheme.line(context));

  Widget _header(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 8, 0),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                gradient: LinearGradient(
                  begin: lumenLit(context),
                  end: lumenShade(context),
                  colors: [
                    MyTheme.snBlue.withOpacity(.18),
                    MyTheme.snCyan.withOpacity(.12),
                  ],
                ),
                border:
                    Border.all(color: MyTheme.snCyan.withOpacity(.30), width: 1),
              ),
              child: const Center(
                child:
                    Icon(Icons.shield_outlined, size: 15, color: MyTheme.snCyan),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                translate('Permissions'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  letterSpacing: lumenLetterSpacing(context, .2),
                  color: MyTheme.textMain(context),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: MyTheme.textMuted(context),
              tooltip: translate('Close'),
              onPressed: widget.close,
            ),
          ],
        ),
      ),
    );
  }

  /// ACCESS-MODE SEGMENT. Reading order runs least -> most access, and the row
  /// mirrors automatically because the three segments are laid out start -> end.
  ///
  /// No sliding pill: the three labels have wildly different widths across
  /// fa/tr/en and a measured pill would need a LayoutBuilder per locale.
  Widget _segment(BuildContext context) {
    final dark = lumenDark(context);
    final fixed = snOptionFixed(kOptionAccessMode);
    final mode = snAccessMode();
    // Exactly the settings page's own values.
    final modes = <String>['view', defaultOptionAccessMode, 'full'];
    const labels = ['Screen Share', 'Custom', 'Full Access'];
    final selected = mode == 'view' ? 0 : (mode == 'full' ? 2 : 1);

    Widget track = Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: dark ? const Color(0x1FFFFFFF) : const Color(0x120F172A),
        border: Border.all(color: MyTheme.line(context), width: 1),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: fixed ? null : () => _setMode(modes[i]),
                child: AnimatedContainer(
                  duration: lumenDur(context, 160),
                  curve: MyTheme.snEase,
                  height: 28,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: i == selected
                        ? LinearGradient(
                            begin: lumenLit(context),
                            end: lumenShade(context),
                            colors: dark
                                ? const [Color(0x38FFFFFF), Color(0x1FFFFFFF)]
                                : const [Color(0xFFFFFFFF), Color(0xF0FFFFFF)],
                          )
                        : null,
                    border: i == selected
                        ? Border.all(
                            color: dark
                                ? const Color(0x2EFFFFFF)
                                : const Color(0x1F0F172A),
                            width: 1)
                        : null,
                    boxShadow: i == selected
                        ? [
                            BoxShadow(
                              color: dark
                                  ? const Color(0x4D000000)
                                  : const Color(0x140F172A),
                              blurRadius: 6,
                              spreadRadius: -2,
                              offset: const Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  child: Center(
                    // fa "اشتراک گذاری صفحه" and tr "Ekran Paylaşımı" are both
                    // borderline in a ~112px cell at 11.5/w700. They must
                    // SHRINK, not clip.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        translate(labels[i]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              i == selected ? FontWeight.w700 : FontWeight.w500,
                          color: i == selected
                              ? MyTheme.textMain(context)
                              : MyTheme.textMuted(context),
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

    if (fixed) {
      track = Opacity(opacity: 0.45, child: IgnorePointer(child: track));
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
      child: fixed
          ? Row(children: [
              Expanded(child: track),
              const SizedBox(width: 6),
              Icon(Icons.lock_outline,
                  size: 13, color: MyTheme.textDim(context)),
            ])
          : track,
    );
  }

  /// THE HONEST ANSWER to "did I just revoke something from a live session?".
  /// With a global option: NO — you changed the policy for the next connection.
  /// `android_permission_may_not_change_tip` says exactly that, is platform
  /// neutral in en/fa/tr, and is already translated:
  /// "Permissions for established connections may not be changed instantly
  /// until reconnected."
  ///
  /// Known limitation: videoConnCount counts VIDEO connections only, so a
  /// file-transfer-only or terminal-only session will not raise this banner.
  Widget _banner(BuildContext context) {
    return AnimatedSize(
      duration: lumenDur(context, 200),
      curve: MyTheme.snEase,
      alignment: Alignment.topCenter,
      child: Obx(() {
        if (stateGlobal.videoConnCount.value <= 0) {
          return const SizedBox(height: 0);
        }
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x1FFBBF24), Color(0x0AFBBF24)],
            ),
            border: Border(
              top: BorderSide(color: Color(0x3DFBBF24), width: 1),
              bottom: BorderSide(color: Color(0x3DFBBF24), width: 1),
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 15, color: lumenAdvisory(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    translate('android_permission_may_not_change_tip'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: MyTheme.textMain(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _row(BuildContext context, _SnPerm p) {
    final forced = snAccessForced();
    return _PermissionRow(
      perm: p,
      // The switch still SHOWS the effective/forced value while locked: a row
      // that silently ignores taps is worse than one that says it cannot move.
      on: forced ?? snPermOn(p.key),
      locked: forced != null || snOptionFixed(p.key),
      onChanged: (v) => _setPermission(p.key, v),
    );
  }

  Widget _footer(BuildContext context) {
    final dark = lumenDark(context);
    final onCount = kSnAccessKeys.where(snPermEffective).length;
    final Color modeAccent = onCount == 4
        ? lumenAdvisory(context)
        : (onCount == 0 ? MyTheme.snGreen : MyTheme.snBlue);
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 12, 0),
        child: Row(
          children: [
            Container(
              height: 22,
              padding: const EdgeInsetsDirectional.only(start: 8, end: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                color: modeAccent.withOpacity(dark ? .16 : .12),
                border: Border.all(color: modeAccent.withOpacity(.34), width: 1),
              ),
              child: Center(
                child: Text(
                  snAccessModeWord(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: modeAccent,
                  ),
                ),
              ),
            ),
            Obx(() {
              final n = stateGlobal.videoConnCount.value;
              if (n <= 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsetsDirectional.only(start: 10),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: MyTheme.snGreen),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${translate('Connected')} · $n',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: MyTheme.textMuted(context),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const Spacer(),
            // NO "Apply" button: every toggle writes through immediately, and
            // an Apply button on an instant-effect control is a lie.
            dialogButton('Close', onPressed: widget.close),
          ],
        ),
      ),
    );
  }
}

/// One 64px permission row.
///
/// What OFF communicates — five simultaneous static signals, no toast, nothing
/// that can be missed or dismissed:
///   1. the row SINKS (glyph well recesses, glyph goes dim, title goes muted);
///   2. a 2px amber bar on the row's LEADING edge fades in over 220ms and then
///      HOLDS — a pulse that decayed would let the operator miss the one thing
///      they need to notice;
///   3. the glyph well flashes amber ONCE, on the ON->OFF transition only:
///      granting is unremarkable, revoking is the event worth registering;
///   4. the footer chip and the rail's four-glyph readout both recompute, so
///      the change stays visible after the sheet closes;
///   5. if a session is live, the amber banner is on screen.
class _PermissionRow extends StatefulWidget {
  const _PermissionRow({
    Key? key,
    required this.perm,
    required this.on,
    required this.locked,
    required this.onChanged,
  }) : super(key: key);

  final _SnPerm perm;
  final bool on;
  final bool locked;
  final ValueChanged<bool> onChanged;

  @override
  State<_PermissionRow> createState() => _PermissionRowState();
}

class _PermissionRowState extends State<_PermissionRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flash = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
  bool _hover = false;

  @override
  void didUpdateWidget(covariant _PermissionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.on && !widget.on) {
      _flash.duration = lumenDur(context, 320);
      _flash.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = lumenDark(context);
    final accent = widget.perm.accent;
    final on = widget.on;

    final Color restFill = on
        ? accent.withOpacity(dark ? .16 : .12)
        : (dark ? const Color(0x14000000) : const Color(0x0A0F172A));

    final Widget glyphWell = AnimatedBuilder(
      animation: _flash,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_flash.value);
        final fill = _flash.value > 0 && _flash.value < 1
            ? Color.alphaBlend(
                lumenAdvisory(context).withOpacity(.20 * (1 - t)), restFill)
            : restFill;
        return AnimatedContainer(
          duration: lumenDur(context, 180),
          curve: MyTheme.snEase,
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: fill,
            border: Border.all(
              color: on ? accent.withOpacity(.34) : MyTheme.line(context),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(widget.perm.icon,
                size: 17, color: on ? accent : MyTheme.textDim(context)),
          ),
        );
      },
    );

    Widget row = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: lumenDur(context, 140),
        curve: MyTheme.snEase,
        height: 64,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 10, 0),
        color: _hover && !widget.locked
            ? (dark ? const Color(0x0AFFFFFF) : const Color(0x0A0F172A))
            : Colors.transparent,
        child: Row(
          children: [
            glyphWell,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                snPermTitle(widget.perm.titleKey),
                // tr "Kopyalanan geçici veriye izin ver" wraps to two lines in
                // the 229px title column and still fits inside 64px.
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: on
                      ? MyTheme.textMain(context)
                      : MyTheme.textMuted(context),
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (widget.locked)
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Icon(Icons.lock_outline,
                    size: 13, color: MyTheme.textDim(context)),
              ),
            LumenSwitch(on: on, accent: accent, onChanged: widget.onChanged),
          ],
        ),
      ),
    );

    if (widget.locked) {
      // The single sanctioned Opacity over a subtree in this design: one 64px
      // locked row.
      row = Opacity(opacity: 0.45, child: IgnorePointer(child: row));
    }

    return Stack(
      children: [
        row,
        // PositionedDirectional, so the marker sits on the row's LEADING edge
        // in all three locales.
        PositionedDirectional(
          start: 0,
          top: 8,
          bottom: 8,
          width: 2,
          child: IgnorePointer(
            child: AnimatedOpacity(
              duration: lumenDur(context, 220),
              curve: MyTheme.snEase,
              opacity: on ? 0 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(1),
                  color: lumenAdvisory(context),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
