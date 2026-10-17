import 'dart:async';
import 'dart:io';
import 'dart:convert';
// Prefixed: an unprefixed dart:ui collides with material on TextStyle/Gradient.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/custom_password.dart';
import 'package:flutter_hbb/common/widgets/glass_container.dart';
import 'package:flutter_hbb/common/widgets/instrument_plate.dart';
import 'package:flutter_hbb/common/widgets/lumen.dart';
import 'package:flutter_hbb/common/widgets/permissions_sheet.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/connection_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_tab_page.dart';
import 'package:flutter_hbb/desktop/widgets/update_progress.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:flutter_hbb/plugin/ui_manager.dart';
import 'package:flutter_hbb/utils/multi_window_manager.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../widgets/button.dart';

class DesktopHomePage extends StatefulWidget {
  const DesktopHomePage({Key? key}) : super(key: key);

  @override
  State<DesktopHomePage> createState() => _DesktopHomePageState();
}

const borderColor = Color(0xFF2F65BA);

class _DesktopHomePageState extends State<DesktopHomePage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _leftPaneScrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;
  var systemError = '';
  StreamSubscription? _uniLinksSubscription;
  var svcStopped = false.obs;
  var watchIsCanScreenRecording = false;
  var watchIsProcessTrust = false;
  var watchIsInputMonitoring = false;
  var watchIsCanRecordAudio = false;
  Timer? _updateTimer;
  bool isCardClosed = false;

  final RxBool _editHover = false.obs;
  final RxBool _accountHover = false.obs;
  final RxBool _block = false.obs;

  final GlobalKey _childKey = GlobalKey();

  /// Last seen access-mode + four-permission signature. See initState: the
  /// permissions row has to stay current when the SAME options are written from
  /// the settings page's Safety tab in another window, and the two surfaces are
  /// not subscribed to each other.
  String _accessSig = '';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isIncomingOnly = bind.isIncomingOnly();
    return _buildBlock(
        child: Stack(
      children: [
        const Positioned.fill(child: GlassBackdrop()),
        // The status line spans the FULL window width, so the rail/work split
        // is an Expanded row above it rather than the page's top-level Row.
        Column(
          children: [
            Expanded(
              child: Row(
                // stretch, not start: a VerticalDivider under a loose vertical
                // constraint collapses to zero height and the 1px seam between
                // the rail and the work area disappears.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildLeftPane(context),
                  // Was a hardcoded white hairline, invisible on the #F3F5FB
                  // light ground — and light is the default theme.
                  if (!isIncomingOnly)
                    VerticalDivider(width: 1, color: MyTheme.line(context)),
                  if (!isIncomingOnly) Expanded(child: buildRightPane(context)),
                ],
              ),
            ),
            // Incoming-only keeps its own inline OnlineStatusWidget inside the
            // pane; a second one here would double the row and the service
            // toggle.
            if (!isIncomingOnly) buildStatusLine(context),
          ],
        ),
      ],
    ));
  }

  /// Full-window-width FRAME strip under both panes. This page only owns the
  /// slot and the hairline — OnlineStatusWidget itself carries the state dot,
  /// relay, latency and the Powered-by link. It MUST stay a descendant of this
  /// page: it resolves Get.find<RxBool>(tag: 'stop-service') against the
  /// Get.put in this file's initState.
  Widget buildStatusLine(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: MyTheme.frameTint(context),
        border: Border(top: BorderSide(color: MyTheme.line(context), width: 1)),
      ),
      child: const OnlineStatusWidget(),
    );
  }

  Widget _buildBlock({required Widget child}) {
    return buildRemoteBlock(
        block: _block, mask: true, use: canBeBlocked, child: child);
  }

  Widget buildLeftPane(BuildContext context) {
    final isIncomingOnly = bind.isIncomingOnly();
    final isOutgoingOnly = bind.isOutgoingOnly();
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: SizedBox(
        // 320 is the operator-rail width from the approved layout. At the old
        // 200 the device ID was clipped by the kebab menu. The incoming-only
        // branch keeps 280 — that window is sized from
        // common.dart imcomingOnlyHomeSize and resizes oddly otherwise.
        width: isIncomingOnly ? 280.0 : 320.0,
        child: Stack(
          children: [
            _buildRailGlass(context),
            if (isIncomingOnly)
              _buildIncomingOnlyPane(context)
            else
              _buildOperatorRail(context),
            if (isOutgoingOnly)
              PositionedDirectional(
                bottom: 6,
                start: 12,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: InkWell(
                    child: Obx(
                      () => Icon(
                        Icons.settings,
                        color: _editHover.value
                            ? textColor
                            : Colors.grey.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                    onTap: () => {
                      if (DesktopSettingPage.tabKeys.isNotEmpty)
                        {
                          DesktopSettingPage.switch2page(
                              DesktopSettingPage.tabKeys[0])
                        }
                    },
                    onHover: (value) => _editHover.value = value,
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  /// LIVE BACKDROPFILTER #2 of the three the app is allowed. Deliberately a
  /// Positioned.fill SIBLING painted *behind* the rail content and never an
  /// ancestor of the notice-stack scroller: a BackdropFilter above a scroller
  /// re-rasterises its whole subtree on every scrolled frame.
  Widget _buildRailGlass(BuildContext context) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(color: MyTheme.frameTint(context)),
        ),
      ),
    );
  }

  /// The OPERATOR RAIL: the "Your Desktop" hero sheet, then the scrollable
  /// notice stack, then the account chip pinned to the bottom.
  ///
  /// The LayoutBuilder is not polish: main.dart's window options never set a
  /// minimumSize, so the rail can be dragged shorter than the hero's natural
  /// 278px. Below 420px of rail the hero drops to 255px (tighter gaps, shorter
  /// service and access rows, no four-glyph readout) — the instrument plate
  /// itself never changes size.
  Widget _buildOperatorRail(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < 420;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // One composed sheet replaces the bare plate + service card: the
          // credential plate, the service row and the permissions row now read
          // as one designed panel rather than three stacked widgets.
          if (!isOutgoingOnly) _buildYourDesktopSheet(context, compact),
          Expanded(
            child: RepaintBoundary(
              child: SingleChildScrollView(
                controller: _leftPaneScrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!isOutgoingOnly) buildPresetPasswordWarning(),
                    _buildHelpCardsSlot(),
                    buildPluginEntry(),
                  ],
                ),
              ),
            ),
          ),
          buildAccountChip(context),
          // Keeps the chip clear of the settings gear, which is pinned at
          // bottom/start of the rail Stack in outgoing-only builds.
          if (isOutgoingOnly) const SizedBox(height: 28),
        ],
      );
    });
  }

  /// HERO A — "Your Desktop" / دسکتاپ شما.
  ///
  /// Three depths visible at once inside 278px, where stock RustDesk has one:
  ///   LIT SHEET (LumenSheet, lifted off the rail's glass by a travelling
  ///   specular rim, a contact hairline and one negative-spread shadow)
  ///     -> EMISSIVE INSTRUMENT (the existing InstrumentPlate, unmodified, now
  ///        seated in a cyan under-plate bloom so light appears to leak from
  ///        beneath it)
  ///       -> RECESSED WELL (LumenWell holding the service row and the pinned
  ///          permissions row — every control that takes input lives in a well).
  ///
  /// ZERO new blur: the sheet already sits on the operator rail's live
  /// BackdropFilter, so blurring here would blur an already-blurred,
  /// already-frameTinted surface for a luminance change under 1%. The app's one
  /// remaining hero blur belongs to the connect command bar.
  Widget _buildYourDesktopSheet(BuildContext context, bool compact) {
    if (!(isDesktop || isWebDesktop)) {
      // Non-desktop reach keeps the pre-LUMEN shape byte for byte: bare plate
      // plus the service card in its own decorated container.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildIDBoard(context),
          Container(
            margin: const EdgeInsetsDirectional.only(
                start: 12, end: 11, bottom: 8),
            decoration: BoxDecoration(
              color: MyTheme.card(context),
              borderRadius: BorderRadius.circular(MyTheme.snRadiusSm),
              border: Border.all(color: MyTheme.line(context), width: 1),
            ),
            child: _buildServiceRow(context, compact),
          ),
        ],
      );
    }
    final dark = lumenDark(context);
    return LumenSheet(
      onGlass: true,
      elevation: LumenElevation.page,
      radius: MyTheme.snRadiusLg,
      margin: const EdgeInsetsDirectional.only(
          start: 12, end: 11, top: 8, bottom: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(11, 10, 11, 11),
      // The plate is opaque and covers this bloom's core, so only the halo
      // escapes around its bottom and trailing edges — which is what makes the
      // instrument read as lit rather than as another dark card. Cyan because
      // the plate's own accent and leading rail already are.
      bloom: PositionedDirectional(
        start: -30,
        top: 24,
        width: 262,
        height: 172,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.20, -0.10),
                radius: .85,
                stops: const [0, .50, 1],
                colors: [
                  MyTheme.snCyan.withOpacity(dark ? .18 : .13),
                  MyTheme.snCyan.withOpacity(dark ? .07 : .05),
                  MyTheme.snCyan.withOpacity(0),
                ],
              ),
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildYourDesktopHeader(context),
          SizedBox(height: compact ? 6 : 9),
          // buildPasswordBoard is not listed separately: it renders as a row
          // inside the instrument plate that buildIDBoard returns.
          buildIDBoard(context, margin: EdgeInsets.zero),
          SizedBox(height: compact ? 7 : 9),
          LumenWell(
            radius: 12,
            children: [
              _buildServiceRow(context, compact),
              // Inset 10 on both sides, plain symmetric padding: a horizontal
              // hairline has no handedness so there is nothing to mirror.
              // width: infinity because LumenWell's Column centres its children
              // rather than stretching them.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  height: 1,
                  width: double.infinity,
                  child: ColoredBox(
                      color: dark
                          ? const Color(0x14FFFFFF)
                          : const Color(0x140F172A)),
                ),
              ),
              PermissionsAccessRow(compact: compact),
            ],
          ),
        ],
      ),
    );
  }

  /// 20px header: the lamp names the panel's direction (cyan = inbound), the
  /// title finally says what the block is, the help glyph restores the desk_tip
  /// string for 0px of vertical rail, and the live pill counts sessions.
  Widget _buildYourDesktopHeader(BuildContext context) {
    return SizedBox(
      height: 20,
      child: Row(
        children: [
          const LumenLamp(color: MyTheme.snCyan),
          const SizedBox(width: 9),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    translate('Your Desktop'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      letterSpacing: lumenLetterSpacing(context, 1.15),
                      color: MyTheme.textMuted(context),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Tooltip(
                  waitDuration: const Duration(milliseconds: 300),
                  message: translate('desk_tip'),
                  child: Icon(Icons.help_outline_outlined,
                      size: 13, color: MyTheme.textDim(context)),
                ),
              ],
            ),
          ),
          // Its own Obx, never the sheet's: an Obx around the sheet would
          // rebuild the instrument plate once a second.
          Obx(() {
            final n = stateGlobal.videoConnCount.value;
            if (n <= 0) return const SizedBox.shrink();
            return Container(
              height: 18,
              padding: const EdgeInsetsDirectional.only(start: 6, end: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                color:
                    MyTheme.snGreen.withOpacity(lumenDark(context) ? .14 : .12),
                border: Border.all(
                    color: MyTheme.snGreen.withOpacity(.34), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: MyTheme.snGreen),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$n',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: MyTheme.snGreen,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// Incoming-only keeps the old single-scroller shape ON PURPOSE: that window
  /// auto-sizes to its content through [_childKey] + [_updateWindowSize], which
  /// only measures correctly while the keyed Column has an intrinsic height
  /// (i.e. contains no Expanded).
  Widget _buildIncomingOnlyPane(BuildContext context) {
    final isOutgoingOnly = bind.isOutgoingOnly();
    return Column(
      children: [
        SingleChildScrollView(
          controller: _leftPaneScrollController,
          child: Column(
            key: _childKey,
            children: [
              if (!isOutgoingOnly) buildPresetPasswordWarning(),
              Align(
                alignment: Alignment.center,
                child: loadLogo(),
              ),
              if (!isOutgoingOnly) buildIDBoard(context),
              _buildHelpCardsSlot(),
              buildPluginEntry(),
              Divider(),
              Padding(
                // Was .marginOnly(bottom: 6, right: 6) — GetX emits physical
                // insets, so the gap landed on the wrong side under fa.
                padding: const EdgeInsetsDirectional.only(bottom: 6, end: 6),
                child: OnlineStatusWidget(
                  onSvcStatusChanged: () {
                    if (isInHomePage()) {
                      Future.delayed(Duration(milliseconds: 300), () {
                        _updateWindowSize();
                      });
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(child: Container())
      ],
    );
  }

  /// Shared by both panes so the incoming-only window-resize trigger keeps
  /// firing from exactly one place.
  Widget _buildHelpCardsSlot() {
    return FutureBuilder<Widget>(
      future:
          Future.value(Obx(() => buildHelpCards(stateGlobal.updateUrl.value))),
      builder: (_, data) {
        if (data.hasData) {
          if (bind.isIncomingOnly()) {
            if (isInHomePage()) {
              Future.delayed(Duration(milliseconds: 300), () {
                _updateWindowSize();
              });
            }
          }
          return data.data!;
        } else {
          return const Offstage();
        }
      },
    );
  }

  /// The service ROW — first row of Hero A's well. Read-only by design: the
  /// single source of truth for the service state is the svcStopped RxBool this
  /// file Get.put()s under tag 'stop-service', and the start/stop control itself
  /// lives in OnlineStatusWidget on the status line.
  ///
  /// It carries no decoration of its own any more: the LumenWell is the surface.
  /// The Obx is load-bearing — drop it and the service state freezes on screen
  /// while the real service keeps toggling.
  Widget _buildServiceRow(BuildContext context, bool compact) {
    return Obx(() {
      final running = !svcStopped.value;
      return Container(
        height: compact ? 38 : 44,
        padding: const EdgeInsetsDirectional.only(start: 10, end: 10),
        child: Row(
          children: [
            _PulseDot(active: running),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    running
                        ? translate('Ready')
                        : translate('Service is not running'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: MyTheme.textMain(context),
                    ),
                  ),
                  Text(
                    running
                        ? translate('Service is running')
                        : translate('Start service'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      height: 1.25,
                      color: MyTheme.textMuted(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  /// Bottom-pinned 40px dashed chip. There is no login FFI to invent here: it
  /// opens the account tab of the settings page, the same page the gear opens.
  /// switch2page no-ops when the tab is absent, so a disabled-account build
  /// cannot land on a missing page.
  Widget buildAccountChip(BuildContext context) {
    if (bind.isDisableAccount()) {
      return const SizedBox.shrink();
    }
    return Obx(() {
      final name = gFFI.userModel.userName.value;
      final signedIn = name.isNotEmpty;
      final color = _accountHover.value || signedIn
          ? MyTheme.textMain(context)
          : MyTheme.textMuted(context);
      return Container(
        height: 40,
        margin: const EdgeInsetsDirectional.only(
            start: 12, end: 11, top: 2, bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(MyTheme.snRadiusSm),
          onTap: () => DesktopSettingPage.switch2page(SettingsTabKey.account),
          onHover: (value) => _accountHover.value = value,
          child: CustomPaint(
            painter: _DashedBorderPainter(
              color: _accountHover.value
                  ? MyTheme.line2(context)
                  : MyTheme.line(context),
              radius: MyTheme.snRadiusSm,
            ),
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsetsDirectional.only(start: 10, end: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(signedIn ? Icons.person : Icons.person_outline,
                        size: 16, color: color),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        signedIn ? name : translate('Login'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    });
  }

  buildRightPane(BuildContext context) {
    return Container(
      color: Colors.transparent,
      child: ConnectionPage(),
    );
  }

  /// The INSTRUMENT layer: device ID and one-time password on one always-dark,
  /// LTR-locked plate. Replaces the two separate GlassContainers that used to
  /// live here — those put two live BackdropFilters inside the left pane's
  /// scroller, so they re-rasterised on every scroll frame.
  /// [margin] defaults to the standalone insets the incoming-only pane needs.
  /// Hero A passes EdgeInsets.zero because the sheet owns the insets there.
  buildIDBoard(BuildContext context, {EdgeInsetsGeometry? margin}) {
    final model = gFFI.serverModel;
    return InstrumentPlate(
      margin: margin ??
          const EdgeInsetsDirectional.only(
              start: 12, end: 11, top: 4, bottom: 6),
      children: [
        InstrumentField(
          label: translate("ID"),
          value: GestureDetector(
            onDoubleTap: () {
              Clipboard.setData(ClipboardData(text: model.serverId.text));
              showToast(translate("Copied"));
            },
            child: TextFormField(
              controller: model.serverId,
              readOnly: true,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 2),
              ),
              style: InstrumentField.valueStyle(),
            ).workaroundFreezeLinuxMint(),
          ),
          actions: [buildPopupMenu(context)],
        ),
        buildPasswordBoard(context),
      ],
    );
  }

  Widget buildPopupMenu(BuildContext context) {
    final textColor = Theme.of(context).textTheme.titleLarge?.color;
    RxBool hover = false.obs;
    return InkWell(
      onTap: DesktopTabPage.onAddSetting,
      child: Tooltip(
        message: translate('Settings'),
        child: Obx(
          () => CircleAvatar(
            radius: 15,
            backgroundColor: hover.value
                ? Theme.of(context).scaffoldBackgroundColor
                : Theme.of(context).colorScheme.background,
            child: Icon(
              Icons.more_vert_outlined,
              size: 20,
              color: hover.value ? textColor : textColor?.withOpacity(0.5),
            ),
          ),
        ),
      ),
      onHover: (value) => hover.value = value,
    );
  }

  buildPasswordBoard(BuildContext context) {
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
          builder: (context, model, child) {
            return buildPasswordBoard2(context, model);
          },
        ));
  }

  /// Renders as a row INSIDE the instrument plate built by [buildIDBoard] —
  /// it no longer carries its own container. Kept as a separate method so the
  /// ChangeNotifierProvider + Consumer<ServerModel> plumbing above still drives
  /// rebuilds (serverPasswd is a plain TextEditingController updated by
  /// ServerModel's timer, so this cannot collapse to an Obx).
  buildPasswordBoard2(BuildContext context, ServerModel model) {
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return InstrumentField(
      label: translate("One-time Password"),
      accent: true,
      bottomGap: 0,
      value: GestureDetector(
        onDoubleTap: () {
          if (showOneTime) {
            Clipboard.setData(ClipboardData(text: model.serverPasswd.text));
            showToast(translate("Copied"));
          }
        },
        child: TextFormField(
          controller: model.serverPasswd,
          readOnly: true,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 2),
          ),
          style: InstrumentField.valueStyle(accent: true),
        ).workaroundFreezeLinuxMint(),
      ),
      actions: [
        if (showOneTime)
          InstrumentAction(
            tooltip: translate('Refresh Password'),
            onTap: () => bind.mainUpdateTemporaryPassword(),
            icon: const RotatedBox(
                quarterTurns: 2, child: Icon(Icons.refresh, size: 13)),
          ),
        if (!bind.isDisableSettings())
          InstrumentAction(
            tooltip: translate('Change Password'),
            onTap: () =>
                DesktopSettingPage.switch2page(SettingsTabKey.safety),
            icon: const Icon(Icons.edit, size: 13),
          ),
      ],
    );
  }

  // buildTip is gone, but both of its strings are back: "Your Desktop" is the
  // hero header's title and desk_tip is the 13px help glyph beside it. As a
  // Tooltip it costs 0px of vertical rail, where the old inline two-line body
  // cost 28px in fa/tr and made the panel height locale-dependent.

  Widget buildHelpCards(String updateUrl) {
    if (!bind.isCustomClient() &&
        updateUrl.isNotEmpty &&
        !isCardClosed &&
        bind.mainUriPrefixSync().contains('rustdesk')) {
      final isToUpdate = (isWindows || isMacOS) && bind.mainIsInstalled();
      String btnText = isToUpdate ? 'Update' : 'Download';
      GestureTapCallback onPressed = () async {
        final Uri url = Uri.parse('https://rustdesk.com/download');
        await launchUrl(url);
      };
      if (isToUpdate) {
        onPressed = () {
          handleUpdate(updateUrl);
        };
      }
      return buildInstallCard(
          "Status",
          "${translate("new-version-of-{${bind.mainGetAppNameSync()}}-tip")} (${bind.mainGetNewVersion()}).",
          btnText,
          onPressed,
          closeButton: true,
          help: isToUpdate ? 'Changelog' : null,
          link: isToUpdate
              ? 'https://github.com/rustdesk/rustdesk/releases/tag/${bind.mainGetNewVersion()}'
              : null);
    }
    if (systemError.isNotEmpty) {
      return buildInstallCard("", systemError, "", () {});
    }

    if (isWindows && !bind.isDisableInstallation()) {
      if (!bind.mainIsInstalled()) {
        return buildInstallCard(
            "", bind.isOutgoingOnly() ? "" : "install_tip", "Install",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainGotoInstall();
        });
      } else if (bind.mainIsInstalledLowerVersion()) {
        return buildInstallCard(
            "Status", "Your installation is lower version.", "Click to upgrade",
            () async {
          await rustDeskWinManager.closeAllSubWindows();
          bind.mainUpdateMe();
        });
      }
    } else if (isMacOS) {
      final isOutgoingOnly = bind.isOutgoingOnly();
      if (!(isOutgoingOnly || bind.mainIsCanScreenRecording(prompt: false))) {
        return buildInstallCard("Permissions", "config_screen", "Configure",
            () async {
          bind.mainIsCanScreenRecording(prompt: true);
          watchIsCanScreenRecording = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly && !bind.mainIsProcessTrusted(prompt: false)) {
        return buildInstallCard("Permissions", "config_acc", "Configure",
            () async {
          bind.mainIsProcessTrusted(prompt: true);
          watchIsProcessTrust = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!bind.mainIsCanInputMonitoring(prompt: false)) {
        return buildInstallCard("Permissions", "config_input", "Configure",
            () async {
          bind.mainIsCanInputMonitoring(prompt: true);
          watchIsInputMonitoring = true;
        }, help: 'Help', link: translate("doc_mac_permission"));
      } else if (!isOutgoingOnly &&
          !svcStopped.value &&
          bind.mainIsInstalled() &&
          !bind.mainIsInstalledDaemon(prompt: false)) {
        return buildInstallCard("", "install_daemon_tip", "Install", () async {
          bind.mainIsInstalledDaemon(prompt: true);
        });
      }
      //// Disable microphone configuration for macOS. We will request the permission when needed.
      // else if ((await osxCanRecordAudio() !=
      //     PermissionAuthorizeType.authorized)) {
      //   return buildInstallCard("Permissions", "config_microphone", "Configure",
      //       () async {
      //     osxRequestAudio();
      //     watchIsCanRecordAudio = true;
      //   });
      // }
    } else if (isLinux) {
      if (bind.isOutgoingOnly()) {
        return Container();
      }
      final LinuxCards = <Widget>[];
      if (bind.isSelinuxEnforcing()) {
        // Check is SELinux enforcing, but show user a tip of is SELinux enabled for simple.
        final keyShowSelinuxHelpTip = "show-selinux-help-tip";
        if (bind.mainGetLocalOption(key: keyShowSelinuxHelpTip) != 'N') {
          LinuxCards.add(buildInstallCard(
            "Warning",
            "selinux_tip",
            "",
            () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link:
                'https://rustdesk.com/docs/en/client/linux/#permissions-issue',
            closeButton: true,
            closeOption: keyShowSelinuxHelpTip,
          ));
        }
      }
      if (bind.mainCurrentIsWayland()) {
        LinuxCards.add(buildInstallCard(
            "Warning", "wayland_experiment_tip", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#x11-required'));
      } else if (bind.mainIsLoginWayland()) {
        LinuxCards.add(buildInstallCard("Warning",
            "Login screen using Wayland is not supported", "", () async {},
            marginTop: LinuxCards.isEmpty ? 20.0 : 5.0,
            help: 'Help',
            link: 'https://rustdesk.com/docs/en/client/linux/#login-screen'));
      }
      if (LinuxCards.isNotEmpty) {
        return Column(
          children: LinuxCards,
        );
      }
    }
    if (bind.isIncomingOnly()) {
      return Align(
        alignment: Alignment.centerRight,
        child: OutlinedButton(
          onPressed: () {
            SystemNavigator.pop(); // Close the application
            // https://github.com/flutter/flutter/issues/66631
            if (isWindows) {
              exit(0);
            }
          },
          child: Text(translate('Quit')),
        ),
      ).marginAll(14);
    }
    return Container();
  }

  Widget buildInstallCard(String title, String content, String btnText,
      GestureTapCallback onPressed,
      {double marginTop = 20.0,
      String? help,
      String? link,
      bool? closeButton,
      String? closeOption}) {
    if (bind.mainGetBuildinOption(key: kOptionHideHelpCards) == 'Y' &&
        content != 'install_daemon_tip') {
      return const SizedBox();
    }
    void closeCard() async {
      if (closeOption != null) {
        await bind.mainSetLocalOption(key: closeOption, value: 'N');
        if (bind.mainGetLocalOption(key: closeOption) == 'N') {
          setState(() {
            isCardClosed = true;
          });
        }
      } else {
        setState(() {
          isCardClosed = true;
        });
      }
    }

    return Stack(
      children: [
        Container(
          margin: EdgeInsets.fromLTRB(
              0, marginTop, 0, bind.isIncomingOnly() ? marginTop : 0),
          child: Container(
              // Was a full-bleed magenta->coral gradient with blanket white
              // text — the loudest thing on the screen and nowhere near the
              // brand. This is an advisory, so give it advisory weight: an
              // amber-tinted card with a hairline, on the brand palette.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(MyTheme.snRadius),
                border: Border.all(color: const Color(0x47FBBF24), width: 1),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x1AFBBF24), Color(0x0AFBBF24)],
                ),
              ),
              margin: const EdgeInsetsDirectional.only(start: 12, end: 11),
              padding: EdgeInsets.all(16),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: (title.isNotEmpty
                          ? <Widget>[
                              Center(
                                  child: Text(
                                translate(title),
                                style: TextStyle(
                                    color: MyTheme.textMain(context),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15),
                              ).marginOnly(bottom: 6)),
                            ]
                          : <Widget>[]) +
                      <Widget>[
                        if (content.isNotEmpty)
                          Text(
                            translate(content),
                            style: TextStyle(
                                height: 1.5,
                                color: MyTheme.textMain(context),
                                fontWeight: FontWeight.normal,
                                fontSize: 13),
                          ).marginOnly(bottom: 20)
                      ] +
                      (btnText.isNotEmpty
                          ? <Widget>[
                              Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    FixedWidthButton(
                                      width: 150,
                                      padding: 8,
                                      isOutline: true,
                                      text: translate(btnText),
                                      textColor: MyTheme.textMain(context),
                                      borderColor: MyTheme.line2(context),
                                      textSize: 20,
                                      radius: 10,
                                      onTap: onPressed,
                                    )
                                  ])
                            ]
                          : <Widget>[]) +
                      (help != null
                          ? <Widget>[
                              Center(
                                  child: InkWell(
                                      onTap: () async =>
                                          await launchUrl(Uri.parse(link!)),
                                      child: Text(
                                        translate(help),
                                        style: TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                            color: MyTheme.textMain(context),
                                            fontSize: 12),
                                      )).marginOnly(top: 6)),
                            ]
                          : <Widget>[]))),
        ),
        if (closeButton != null && closeButton == true)
          PositionedDirectional(
            top: 18,
            end: 0,
            child: IconButton(
              icon: Icon(
                Icons.close,
                // Was Colors.white — invisible on the amber card in the light
                // theme, which is the default.
                color: MyTheme.textMuted(context),
                size: 20,
              ),
              onPressed: closeCard,
            ),
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 1), () async {
      await gFFI.serverModel.fetchID();
      final error = await bind.mainGetError();
      if (systemError != error) {
        systemError = error;
        setState(() {});
      }
      final v = await mainGetBoolOption(kOptionStopService);
      if (v != svcStopped.value) {
        svcStopped.value = v;
        setState(() {});
      }
      // No new timer: five sync config reads folded into the tick that already
      // does two. This keeps the pinned permissions row honest when the Safety
      // tab writes the same five options from another window.
      if (isDesktop || isWebDesktop) {
        final sig = snAccessSignature();
        if (sig != _accessSig) {
          _accessSig = sig;
          gFFI.serverModel.syncIncomingPermissions();
          if (mounted) setState(() {});
        }
      }
      if (watchIsCanScreenRecording) {
        if (bind.mainIsCanScreenRecording(prompt: false)) {
          watchIsCanScreenRecording = false;
          setState(() {});
        }
      }
      if (watchIsProcessTrust) {
        if (bind.mainIsProcessTrusted(prompt: false)) {
          watchIsProcessTrust = false;
          setState(() {});
        }
      }
      if (watchIsInputMonitoring) {
        if (bind.mainIsCanInputMonitoring(prompt: false)) {
          watchIsInputMonitoring = false;
          // Do not notify for now.
          // Monitoring may not take effect until the process is restarted.
          // rustDeskWinManager.call(
          //     WindowType.RemoteDesktop, kWindowDisableGrabKeyboard, '');
          setState(() {});
        }
      }
      if (watchIsCanRecordAudio) {
        if (isMacOS) {
          Future.microtask(() async {
            if ((await osxCanRecordAudio() ==
                PermissionAuthorizeType.authorized)) {
              watchIsCanRecordAudio = false;
              setState(() {});
            }
          });
        } else {
          watchIsCanRecordAudio = false;
          setState(() {});
        }
      }
    });
    Get.put<RxBool>(svcStopped, tag: 'stop-service');
    rustDeskWinManager.registerActiveWindowListener(onActiveWindowChanged);

    screenToMap(window_size.Screen screen) => {
          'frame': {
            'l': screen.frame.left,
            't': screen.frame.top,
            'r': screen.frame.right,
            'b': screen.frame.bottom,
          },
          'visibleFrame': {
            'l': screen.visibleFrame.left,
            't': screen.visibleFrame.top,
            'r': screen.visibleFrame.right,
            'b': screen.visibleFrame.bottom,
          },
          'scaleFactor': screen.scaleFactor,
        };

    bool isChattyMethod(String methodName) {
      switch (methodName) {
        case kWindowBumpMouse: return true;
      }

      return false;
    }

    rustDeskWinManager.setMethodHandler((call, fromWindowId) async {
      if (!isChattyMethod(call.method)) {
        debugPrint(
          "[Main] call ${call.method} with args ${call.arguments} from window $fromWindowId");
      }
      if (call.method == kWindowMainWindowOnTop) {
        windowOnTop(null);
      } else if (call.method == kWindowRefreshCurrentUser) {
        gFFI.userModel.refreshCurrentUser();
      } else if (call.method == kWindowGetWindowInfo) {
        final screen = (await window_size.getWindowInfo()).screen;
        if (screen == null) {
          return '';
        } else {
          return jsonEncode(screenToMap(screen));
        }
      } else if (call.method == kWindowGetScreenList) {
        return jsonEncode(
            (await window_size.getScreenList()).map(screenToMap).toList());
      } else if (call.method == kWindowActionRebuild) {
        reloadCurrentWindow();
      } else if (call.method == kWindowEventShow) {
        await rustDeskWinManager.registerActiveWindow(call.arguments["id"]);
      } else if (call.method == kWindowEventHide) {
        await rustDeskWinManager.unregisterActiveWindow(call.arguments['id']);
      } else if (call.method == kWindowConnect) {
        await connectMainDesktop(
          call.arguments['id'],
          isFileTransfer: call.arguments['isFileTransfer'],
          isViewCamera: call.arguments['isViewCamera'],
          isTerminal: call.arguments['isTerminal'],
          isTcpTunneling: call.arguments['isTcpTunneling'],
          isRDP: call.arguments['isRDP'],
          password: call.arguments['password'],
          forceRelay: call.arguments['forceRelay'],
          connToken: call.arguments['connToken'],
        );
      } else if (call.method == kWindowBumpMouse) {
        return RdPlatformChannel.instance.bumpMouse(
          dx: call.arguments['dx'],
          dy: call.arguments['dy']);
      } else if (call.method == kWindowEventMoveTabToNewWindow) {
        final args = call.arguments.split(',');
        int? windowId;
        try {
          windowId = int.parse(args[0]);
        } catch (e) {
          debugPrint("Failed to parse window id '${call.arguments}': $e");
        }
        WindowType? windowType;
        try {
          windowType = WindowType.values.byName(args[3]);
        } catch (e) {
          debugPrint("Failed to parse window type '${call.arguments}': $e");
        }
        if (windowId != null && windowType != null) {
          await rustDeskWinManager.moveTabToNewWindow(
              windowId, args[1], args[2], windowType);
        }
      } else if (call.method == kWindowEventOpenMonitorSession) {
        final args = jsonDecode(call.arguments);
        final windowId = args['window_id'] as int;
        final peerId = args['peer_id'] as String;
        final display = args['display'] as int;
        final displayCount = args['display_count'] as int;
        final windowType = args['window_type'] as int;
        final screenRect = parseParamScreenRect(args);
        await rustDeskWinManager.openMonitorSession(
            windowId, peerId, display, displayCount, screenRect, windowType);
      } else if (call.method == kWindowEventRemoteWindowCoords) {
        final windowId = int.tryParse(call.arguments);
        if (windowId != null) {
          return jsonEncode(
              await rustDeskWinManager.getOtherRemoteWindowCoords(windowId));
        }
      }
    });
    _uniLinksSubscription = listenUniLinks();

    if (bind.isIncomingOnly()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _updateWindowSize();
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  _updateWindowSize() {
    RenderObject? renderObject = _childKey.currentContext?.findRenderObject();
    if (renderObject == null) {
      return;
    }
    if (renderObject is RenderBox) {
      final size = renderObject.size;
      if (size != imcomingOnlyHomeSize) {
        imcomingOnlyHomeSize = size;
        windowManager.setSize(getIncomingOnlyHomeSize());
      }
    }
  }

  @override
  void dispose() {
    _uniLinksSubscription?.cancel();
    Get.delete<RxBool>(tag: 'stop-service');
    _updateTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      shouldBeBlocked(_block, canBeBlocked);
    }
  }

  Widget buildPluginEntry() {
    final entries = PluginUiManager.instance.entries.entries;
    return Offstage(
      offstage: entries.isEmpty,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map((entry) {
            return entry.value;
          })
        ],
      ),
    );
  }
}

/// Green status dot with a slow expanding halo while the service is up.
/// RepaintBoundary'd: it ticks every frame, and without one it would dirty the
/// whole rail — including the notice-stack scroller — on each pulse.
class _PulseDot extends StatefulWidget {
  const _PulseDot({Key? key, required this.active}) : super(key: key);

  final bool active;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? MyTheme.snGreen : MyTheme.textDim(context);
    return RepaintBoundary(
      child: SizedBox(
        width: 18,
        height: 18,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = Curves.easeOut.transform(_controller.value);
            return Stack(
              alignment: Alignment.center,
              children: [
                if (widget.active)
                  Container(
                    width: 8 + 10 * t,
                    height: 8 + 10 * t,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.30 * (1 - t)),
                    ),
                  ),
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: color),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Dashed rounded outline. Flutter has no dashed BorderSide, and a DottedBorder
/// package dependency is not worth one chip.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 1 || size.height <= 1) {
      return;
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Inset by half the stroke so the dashes stay inside the chip's box.
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
        Radius.circular(radius),
      ));
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var start = 0.0;
      while (start < metric.length) {
        final end = start + dash;
        canvas.drawPath(
            metric.extractPath(
                start, end > metric.length ? metric.length : end),
            paint);
        start = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

void setPasswordDialog({VoidCallback? notEmptyCallback}) async {
  final p0 = TextEditingController(text: "");
  final p1 = TextEditingController(text: "");
  var errMsg0 = "";
  var errMsg1 = "";
  final localPasswordSet =
      (await bind.mainGetCommon(key: "local-permanent-password-set")) == "true";
  final permanentPasswordSet =
      (await bind.mainGetCommon(key: "permanent-password-set")) == "true";
  final presetPassword = permanentPasswordSet && !localPasswordSet;
  var canSubmit = false;
  final RxString rxPass = "".obs;
  final rules = [
    DigitValidationRule(),
    UppercaseValidationRule(),
    LowercaseValidationRule(),
    // SpecialCharacterValidationRule(),
    MinCharactersValidationRule(8),
  ];
  final maxLength = bind.mainMaxEncryptLen();
  final statusTip = localPasswordSet
      ? translate('password-hidden-tip')
      : (presetPassword ? translate('preset-password-in-use-tip') : '');
  final showStatusTipOnMobile =
      statusTip.isNotEmpty && !isDesktop && !isWebDesktop;

  gFFI.dialogManager.show((setState, close, context) {
    updateCanSubmit() {
      canSubmit = p0.text.trim().isNotEmpty || p1.text.trim().isNotEmpty;
    }

    submit() async {
      if (!canSubmit) {
        return;
      }
      setState(() {
        errMsg0 = "";
        errMsg1 = "";
      });
      final pass = p0.text.trim();
      if (pass.isNotEmpty) {
        final Iterable violations = rules.where((r) => !r.validate(pass));
        if (violations.isNotEmpty) {
          setState(() {
            errMsg0 =
                '${translate('Prompt')}: ${violations.map((r) => r.name).join(', ')}';
          });
          return;
        }
      }
      if (p1.text.trim() != pass) {
        setState(() {
          errMsg1 =
              '${translate('Prompt')}: ${translate("The confirmation is not identical.")}';
        });
        return;
      }
      final ok = await bind.mainSetPermanentPasswordWithResult(password: pass);
      if (!ok) {
        setState(() {
          errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
        });
        return;
      }
      if (pass.isNotEmpty) {
        notEmptyCallback?.call();
      }
      close();
    }

    return CustomAlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.key, color: MyTheme.accent),
          Text(translate("Set Password")).paddingOnly(left: 10),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 500),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 6.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Password'),
                        errorText: errMsg0.isNotEmpty ? errMsg0 : null),
                    controller: p0,
                    autofocus: true,
                    onChanged: (value) {
                      rxPass.value = value.trim();
                      setState(() {
                        errMsg0 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: PasswordStrengthIndicator(password: rxPass)),
              ],
            ).marginOnly(top: 2, bottom: showStatusTipOnMobile ? 2 : 8),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    obscureText: true,
                    decoration: InputDecoration(
                        labelText: translate('Confirmation'),
                        errorText: errMsg1.isNotEmpty ? errMsg1 : null),
                    controller: p1,
                    onChanged: (value) {
                      setState(() {
                        errMsg1 = '';
                        updateCanSubmit();
                      });
                    },
                    maxLength: maxLength,
                  ).workaroundFreezeLinuxMint(),
                ),
              ],
            ),
            if (statusTip.isNotEmpty)
              Row(
                children: [
                  Icon(Icons.info, color: Colors.amber, size: 18)
                      .marginOnly(right: 6),
                  Expanded(
                      child: Text(
                    statusTip,
                    style: const TextStyle(fontSize: 13, height: 1.1),
                  ))
                ],
              ).marginOnly(top: 6, bottom: 2),
            SizedBox(
              height: showStatusTipOnMobile ? 0.0 : 8.0,
            ),
            Obx(() => Wrap(
                  runSpacing: showStatusTipOnMobile ? 2.0 : 8.0,
                  spacing: 4,
                  children: rules.map((e) {
                    var checked = e.validate(rxPass.value.trim());
                    return Chip(
                        label: Text(
                          e.name,
                          style: TextStyle(
                              color: checked
                                  ? const Color(0xFF0A9471)
                                  : Color.fromARGB(255, 198, 86, 157)),
                        ),
                        backgroundColor: checked
                            ? const Color(0xFFD0F7ED)
                            : Color.fromARGB(255, 247, 205, 232));
                  }).toList(),
                ))
          ],
        ),
      ),
      actions: (() {
        final cancelButton = dialogButton(
          "Cancel",
          icon: Icon(Icons.close_rounded),
          onPressed: close,
          isOutline: true,
        );
        final removeButton = dialogButton(
          "Remove",
          icon: Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            setState(() {
              errMsg0 = "";
              errMsg1 = "";
            });
            final ok =
                await bind.mainSetPermanentPasswordWithResult(password: "");
            if (!ok) {
              setState(() {
                errMsg0 = '${translate('Prompt')}: ${translate("Failed")}';
              });
              return;
            }
            close();
          },
          buttonStyle: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
        );
        final okButton = dialogButton(
          "OK",
          icon: Icon(Icons.done_rounded),
          onPressed: canSubmit ? submit : null,
        );
        if (!isDesktop && !isWebDesktop && localPasswordSet) {
          return [
            Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    cancelButton,
                    const SizedBox(width: 4),
                    removeButton,
                    const SizedBox(width: 4),
                    okButton,
                  ],
                ),
              ),
            ),
          ];
        }
        return [
          cancelButton,
          if (localPasswordSet) removeButton,
          okButton,
        ];
      })(),
      onSubmit: canSubmit ? submit : null,
      onCancel: close,
    );
  });
}
