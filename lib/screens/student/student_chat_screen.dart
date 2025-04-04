import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../../utils/app_colors.dart';
import 'student_chat_detail_screen.dart';

class StudentChatScreen extends StatefulWidget {
  const StudentChatScreen({Key? key}) : super(key: key);

  @override
  State<StudentChatScreen> createState() => _StudentChatScreenState();
}

class _StudentChatScreenState extends State<StudentChatScreen> with SingleTickerProviderStateMixin {
  final firebase.FirebaseAuth _firebaseAuth = firebase.FirebaseAuth.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _showOnlyActive = false;
  String _searchQuery = '';
  List<Map<String, dynamic>> _conversations = [];
  List<Map<String, dynamic>> _allCounselors = []; // Store all counselors
  final TextEditingController _searchController = TextEditingController();
  List<RealtimeChannel> _channels = [];
  bool _isAnonymousMode = false;
  Map<String, dynamic>? _userProfile;
  String? _currentUserId;

  // Flag to track if the widget is still mounted
  bool _isMounted = true;

  // Animation controller for tab switching
  late AnimationController _tabAnimationController;
  late Animation<double> _tabAnimation;

  @override
  void initState() {
    super.initState();
    _currentUserId = _firebaseAuth.currentUser?.uid;
    _loadUserProfile();
    _loadConversations();
    _setupRealtimeSubscription();

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
    _isMounted = false;
    _searchController.dispose();
    _tabAnimationController.dispose();
    // Unsubscribe from all channels
    for (var channel in _channels) {
      channel.unsubscribe();
    }
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) return;

    try {
      final data = await _supabase
          .from('user_profiles')
          .select('*')
          .eq('user_id', userId)
          .single();

      if (!_isMounted) return;

      setState(() {
        _userProfile = data;
        _isAnonymousMode = data['is_anonymous'] ?? false;
      });
    } catch (e) {
      print('Error loading user profile: $e');
    }
  }

  Future<void> _toggleAnonymousMode() async {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) return;

    try {
      // Update the user profile
      await _supabase
          .from('user_profiles')
          .update({'is_anonymous': !_isAnonymousMode})
          .eq('user_id', userId);

      if (!_isMounted) return;

      setState(() {
        _isAnonymousMode = !_isAnonymousMode;
        if (_userProfile != null) {
          _userProfile!['is_anonymous'] = _isAnonymousMode;
        }
      });

      Fluttertoast.showToast(
        msg: _isAnonymousMode
            ? "Anonymous mode enabled"
            : "Anonymous mode disabled",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: AppColors.primary,
      );
    } catch (e) {
      print('Error toggling anonymous mode: $e');
      Fluttertoast.showToast(
        msg: "Error changing anonymous mode",
        toastLength: Toast.LENGTH_SHORT,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  void _setupRealtimeSubscription() {
    // Subscribe to changes in user_profiles table to update online status in real-time
    final profilesChannel = _supabase.channel('public:user_profiles');
    profilesChannel
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'user_profiles',
      callback: (payload) {
        // When a user's online status changes, refresh the counselor list
        if (_isMounted) {
          _loadConversations();

          // If it's the current user's profile that changed, update the local state
          final userId = _firebaseAuth.currentUser?.uid;
          if (userId != null && payload.newRecord != null && payload.newRecord!['user_id'] == userId) {
            setState(() {
              _userProfile = payload.newRecord;
              _isAnonymousMode = payload.newRecord!['is_anonymous'] ?? false;
            });
          }
        }
      },
    )
        .subscribe();

    _channels.add(profilesChannel);

    // Subscribe to new messages
    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId != null) {
      final messagesChannel = _supabase.channel('public:messages');
      messagesChannel
          .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload) {
          // When a new message is received, refresh the conversations
          if (_isMounted) {
            _loadConversations();
          }
        },
      )
          .subscribe();

      _channels.add(messagesChannel);
    }
  }

  Future<void> _loadConversations() async {
    if (!_isMounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch all counselors
      final counselorsData = await _supabase
          .from('user_profiles')
          .select('*')
          .eq('user_type', 'counselor')
          .order('full_name');

      if (!_isMounted) return;

      // Store all counselors
      _allCounselors = List<Map<String, dynamic>>.from(counselorsData);

      // Get all messages between student and counselors
      final currentUserId = _firebaseAuth.currentUser?.uid;
      if (currentUserId == null) return;

      final messagesData = await _supabase
          .from('messages')
          .select('*')
          .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
          .order('created_at', ascending: false);

      // Group messages by conversation
      Map<String, List<Map<String, dynamic>>> conversationGroups = {};

      for (var message in messagesData) {
        String counselorId;
        if (message['sender_id'] == currentUserId) {
          counselorId = message['receiver_id'];
        } else {
          counselorId = message['sender_id'];
        }

        // Create a unique conversation ID that includes anonymity status
        bool isAnonymous = message['is_anonymous'] == true;
        String conversationKey = '$counselorId:${isAnonymous ? 'anonymous' : 'regular'}';

        if (!conversationGroups.containsKey(conversationKey)) {
          conversationGroups[conversationKey] = [];
        }

        conversationGroups[conversationKey]!.add(message);
      }

      // Create conversation list with the most recent message for each conversation
      List<Map<String, dynamic>> conversations = [];

      // First, add all existing conversations
      for (var entry in conversationGroups.entries) {
        // Sort messages by date (newest first)
        entry.value.sort((a, b) =>
            DateTime.parse(b['created_at']).compareTo(DateTime.parse(a['created_at']))
        );

        // Get the most recent message
        var recentMessage = entry.value.first;

        // Extract counselor ID and anonymity from the conversation key
        String counselorId = entry.key.split(':')[0];
        bool isAnonymous = entry.key.split(':')[1] == 'anonymous';

        // Find the counselor in the counselors list
        final counselor = _allCounselors.firstWhere(
              (c) => c['user_id'] == counselorId,
          orElse: () => {'user_id': counselorId, 'full_name': 'Unknown Counselor', 'is_online': false},
        );

        // Count unread messages (only those sent by the counselor to the student)
        int unreadCount = entry.value.where((msg) =>
        msg['sender_id'] == counselorId &&
            msg['receiver_id'] == currentUserId &&
            !(msg['is_read'] ?? true)
        ).length;

        // Create conversation object
        Map<String, dynamic> conversation = {
          'counselor': counselor,
          'recent_message': recentMessage,
          'is_anonymous': isAnonymous,
          'unread_count': unreadCount,
          'has_conversation': true,
          'conversation_key': entry.key, // Store the conversation key for reference
        };

        conversations.add(conversation);
      }

      // Track which counselors already have conversations (both regular and anonymous)
      Map<String, Set<String>> counselorConversationTypes = {};

      for (var convo in conversations) {
        String counselorId = convo['counselor']['user_id'];
        bool isAnonymous = convo['is_anonymous'];

        if (!counselorConversationTypes.containsKey(counselorId)) {
          counselorConversationTypes[counselorId] = {};
        }

        counselorConversationTypes[counselorId]!.add(isAnonymous ? 'anonymous' : 'regular');
      }

      // Then add counselors that don't have any conversations yet
      for (var counselor in _allCounselors) {
        String counselorId = counselor['user_id'];

        // If counselor doesn't have any conversations, add both regular and anonymous options
        if (!counselorConversationTypes.containsKey(counselorId)) {
          // Add regular conversation option
          Map<String, dynamic> regularConversation = {
            'counselor': counselor,
            'recent_message': null,
            'is_anonymous': false,
            'unread_count': 0,
            'has_conversation': false,
            'conversation_key': '$counselorId:regular',
          };
          conversations.add(regularConversation);

          // Add anonymous conversation option
          Map<String, dynamic> anonymousConversation = {
            'counselor': counselor,
            'recent_message': null,
            'is_anonymous': true,
            'unread_count': 0,
            'has_conversation': false,
            'conversation_key': '$counselorId:anonymous',
          };
          conversations.add(anonymousConversation);
        }
        // If counselor has only one type of conversation, add the other type
        else {
          Set<String> existingTypes = counselorConversationTypes[counselorId]!;

          // Add regular conversation option if it doesn't exist
          if (!existingTypes.contains('regular')) {
            Map<String, dynamic> regularConversation = {
              'counselor': counselor,
              'recent_message': null,
              'is_anonymous': false,
              'unread_count': 0,
              'has_conversation': false,
              'conversation_key': '$counselorId:regular',
            };
            conversations.add(regularConversation);
          }

          // Add anonymous conversation option if it doesn't exist
          if (!existingTypes.contains('anonymous')) {
            Map<String, dynamic> anonymousConversation = {
              'counselor': counselor,
              'recent_message': null,
              'is_anonymous': true,
              'unread_count': 0,
              'has_conversation': false,
              'conversation_key': '$counselorId:anonymous',
            };
            conversations.add(anonymousConversation);
          }
        }
      }

      if (!_isMounted) return;

      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });

    } catch (e) {
      print('Error loading conversations: $e');
      if (!_isMounted) return;

      setState(() {
        _isLoading = false;
      });

      Fluttertoast.showToast(
        msg: "Error loading conversations: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  List<Map<String, dynamic>> _getFilteredConversations() {
    return _conversations.where((conversation) {
      final counselor = conversation['counselor'];

      // Filter by active status if needed
      if (_showOnlyActive && !(counselor['is_online'] ?? false)) {
        return false;
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final name = counselor['full_name'] ?? '';
        return name.toLowerCase().contains(_searchQuery.toLowerCase());
      }

      return true;
    }).toList();
  }

  void _navigateToChatDetail(Map<String, dynamic> conversation) {
    final counselor = conversation['counselor'];
    final isAnonymous = conversation['is_anonymous'];

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentChatDetailScreen(
          recipientId: counselor['user_id'],
          recipientName: counselor['full_name'] ?? 'Counselor',
          isRecipientOnline: counselor['is_online'] ?? false,
          isAnonymousMode: isAnonymous,
          conversationFilter: isAnonymous, // This ensures we only show messages matching this anonymity status
        ),
      ),
    ).then((_) {
      // Refresh data when returning from chat detail
      if (_isMounted) {
        _loadConversations();
        _loadUserProfile(); // Refresh anonymous mode status
      }
    });
  }

  void _toggleActiveFilter(bool showActive) {
    if (!_isMounted) return;

    setState(() {
      _showOnlyActive = showActive;
    });

    // Animate the tab indicator
    if (showActive) {
      _tabAnimationController.forward();
    } else {
      _tabAnimationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredConversations = _getFilteredConversations();
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chat',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          // Anonymous mode toggle
          IconButton(
            icon: Icon(
              _isAnonymousMode ? Icons.visibility_off : Icons.visibility,
              color: Colors.white,
            ),
            onPressed: _toggleAnonymousMode,
            tooltip: _isAnonymousMode ? 'Disable Anonymous Mode' : 'Enable Anonymous Mode',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadConversations,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Anonymous mode banner
          if (_isAnonymousMode)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.grey.shade800,
              child: Row(
                children: [
                  const Icon(Icons.visibility_off, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Anonymous mode is enabled. Your identity is hidden from counselors.',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleAnonymousMode,
                    child: const Text(
                      'Disable',
                      style: TextStyle(color: Colors.white),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 0),
                    ),
                  ),
                ],
              ),
            ),

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
                  hintText: 'Search counselors',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  border: InputBorder.none,
                  icon: Icon(Icons.search, color: Colors.grey.shade600),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      if (_isMounted) {
                        setState(() {
                          _searchQuery = '';
                        });
                      }
                    },
                  )
                      : null,
                ),
                onChanged: (value) {
                  if (_isMounted) {
                    setState(() {
                      _searchQuery = value;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Tabs for All/Active
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
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
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
                          onTap: () => _toggleActiveFilter(false),
                          child: Center(
                            child: Text(
                              'All',
                              style: TextStyle(
                                color: !_showOnlyActive ? Colors.white : Colors.grey.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _toggleActiveFilter(true),
                          child: Center(
                            child: Text(
                              'Active',
                              style: TextStyle(
                                color: _showOnlyActive ? Colors.white : Colors.grey.shade700,
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
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            )
                : filteredConversations.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _showOnlyActive ? Icons.person_off : Icons.search_off,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _showOnlyActive
                        ? 'No active counselors found'
                        : 'No counselors found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _showOnlyActive
                        ? 'Try checking all counselors'
                        : 'Try a different search term',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
                : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadConversations,
              child: AnimationLimiter(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredConversations.length,
                  itemBuilder: (context, index) {
                    final conversation = filteredConversations[index];
                    final counselor = conversation['counselor'];
                    final recentMessage = conversation['recent_message'];
                    final isAnonymous = conversation['is_anonymous'];
                    final unreadCount = conversation['unread_count'] ?? 0;
                    final hasConversation = conversation['has_conversation'] ?? false;

                    // Get message details
                    String lastMessage = isAnonymous
                        ? 'Start an anonymous conversation'
                        : 'Start a conversation';
                    String time = '';
                    bool isVoiceMessage = false;

                    if (recentMessage != null) {
                      // Check if it's a voice message
                      isVoiceMessage = recentMessage['voice_url'] != null;
                      lastMessage = isVoiceMessage
                          ? '🎤 Voice message'
                          : (recentMessage['content'] ?? 'No message');

                      // Format time
                      final createdAt = DateTime.parse(recentMessage['created_at']);
                      final now = DateTime.now();
                      final difference = now.difference(createdAt);

                      if (difference.inDays > 6) {
                        // Show date for older messages
                        time = DateFormat('MMM d').format(createdAt);
                      } else if (difference.inDays > 0) {
                        // Show day of week
                        time = DateFormat('EEE').format(createdAt);
                      } else {
                        // Show time for today's messages
                        time = DateFormat('h:mm a').format(createdAt);
                      }
                    }

                    return AnimationConfiguration.staggeredList(
                      position: index,
                      duration: const Duration(milliseconds: 375),
                      child: SlideAnimation(
                        verticalOffset: 50.0,
                        child: FadeInAnimation(
                          child: _buildChatItem(
                            name: counselor['full_name'] ?? 'Counselor',
                            lastMessage: lastMessage,
                            time: time,
                            unreadCount: unreadCount,
                            isOnline: counselor['is_online'] ?? false,
                            isVoiceMessage: isVoiceMessage,
                            isAnonymous: isAnonymous,
                            hasConversation: hasConversation,
                            onTap: () => _navigateToChatDetail(conversation),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatItem({
    required String name,
    required String lastMessage,
    required String time,
    required int unreadCount,
    required bool isOnline,
    required Function() onTap,
    bool isVoiceMessage = false,
    bool isAnonymous = false,
    bool hasConversation = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: unreadCount > 0
              ? Colors.blue.shade50
              : hasConversation
              ? Colors.white
              : isAnonymous
              ? Colors.grey.shade100  // Darker background for anonymous
              : Colors.grey.shade50,  // Lighter background for regular
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
          border: isAnonymous
              ? Border.all(color: Colors.grey.shade300, width: 1)
              : null,
        ),
        child: Row(
          children: [
            // Avatar with online indicator
            Stack(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: isAnonymous ? Colors.grey.shade700 : AppColors.counselorColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (isAnonymous ? Colors.grey.shade700 : AppColors.counselorColor).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                      isAnonymous ? Icons.visibility_off : Icons.person,
                      color: Colors.white,
                      size: 32
                  ),
                ),
                if (isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          if (isAnonymous) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade800,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Anonymous',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (time.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: unreadCount > 0
                                ? AppColors.primary.withOpacity(0.1)
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            time,
                            style: TextStyle(
                              color: unreadCount > 0
                                  ? AppColors.primary
                                  : Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (isVoiceMessage)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.mic,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      if (isAnonymous && !isVoiceMessage)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade800.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.visibility_off,
                            size: 16,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      if (!hasConversation)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isAnonymous
                                ? Colors.grey.shade700.withOpacity(0.1)
                                : Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.add_comment,
                            size: 16,
                            color: isAnonymous ? Colors.grey.shade700 : Colors.blue,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: TextStyle(
                            color: unreadCount > 0
                                ? Colors.black87
                                : hasConversation
                                ? Colors.grey.shade600
                                : isAnonymous
                                ? Colors.grey.shade700
                                : Colors.blue.shade700, // Blue text for new conversations
                            fontWeight: unreadCount > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
                            fontStyle: !hasConversation ? FontStyle.italic : FontStyle.normal,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

