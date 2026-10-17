// main window right pane

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/popup_menu.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_hbb/models/peer_model.dart';

import '../../common.dart';
import '../../common/widgets/glass_container.dart';
import '../../common/widgets/lumen.dart';
import '../../common/formatter/id_formatter.dart';
import '../../common/widgets/peer_tab_page.dart';
import '../../common/widgets/autocomplete.dart';
import '../../models/platform_model.dart';
import '../../desktop/widgets/material_mod_popup_menu.dart' as mod_menu;

class OnlineStatusWidget extends StatefulWidget {
  const OnlineStatusWidget({Key? key, this.onSvcStatusChanged})
      : super(key: key);

  final VoidCallback? onSvcStatusChanged;

  @override
  State<OnlineStatusWidget> createState() => _OnlineStatusWidgetState();
}

/// State for the connection page.
class _OnlineStatusWidgetState extends State<OnlineStatusWidget> {
  final _svcStopped = Get.find<RxBool>(tag: 'stop-service');
  final _svcIsUsingPublicServer = true.obs;
  // Signalling endpoint this client is actually pointed at, read from the
  // options in updateStatus(). Empty means "nothing configured", in which case
  // the whole segment is dropped rather than filled with a guess.
  final _serverLabelKey = ''.obs;
  final _serverHost = ''.obs;
  Timer? _updateTimer;

  // Status-line type size. The strip is a fixed 28px FRAME element now, so the
  // old em * 3 = 42px box is gone; isIncomingOnly keeps an unbounded height
  // because that host stacks two rows in a Column.
  double get em => 12.0;
  double? get height => bind.isIncomingOnly() ? null : 28;

  void onUsePublicServerGuide() {
    const url = "https://www.servernet.cloud";
    canLaunchUrlString(url).then((can) {
      if (can) {
        launchUrlString(url);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(Duration(seconds: 1), () async {
      updateStatus();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    startServiceWidget() => Offstage(
          offstage: !_svcStopped.value,
          child: Padding(
            // Directional: this gap follows the status text, which sits at the
            // start edge in en/tr and at the end edge in fa.
            padding: const EdgeInsetsDirectional.only(start: 10),
            child: InkWell(
                onTap: () async {
                  await start_service(true);
                },
                child: Text(translate("Start service"),
                    style: TextStyle(
                        decoration: TextDecoration.underline, fontSize: em))),
          ),
        );

    setupServerWidget() => Flexible(
          child: Offstage(
            offstage: !(!_svcStopped.value &&
                stateGlobal.svcStatus.value == SvcStatus.ready &&
                _svcIsUsingPublicServer.value),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(', ', style: TextStyle(fontSize: em)),
                Flexible(
                  child: InkWell(
                    onTap: onUsePublicServerGuide,
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            translate('setup_server_tip'),
                            style: TextStyle(
                                decoration: TextDecoration.underline,
                                fontSize: em),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );

    // Brand tokens instead of the old inline ARGB literals.
    statusColor() => _svcStopped.value ||
            stateGlobal.svcStatus.value == SvcStatus.connecting
        ? kColorWarn
        : (stateGlobal.svcStatus.value == SvcStatus.ready
            ? MyTheme.snGreen
            : Theme.of(context).colorScheme.error);

    basicWidget() => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Everything up to the Spacer lives in one Expanded group so the
            // brand link below stays flush with the trailing edge no matter how
            // little of their share the flexible segments actually consume.
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // The status lamp. Same 7px core the flat dot had, now with
                  // LUMEN's static 18px halo so the strip reads as part of the
                  // same lit material as the two hero panels. It reports
                  // exactly what it reported before: warn / green / error.
                  //
                  // Margin 3, not 8: the lamp's footprint is 18px against the
                  // dot's 8, and 3 + 18 + 3 = 24 keeps the strip's start offset
                  // — and therefore the isIncomingOnly second row's start: 24
                  // below — pixel-identical. Symmetric, so nothing to mirror.
                  LumenLamp(color: statusColor()).marginSymmetric(horizontal: 3),
                  Flexible(
                    child: Container(
                      width: isIncomingOnly ? 226 : null,
                      child: _buildConnStatusMsg(),
                    ),
                  ),
                  // stop
                  if (!isIncomingOnly) startServiceWidget(),
                  // ready && public
                  // No need to show the guide if is custom client.
                  if (!isIncomingOnly) setupServerWidget(),
                  // relay label + host. No latency segment: nothing in this
                  // process exposes a round-trip time to the signalling server,
                  // and a made-up number is worse than no number.
                  if (!isIncomingOnly && _serverHost.value.isNotEmpty)
                    _buildServerSegment(context),
                  const Spacer(),
                ],
              ),
            ),
            // Trailing end of the strip. Row order, not Positioned(right:), so
            // it mirrors to the left edge under fa.
            // loadPowered() carries a 6px top margin of its own; the matching
            // bottom pad keeps it optically centred in the 28px strip.
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: loadPowered(context),
            ),
          ],
        );

    return Padding(
      padding: EdgeInsetsDirectional.only(end: isIncomingOnly ? 8 : 10),
      child: Container(
        height: height,
        child: Obx(() => isIncomingOnly
            ? Column(
                children: [
                  basicWidget(),
                  Padding(
                    // start 24 = dot (8) + its 8/8 margins, so the link lines
                    // up under the status text in both directions.
                    padding:
                        const EdgeInsetsDirectional.only(top: 2.0, start: 24.0),
                    child: Align(
                      child: startServiceWidget(),
                      alignment: AlignmentDirectional.centerStart,
                    ),
                  ),
                ],
              )
            : basicWidget()),
      ),
    );
  }

  /// "Relay server: host". The host is machine-readable, so it is mono and
  /// pinned to LTR even in fa.
  Widget _buildServerSegment(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // A 1px hairline instead of a bullet glyph. LUMEN separates with light,
        // not with punctuation, and a vertical rule has no handedness — the
        // '  •  ' string also picked up the ambient font fallback differently
        // in fa than in en, so the optical gap moved with the locale.
        Container(
          width: 1,
          height: 12,
          color: MyTheme.line2(context),
          margin: const EdgeInsetsDirectional.only(start: 10, end: 10),
        ),
        Text(
          '${translate(_serverLabelKey.value)}: ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: em, color: MyTheme.textMuted(context)),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 200),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              _serverHost.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: em,
                fontFamilyFallback: MyTheme.plateMono,
                color: MyTheme.textMain(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  _buildConnStatusMsg() {
    widget.onSvcStatusChanged?.call();
    return Text(
      _svcStopped.value
          ? translate("Service is not running")
          : stateGlobal.svcStatus.value == SvcStatus.connecting
              ? translate("connecting_status")
              : stateGlobal.svcStatus.value == SvcStatus.notReady
                  ? translate("not_ready_status")
                  : translate('Ready'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // w500: this is the strip's one primary value, and it now sits beside a
      // lamp with a halo rather than a flat dot. No letterSpacing — see
      // lumenLetterSpacing: it would split Persian letter joins.
      style: TextStyle(
        fontSize: em,
        fontWeight: FontWeight.w500,
        color: MyTheme.textMain(context),
      ),
    );
  }

  updateStatus() async {
    final status =
        jsonDecode(await bind.mainGetConnectStatus()) as Map<String, dynamic>;
    final statusNum = status['status_num'] as int;
    if (statusNum == 0) {
      stateGlobal.svcStatus.value = SvcStatus.connecting;
    } else if (statusNum == -1) {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    } else if (statusNum == 1) {
      stateGlobal.svcStatus.value = SvcStatus.ready;
    } else {
      stateGlobal.svcStatus.value = SvcStatus.notReady;
    }
    _svcIsUsingPublicServer.value = await bind.mainIsUsingPublicServer();
    try {
      stateGlobal.videoConnCount.value = status['video_conn_count'] as int;
    } catch (_) {}
    _updateServerInfo();
  }

  /// The strip reports the endpoint the client is really pointed at: the
  /// explicit relay if one is set, otherwise the rendezvous (ID) server, and
  /// finally whatever the build was stamped with. Rx assignment is a no-op when
  /// the value is unchanged, so this 1 Hz poll does not force a rebuild.
  void _updateServerInfo() {
    var labelKey = 'Relay Server';
    var host = bind.mainGetOptionSync(key: 'relay-server').trim();
    if (host.isEmpty) {
      labelKey = 'ID Server';
      host = bind.mainGetOptionSync(key: 'custom-rendezvous-server').trim();
    }
    if (host.isEmpty) {
      host = bind.mainGetBuildinOption(key: 'custom-rendezvous-server').trim();
    }
    _serverLabelKey.value = host.isEmpty ? '' : labelKey;
    _serverHost.value = host;
  }
}

/// Connection page for connecting to a remote peer.
class ConnectionPage extends StatefulWidget {
  const ConnectionPage({Key? key}) : super(key: key);

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

/// State for the connection page.
class _ConnectionPageState extends State<ConnectionPage>
    with SingleTickerProviderStateMixin, WindowListener {
  /// Controller for the id input bar.
  final _idController = IDTextEditingController();

  final RxBool _idInputFocused = false.obs;
  final FocusNode _idFocusNode = FocusNode();
  final TextEditingController _idEditingController = TextEditingController();

  String selectedConnectionType = 'Connect';

  bool isWindowMinimized = false;

  final AllPeersLoader _allPeersLoader = AllPeersLoader();

  // https://github.com/flutter/flutter/issues/157244
  Iterable<Peer> _autocompleteOpts = [];

  final _menuOpen = false.obs;

  @override
  void initState() {
    super.initState();
    _allPeersLoader.init(setState);
    _idFocusNode.addListener(onFocusChanged);
    if (_idController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final lastRemoteId = await bind.mainGetLastRemoteId();
        if (lastRemoteId != _idController.id) {
          setState(() {
            _idController.id = lastRemoteId;
          });
        }
      });
    }
    Get.put<TextEditingController>(_idEditingController);
    Get.put<IDTextEditingController>(_idController);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _idController.dispose();
    windowManager.removeListener(this);
    _allPeersLoader.clear();
    _idFocusNode.removeListener(onFocusChanged);
    _idFocusNode.dispose();
    _idEditingController.dispose();
    if (Get.isRegistered<IDTextEditingController>()) {
      Get.delete<IDTextEditingController>();
    }
    if (Get.isRegistered<TextEditingController>()) {
      Get.delete<TextEditingController>();
    }
    super.dispose();
  }

  @override
  void onWindowEvent(String eventName) {
    super.onWindowEvent(eventName);
    if (eventName == 'minimize') {
      isWindowMinimized = true;
    } else if (eventName == 'maximize' || eventName == 'restore') {
      if (isWindowMinimized && isWindows) {
        // windows can't update when minimized.
        Get.forceAppUpdate();
      }
      isWindowMinimized = false;
    }
  }

  @override
  void onWindowEnterFullScreen() {
    // Remove edge border by setting the value to zero.
    stateGlobal.resizeEdgeSize.value = 0;
  }

  @override
  void onWindowLeaveFullScreen() {
    // Restore edge border to default edge size.
    stateGlobal.resizeEdgeSize.value = stateGlobal.isMaximized.isTrue
        ? kMaximizeEdgeSize
        : windowResizeEdgeSize;
  }

  @override
  void onWindowClose() {
    super.onWindowClose();
    bind.mainOnMainWindowClose();
  }

  void onFocusChanged() {
    _idInputFocused.value = _idFocusNode.hasFocus;
    if (_idFocusNode.hasFocus) {
      if (_allPeersLoader.needLoad) {
        _allPeersLoader.getAllPeers();
      }

      final textLength = _idEditingController.value.text.length;
      // Select all to facilitate removing text, just following the behavior of address input of chrome.
      _idEditingController.selection =
          TextSelection(baseOffset: 0, extentOffset: textLength);
    }
  }

  @override
  Widget build(BuildContext context) {
    // isOutgoingOnly is no longer read here: the status line and the ID board
    // moved to desktop_home_page.dart, which gates both on it there.
    return Column(
      children: [
        Expanded(
            child: Padding(
                // Directional: the gap belongs against the operator-rail
                // divider, which moves to the right edge under fa.
                padding: const EdgeInsetsDirectional.only(start: 12.0),
                child: Column(
          children: [
            // HERO B names itself now. The header carries the outbound lamp and
            // the id_input_tip help glyph that used to hang off the in-bar
            // label; see _buildHeroHeader.
            _buildHeroHeader(context),
            const SizedBox(height: 8),
            // The command bar is full width now, so Expanded rather than
            // Flexible: it must claim the whole work area, not shrink to the
            // intrinsic width of its contents.
            Row(
              children: [
                Expanded(child: _buildRemoteIDTextField(context)),
              ],
            ),
            // 14, not 12: the bar grew to 72px with a 24px radius, and a 12px
            // seam made the deck look glued to it instead of seated under it.
            const SizedBox(height: 14),
            Expanded(child: _buildDeck(context)),
          ],
        ))),
        // The status strip moved to DesktopHomePage.buildStatusLine so it spans
        // the full window width, under the rail as well as this pane. Leaving a
        // copy here rendered it twice.
      ],
    );
  }

  /// Hero B's header. 18px of type and one lamp buys the panel a name and an
  /// explanation in three languages — stock RustDesk has neither.
  ///
  /// The lamp is BLUE because this panel is outbound; Hero A ("Your Desktop")
  /// carries the cyan inbound one. Two colours do that job better than an icon
  /// would at 11px across fa/en/tr.
  ///
  /// The height is fixed on purpose: the IRANSans -> Segoe UI fallback on the
  /// four Turkish glyphs shifts the baseline about half a pixel at w700/11px,
  /// and a fixed box means that can never reflow the bar below it.
  Widget _buildHeroHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 14),
      child: SizedBox(
        height: 18,
        child: Row(
          children: [
            const LumenLamp(color: MyTheme.snBlue),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                translate('Control Remote Desktop'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  // 0 under fa: letterSpacing splits Persian letter joins.
                  letterSpacing: lumenLetterSpacing(context, 1.15),
                  color: MyTheme.textMuted(context),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // id_input_tip lives here now, not on the in-bar label — a Tooltip
            // on a 13px glyph delivers the whole string for 0px of layout,
            // where an inline body would cost 28px in fa/tr and make the
            // panel's height depend on the locale.
            Tooltip(
              waitDuration: const Duration(milliseconds: 300),
              message: translate('id_input_tip'),
              child: Icon(
                Icons.help_outline_outlined,
                size: 13,
                color: MyTheme.textDim(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// THE DECK. Opaque on purpose and forever: the aurora used to bleed straight
  /// through the peer list, and 12px text over a gradient is the one thing this
  /// design must never do. No GlassContainer here under any circumstances —
  /// this subtree holds ListView.builder and DynamicGridView.builder, and a
  /// blur above a scroller re-rasterises every frame.
  ///
  /// The topStart radius matches the command bar's 24 so the bar and the deck
  /// read as one object, and a 1px specular lip sits on the seam. That lip is a
  /// Stack SIBLING painted above PeerTabPage, never an ancestor of it.
  Widget _buildDeck(BuildContext context) {
    final isDark = lumenDark(context);
    return Container(
      decoration: BoxDecoration(
        color: MyTheme.deck(context),
        border: Border(top: BorderSide(color: MyTheme.line(context))),
        borderRadius: const BorderRadiusDirectional.only(
          topStart: Radius.circular(MyTheme.snRadiusLg),
        ).resolve(Directionality.of(context)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PeerTabPage(),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 1,
            child: IgnorePointer(
              child: ColoredBox(
                color: isDark ? const Color(0x14FFFFFF) : const Color(0xCCFFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Callback for the connect button.
  /// Connects to the selected peer.
  void onConnect(
      {bool isFileTransfer = false,
      bool isViewCamera = false,
      bool isTerminal = false}) {
    var id = _idController.id;
    connect(context, id,
        isFileTransfer: isFileTransfer,
        isViewCamera: isViewCamera,
        isTerminal: isTerminal);
  }

  /// THE COMMAND BAR — 72px, and the only genuinely translucent object in the
  /// product. That is its role in the composition: Hero A is a sheet lifted off
  /// glass, Hero B *is* glass.
  ///
  /// This holds the app's third and last live BackdropFilter (title bar and
  /// operator rail own the other two). It is RE-PARAMETERISED here, never
  /// added: net new blur instances across this whole change is ZERO, and sigma
  /// stays at 8.
  ///
  /// Why this surface earns the blur over every alternative:
  ///  (a) it is the only hero whose backdrop is the RAW aurora — Hero A already
  ///      sits on the rail's blur plus its frameTint, so a blur there would
  ///      blur an already-blurred surface for a sub-1% luminance change;
  ///  (b) at 29-40% alpha (dark) / 62-78% (light) these are the lowest alphas
  ///      in the product, which is what makes the bar feel physically in front
  ///      of the app. Static translucency that low over an UNBLURRED aurora
  ///      would put the blobs' edge frequency directly behind an 18px mono text
  ///      field. NOTE THE RATIONALE: GlassBackdrop is a StatelessWidget with no
  ///      Ticker — the aurora is STATIC. This is a spatial-frequency argument,
  ///      not a motion one. Nobody may justify this blur with "the frosted edge
  ///      shifts as the blobs drift", and nobody may add a drift animation to
  ///      make that true. A static backdrop is in fact the cheapest possible
  ///      case for the raster cache;
  ///  (c) nothing in its subtree scrolls — the autocomplete dropdown is a
  ///      RawAutocomplete OVERLAY child, not a descendant, and the peer deck's
  ///      builders are siblings below it. This blur never re-rasterises on a
  ///      scroll tick, which is the failure mode the three-blur rule exists to
  ///      prevent;
  ///  (d) it is fixed height, full width and never moves.
  Widget _buildRemoteIDTextField(BuildContext context) {
    final isDark = lumenDark(context);
    return LayoutBuilder(builder: (context, constraints) {
      // Sized for the longest locale: tr/fa labels run ~40% longer than en, so
      // the leading label is dropped first and the secondary command collapses
      // to its icon before anything can overflow. Both thresholds moved up by
      // 40px because the controls grew ~8px each (36 -> 40, field 36 -> 44).
      final showLabel = constraints.maxWidth >= 660;
      final compactTransfer = constraints.maxWidth < 500;
      return GlassContainer(
        height: 72,
        borderRadius: MyTheme.snRadiusLg,
        // UNCHANGED. Do not raise this: over a static backdrop a higher sigma
        // is a real cost for an imperceptible gain.
        blurSigma: 8,
        // The rim painter owns the edge. A uniform 1px border is the clearest
        // tell of a glassmorphism template, so GlassContainer's default one is
        // suppressed rather than restyled.
        borderColor: Colors.transparent,
        borderWidth: 0,
        // The inner Stack pads, so the bloom and the rim can reach the corners.
        padding: EdgeInsets.zero,
        // Passing `gradient` makes GlassContainer's tint/opacity silent no-ops,
        // which is intended: the fill runs lit-corner -> shade-corner, and it
        // mirrors with the locale.
        gradient: LinearGradient(
          begin: lumenLit(context),
          end: lumenShade(context),
          colors: isDark
              ? const [Color(0x66131C31), Color(0x4A0B0F1B)] // 40% -> 29%
              : const [Color(0xC7FFFFFF), Color(0x9EF4F7FD)], // 78% -> 62%
        ),
        // Exactly one shadow, negative spread: a seat under the bar, not a halo
        // around it. Passing a list also suppresses GlassContainer's default
        // 24px shadow, which was a halo.
        boxShadow: [
          BoxShadow(
            color: isDark ? const Color(0x59000000) : const Color(0x140F172A),
            blurRadius: 22,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
        child: Stack(
          // Centre, so the 44px well and the 40px buttons sit optically in the
          // 72px bar instead of hanging off the top edge.
          alignment: Alignment.center,
          children: [
            // The one bloom this surface is allowed, clipped by
            // GlassContainer's own ClipRRect. Trailing corner, so it never
            // competes with the rim's lit corner at the reading entry.
            PositionedDirectional(
              end: -40,
              top: -34,
              width: 230,
              height: 160,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: .78,
                      stops: const [0, .5, 1],
                      colors: [
                        MyTheme.snBlue.withOpacity(isDark ? .20 : .13),
                        MyTheme.snCyan.withOpacity(isDark ? .08 : .05),
                        MyTheme.snCyan.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // THE SIGNATURE. Under the content, so the rim can never dim text.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: LumenRimPainter(
                    radius: MyTheme.snRadiusLg,
                    dark: isDark,
                    lit: lumenLit(context),
                    shade: lumenShade(context),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 14, 0),
              child: Ink(
                child: Row(
                  children: [
                    if (showLabel) _buildBarLabel(context),
                    if (showLabel) const SizedBox(width: 14),
                    Expanded(child: _buildIdInput(context)),
                    const SizedBox(width: 12),
                    _buildConnectButton(context),
                    const SizedBox(width: 8),
                    _buildTransferFileButton(context, compact: compactTransfer),
                    const SizedBox(width: 8),
                    _buildOverflowButton(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Built locally on purpose: common/widgets/connection_page_title.dart is
  /// shared with mobile and must not grow a desktop-only compact variant.
  ///
  /// The help glyph that used to sit beside this label moved up into
  /// _buildHeroHeader. Leaving both would have shown the same 400-character
  /// id_input_tip twice on one panel. The label itself STAYS: at >= 660px it
  /// costs nothing and is a useful affordance.
  Widget _buildBarLabel(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 172),
      child: Text(
        translate('Remote ID'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: MyTheme.textMuted(context),
        ),
      ),
    );
  }

  /// Primary command. The ambient elevatedButtonTheme only paints a flat fill,
  /// so the brand gradient goes on an explicit Ink.decoration.
  ///
  /// 40px tall and 12px round so it seats with the 44px ID well beside it. Two
  /// LUMEN additions: a 1px top specular inside its own clip, and the accent's
  /// OWN bloom instead of a black shadow — an accent surface that casts a grey
  /// shadow reads as a sticker, one that casts its own colour reads as lit.
  ///
  /// MyTheme.snGradient stays ABSOLUTE (it is brand identity, not a lighting
  /// cue) — unlike the rim, it does not mirror under fa.
  Widget _buildConnectButton(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: MyTheme.snGradient,
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x593B82F6),
              blurRadius: 16,
              spreadRadius: -4,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: () {
            onConnect();
          },
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(
              children: [
                Container(
                  height: 40,
                  constraints: const BoxConstraints(minWidth: 88, maxWidth: 168),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    translate("Connect"),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                // Horizontal, so there is nothing to mirror.
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: 1,
                  child: const IgnorePointer(
                    child: ColoredBox(color: Color(0x59FFFFFF)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Promoted out of the overflow menu: file transfer is a first-class command,
  /// not a hidden one. View camera and Terminal stay in the overflow.
  Widget _buildTransferFileButton(BuildContext context,
      {required bool compact}) {
    // 12, matching Connect and the ID well: at 40px tall, snRadiusSm's 10 read
    // as a different family of corner from the 24px bar around it.
    final radius = BorderRadius.circular(12);
    final fg = MyTheme.textMain(context);
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: () => onConnect(isFileTransfer: true),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          constraints:
              BoxConstraints(minWidth: 40, maxWidth: compact ? 40 : 164),
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: MyTheme.line2(context)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_outlined, size: 15, color: fg),
              if (!compact) const SizedBox(width: 6),
              if (!compact)
                Flexible(
                  child: Text(
                    translate("Transfer file"),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: fg),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return compact
        ? Tooltip(
            waitDuration: const Duration(milliseconds: 300),
            message: translate("Transfer file"),
            child: button,
          )
        : button;
  }

  /// The ID field. Machine-readable value: pinned to LTR with a mono fallback
  /// so a Persian UI can never render a device ID in Persian digits.
  Widget _buildIdInput(BuildContext context) {
    return LayoutBuilder(builder: (context, fieldConstraints) {
      // The dropdown is anchored to the field, so measuring the field is how
      // the overlay tracks the width of the bar at any window size.
      final overlayMaxWidth = fieldConstraints.maxWidth;
      return RawAutocomplete<Peer>(
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text == '') {
                      _autocompleteOpts = const Iterable<Peer>.empty();
                    } else if (_allPeersLoader.peers.isEmpty &&
                        !_allPeersLoader.isPeersLoaded) {
                      Peer emptyPeer = Peer(
                        id: '',
                        username: '',
                        hostname: '',
                        alias: '',
                        platform: '',
                        tags: [],
                        hash: '',
                        password: '',
                        forceAlwaysRelay: false,
                        rdpPort: '',
                        rdpUsername: '',
                        loginName: '',
                        device_group_name: '',
                        note: '',
                      );
                      _autocompleteOpts = [emptyPeer];
                    } else {
                      String textWithoutSpaces =
                          textEditingValue.text.replaceAll(" ", "");
                      if (int.tryParse(textWithoutSpaces) != null) {
                        textEditingValue = TextEditingValue(
                          text: textWithoutSpaces,
                          selection: textEditingValue.selection,
                        );
                      }
                      String textToFind = textEditingValue.text.toLowerCase();
                      _autocompleteOpts = _allPeersLoader.peers
                          .where((peer) =>
                              peer.id.toLowerCase().contains(textToFind) ||
                              peer.username
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.hostname
                                  .toLowerCase()
                                  .contains(textToFind) ||
                              peer.alias.toLowerCase().contains(textToFind))
                          .toList();
                      _allPeersLoader.queryOnlines(_autocompleteOpts);
                    }
                    return _autocompleteOpts;
                  },
                  focusNode: _idFocusNode,
                  textEditingController: _idEditingController,
                  fieldViewBuilder: (
                    BuildContext context,
                    TextEditingController fieldTextEditingController,
                    FocusNode fieldFocusNode,
                    VoidCallback onFieldSubmitted,
                  ) {
                    updateTextAndPreserveSelection(
                        fieldTextEditingController, _idController.text);
                    // The Obx stays here: _idInputFocused drives the hint AND
                    // the well's focus state, and hoisting the field out of it
                    // kills that reactivity.
                    return Obx(() {
                      final focused = _idInputFocused.value;
                      final isDark = lumenDark(context);
                      final d = lumenDur(context, 160);
                      // THE ID WELL — a recess, per the three-depth rule: every
                      // control that receives input lives in a well. Free, in
                      // the sense that _idInputFocused already existed.
                      return AnimatedContainer(
                        duration: d,
                        curve: MyTheme.snEase,
                        height: 44,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          // Always darker than its host, in both themes.
                          color: isDark
                              ? const Color(0x2E000000)
                              : const Color(0x0A0F172A),
                          borderRadius: BorderRadius.circular(12),
                          // TRANSPARENT when unfocused rather than absent: a
                          // border that appears on focus insets the child, and
                          // the caret would jump 1px on every focus change.
                          border: Border.all(
                            color: focused
                                ? MyTheme.snCyan.withOpacity(.42)
                                : Colors.transparent,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // The accent glows from BENEATH the surface rather
                            // than colouring it. Always mounted and tweened
                            // through its own alpha, not wrapped in an
                            // AnimatedOpacity: Opacity allocates an offscreen
                            // buffer, and a lerped gradient does not.
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedContainer(
                                  duration: d,
                                  curve: MyTheme.snEase,
                                  decoration: BoxDecoration(
                                    gradient: RadialGradient(
                                      radius: .9,
                                      colors: [
                                        MyTheme.snCyan
                                            .withOpacity(focused ? .10 : 0),
                                        MyTheme.snCyan.withOpacity(0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Light does not reach into a recess...
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: 1,
                              child: IgnorePointer(
                                child: ColoredBox(
                                  color: isDark
                                      ? const Color(0x1F000000)
                                      : const Color(0x120F172A),
                                ),
                              ),
                            ),
                            // ...and returns off the near lip, which goes cyan
                            // on focus. Plain left/right: a horizontal line has
                            // no handedness, so there is nothing to mirror.
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 1,
                              child: IgnorePointer(
                                child: AnimatedContainer(
                                  duration: d,
                                  curve: MyTheme.snEase,
                                  color: focused
                                      ? MyTheme.snCyan.withOpacity(.62)
                                      : (isDark
                                          ? const Color(0x0FFFFFFF)
                                          : const Color(0x99FFFFFF)),
                                ),
                              ),
                            ),
                            // The field itself is unchanged: LTR-pinned with a
                            // mono fallback so a Persian UI can never render a
                            // device ID in Persian digits.
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: TextField(
                                autocorrect: false,
                                enableSuggestions: false,
                                keyboardType: TextInputType.visiblePassword,
                                focusNode: fieldFocusNode,
                                style: TextStyle(
                                  fontFamily: MyTheme.monoFamily,
                                  fontFamilyFallback: MyTheme.monoFallback,
                                  // 22/13 gave a ~57px intrinsic height, which
                                  // overflowed the bar once borders were added.
                                  fontSize: 18,
                                  height: 1.3,
                                ),
                                maxLines: 1,
                                cursorColor: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.color,
                                decoration: InputDecoration(
                                    filled: false,
                                    counterText: '',
                                    // REQUIRED, not cosmetic: the ambient
                                    // desktop inputDecorationTheme supplies an
                                    // OutlineInputBorder(radius 8), which would
                                    // draw a second 8px box inside the well's
                                    // 12px one. The well IS the border now.
                                    border: InputBorder.none,
                                    hintText: _idInputFocused.value
                                        ? null
                                        : translate('Enter Remote ID'),
                                    // textMuted, not textDim: textDim light is
                                    // #68728A, which measures ~4.4:1 against
                                    // this bar's local ground and fails AA for
                                    // a 14px hint. textMuted #5A6478 is ~5.8:1.
                                    hintStyle: TextStyle(
                                        fontSize: 14,
                                        color: MyTheme.textMuted(context)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8)),
                                controller: fieldTextEditingController,
                                inputFormatters: [IDTextInputFormatter()],
                                onChanged: (v) {
                                  _idController.id = v;
                                },
                                onSubmitted: (_) {
                                  onConnect();
                                },
                              ),
                            ).workaroundFreezeLinuxMint(),
                          ],
                        ),
                      );
                    });
                  },
                  onSelected: (option) {
                    setState(() {
                      _idController.id = option.id;
                      FocusScope.of(context).unfocus();
                    });
                  },
                  optionsViewBuilder: (BuildContext context,
                      AutocompleteOnSelected<Peer> onSelected,
                      Iterable<Peer> options) {
                    options = _autocompleteOpts;
                    double maxHeight = options.length * 50;
                    if (options.length == 1) {
                      maxHeight = 52;
                    } else if (options.length == 3) {
                      maxHeight = 146;
                    } else if (options.length == 4) {
                      maxHeight = 193;
                    }
                    maxHeight = maxHeight.clamp(0, 200);

                    return Align(
                      // Directional: the dropdown hangs off the start edge of
                      // the field, which is the right edge under fa.
                      alignment: AlignmentDirectional.topStart,
                      child: Container(
                          decoration: BoxDecoration(
                            // borderRadius on the shadow's own decoration too,
                            // or a negative-spread shadow shows square corners
                            // behind the rounded clip below it.
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: lumenDark(context)
                                    ? const Color(0x73000000)
                                    : const Color(0x240F172A),
                                blurRadius: 26,
                                spreadRadius: -8,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                              // 12, seating with the ID well it hangs from.
                              borderRadius: BorderRadius.circular(12),
                              child: Material(
                                elevation: 4,
                                // DECK layer: this holds a ListView, so it is
                                // OPAQUE and explicitly never glass. Do not
                                // reach for GlassContainer here — a blur above
                                // a scroller re-rasterises every frame.
                                color: MyTheme.card(context),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: maxHeight,
                                    maxWidth: overlayMaxWidth,
                                  ),
                                  child: _allPeersLoader.peers.isEmpty &&
                                          !_allPeersLoader.isPeersLoaded
                                      ? Container(
                                          height: 80,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ))
                                      : Padding(
                                          padding:
                                              const EdgeInsets.only(top: 5),
                                          child: ListView(
                                            children: options
                                                .map((peer) =>
                                                    AutocompletePeerTile(
                                                        onSelect: () =>
                                                            onSelected(peer),
                                                        peer: peer))
                                                .toList(),
                                          ),
                                        ),
                                ),
                              ))),
                    );
                  },
      );
    });
  }

  /// Overflow. Transfer file was promoted to a visible button on the bar; View
  /// camera and Terminal stay here.
  Widget _buildOverflowButton(BuildContext context) {
    return Container(
      height: 40.0,
      width: 40.0,
      decoration: BoxDecoration(
        border: Border.all(color: MyTheme.line2(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: StatefulBuilder(
          builder: (context, setState) {
            var offset = Offset(0, 0);
            return Obx(() => InkWell(
                  child: _menuOpen.value
                      ? Transform.rotate(
                          angle: pi,
                          child: Icon(IconFont.more, size: 14),
                        )
                      : Icon(IconFont.more, size: 14),
                  onTapDown: (e) {
                    offset = e.globalPosition;
                  },
                  onTap: () async {
                    _menuOpen.value = true;
                    final x = offset.dx;
                    final y = offset.dy;
                    await mod_menu
                        .showMenu(
                      context: context,
                      position: RelativeRect.fromLTRB(x, y, x, y),
                      items: [
                        ('View camera', () => onConnect(isViewCamera: true)),
                        (
                          '${translate('Terminal')} (beta)',
                          () => onConnect(isTerminal: true)
                        ),
                      ]
                          .map((e) => MenuEntryButton<String>(
                                childBuilder: (TextStyle? style) => Text(
                                  translate(e.$1),
                                  style: style,
                                ),
                                proc: () => e.$2(),
                                padding: EdgeInsets.symmetric(
                                    horizontal: kDesktopMenuPadding.left),
                                dismissOnClicked: true,
                              ))
                          .map((e) => e.build(
                              context,
                              const MenuConfig(
                                  commonColor:
                                      CustomPopupMenuTheme.commonColor,
                                  height: CustomPopupMenuTheme.height,
                                  dividerHeight:
                                      CustomPopupMenuTheme.dividerHeight)))
                          .expand((i) => i)
                          .toList(),
                      elevation: 8,
                    )
                        .then((_) {
                      _menuOpen.value = false;
                    });
                  },
                ));
          },
        ),
      ),
    );
  }
}
