import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:flutter/services.dart';

import '../../common/shared_state.dart';

/// The three languages servernet.cloud ships. The pill shows the ISO code, not
/// the endonym: a code is the same width in every locale, so the segment can
/// never overflow the way "Türkçe"/"فارسی" would. The endonym is the tooltip.
class _QuickLang {
  final String key;
  final String code;
  final String name;
  const _QuickLang(this.key, this.code, this.name);
}

const _kQuickLangs = <_QuickLang>[
  _QuickLang('fa', 'FA', 'فارسی'),
  _QuickLang('en', 'EN', 'English'),
  _QuickLang('tr', 'TR', 'Türkçe'),
];

/// Track/cell height of the title-bar segment controls. Kept under the 28px
/// tail box so the pills stay optically centred in the 40px bar.
const double _kSegHeight = 24;

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: Icons.build_sharp,
          unselectedIcon: Icons.build_outlined,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: Icons.home_sharp,
        unselectedIcon: Icons.home_outlined,
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
        )));
    if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  @override
  void initState() {
    super.initState();
    // HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  /*
  bool _handleKeyEvent(KeyEvent event) {
    if (!mouseIn && event is KeyDownEvent) {
      print('key down: ${event.logicalKey}');
      shouldBeBlocked(_block, canBeBlocked);
    }
    return false; // allow it to propagate
  }
  */

  @override
  void dispose() {
    // HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    Get.delete<DesktopTabController>();

    super.dispose();
  }

  // Quick light/dark theme toggle in the top bar. Styled as a single square
  // cell so it reads as a fourth segment next to the language track.
  Widget _quickThemeButton(BuildContext context) {
    // Derive the glyph from the SAME value the tap applies, so the icon always
    // previews the result of the click instead of describing the current state.
    final next = MyTheme.currentThemeMode() == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    final toDark = next == ThemeMode.dark;
    return Tooltip(
      message: translate('Theme'),
      waitDuration: const Duration(seconds: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => MyTheme.changeDarkMode(next),
          child: Container(
            width: _kSegHeight,
            height: _kSegHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MyTheme.line(context),
              borderRadius: BorderRadius.circular(MyTheme.snRadiusSm),
            ),
            child: Icon(
              toDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              size: 14,
              color: MyTheme.textMuted(context),
            ),
          ),
        ),
      ),
    );
  }

  /// The stored option may be '', 'default' or a full tag such as 'fa_IR'.
  /// Reduce it to a bare subtag so the segment can still mark the right pill,
  /// and fall back to whatever Localizations actually resolved when unset.
  String _activeLang(BuildContext context) {
    var stored = '';
    try {
      stored = bind.mainGetLocalOption(key: kCommConfKeyLang);
    } catch (_) {}
    final key = stored.split(RegExp(r'[_-]')).first.toLowerCase();
    if (_kQuickLangs.any((l) => l.key == key)) return key;
    final resolved =
        Localizations.maybeLocaleOf(context)?.languageCode.toLowerCase() ?? '';
    return _kQuickLangs.any((l) => l.key == resolved) ? resolved : 'en';
  }

  Future<void> _setLang(String key) async {
    // Side-effect chain kept verbatim: the option write must land before the
    // Rust side switches language, and reloadAllWindows() rebuilds every window
    // (which is also what re-reads the locale and flips Directionality).
    await bind.mainSetLocalOption(key: kCommConfKeyLang, value: key);
    bind.mainChangeLanguage(lang: key);
    reloadAllWindows();
  }

  // FA | EN | TR segmented control. Reads the live value of the same option the
  // handler writes, so the current language is actually marked.
  Widget _quickLangSegment(BuildContext context) {
    final active = _activeLang(context);
    return Container(
      height: _kSegHeight,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: MyTheme.line(context),
        borderRadius: BorderRadius.circular(MyTheme.snRadiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _kQuickLangs.map((l) {
          final selected = l.key == active;
          return Tooltip(
            message: l.name,
            waitDuration: const Duration(seconds: 1),
            child: MouseRegion(
              cursor: selected
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: GestureDetector(
                onTap: selected ? null : () => _setLang(l.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: MyTheme.snEase,
                  width: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // Absolute-Alignment brand gradient: must not mirror in RTL.
                    gradient: selected ? MyTheme.snGradient : null,
                    borderRadius: BorderRadius.circular(MyTheme.snRadiusSm - 3),
                  ),
                  child: Text(
                    l.code,
                    style: TextStyle(
                      fontSize: 10,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .4,
                      color: selected ? Colors.white : MyTheme.textDim(context),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: DesktopTab(
              controller: tabController,
              // The tab bar hands `tail` no vertical constraint, so the pills
              // would stretch to the full bar height without this box.
              tail: Center(
                child: SizedBox(
                  height: 28,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _quickLangSegment(context),
                      const SizedBox(width: 6),
                      _quickThemeButton(context),
                      Offstage(
                        offstage:
                            bind.isIncomingOnly() || bind.isDisableSettings(),
                        // Spacer sits inside the Offstage so hiding Settings
                        // does not leave a dead gap, and as a Row child it
                        // needs no directional inset to mirror correctly.
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 6),
                            ActionIcon(
                              message: 'Settings',
                              icon: IconFont.menu,
                              onTap: DesktopTabPage.onAddSetting,
                              isClose: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )));
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}
