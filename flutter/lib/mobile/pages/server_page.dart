import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/mobile/widgets/dialog.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../common/widgets/glass_container.dart';
import '../../common/widgets/instrument_plate.dart';
import '../../common/widgets/lumen.dart';
import '../../common/widgets/permissions_sheet.dart';
import '../../common/widgets/dialog.dart';
import '../../consts.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'home_page.dart';

class ServerPage extends StatefulWidget implements PageShape {
  @override
  final title = translate("Share screen");

  @override
  final icon = const Icon(Icons.mobile_screen_share);

  @override
  final appBarActions = (!bind.isDisableSettings() &&
          bind.mainGetBuildinOption(key: kOptionHideSecuritySetting) != 'Y')
      ? [_DropDownAction()]
      : [];

  ServerPage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _ServerPageState();
}

class _DropDownAction extends StatelessWidget {
  _DropDownAction();

  // should only have one action
  final actions = [
    PopupMenuButton<String>(
        tooltip: "",
        icon: const Icon(Icons.more_vert),
        itemBuilder: (context) {
          listTile(String text, bool checked) {
            return ListTile(
                title: Text(translate(text)),
                trailing: Icon(
                  Icons.check,
                  color: checked ? null : Colors.transparent,
                ));
          }

          final approveMode = gFFI.serverModel.approveMode;
          final verificationMethod = gFFI.serverModel.verificationMethod;
          final showPasswordOption = approveMode != 'click';
          final isApproveModeFixed = isOptionFixed(kOptionApproveMode);
          final isNumericOneTimePasswordFixed =
              isOptionFixed(kOptionAllowNumericOneTimePassword);
          final isAllowNumericOneTimePassword =
              gFFI.serverModel.allowNumericOneTimePassword;
          return [
            if (!isChangeIdDisabled())
              PopupMenuItem(
                enabled: gFFI.serverModel.connectStatus > 0,
                value: "changeID",
                child: Text(translate("Change ID")),
              ),
            if (!isChangeIdDisabled()) const PopupMenuDivider(),
            PopupMenuItem(
              value: 'AcceptSessionsViaPassword',
              child: listTile(
                  'Accept sessions via password', approveMode == 'password'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: 'AcceptSessionsViaClick',
              child:
                  listTile('Accept sessions via click', approveMode == 'click'),
              enabled: !isApproveModeFixed,
            ),
            PopupMenuItem(
              value: "AcceptSessionsViaBoth",
              child: listTile("Accept sessions via both",
                  approveMode != 'password' && approveMode != 'click'),
              enabled: !isApproveModeFixed,
            ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption &&
                verificationMethod != kUseTemporaryPassword &&
                !isChangePermanentPasswordDisabled())
              PopupMenuItem(
                value: "setPermanentPassword",
                child: Text(translate("Set permanent password")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "setTemporaryPasswordLength",
                child: Text(translate("One-time password length")),
              ),
            if (showPasswordOption &&
                verificationMethod != kUsePermanentPassword)
              PopupMenuItem(
                value: "allowNumericOneTimePassword",
                child: listTile(translate("Numeric one-time password"),
                    isAllowNumericOneTimePassword),
                enabled: !isNumericOneTimePasswordFixed,
              ),
            if (showPasswordOption) const PopupMenuDivider(),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseTemporaryPassword,
                child: listTile('Use one-time password',
                    verificationMethod == kUseTemporaryPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUsePermanentPassword,
                child: listTile('Use permanent password',
                    verificationMethod == kUsePermanentPassword),
              ),
            if (showPasswordOption)
              PopupMenuItem(
                value: kUseBothPasswords,
                child: listTile(
                    'Use both passwords',
                    verificationMethod != kUseTemporaryPassword &&
                        verificationMethod != kUsePermanentPassword),
              ),
          ];
        },
        onSelected: (value) async {
          if (value == "changeID") {
            changeIdDialog();
          } else if (value == "setPermanentPassword") {
            setPasswordDialog();
          } else if (value == "setTemporaryPasswordLength") {
            setTemporaryPasswordLengthDialog(gFFI.dialogManager);
          } else if (value == "allowNumericOneTimePassword") {
            gFFI.serverModel.switchAllowNumericOneTimePassword();
            gFFI.serverModel.updatePasswordModel();
          } else if (value == kUsePermanentPassword ||
              value == kUseTemporaryPassword ||
              value == kUseBothPasswords) {
            callback() {
              bind.mainSetOption(key: kOptionVerificationMethod, value: value);
              gFFI.serverModel.updatePasswordModel();
            }

            if (value == kUsePermanentPassword &&
                (await bind.mainGetCommon(key: "permanent-password-set")) !=
                    "true") {
              if (isChangePermanentPasswordDisabled()) {
                callback();
                return;
              }
              setPasswordDialog(notEmptyCallback: callback);
            } else {
              callback();
            }
          } else if (value.startsWith("AcceptSessionsVia")) {
            value = value.substring("AcceptSessionsVia".length);
            if (value == "Password") {
              gFFI.serverModel.setApproveMode('password');
            } else if (value == "Click") {
              gFFI.serverModel.setApproveMode('click');
            } else {
              gFFI.serverModel.setApproveMode(defaultOptionApproveMode);
            }
          }
        })
  ];

  @override
  Widget build(BuildContext context) {
    return actions[0];
  }
}

class _ServerPageState extends State<ServerPage> {
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _updateTimer = periodic_immediate(const Duration(seconds: 3), () async {
      await gFFI.serverModel.fetchID();
    });
    gFFI.serverModel.checkAndroidPermission();
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    checkService();
    return ChangeNotifierProvider.value(
        value: gFFI.serverModel,
        child: Consumer<ServerModel>(
            builder: (context, serverModel, child) => SingleChildScrollView(
                  controller: gFFI.serverModel.controller,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        buildPresetPasswordWarningMobile(),
                        gFFI.serverModel.isStart
                            ? ServerInfo()
                            : ServiceNotRunningNotification(),
                        const ConnectionManager(),
                        const PermissionChecker(),
                        SizedBox.fromSize(size: const Size(0, 15.0)),
                      ],
                    ),
                  ),
                )));
  }
}

void checkService() async {
  gFFI.invokeMethod("check_service");
  // for Android 10/11, request MANAGE_EXTERNAL_STORAGE permission from system setting page
  if (AndroidPermissionManager.isWaitingFile() && !gFFI.serverModel.fileOk) {
    AndroidPermissionManager.complete(kManageExternalStorage,
        await AndroidPermissionManager.check(kManageExternalStorage));
    debugPrint("file permission finished");
  }
}

class ServiceNotRunningNotification extends StatelessWidget {
  ServiceNotRunningNotification({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    return PaddingCard(
        title: translate("Service is not running"),
        titleIcon:
            const Icon(Icons.warning_amber_sharp, color: Colors.redAccent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(translate("android_start_service_tip"),
                    style:
                        const TextStyle(fontSize: 12, color: MyTheme.darkGray))
                .marginOnly(bottom: 8),
            ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow),
                onPressed: () {
                  if (gFFI.userModel.userName.value.isEmpty &&
                      bind.mainGetLocalOption(key: "show-scam-warning") !=
                          "N") {
                    showScamWarning(context, serverModel);
                  } else {
                    serverModel.toggleService();
                  }
                },
                label: Text(translate("Start service")))
          ],
        ));
  }
}

class ScamWarningDialog extends StatefulWidget {
  final ServerModel serverModel;

  ScamWarningDialog({required this.serverModel});

  @override
  ScamWarningDialogState createState() => ScamWarningDialogState();
}

class ScamWarningDialogState extends State<ScamWarningDialog> {
  int _countdown = bind.isCustomClient() ? 0 : 12;
  bool show_warning = false;
  late Timer _timer;
  late ServerModel _serverModel;

  @override
  void initState() {
    super.initState();
    _serverModel = widget.serverModel;
    startCountdown();
  }

  void startCountdown() {
    const oneSecond = Duration(seconds: 1);
    _timer = Timer.periodic(oneSecond, (timer) {
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isButtonLocked = _countdown > 0;

    return AlertDialog(
      content: ClipRRect(
        borderRadius: BorderRadius.circular(20.0),
        child: SingleChildScrollView(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color(0xffe242bc),
                  Color(0xfff4727c),
                ],
              ),
            ),
            padding: EdgeInsets.all(25.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_sharp,
                      color: Colors.white,
                    ),
                    SizedBox(width: 10),
                    Text(
                      translate("Warning"),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20.0,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20),
                Center(
                  child: Image.asset(
                    'assets/scam.png',
                    width: 180,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  translate("scam_title"),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22.0,
                  ),
                ),
                SizedBox(height: 18),
                Text(
                  "${translate("scam_text1")}\n\n${translate("scam_text2")}\n",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                Row(
                  children: <Widget>[
                    Checkbox(
                      value: show_warning,
                      onChanged: (value) {
                        setState(() {
                          show_warning = value!;
                        });
                      },
                    ),
                    Text(
                      translate("Don't show again"),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15.0,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        onPressed: isButtonLocked
                            ? null
                            : () {
                                Navigator.of(context).pop();
                                _serverModel.toggleService();
                                if (show_warning) {
                                  bind.mainSetLocalOption(
                                      key: "show-scam-warning", value: "N");
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          isButtonLocked
                              ? "${translate("I Agree")} (${_countdown}s)"
                              : translate("I Agree"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(width: 15),
                    Container(
                      constraints: BoxConstraints(maxWidth: 150),
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                        ),
                        child: Text(
                          translate("Decline"),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13.0,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      contentPadding: EdgeInsets.all(0.0),
    );
  }
}

class ServerInfo extends StatelessWidget {
  final model = gFFI.serverModel;
  final emptyController = TextEditingController(text: "-");

  ServerInfo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);

    void copyToClipboard(String value) {
      Clipboard.setData(ClipboardData(text: value));
      showToast(translate('Copied'));
    }

    final showOneTime = serverModel.approveMode != 'click' &&
        serverModel.verificationMethod != kUsePermanentPassword;

    return PaddingCard(
        title: translate('Your Device'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Both machine-readable values sit on the instrument plate, which
            // is a Directionality.ltr island — so a Persian user physically
            // cannot get a device ID rendered with Arabic-Indic digits or
            // reordered by the bidi algorithm. It also retires the old
            // .marginOnly(left: 39) indent: that emits a PHYSICAL inset, so it
            // stayed on the left in RTL instead of mirroring.
            InstrumentPlate(
              children: [
                InstrumentField(
                  label: translate('ID'),
                  value: GestureDetector(
                    onDoubleTap: () =>
                        copyToClipboard(model.serverId.text.trim()),
                    child: Text(
                      model.serverId.text,
                      style: InstrumentField.valueStyle(),
                    ),
                  ),
                  actions: [
                    InstrumentAction(
                      icon: const Icon(Icons.copy_outlined),
                      tooltip: translate('Copy to clipboard'),
                      onTap: () => copyToClipboard(model.serverId.text.trim()),
                    ),
                  ],
                ),
                InstrumentField(
                  label: translate('One-time Password'),
                  accent: showOneTime,
                  bottomGap: 0,
                  value: GestureDetector(
                    onDoubleTap: !showOneTime
                        ? null
                        : () => copyToClipboard(model.serverPasswd.text.trim()),
                    child: Text(
                      !showOneTime ? '-' : model.serverPasswd.text,
                      style: InstrumentField.valueStyle(accent: showOneTime),
                    ),
                  ),
                  actions: !showOneTime
                      ? const []
                      : [
                          InstrumentAction(
                            icon: const Icon(Icons.refresh),
                            tooltip: translate('Refresh Password'),
                            onTap: () => bind.mainUpdateTemporaryPassword(),
                          ),
                          InstrumentAction(
                            icon: const Icon(Icons.copy_outlined),
                            tooltip: translate('Copy to clipboard'),
                            onTap: () =>
                                copyToClipboard(model.serverPasswd.text.trim()),
                          ),
                        ],
                ),
              ],
            ),
            _ServiceStateLine(status: serverModel.connectStatus)
                .marginOnly(top: 14),
          ],
        ));
  }
}

/// The one prose line on this card: whether the relay is reachable.
///
/// It stays off the plate on purpose — it is a sentence, not a value, so it
/// follows the reading direction and uses directional insets.
class _ServiceStateLine extends StatelessWidget {
  const _ServiceStateLine({Key? key, required this.status}) : super(key: key);

  /// ServerModel.connectStatus: -1 failed, 0 connecting, 1 ready.
  final int status;

  @override
  Widget build(BuildContext context) {
    late final Widget mark;
    late final String label;
    switch (status) {
      case -1:
        mark = const Icon(Icons.warning_amber_rounded,
            color: MyTheme.snAmber, size: 20);
        label = translate('not_ready_status');
        break;
      case 0:
        mark = const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2));
        label = translate('connecting_status');
        break;
      default:
        mark = const Icon(Icons.check_circle_outline,
            color: MyTheme.snGreen, size: 20);
        label = translate('Ready');
    }
    return Row(
      children: [
        SizedBox(width: 20, height: 20, child: Center(child: mark)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.45,
              color: Theme.of(context).textTheme.bodyMedium?.color,
            ),
          ),
        ),
      ],
    );
  }
}

class PermissionChecker extends StatefulWidget {
  const PermissionChecker({Key? key}) : super(key: key);

  @override
  State<PermissionChecker> createState() => _PermissionCheckerState();
}

class _PermissionCheckerState extends State<PermissionChecker> {
  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    final hasAudioPermission = androidVersion >= 30;
    final hideStopService = isAndroid &&
        bind.mainGetBuildinOption(key: kOptionHideStopService) == 'Y';
    final allowPermChangeInAcceptWindow = option2bool(
        kOptionEnablePermChangeInAcceptWindow,
        bind.mainGetBuildinOption(
          key: kOptionEnablePermChangeInAcceptWindow,
        ));
    final permissionChangeLocked = isAndroid &&
        serverModel.clients.any((c) => !c.disconnected) &&
        !allowPermChangeInAcceptWindow;

    // The four capability rows carry the SAME brand hue as their desktop
    // counterparts in permissions_sheet.dart, so one product speaks one colour
    // language: input blue, clipboard cyan, file violet, audio green.
    //
    // Screen Capture is deliberately NOT given a fifth hue. It is the service
    // master, not a capability — with it off the other four cannot do anything
    // — so it sits above the well instead of competing inside it.
    final capabilities = <Widget>[
      PermissionRow(
        translate("Input Control"),
        serverModel.inputOk,
        serverModel.toggleInput,
        icon: Icons.keyboard,
        accent: MyTheme.snBlue,
      ),
      PermissionRow(
        translate("Enable clipboard"),
        serverModel.clipboardOk,
        serverModel.toggleClipboard,
        icon: Icons.content_paste,
        accent: MyTheme.snCyan,
        enabled: !permissionChangeLocked,
      ),
      PermissionRow(
        translate("Transfer file"),
        serverModel.fileOk,
        serverModel.toggleFile,
        icon: Icons.folder_outlined,
        accent: MyTheme.snViolet,
        enabled: !permissionChangeLocked,
      ),
      if (hasAudioPermission)
        PermissionRow(
          translate("Audio Capture"),
          serverModel.audioOk,
          serverModel.toggleAudio,
          icon: Icons.volume_up_outlined,
          accent: MyTheme.snGreen,
          enabled: !permissionChangeLocked,
          last: true,
        )
      else
        _PermissionNote(text: translate("android_version_audio_tip")),
    ];

    return PaddingCard(
        title: translate("Permissions"),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (serverModel.mediaOk && !hideStopService)
            ElevatedButton.icon(
                    style: ButtonStyle(
                        backgroundColor:
                            MaterialStateProperty.all(const Color(0xFFDC2626))),
                    icon: const Icon(Icons.stop),
                    onPressed: serverModel.toggleService,
                    label: Text(translate("Stop service")))
                .marginOnly(bottom: 10),
          if (!hideStopService || !serverModel.mediaOk)
            PermissionRow(
              translate("Screen Capture"),
              serverModel.mediaOk,
              !serverModel.mediaOk &&
                      gFFI.userModel.userName.value.isEmpty &&
                      bind.mainGetLocalOption(key: "show-scam-warning") != "N"
                  ? () => showScamWarning(context, serverModel)
                  : serverModel.toggleService,
              icon: Icons.screen_share_outlined,
              accent: MyTheme.snCyan,
              master: true,
            ).marginOnly(bottom: 10),
          // Inputs belong in a recessed well — that is the LUMEN role for
          // anything that takes a touch.
          LumenWell(children: capabilities),
        ]));
  }
}

/// One permission row.
///
/// Restyled only: the callbacks still run ServerModel.toggleInput/Clipboard/
/// File/Audio, which on Android drive the real runtime-permission flow. Those
/// four are NOT the desktop `enable-*` options and must not be swapped for
/// them — the mobile server page is the only caller of
/// checkAndroidPermission(), so these mirrors are authoritative here.
class PermissionRow extends StatelessWidget {
  const PermissionRow(this.name, this.isOk, this.onPressed,
      {Key? key,
      required this.icon,
      required this.accent,
      this.enabled = true,
      this.master = false,
      this.last = false})
      : super(key: key);

  final String name;
  final bool isOk;
  final VoidCallback onPressed;
  final IconData icon;
  final Color accent;
  final bool enabled;

  /// The service master sits in a well of its own, above the capabilities.
  final bool master;

  /// Suppresses the divider on the final row inside a well.
  final bool last;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 10, 11),
      child: Row(
        children: [
          LumenGlyphCell(icon: icon, on: isOk, accent: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: master ? FontWeight.w600 : FontWeight.w500,
                color: !enabled
                    ? MyTheme.textDim(context)
                    : Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          LumenSwitch(
            on: isOk,
            accent: accent,
            onChanged: enabled ? (_) => onPressed() : null,
          ),
        ],
      ),
    );

    final tappable = InkWell(onTap: enabled ? onPressed : null, child: row);

    if (master) {
      return LumenWell(children: [tappable]);
    }
    if (last) {
      return tappable;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tappable,
        // Hairline between rows, inset to the text column so the group reads as
        // one list rather than a stack of boxes. Directional on purpose: the
        // inset has to follow the reading direction.
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 44),
          child: Container(
            height: 1,
            color: lumenDark(context)
                ? const Color(0x14FFFFFF)
                : const Color(0x0F0F172A),
          ),
        ),
      ],
    );
  }
}

/// Shown instead of the audio row on Android below 11, where the platform has
/// no capture permission to ask for.
class _PermissionNote extends StatelessWidget {
  const _PermissionNote({Key? key, required this.text}) : super(key: key);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 12, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: MyTheme.textDim(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: MyTheme.textDim(context)),
            ),
          ),
        ],
      ),
    );
  }
}

class ConnectionManager extends StatelessWidget {
  const ConnectionManager({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final serverModel = Provider.of<ServerModel>(context);
    return Column(
        children: serverModel.clients
            .map((client) => PaddingCard(
                title: translate(
                    client.isFileTransfer ? "Transfer file" : "Share screen"),
                titleIcon: client.isFileTransfer
                    ? Icon(Icons.folder_outlined)
                    : Icon(Icons.mobile_screen_share),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: ClientInfo(client)),
                      Expanded(
                          flex: -1,
                          child: client.isFileTransfer || !client.authorized
                              ? const SizedBox.shrink()
                              : IconButton(
                                  onPressed: () {
                                    gFFI.chatModel.changeCurrentKey(
                                        MessageKey(client.peerId, client.id));
                                    final bar = navigationBarKey.currentWidget;
                                    if (bar != null) {
                                      bar as BottomNavigationBar;
                                      bar.onTap!(1);
                                    }
                                  },
                                  icon: unreadTopRightBuilder(
                                      client.unreadChatMessageCount)))
                    ],
                  ),
                  client.authorized
                      ? const SizedBox.shrink()
                      : Text(
                          translate("android_new_connection_tip"),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ).marginOnly(bottom: 5),
                  client.authorized
                      ? _buildDisconnectButton(client)
                      : _buildNewConnectionHint(serverModel, client),
                  if (client.incomingVoiceCall && !client.inVoiceCall)
                    ..._buildNewVoiceCallHint(context, serverModel, client),
                ])))
            .toList());
  }

  Widget _buildDisconnectButton(Client client) {
    final disconnectButton = ElevatedButton.icon(
      style: ButtonStyle(backgroundColor: MaterialStatePropertyAll(Colors.red)),
      icon: const Icon(Icons.close),
      onPressed: () {
        bind.cmCloseConnection(connId: client.id);
        gFFI.invokeMethod("cancel_notification", client.id);
      },
      label: Text(translate("Disconnect")),
    );
    final buttons = [disconnectButton];
    if (client.inVoiceCall) {
      buttons.insert(
        0,
        ElevatedButton.icon(
          style: ButtonStyle(
              backgroundColor: MaterialStatePropertyAll(Colors.red)),
          icon: const Icon(Icons.phone),
          label: Text(translate("Stop")),
          onPressed: () {
            bind.cmCloseVoiceCall(id: client.id);
            gFFI.invokeMethod("cancel_notification", client.id);
          },
        ),
      );
    }

    if (buttons.length == 1) {
      return Container(
        alignment: Alignment.centerRight,
        child: disconnectButton,
      );
    } else {
      return Row(
        children: buttons,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
      );
    }
  }

  Widget _buildNewConnectionHint(ServerModel serverModel, Client client) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      TextButton(
          child: Text(translate("Dismiss")),
          onPressed: () {
            serverModel.sendLoginResponse(client, false);
          }).marginOnly(right: 15),
      if (serverModel.approveMode != 'password')
        ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: Text(translate("Accept")),
            onPressed: () {
              serverModel.sendLoginResponse(client, true);
            }),
    ]);
  }

  List<Widget> _buildNewVoiceCallHint(
      BuildContext context, ServerModel serverModel, Client client) {
    return [
      Text(
        translate("android_new_voice_call_tip"),
        style: Theme.of(context).textTheme.bodyMedium,
      ).marginOnly(bottom: 5),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(
            child: Text(translate("Dismiss")),
            onPressed: () {
              serverModel.handleVoiceCall(client, false);
            }).marginOnly(right: 15),
        if (serverModel.approveMode != 'password')
          ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: Text(translate("Accept")),
              onPressed: () {
                serverModel.handleVoiceCall(client, true);
              }),
      ])
    ];
  }
}

class PaddingCard extends StatelessWidget {
  const PaddingCard({Key? key, required this.child, this.title, this.titleIcon})
      : super(key: key);

  final String? title;
  final Icon? titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final children = [child];
    if (title != null) {
      children.insert(
          0,
          Padding(
              padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
              child: Row(
                children: [
                  titleIcon?.marginOnly(right: 10) ?? const SizedBox.shrink(),
                  Expanded(
                    child: Text(title!,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.merge(TextStyle(fontWeight: FontWeight.bold))),
                  )
                ],
              )));
    }
    return SizedBox(
        width: double.maxFinite,
        child: GlassContainer(
          borderRadius: 16,
          margin: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 0),
          padding:
              const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
          child: Column(
            children: children,
          ),
        ));
  }
}

class ClientInfo extends StatelessWidget {
  final Client client;
  ClientInfo(this.client);

  @override
  Widget build(BuildContext context) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(children: [
          Row(
            children: [
              Expanded(
                  flex: -1,
                  child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildAvatar(context))),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(client.name, style: const TextStyle(fontSize: 18)),
                    const SizedBox(width: 8),
                    Text(client.peerId, style: const TextStyle(fontSize: 10))
                  ]))
            ],
          ),
        ]));
  }

  Widget _buildAvatar(BuildContext context) {
    final fallback = CircleAvatar(
      backgroundColor: str2color(client.name,
          Theme.of(context).brightness == Brightness.light ? 255 : 150),
      child: Text(client.name.isNotEmpty ? client.name[0] : '?'),
    );
    return buildAvatarWidget(
          avatar: client.avatar,
          size: 40,
          fallback: fallback,
        ) ??
        fallback;
  }
}

void androidChannelInit() {
  gFFI.setMethodCallHandler((method, arguments) {
    debugPrint("flutter got android msg,$method,$arguments");
    try {
      switch (method) {
        case "start_capture":
          {
            gFFI.dialogManager.dismissAll();
            gFFI.serverModel.updateClientState();
            break;
          }
        case "on_state_changed":
          {
            var name = arguments["name"] as String;
            var value = arguments["value"] as String == "true";
            debugPrint("from jvm:on_state_changed,$name:$value");
            gFFI.serverModel.changeStatue(name, value);
            break;
          }
        case "on_android_permission_result":
          {
            var type = arguments["type"] as String;
            var result = arguments["result"] as bool;
            AndroidPermissionManager.complete(type, result);
            break;
          }
        case "on_media_projection_canceled":
          {
            gFFI.serverModel.stopService();
            break;
          }
        case "msgbox":
          {
            var type = arguments["type"] as String;
            var title = arguments["title"] as String;
            var text = arguments["text"] as String;
            var link = (arguments["link"] ?? '') as String;
            msgBox(gFFI.sessionId, type, title, text, link, gFFI.dialogManager);
            break;
          }
        case "stop_service":
          {
            print(
                "stop_service by kotlin, isStart:${gFFI.serverModel.isStart}");
            if (gFFI.serverModel.isStart) {
              gFFI.serverModel.stopService();
            }
            break;
          }
      }
    } catch (e) {
      debugPrintStack(label: "MethodCallHandler err:$e");
    }
    return "";
  });
}

void showScamWarning(BuildContext context, ServerModel serverModel) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return ScamWarningDialog(serverModel: serverModel);
    },
  );
}
