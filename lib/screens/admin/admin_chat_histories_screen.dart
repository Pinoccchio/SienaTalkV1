import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../utils/app_colors.dart';

class AdminChatHistoriesScreen extends StatefulWidget {
  const AdminChatHistoriesScreen({Key? key}) : super(key: key);

  @override
  State<AdminChatHistoriesScreen> createState() => _AdminChatHistoriesScreenState();
}

class _AdminChatHistoriesScreenState extends State<AdminChatHistoriesScreen> with SingleTickerProviderStateMixin {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Store unique conversations
  List<Map<String, dynamic>> _conversations = [];
  Map<String, Map<String, dynamic>> _userProfiles = {};

  // Animation controller for tab switching
  late AnimationController _tabAnimationController;
  late Animation<double> _tabAnimation;
  bool _showOnlyRecent = false;

  @override
  void initState() {
    super.initState();
    _loadConversations();

    // Initialize animation controller
    _tabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _tabAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _tabAnimationController,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch all non-anonymous messages
      final messagesData = await _supabase
          .from('messages')
          .select('*')
          .eq('is_anonymous', false)
          .order('created_at', ascending: false);

      // Group messages by student-counselor pairs
      Map<String, Map<String, dynamic>> conversationMap = {};

      for (var message in messagesData) {
        final senderId = message['sender_id'] as String?;
        final receiverId = message['receiver_id'] as String?;

        if (senderId == null || receiverId == null) continue;

        // Create a unique key for this student-counselor pair
        // We need to determine which is student and which is counselor
        String? studentId;
        String? counselorId;

        // Get user profiles if not already cached
        if (!_userProfiles.containsKey(senderId)) {
          await _fetchAndCacheUserProfile(senderId);
        }

        if (!_userProfiles.containsKey(receiverId)) {
          await _fetchAndCacheUserProfile(receiverId);
        }

        // Determine student and counselor based on user_type
        if (_userProfiles[senderId]?['user_type'] == 'student' &&
            _userProfiles[receiverId]?['user_type'] == 'counselor') {
          studentId = senderId;
          counselorId = receiverId;
        } else if (_userProfiles[senderId]?['user_type'] == 'counselor' &&
            _userProfiles[receiverId]?['user_type'] == 'student') {
          studentId = receiverId;
          counselorId = senderId;
        } else {
          // Skip if we can't determine student/counselor
          continue;
        }

        final conversationKey = '$studentId-$counselorId';

        // If this is a new conversation, create an entry
        if (!conversationMap.containsKey(conversationKey)) {
          conversationMap[conversationKey] = {
            'student_id': studentId,
            'counselor_id': counselorId,
            'student_name': _userProfiles[studentId]?['full_name'] ?? 'Unknown Student',
            'counselor_name': _userProfiles[counselorId]?['full_name'] ?? 'Unknown Counselor',
            'last_message': message['content'],
            'last_message_time': message['created_at'],
            'has_voice': message['voice_url'] != null && message['voice_url'].toString().isNotEmpty,
            'messages_count': 1,
            'last_message_data': message,
          };
        } else {
          // Update existing conversation with latest message info
          conversationMap[conversationKey]!['messages_count'] =
              (conversationMap[conversationKey]!['messages_count'] as int) + 1;

          // Check if this message is newer
          final existingTime = DateTime.parse(conversationMap[conversationKey]!['last_message_time']);
          final newTime = DateTime.parse(message['created_at']);

          if (newTime.isAfter(existingTime)) {
            conversationMap[conversationKey]!['last_message'] = message['content'];
            conversationMap[conversationKey]!['last_message_time'] = message['created_at'];
            conversationMap[conversationKey]!['has_voice'] =
                message['voice_url'] != null && message['voice_url'].toString().isNotEmpty;
            conversationMap[conversationKey]!['last_message_data'] = message;
          }
        }
      }

      // Convert map to list
      List<Map<String, dynamic>> conversations = conversationMap.values.toList();

      // Sort by last message time (newest first)
      conversations.sort((a, b) {
        final aTime = DateTime.parse(a['last_message_time']);
        final bTime = DateTime.parse(b['last_message_time']);
        return bTime.compareTo(aTime);
      });

      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading conversations: $e');
      setState(() {
        _errorMessage = 'Failed to load conversations: $e';
        _isLoading = false;
      });

      Fluttertoast.showToast(
        msg: "Error loading conversations: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _fetchAndCacheUserProfile(String userId) async {
    try {
      final userData = await _supabase
          .from('user_profiles')
          .select('*')
          .eq('user_id', userId)
          .single();

      _userProfiles[userId] = userData;
    } catch (e) {
      print('Error fetching user profile for $userId: $e');
      _userProfiles[userId] = {
        'user_id': userId,
        'full_name': 'Unknown User',
        'user_type': 'unknown'
      };
    }
  }

  List<Map<String, dynamic>> _getFilteredConversations() {
    return _conversations.where((conversation) {
      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final studentName = conversation['student_name'] ?? '';
        final counselorName = conversation['counselor_name'] ?? '';
        final lastMessage = conversation['last_message'] ?? '';

        return studentName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            counselorName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            lastMessage.toLowerCase().contains(_searchQuery.toLowerCase());
      }

      // Filter by recency if needed
      if (_showOnlyRecent) {
        final lastMessageTime = DateTime.parse(conversation['last_message_time']);
        final now = DateTime.now();
        final difference = now.difference(lastMessageTime);

        // Show only conversations with messages in the last 7 days
        return difference.inDays <= 7;
      }

      return true;
    }).toList();
  }

  void _toggleRecentFilter(bool showRecent) {
    setState(() {
      _showOnlyRecent = showRecent;
    });

    // Animate the tab indicator
    if (showRecent) {
      _tabAnimationController.forward();
    } else {
      _tabAnimationController.reverse();
    }
  }

  Future<void> _viewConversation(Map<String, dynamic> conversation) async {
    // Navigate to conversation detail screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdminConversationDetailScreen(
          studentId: conversation['student_id'],
          counselorId: conversation['counselor_id'],
          studentName: conversation['student_name'] ?? 'Unknown Student',
          counselorName: conversation['counselor_name'] ?? 'Unknown Counselor',
        ),
      ),
    ).then((_) {
      // Refresh data when returning from detail view
      _loadConversations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredConversations = _getFilteredConversations();
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chat Histories',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.adminColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadConversations,
            tooltip: 'Refresh Conversations',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.shade200,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search conversations',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  border: InputBorder.none,
                  icon: Icon(Icons.search, color: Colors.grey.shade600),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                      : null,
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tabs for All/Recent
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Stack(
                children: [
                  // Animated tab indicator
                  AnimatedBuilder(
                    animation: _tabAnimation,
                    builder: (context, child) {
                      return Positioned(
                        left: _tabAnimation.value * (screenWidth - 32) / 2,
                        top: 5,
                        bottom: 5,
                        width: (screenWidth - 32) / 2,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.adminColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.adminColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  // Tab buttons
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _toggleRecentFilter(false),
                          child: Center(
                            child: Text(
                              'All',
                              style: TextStyle(
                                color: !_showOnlyRecent ? Colors.white : Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _toggleRecentFilter(true),
                          child: Center(
                            child: Text(
                              'Recent',
                              style: TextStyle(
                                color: _showOnlyRecent ? Colors.white : Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Conversation list
          Expanded(
            child: _isLoading
                ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.adminColor),
              ),
            )
                : (_errorMessage != null
                ? _buildErrorView()
                : _buildConversationsList(filteredConversations)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Error loading conversations',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'Unknown error'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadConversations,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.adminColor,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationsList(List<Map<String, dynamic>> conversations) {
    if (conversations.isEmpty) {
      return Center(
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
              _showOnlyRecent
                  ? 'No recent conversations found'
                  : 'No non-anonymous conversations found',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            if (_searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Try a different search term',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadConversations,
      child: AnimationLimiter(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: conversations.length,
          itemBuilder: (context, index) {
            final conversation = conversations[index];
            final studentName = conversation['student_name'] ?? 'Unknown Student';
            final counselorName = conversation['counselor_name'] ?? 'Unknown Counselor';
            final lastMessage = conversation['last_message'] as String? ?? 'No messages';
            final hasVoice = conversation['has_voice'] ?? false;
            final messagesCount = conversation['messages_count'] ?? 0;
            final lastMessageData = conversation['last_message_data'];

            String timeAgo = '';
            if (conversation['last_message_time'] != null) {
              final lastMessageTime = DateTime.parse(conversation['last_message_time']);
              timeAgo = _getTimeAgo(lastMessageTime);
            }

            return AnimationConfiguration.staggeredList(
              position: index,
              duration: const Duration(milliseconds: 375),
              child: SlideAnimation(
                verticalOffset: 50.0,
                child: FadeInAnimation(
                  child: Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: InkWell(
                      onTap: () => _viewConversation(conversation),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: AppColors.studentColor,
                                        radius: 16,
                                        child: const Icon(Icons.person, color: Colors.white, size: 16),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          "$studentName (Student)",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: AppColors.studentColor,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  timeAgo,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: AppColors.counselorColor,
                                  radius: 16,
                                  child: const Icon(Icons.person, color: Colors.white, size: 16),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "$counselorName (Counselor)",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: AppColors.counselorColor,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (hasVoice)
                                  const Icon(
                                    Icons.mic,
                                    size: 16,
                                    color: Colors.grey,
                                  ),
                                if (hasVoice)
                                  const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    hasVoice ? 'Voice message' : lastMessage,
                                    style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontSize: 14,
                                      fontStyle: hasVoice ? FontStyle.italic : FontStyle.normal,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$messagesCount messages',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => _viewConversation(conversation),
                                  icon: const Icon(Icons.visibility, size: 16),
                                  label: const Text('View Details'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.adminColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} ${(difference.inDays / 365).floor() == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} ${(difference.inDays / 30).floor() == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }
}

// Conversation detail screen to view the full conversation
class AdminConversationDetailScreen extends StatefulWidget {
  final String studentId;
  final String counselorId;
  final String studentName;
  final String counselorName;

  const AdminConversationDetailScreen({
    Key? key,
    required this.studentId,
    required this.counselorId,
    required this.studentName,
    required this.counselorName,
  }) : super(key: key);

  @override
  State<AdminConversationDetailScreen> createState() => _AdminConversationDetailScreenState();
}

class _AdminConversationDetailScreenState extends State<AdminConversationDetailScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _messages = [];
  String? _currentlyPlayingId;
  Map<String, double> _audioPositions = {};
  Map<String, double> _audioDurations = {};
  bool _isAudioPlayerReady = false;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _setupAudioPlayer();
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

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Fetch all non-anonymous messages between this student and counselor
      // We need to use sender_id and receiver_id to find messages in both directions
      final messagesData = await _supabase
          .from('messages')
          .select('*')
          .or('and(sender_id.eq.${widget.studentId},receiver_id.eq.${widget.counselorId}),and(sender_id.eq.${widget.counselorId},receiver_id.eq.${widget.studentId})')
          .eq('is_anonymous', false)
          .order('created_at', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(messagesData);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading messages: $e');
      setState(() {
        _errorMessage = 'Failed to load messages: $e';
        _isLoading = false;
      });

      Fluttertoast.showToast(
        msg: "Error loading messages: $e",
        toastLength: Toast.LENGTH_LONG,
        backgroundColor: Colors.red,
      );
    }
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

  String _formatDuration(double milliseconds) {
    final duration = Duration(milliseconds: milliseconds.round());
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat: ${widget.studentName} (Student)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              'Counselor: ${widget.counselorName}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.adminColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadMessages,
            tooltip: 'Refresh Messages',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_errorMessage != null
          ? _buildErrorView()
          : _buildMessagesList()),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Error loading messages',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(_errorMessage ?? 'Unknown error'),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _loadMessages,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.adminColor,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            const Text(
              'No messages in this conversation',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        final isFromStudent = message['sender_id'] == widget.studentId;
        final messageTime = DateTime.parse(message['created_at']);
        final formattedTime = DateFormat('MMM d, h:mm a').format(messageTime);

        // Check if the message is a voice message
        final voiceUrl = message['voice_url'] as String?;
        final hasVoice = voiceUrl != null && voiceUrl.isNotEmpty;
        final messageId = message['id'] ?? 'msg-$index';
        final isPlaying = _currentlyPlayingId == messageId;
        final position = _audioPositions[messageId] ?? 0.0;
        final duration = _audioDurations[messageId] ?? 100.0;
        final progress = duration > 0 ? position / duration : 0.0;

        return Align(
          alignment: isFromStudent ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isFromStudent ? AppColors.studentColor.withOpacity(0.1) : AppColors.counselorColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isFromStudent ? AppColors.studentColor.withOpacity(0.3) : AppColors.counselorColor.withOpacity(0.3),
              ),
            ),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isFromStudent ? "${widget.studentName} (Student)" : "${widget.counselorName} (Counselor)",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isFromStudent ? AppColors.studentColor : AppColors.counselorColor,
                        fontSize: 12,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formattedTime,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                if (hasVoice)
                  InkWell(
                    onTap: () => _playVoiceMessage(messageId, voiceUrl!),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPlaying ? Icons.pause : Icons.play_arrow,
                          color: isFromStudent ? AppColors.studentColor : AppColors.counselorColor,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LinearProgressIndicator(
                                value: isPlaying ? progress : 0,
                                backgroundColor: Colors.grey.shade300,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  isFromStudent ? AppColors.studentColor : AppColors.counselorColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isPlaying
                                    ? '${_formatDuration(position)} / ${_formatDuration(duration)}'
                                    : 'Voice message',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontStyle: isPlaying ? FontStyle.normal : FontStyle.italic,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    message['content'] as String? ?? '',
                    style: const TextStyle(fontSize: 14),
                  ),

                // Show edited indicator if message was edited
                if (message['is_edited'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '(edited)',
                      style: TextStyle(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

