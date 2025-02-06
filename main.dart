import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '24/7 Video Channels',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: HomeScreen(),
    );
  }
}

/// نموذج بيانات القناة
class Channel {
  final String id;
  final String name;
  final int maxVideos;
  final List<String> videoUrls;
  final String ownerId;

  Channel({
    required this.id,
    required this.name,
    required this.maxVideos,
    required this.videoUrls,
    required this.ownerId,
  });
}

/// خدمة Firebase للمهام الأساسية
class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // إنشاء قناة جديدة
  Future<void> createChannel(String name, int maxVideos, String ownerId) async {
    try {
      await _firestore.collection('channels').add({
        'name': name,
        'maxVideos': maxVideos,
        'videoUrls': [],
        'ownerId': ownerId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw 'خطأ في إنشاء القناة: ${e.toString()}';
    }
  }

  // رفع فيديو إلى التخزين
  Future<String> uploadVideo(String channelId, File file) async {
    try {
      final ref = _storage.ref('channels/$channelId/${DateTime.now().millisecondsSinceEpoch}.mp4');
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (e) {
      throw 'خطأ في رفع الفيديو: ${e.toString()}';
    }
  }

  // تحديث القناة بإضافة رابط الفيديو
  Future<void> addVideoToChannel(String channelId, String videoUrl) async {
    try {
      await _firestore.collection('channels').doc(channelId).update({
        'videoUrls': FieldValue.arrayUnion([videoUrl])
      });
    } catch (e) {
      throw 'خطأ في إضافة الفيديو: ${e.toString()}';
    }
  }

  // جلب جميع القنوات
  Stream<List<Channel>> getChannelsStream() {
    return _firestore.collection('channels').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return Channel(
          id: doc.id,
          name: doc['name'],
          maxVideos: doc['maxVideos'],
          videoUrls: List<String>.from(doc['videoUrls']),
          ownerId: doc['ownerId'],
        );
      }).toList();
    });
  }

  // حذف القناة وجميع فيديوهاتها
  Future<void> deleteChannel(String channelId) async {
    try {
      // حذف الفيديوهات من التخزين
      final listResult = await _storage.ref('channels/$channelId').listAll();
      await Future.wait(listResult.items.map((ref) => ref.delete()));
      
      // حذف بيانات القناة
      await _firestore.collection('channels').doc(channelId).delete();
    } catch (e) {
      throw 'خطأ في حذف القناة: ${e.toString()}';
    }
  }
}

/// الشاشة الرئيسية
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('القنوات النشطة')),
      body: StreamBuilder<List<Channel>>(
        stream: _firebaseService.getChannelsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text('حدث خطأ ما!'));
          if (!snapshot.hasData) return Center(child: CircularProgressIndicator());

          final channels = snapshot.data!;
          return ListView.builder(
            itemCount: channels.length,
            itemBuilder: (context, index) => _buildChannelTile(channels[index]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.add),
        onPressed: () => _showCreateChannelDialog(context),
      ),
    );
  }

  Widget _buildChannelTile(Channel channel) {
    return ListTile(
      title: Text(channel.name),
      subtitle: Text('${channel.videoUrls.length}/${channel.maxVideos} فيديو'),
      trailing: IconButton(
        icon: Icon(Icons.delete),
        onPressed: () => _deleteChannel(channel),
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VideoPlayerScreen(channel: channel)),
      ),
    );
  }

  void _showCreateChannelDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    String name = '';
    int maxVideos = 5;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('إنشاء قناة جديدة'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: InputDecoration(labelText: 'اسم القناة'),
                validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                onChanged: (v) => name = v,
              ),
              DropdownButtonFormField<int>(
                value: maxVideos,
                items: [5, 10, 15].map((num) => DropdownMenuItem(
                  value: num,
                  child: Text('الحد الأقصى: $num فيديو'),
                )).toList(),
                onChanged: (v) => maxVideos = v!,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  await _firebaseService.createChannel(name, maxVideos, 'user123');
                  Navigator.pop(context);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
                }
              }
            },
            child: Text('إنشاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteChannel(Channel channel) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف القناة'),
        content: Text('هل أنت متأكد من حذف "${channel.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _firebaseService.deleteChannel(channel.id);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

/// شاشة تشغيل الفيديوهات
class VideoPlayerScreen extends StatefulWidget {
  final Channel channel;

  VideoPlayerScreen({required this.channel});

  @override
  _VideoPlayerScreenState createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  int _currentVideoIndex = 0;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  void _initializeVideo() {
    if (widget.channel.videoUrls.isEmpty) return;

    _controller = VideoPlayerController.network(widget.channel.videoUrls[_currentVideoIndex])
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _setupVideoListener();
      });
  }

  void _setupVideoListener() {
    _controller.addListener(() {
      if (_controller.value.position >= _controller.value.duration) {
        _playNextVideo();
      }
    });
  }

  void _playNextVideo() {
    _currentVideoIndex = (_currentVideoIndex + 1) % widget.channel.videoUrls.length;
    _controller = VideoPlayerController.network(widget.channel.videoUrls[_currentVideoIndex])
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _setupVideoListener();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      body: widget.channel.videoUrls.isEmpty
          ? Center(child: Text('لا يوجد فيديوهات في هذه القناة'))
          : Column(
              children: [
                AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
                VideoProgressIndicator(_controller, allowScrubbing: true),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.upload_file),
        onPressed: () => _uploadVideo(context),
      ),
    );
  }

  Future<void> _uploadVideo(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.video);
      if (result == null) return;

      final file = File(result.files.single.path!);
      final videoUrl = await FirebaseService().uploadVideo(widget.channel.id, file);
      await FirebaseService().addVideoToChannel(widget.channel.id, videoUrl);
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم رفع الفيديو بنجاح')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
