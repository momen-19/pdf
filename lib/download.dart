import 'dart:io';
import 'dart:isolate';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_android/path_provider_android.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:test_app/item.dart';

import 'main.dart';

class Download extends StatefulWidget{
  final TargetPlatform? platform;

    Download({this.platform});

  @override
  _DownloadState createState() => _DownloadState();
}

class _DownloadState extends State<Download> {
  final ReceivePort _port = ReceivePort();
  late bool _isLoading;
  late bool _permissionReady;
  late String _localPath;

  final _documents = [
    {
      'name': 'Learning Android Studio',
      'link':
          'http://barbra-coco.dyndns.org/student/learning_android_studio.pdf'
    },
    {
      'name': 'Canyonlands National Park',
      'link':
          'https://upload.wikimedia.org/wikipedia/commons/7/78/Canyonlands_National_Park%E2%80%A6Needles_area_%286294480744%29.jpg'
    },
    {
      'name': 'Big Buck Bunny',
      'link':
          'http://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4'
    },
  ];

  late List<MyItem> itemsList;

  @override
  void initState() {
    super.initState();
    _bindBackgroundIsolate();
    FlutterDownloader.registerCallback(downloadCallback);
    _isLoading = true;
    _permissionReady = false;
    _prepare();
  }

  void _bindBackgroundIsolate() {
    bool isSuccess = IsolateNameServer.registerPortWithName(
        _port.sendPort, 'downloader_send_port');
    if (!isSuccess) {
      _unbindBackgroundIsolate();
      _bindBackgroundIsolate();
      return;
    }
    _port.listen((dynamic data) {
      if (debug) {
        print('UI Isolate Callback: $data');
      }
      /*
       Update UI with the latest progress
       */
      String? id = data[0];
      DownloadTaskStatus? status = data[1];
      int progress = data[2];

      if (itemsList.isNotEmpty) {
        final item = itemsList.firstWhere((it) => it.itemID == id);
        setState(() {
          item.status = status;
          item.progress = progress;
        });
      }
    });
  }

  void _unbindBackgroundIsolate() {
    IsolateNameServer.removePortNameMapping('downloader_send_port');
  }

  static void downloadCallback(
      String id, DownloadTaskStatus status, int progress) {
    if (debug) {
      print(
          'Background Isolate Callback: task ($id) is in status ($status) and process ($progress)');
    }
    final SendPort send =
        IsolateNameServer.lookupPortByName('downloader_send_port')!;
    send.send([id, status, progress]);
  }

  Future _prepare() async {
    itemsList = [];
    itemsList.addAll(_documents.map((doc) =>
        MyItem(name: doc['name'].toString(), url: doc['link'].toString())));
    _permissionReady = await _checkPermission();

    if (_permissionReady) {
      await _prepareSaveDir();
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<bool> _checkPermission() async {
    if (Platform.isIOS) return true;

    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
    if (widget.platform == TargetPlatform.android)
    // && androidInfo.version.sdkInt! <= 28)
    {
      final status = await Permission.storage.status;
      if (status != PermissionStatus.granted) {
        final result = await Permission.storage.request();
        if (result == PermissionStatus.granted) {
          return true;
        }
      } else {
        return true;
      }
    } else {
      return true;
    }
    return false;
  }

  Future<void> _prepareSaveDir() async {
    _localPath = (await _findLocalPath())!;
    final savedDir = Directory(_localPath);
    bool hasExisted = await savedDir.exists();
    if (!hasExisted) {
      savedDir.create();
    }
  }

  Future<String?> _findLocalPath() async {
    var externalStorageDirPath;
    if (Platform.isAndroid) {
      try {
        externalStorageDirPath = await PathProviderAndroid()
            .getDownloadsPath(); //AndroidPathProvider.downloadsPath;
      } catch (e) {
        final directory = await getExternalStorageDirectory();
        externalStorageDirPath = directory?.path;
      }
    } else if (Platform.isIOS) {
      externalStorageDirPath =
          (await getApplicationDocumentsDirectory()).absolute.path;
    }
    return externalStorageDirPath;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Download File App'),
        ),
        body: Builder(
          builder: (context) => _isLoading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : _permissionReady
                  ? Center(
                      child: ListView(
                        children: itemsList
                            .map(
                              (it) => DownloadITem(
                                  myItem: it,
                                  openItem: (myItem) {
                                    _openDownloadedFile(myItem).then((success) {
                                      if (!success) {
                                        Scaffold.of(context).showSnackBar(
                                          const SnackBar(
                                            content:
                                                Text('Cannot open this file'),
                                          ),
                                        );
                                      }
                                    });
                                  },
                                  onActionClick: (myItem) async {
                                    if (myItem.status ==
                                        DownloadTaskStatus.undefined) {
                                      myItem.itemID =
                                          await FlutterDownloader.enqueue(
                                        url: myItem.url,
                                        savedDir: _localPath,
                                        showNotification: true,
                                        openFileFromNotification: true,
                                        saveInPublicStorage: true,
                                      );
                                      //_requestDownload(myItem);
                                    } else if (myItem.status ==
                                        DownloadTaskStatus.running) {
                                      await FlutterDownloader.pause(
                                          taskId: myItem.itemID!);
                                    } else if (myItem.status ==
                                        DownloadTaskStatus.paused) {
                                      String? newTaskId =
                                          await FlutterDownloader.resume(
                                              taskId: myItem.itemID!);
                                      myItem.itemID = newTaskId;
                                    } else if (myItem.status ==
                                        DownloadTaskStatus.complete) {
                                      await FlutterDownloader.remove(
                                          taskId: myItem.itemID!,
                                          shouldDeleteContent: true);
                                      await _prepare();
                                      setState(() {});
                                    } else if (myItem.status ==
                                        DownloadTaskStatus.failed) {
                                      String? newTaskId =
                                          await FlutterDownloader.retry(
                                              taskId: myItem.itemID!);
                                      myItem.itemID = newTaskId;
                                    }
                                  }),
                            )
                            .toList(),
                      ),
                    )
                  : Container(),
        ));
  }

  Future<bool> _openDownloadedFile(MyItem item) {
    if (item != null) {
      return FlutterDownloader.open(taskId: item.itemID!);
    } else {
      return Future.value(false);
    }
  }

  @override
  void dispose() {
    _unbindBackgroundIsolate();
    super.dispose();
  }
}

class DownloadITem extends StatelessWidget {
  final MyItem myItem;
  final Function(MyItem) openItem;
  final Function(MyItem) onActionClick;

  DownloadITem(
      {required this.myItem,
      required this.openItem,
      required this.onActionClick});

  @override
  Widget build(BuildContext context) {
    return Container(
      //color: Colors.pink[50],
      padding: const EdgeInsets.only(
        left: 16.0,
        right: 8.0,
      ),
      child: InkWell(
        onTap: myItem.status == DownloadTaskStatus.complete
            ? () {
                openItem(myItem);
              }
            : null,
        child: Stack(
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              height: 64.0,
              //  color: Colors.amber,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      myItem.name,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: _buildActionForTask(myItem),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0.0,
              right: 0.0,
              bottom: 0.0,
              child: LinearProgressIndicator(
                value: myItem.progress / 100,
              ),
            )
            //: Container()
          ].toList(),
        ),
      ),
    );
  }

  Widget? _buildActionForTask(MyItem item) {
    if (item.status == DownloadTaskStatus.undefined) {
      return RawMaterialButton(
        onPressed: () {
          onActionClick(item);
        },
        shape: const CircleBorder(),
        constraints: const BoxConstraints(minHeight: 32.0, minWidth: 32.0),
        child: const Icon(Icons.file_download),
      );
    } else if (item.status == DownloadTaskStatus.running) {
      return RawMaterialButton(
        onPressed: () {
          onActionClick(item);
        },
        shape: const CircleBorder(),
        constraints: const BoxConstraints(minHeight: 32.0, minWidth: 32.0),
        child: const Icon(
          Icons.pause,
          color: Colors.red,
        ),
      );
    } else if (item.status == DownloadTaskStatus.paused) {
      return RawMaterialButton(
        onPressed: () {
          onActionClick(item);
        },
        shape: const CircleBorder(),
        constraints: const BoxConstraints(minHeight: 32.0, minWidth: 32.0),
        child: const Icon(
          Icons.play_arrow,
          color: Colors.green,
        ),
      );
    } else if (item.status == DownloadTaskStatus.complete) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text(
            'Ready',
            style: TextStyle(color: Colors.green),
          ),
          RawMaterialButton(
            onPressed: () {
              onActionClick(item);
            },
            shape: const CircleBorder(),
            constraints: const BoxConstraints(minHeight: 32.0, minWidth: 32.0),
            child: const Icon(
              Icons.delete_forever,
              color: Colors.red,
            ),
          )
        ],
      );
    } else if (item.status == DownloadTaskStatus.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Text('Failed', style: TextStyle(color: Colors.red)),
          RawMaterialButton(
            onPressed: () {
              onActionClick(item);
            },
            shape: const CircleBorder(),
            constraints: const BoxConstraints(minHeight: 32.0, minWidth: 32.0),
            child: const Icon(
              Icons.refresh,
              color: Colors.green,
            ),
          )
        ],
      );
    } else {
      return null;
    }
  }
}
