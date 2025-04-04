import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/app_colors.dart';

class CounselorChatDetailScreen extends StatefulWidget {
  final String studentId;
  final String studentName;
  final String studentEmail;
  final bool isAnonymousConversation;
  final bool conversationFilter; // true for anonymous, false for regular
  final VoidCallback? onMessageSent;

  const CounselorChatDetailScreen({
    Key? key,
    required this.studentId,
    required this.studentName,
    required this.studentEmail,
    this.isAnonymousConversation = false,
    this.conversationFilter = false,
    this.onMessageSent,
  }) : super(key: key);

  @override
  State<CounselorChatDetailScreen> createState() => _CounselorChatDetailScreenState();
}

class _CounselorChatDetailScreenState extends State<CounselorChatDetailScreen> {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Uuid _uuid = const Uuid();

  bool _isLoading = true;
  bool _isSending = false;
  bool _isRecording = false;
  bool _isRecorderInitialized = false;
  String? _recordingPath;
  List<Map<String, dynamic>> _messages = [];
  bool _isStudentOnline = false;
  String? _currentUserId;
  RealtimeChannel? _messagesChannel;
  RealtimeChannel? _profilesChannel;
  String? _currentlyPlayingId;
  Map<String, StreamSubscription<Duration>> _audioPositionSubscriptions = {};
  Map<String, double> _audioPositions = {};
  Map<String, double> _audioDurations = {};
  // Recording duration tracking
  Timer? _recordingTimer;
  int _recordingDuration = 0;
  // Track if audio player is ready
  bool _isAudioPlayerReady = false;
  // Message editing
  String? _editingMessageId;
  String _originalMessageContent = '';
  // Check if conversation is anonymous
  bool _isAnonymousConversation = false;

  @override
  void initState() {
    super.initState();
    _currentUserId = _firebaseAuth.currentUser?.uid;
    _isAnonymousConversation = widget.isAnonymousConversation;
    _initRecorder();
    _loadMessages();
    _setupRealtimeSubscription();
    _setupAudioPlayer();
    _checkStudentStatus();
  }

  Future<void> _initRecorder() async {
    try {
      final status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        print('Microphone permission denied: $status');
        Fluttertoast.showToast(
          msg: "Microphone permission is required to record voice messages",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
        );
        return;
      }

      await _audioRecorder.openRecorder();
      _isRecorderInitialized = true;
      print('Audio recorder initialized successfully');
    } catch (e) {
      print('Error initializing recorder: $e');
      Fluttertoast.showToast(
        msg: "Failed to initialize audio recorder: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _checkStudentStatus() async {
    try {
      final data = await _supabase
          .from('user_profiles')
          .select('is_online')
          .eq('user_id', widget.studentId)
          .single();

      if (mounted) {
        setState(() {
          _isStudentOnline = data['is_online'] ?? false;
        });
      }
    } catch (e) {
      print('Error checking student status: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesChannel?.unsubscribe();
    _profilesChannel?.unsubscribe();
    if (_isRecorderInitialized) {
      _audioRecorder.closeRecorder();
    }
    _audioPlayer.dispose();
    _recordingTimer?.cancel();
    // Cancel all audio position subscriptions
    for (var subscription in _audioPositionSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _setupAudioPlayer() {
    // Set up player completion listener
    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted && _currentlyPlayingId != null) {
        setState(() {
          _currentlyPlayingId = null;
        });
      }
    });

    // Set up position tracking for all audio playback
    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted && _currentlyPlayingId != null) {
        setState(() {
          _audioPositions[_currentlyPlayingId!] = position.inMilliseconds.toDouble();
        });
      }
    });

    // Set up duration tracking for all audio playback
    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted && _currentlyPlayingId != null) {
        setState(() {
          _audioDurations[_currentlyPlayingId!] = duration.inMilliseconds.toDouble();
          _isAudioPlayerReady = true;
        });
      }
    });

    // Set player ready state
    _isAudioPlayerReady = true;
  }

  void _setupRealtimeSubscription() {
    // Subscribe to changes in user_profiles table to update online status in real-time
    _profilesChannel = _supabase
        .channel('public:user_profiles:${widget.studentId}')
        .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'user_profiles',
        callback: (payload) {
          if (mounted && payload.newRecord != null) {
            final newRecord = payload.newRecord as Map<String, dynamic>;
            setState(() {
              _isStudentOnline = newRecord['is_online'] ?? false;
            });
          }
        })
        .subscribe();

    // Subscribe to new messages
    _messagesChannel = _supabase
        .channel('public:messages:chat')
        .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          if (payload.newRecord != null) {
            final newMessage = payload.newRecord as Map<String, dynamic>;
            final senderId = newMessage['sender_id'];
            final receiverId = newMessage['receiver_id'];
            final isAnonymous = newMessage['is_anonymous'] ?? false;

            // Only add message if it's relevant to this chat, matches our anonymity filter
            // Check if it's between the current user and the student
            if ((senderId == widget.studentId && receiverId == _currentUserId) ||
                (senderId == _currentUserId && receiverId == widget.studentId)) {

              // Only add if the anonymity status matches the current conversation filter
              if (isAnonymous == widget.conversationFilter) {
                if (mounted) {
                  setState(() {
                    _messages.insert(0, Map<String, dynamic>.from(newMessage));
                  });

                  // Mark message as read if it's from the student
                  if (senderId == widget.studentId) {
                    _markMessageAsRead(newMessage['id']);
                  }

                  // Scroll to bottom
                  _scrollToBottom();
                }
              }
            }
          }
        })
        .onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          if (payload.newRecord != null) {
            final updatedMessage = payload.newRecord as Map<String, dynamic>;
            final messageId = updatedMessage['id'];
            final isAnonymous = updatedMessage['is_anonymous'] ?? false;

            // Only update if it matches our anonymity filter
            if (isAnonymous == widget.conversationFilter) {
              if (mounted) {
                // Find and update the message in our list
                final index = _messages.indexWhere((msg) => msg['id'] == messageId);
                if (index != -1) {
                  setState(() {
                    _messages[index] = Map<String, dynamic>.from(updatedMessage);
                  });
                }
              }
            }
          }
        })
        .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          if (payload.oldRecord != null) {
            final deletedMessage = payload.oldRecord as Map<String, dynamic>;
            final messageId = deletedMessage['id'];

            if (mounted) {
              // Remove the message from our list
              setState(() {
                _messages.removeWhere((msg) => msg['id'] == messageId);
              });
            }
          }
        })
        .subscribe();
  }

  Future<void> _loadMessages() async {
    if (_currentUserId == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch messages between current user and student, filtered by anonymity
      final data = await _supabase
          .from('messages')
          .select('*')
          .or('and(sender_id.eq.${_currentUserId},receiver_id.eq.${widget.studentId}),and(sender_id.eq.${widget.studentId},receiver_id.eq.${_currentUserId})')
          .eq('is_anonymous', widget.conversationFilter)
          .order('created_at', ascending: false);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });

        // Mark unread messages as read
        _markUnreadMessagesAsRead();

        // Scroll to bottom
        _scrollToBottom();
      }
    } catch (e) {
      print('Error loading messages: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        Fluttertoast.showToast(
          msg: "Error loading messages: $e",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  void _markUnreadMessagesAsRead() {
    if (_currentUserId == null) return;

    // Find all unread messages from the student
    final unreadMessages = _messages.where((msg) =>
    msg['sender_id'] == widget.studentId &&
        msg['receiver_id'] == _currentUserId &&
        !(msg['is_read'] ?? true)
    ).toList();

    // Mark each message as read
    for (var message in unreadMessages) {
      _markMessageAsRead(message['id']);
    }
  }

  Future<void> _markMessageAsRead(String? messageId) async {
    if (messageId == null) return;

    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('id', messageId);
    } catch (e) {
      print('Error marking message as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    // If we're editing a message, update it instead
    if (_editingMessageId != null) {
      await _updateMessage();
      return;
    }

    final messageText = _messageController.text.trim();
    if ((messageText.isEmpty && _recordingPath == null) || _currentUserId == null || _isSending) return;

    final now = DateTime.now().toIso8601String();

    // Clear input field immediately
    _messageController.clear();

    // Set sending state
    setState(() {
      _isSending = true;
    });

    try {
      Map<String, dynamic> newMessage = {
        'sender_id': _currentUserId,
        'receiver_id': widget.studentId,
        'is_read': false,
        'created_at': now,
        'is_anonymous': widget.conversationFilter, // Set anonymity based on conversation type
      };

      // Handle voice message if recording exists
      if (_recordingPath != null) {
        print('Sending voice message from path: $_recordingPath');

        final file = File(_recordingPath!);

        // Check if file exists
        if (!await file.exists()) {
          throw Exception('Recording file does not exist at path: $_recordingPath');
        }

        final fileSize = await file.length();
        print('Voice file size: $fileSize bytes');

        if (fileSize <= 0) {
          throw Exception('Recording file is empty (0 bytes)');
        }

        final fileName = '${_uuid.v4()}.aac';
        print('Uploading voice message with filename: $fileName');

        try {
          // Upload to Supabase Storage
          await _supabase
              .storage
              .from('voice.message')
              .upload(fileName, file);

          print('Voice file uploaded successfully');

          // Get public URL
          final voiceUrl = _supabase
              .storage
              .from('voice.message')
              .getPublicUrl(fileName);

          print('Voice URL generated: $voiceUrl');

          // Add voice URL to message
          newMessage['content'] = 'Voice message';
          newMessage['voice_url'] = voiceUrl;
        } catch (uploadError) {
          print('Error uploading voice file: $uploadError');
          Fluttertoast.showToast(
            msg: "Failed to upload voice message: $uploadError",
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.red,
          );
          throw uploadError;
        }

        // Reset recording path
        setState(() {
          _recordingPath = null;
        });
      } else {
        // Regular text message
        newMessage['content'] = messageText;
      }

      // Add message to UI immediately (optimistic update)
      setState(() {
        _messages.insert(0, Map<String, dynamic>.from(newMessage));
      });

      // Scroll to bottom
      _scrollToBottom();

      // Insert new message to database
      try {
        final response = await _supabase.from('messages').insert(newMessage).select();
        print('Message inserted into database: ${response.isNotEmpty ? 'success' : 'no response'}');

        if (mounted && response.isNotEmpty) {
          // Update the message in the list with the one from the database (to get the ID)
          setState(() {
            _messages[0] = response[0];
            _isSending = false;
          });
        }

        // Notify parent that a message was sent
        widget.onMessageSent?.call();
      } catch (dbError) {
        print('Error inserting message into database: $dbError');
        Fluttertoast.showToast(
          msg: "Failed to save message to database: $dbError",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
        );
        throw dbError;
      }
    } catch (e) {
      print('Error sending message: $e');

      if (mounted) {
        // Remove the optimistic message on error
        setState(() {
          _messages.removeAt(0);
          _isSending = false;
        });

        Fluttertoast.showToast(
          msg: "Failed to send message: $e",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
        );
      }
    }
  }

  Future<void> _updateMessage() async {
    if (_editingMessageId == null || _currentUserId == null) return;

    final messageText = _messageController.text.trim();
    if (messageText.isEmpty) return;

    // Clear input field immediately
    _messageController.clear();

    // Reset editing state
    final editingId = _editingMessageId;
    setState(() {
      _editingMessageId = null;
      _isSending = true;
    });

    try {
      // Update message in database
      await _supabase
          .from('messages')
          .update({
        'content': messageText,
        'is_edited': true,
        'edited_at': DateTime.now().toIso8601String(),
      })
          .eq('id', editingId as String)
          .eq('sender_id', _currentUserId as String); // Cast to fix type error

      // Find and update the message in our list
      if (mounted) {
        final index = _messages.indexWhere((msg) => msg['id'] == editingId);
        if (index != -1) {
          setState(() {
            _messages[index]['content'] = messageText;
            _messages[index]['is_edited'] = true;
            _messages[index]['edited_at'] = DateTime.now().toIso8601String();
            _isSending = false;
          });
        }
      }

      Fluttertoast.showToast(
        msg: "Message updated",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.green,
      );
    } catch (e) {
      print('Error updating message: $e');
      setState(() {
        _isSending = false;
      });

      Fluttertoast.showToast(
        msg: "Failed to update message: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _deleteMessage(String? messageId) async {
    if (_currentUserId == null || messageId == null) return;

    try {
      // Delete message from database
      await _supabase
          .from('messages')
          .delete()
          .eq('id', messageId)
          .eq('sender_id', _currentUserId as String); // Cast to fix type error

      // Remove the message from our list
      if (mounted) {
        setState(() {
          _messages.removeWhere((msg) => msg['id'] == messageId);
        });

        Fluttertoast.showToast(
          msg: "Message deleted",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.green,
        );
      }
    } catch (e) {
      print('Error deleting message: $e');
      Fluttertoast.showToast(
        msg: "Failed to delete message: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  void _editMessage(Map<String, dynamic> message) {
    if (message['voice_url'] != null) {
      // Can't edit voice messages
      Fluttertoast.showToast(
        msg: "Voice messages cannot be edited",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.orange,
      );
      return;
    }

    final content = message['content'] ?? '';

    setState(() {
      _editingMessageId = message['id'];
      _originalMessageContent = content;
      _messageController.text = content;
    });

    // Focus the text field
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelEditing() {
    setState(() {
      _editingMessageId = null;
      _messageController.text = '';
    });
  }

  // Show message options dialog
  void _showMessageOptions(BuildContext context, Map<String, dynamic> message) {
    final messageId = message['id'];
    final isVoiceMessage = message['voice_url'] != null;

    if (messageId == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  _showDeleteConfirmation(context, messageId);
                },
              ),
              if (!isVoiceMessage)
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    _showEditConfirmation(context, message);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  // Add a new method for delete confirmation
  void _showDeleteConfirmation(BuildContext context, String messageId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('Are you sure you want to delete this message? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(messageId);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // Add a new method for edit confirmation
  void _showEditConfirmation(BuildContext context, Map<String, dynamic> message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Message'),
        content: const Text('Do you want to edit this message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue,
            ),
            onPressed: () {
              Navigator.pop(context);
              _editMessage(message);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Future<void> _startRecording() async {
    if (!_isRecorderInitialized) {
      print('Cannot start recording: recorder not initialized');
      Fluttertoast.showToast(
        msg: "Audio recorder not initialized",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
      return;
    }

    try {
      // Get temp directory
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.aac';
      print('Starting recording to path: $path');

      // Start recording
      await _audioRecorder.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
      );

      print('Recording started successfully');

      setState(() {
        _isRecording = true;
        _recordingPath = path;
        _recordingDuration = 0;
      });

      // Start a timer to track recording duration
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _recordingDuration++;
        });
      });
    } catch (e) {
      print('Error starting recording: $e');
      Fluttertoast.showToast(
        msg: "Failed to start recording: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) {
      print('Cannot stop recording: not currently recording');
      return;
    }

    try {
      // Stop the recording timer
      _recordingTimer?.cancel();

      // Stop recording
      final recordedPath = await _audioRecorder.stopRecorder();
      print('Recording stopped. File saved at: $recordedPath');

      // Verify the file exists and has content
      final file = File(_recordingPath!);
      if (await file.exists()) {
        final size = await file.length();
        print('Recorded file size: $size bytes');

        if (size <= 0) {
          print('Warning: Recorded file is empty (0 bytes)');
          Fluttertoast.showToast(
            msg: "Recording is empty. Please try again.",
            toastLength: Toast.LENGTH_SHORT,
            gravity: ToastGravity.BOTTOM,
            backgroundColor: Colors.orange,
          );
          setState(() {
            _isRecording = false;
            _recordingPath = null;
          });
          return;
        }
      } else {
        print('Error: Recorded file does not exist at path: $_recordingPath');
        Fluttertoast.showToast(
          msg: "Recording file not found. Please try again.",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
          backgroundColor: Colors.red,
        );
        setState(() {
          _isRecording = false;
          _recordingPath = null;
        });
        return;
      }

      setState(() {
        _isRecording = false;
      });

      // Send the voice message
      _sendMessage();
    } catch (e) {
      print('Error stopping recording: $e');
      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });

      Fluttertoast.showToast(
        msg: "Failed to record voice message: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;

    try {
      // Stop the recording timer
      _recordingTimer?.cancel();

      // Stop recording without sending
      final path = await _audioRecorder.stopRecorder();
      print('Recording canceled. File was at: $path');

      // Try to delete the file
      try {
        final file = File(_recordingPath!);
        if (await file.exists()) {
          await file.delete();
          print('Canceled recording file deleted');
        }
      } catch (deleteError) {
        print('Error deleting canceled recording: $deleteError');
      }

      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });
    } catch (e) {
      print('Error canceling recording: $e');
      setState(() {
        _isRecording = false;
        _recordingPath = null;
      });
    }
  }

  String _formatRecordingDuration() {
    final minutes = (_recordingDuration ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordingDuration % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _playVoiceMessage(String messageId, String url) async {
    print('Attempting to play voice message: $url');

    // If already playing this message, stop it
    if (_currentlyPlayingId == messageId) {
      await _audioPlayer.stop();
      setState(() {
        _currentlyPlayingId = null;
      });
      return;
    }

    // If playing another message, stop it first
    if (_currentlyPlayingId != null) {
      await _audioPlayer.stop();
    }

    try {
      // Set the current playing ID before starting playback
      // This ensures the UI updates immediately
      setState(() {
        _currentlyPlayingId = messageId;

        // Initialize with default values to show animation immediately
        if (_audioDurations[messageId] == null) {
          _audioDurations[messageId] = 100.0; // Default duration until real one is loaded
          _audioPositions[messageId] = 0.0;
        }
      });

      // Pre-load the audio source
      await _audioPlayer.setSourceUrl(url);

      // Start playback
      await _audioPlayer.resume();
      print('Voice message playback started');

    } catch (e) {
      print('Error playing voice message: $e');
      setState(() {
        _currentlyPlayingId = null;
      });
      Fluttertoast.showToast(
        msg: "Failed to play voice message: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  String _formatMessageTime(String timestamp) {
    final dateTime = DateTime.parse(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (messageDate == today) {
      return DateFormat('h:mm a').format(dateTime);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return 'Yesterday, ${DateFormat('h:mm a').format(dateTime)}';
    } else {
      return DateFormat('MMM d, h:mm a').format(dateTime);
    }
  }

  String _formatDuration(double milliseconds) {
    final duration = Duration(milliseconds: milliseconds.round());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    String title = widget.isAnonymousConversation ? 'Anonymous Student' : widget.studentName;
    String conversationType = widget.conversationFilter ? 'Anonymous' : 'Regular';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (!widget.isAnonymousConversation)
              Text(
                widget.studentEmail,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            Text(
              _isStudentOnline ? 'Online' : 'Offline',
              style: TextStyle(
                fontSize: 12,
                color: _isStudentOnline ? Colors.green.shade300 : Colors.grey.shade300,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.counselorColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadMessages,
            tooltip: 'Refresh Messages',
          ),
        ],
      ),
      body: Column(
        children: [
          // Conversation type indicator
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            color: widget.conversationFilter ? Colors.grey.shade200 : Colors.blue.shade50,
            child: Row(
              children: [
                Icon(
                  widget.conversationFilter ? Icons.visibility_off : Icons.visibility,
                  size: 16,
                  color: widget.conversationFilter ? Colors.grey : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.conversationFilter
                        ? 'This is an anonymous conversation. The student\'s identity is hidden.'
                        : 'This is a regular conversation. The student\'s identity is visible.',
                    style: TextStyle(
                      fontSize: 12,
                      color: widget.conversationFilter ? Colors.grey.shade700 : Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Messages list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start a conversation with ${widget.isAnonymousConversation ? 'this student' : widget.studentName}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              reverse: true,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isMe = message['sender_id'] == _currentUserId;
                final time = message['created_at'] != null
                    ? _formatMessageTime(message['created_at'])
                    : '';
                final messageId = message['id'];
                final isSending = messageId == null;
                final isVoiceMessage = message['voice_url'] != null;
                final isEdited = message['is_edited'] ?? false;
                final isAnonymous = message['is_anonymous'] ?? false;

                return isVoiceMessage
                    ? _buildVoiceMessageBubble(
                  messageId: messageId ?? 'temp-${index}',
                  voiceUrl: message['voice_url'] ?? '',
                  time: time,
                  isMe: isMe,
                  isRead: message['is_read'] ?? false,
                  isSending: isSending,
                  isAnonymous: isAnonymous && !isMe,
                  message: message,
                )
                    : _buildMessageBubble(
                  message: message['content'] ?? '',
                  time: time,
                  isMe: isMe,
                  isRead: message['is_read'] ?? false,
                  isSending: isSending,
                  isEdited: isEdited,
                  isAnonymous: isAnonymous && !isMe,
                  messageData: message,
                );
              },
            ),
          ),

          // Editing indicator
          if (_editingMessageId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Editing message',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.blue),
                    onPressed: _cancelEditing,
                  ),
                ],
              ),
            ),

          // Recording indicator
          if (_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey.shade100,
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.mic, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _formatRecordingDuration(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Recording...',
                        style: TextStyle(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Cancel button
                      OutlinedButton.icon(
                        onPressed: _cancelRecording,
                        icon: const Icon(Icons.close, color: Colors.red),
                        label: const Text(
                          'Cancel',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Send button
                      ElevatedButton.icon(
                        onPressed: _stopRecording,
                        icon: const Icon(Icons.send, color: Colors.white),
                        label: const Text(
                          'Send',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.counselorColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          // Message input
          if (!_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade200,
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.mic, color: AppColors.counselorColor),
                      onPressed: _startRecording,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _messageController,
                        decoration: InputDecoration(
                          hintText: _editingMessageId != null
                              ? 'Edit message...'
                              : 'Type a message...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                        ),
                        textCapitalization: TextCapitalization.sentences,
                        minLines: 1,
                        maxLines: 5,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    IconButton(
                      icon: _isSending
                          ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.counselorColor,
                        ),
                      )
                          : Icon(
                          _editingMessageId != null ? Icons.check : Icons.send,
                          color: AppColors.counselorColor
                      ),
                      onPressed: _isSending ? null : _sendMessage,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required String message,
    required String time,
    required bool isMe,
    required bool isRead,
    required Map<String, dynamic> messageData,
    bool isSending = false,
    bool isEdited = false,
    bool isAnonymous = false,
  }) {
    final messageId = messageData['id'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            CircleAvatar(
              radius: 16,
              backgroundColor: isAnonymous ? Colors.grey.shade700 : AppColors.primary,
              child: Icon(
                  isAnonymous ? Icons.visibility_off : Icons.person,
                  color: Colors.white,
                  size: 16
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onLongPress: isMe && messageId != null && !isSending
                  ? () => _showMessageOptions(context, messageData)
                  : null,
              child: _buildMessageContent(
                message: message,
                time: time,
                isMe: isMe,
                isRead: isRead,
                isSending: isSending,
                isEdited: isEdited,
                isAnonymous: isAnonymous,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isMe)
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.counselorColor,
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageContent({
    required String message,
    required String time,
    required bool isMe,
    required bool isRead,
    bool isSending = false,
    bool isEdited = false,
    bool isAnonymous = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.counselorColor
            : (isAnonymous ? Colors.grey.shade700 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: TextStyle(
              color: isMe || isAnonymous ? Colors.white : Colors.black,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSending ? 'Sending...' : time,
                style: TextStyle(
                  color: isMe || isAnonymous ? Colors.white70 : Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              if (isEdited) ...[
                const SizedBox(width: 4),
                Text(
                  '(edited)',
                  style: TextStyle(
                    color: isMe || isAnonymous ? Colors.white70 : Colors.grey.shade600,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (isMe && !isSending) ...[
                const SizedBox(width: 4),
                Icon(
                  isRead ? Icons.done_all : Icons.done,
                  size: 14,
                  color: isRead ? Colors.white70 : Colors.white54,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceMessageBubble({
    required String messageId,
    required String voiceUrl,
    required String time,
    required bool isMe,
    required bool isRead,
    required Map<String, dynamic> message,
    bool isSending = false,
    bool isAnonymous = false,
  }) {
    final isPlaying = _currentlyPlayingId == messageId;
    final position = _audioPositions[messageId] ?? 0.0;
    final duration = _audioDurations[messageId] ?? 100.0; // Default duration if not loaded yet
    final progress = duration > 0 ? position / duration : 0.0;
    final id = message['id']; // Get the ID from the message map

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            CircleAvatar(
              radius: 16,
              backgroundColor: isAnonymous ? Colors.grey.shade700 : AppColors.primary,
              child: Icon(
                  isAnonymous ? Icons.visibility_off : Icons.person,
                  color: Colors.white,
                  size: 16
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: GestureDetector(
              onLongPress: isMe && id != null && !isSending
                  ? () => _showMessageOptions(context, message)
                  : null,
              child: _buildVoiceMessageContent(
                messageId: messageId,
                voiceUrl: voiceUrl,
                time: time,
                isMe: isMe,
                isRead: isRead,
                isSending: isSending,
                isPlaying: isPlaying,
                progress: progress,
                position: position,
                duration: duration,
                isAnonymous: isAnonymous,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isMe)
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.counselorColor,
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
        ],
      ),
    );
  }

  Widget _buildVoiceMessageContent({
    required String messageId,
    required String voiceUrl,
    required String time,
    required bool isMe,
    required bool isRead,
    required bool isSending,
    required bool isPlaying,
    required double progress,
    required double position,
    required double duration,
    required bool isAnonymous,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isMe
            ? AppColors.counselorColor
            : (isAnonymous ? Colors.grey.shade700 : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Voice message player
          InkWell(
            onTap: isSending ? null : () => _playVoiceMessage(messageId, voiceUrl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: isMe || isAnonymous ? Colors.white : AppColors.counselorColor,
                  size: 24,
                ),
                const SizedBox(width: 8),
                if (isSending)
                  SizedBox(
                    width: 100,
                    child: LinearProgressIndicator(
                      backgroundColor: isMe ? Colors.white30 : Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isMe ? Colors.white : AppColors.counselorColor,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          value: isPlaying ? progress : 0,
                          backgroundColor: isMe || isAnonymous ? Colors.white30 : Colors.grey.shade300,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isMe || isAnonymous ? Colors.white : AppColors.counselorColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPlaying
                              ? _formatDuration(position) + ' / ' + _formatDuration(duration)
                              : 'Voice message',
                          style: TextStyle(
                            color: isMe || isAnonymous ? Colors.white : Colors.black,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isSending ? 'Sending...' : time,
                style: TextStyle(
                  color: isMe || isAnonymous ? Colors.white70 : Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              if (isMe && !isSending) ...[
                const SizedBox(width: 4),
                Icon(
                  isRead ? Icons.done_all : Icons.done,
                  size: 14,
                  color: isRead ? Colors.white70 : Colors.white54,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

