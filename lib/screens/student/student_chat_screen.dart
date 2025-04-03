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
  List<Map<String, dynamic>> _counselors = [];
  Map<String, dynamic> _recentMessages = {};
  final TextEditingController _searchController = TextEditingController();
  List<RealtimeChannel> _channels = [];

  // Flag to track if the widget is still mounted
  bool _isMounted = true;

  // Animation controller for tab switching
  late AnimationController _tabAnimationController;
  late Animation<double> _tabAnimation;

  @override
  void initState() {
    super.initState();
    _loadCounselors();
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
          _loadCounselors();
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
          // When a new message is received, refresh the messages
          if (_isMounted) {
            _loadRecentMessages();
          }
        },
      )
          .subscribe();

      _channels.add(messagesChannel);
    }
  }

  Future<void> _loadCounselors() async {
    if (!_isMounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Fetch all counselors
      final data = await _supabase
          .from('user_profiles')
          .select('*')
          .eq('user_type', 'counselor')
          .order('full_name');

      if (!_isMounted) return;

      setState(() {
        _counselors = List<Map<String, dynamic>>.from(data);
        _isLoading = false;
      });

      // Load recent messages for each counselor
      _loadRecentMessages();

    } catch (e) {
      print('Error loading counselors: $e');
      if (!_isMounted) return;

      setState(() {
        _isLoading = false;
      });

      Fluttertoast.showToast(
        msg: "Error loading counselors: $e",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
        backgroundColor: Colors.red,
      );
    }
  }

  Future<void> _loadRecentMessages() async {
    if (!_isMounted) return;

    final currentUserId = _firebaseAuth.currentUser?.uid;
    if (currentUserId == null) return;

    try {
      // For each counselor, fetch the most recent message
      Map<String, dynamic> recentMessages = {};

      for (var counselor in _counselors) {
        if (!_isMounted) return;

        final counselorId = counselor['user_id'];

        // Get the most recent message between the current user and this counselor
        final messages = await _supabase
            .from('messages')
            .select('*')
            .or('sender_id.eq.$currentUserId,receiver_id.eq.$currentUserId')
            .or('sender_id.eq.$counselorId,receiver_id.eq.$counselorId')
            .order('created_at', ascending: false)
            .limit(1);

        if (messages.isNotEmpty) {
          recentMessages[counselorId] = messages[0];
        }
      }

      if (!_isMounted) return;

      setState(() {
        _recentMessages = recentMessages;
      });
    } catch (e) {
      print('Error loading recent messages: $e');
    }
  }

  List<Map<String, dynamic>> _getFilteredCounselors() {
    return _counselors.where((counselor) {
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

  void _navigateToChatDetail(Map<String, dynamic> counselor) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentChatDetailScreen(
          recipientId: counselor['user_id'],
          recipientName: counselor['full_name'] ?? 'Counselor',
          isRecipientOnline: counselor['is_online'] ?? false,
        ),
      ),
    ).then((_) {
      // Refresh data when returning from chat detail
      if (_isMounted) {
        _loadRecentMessages();
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
    final filteredCounselors = _getFilteredCounselors();
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
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Colors.white),
            onPressed: () {
              // TODO: Navigate to notifications screen
              Fluttertoast.showToast(
                msg: "Notifications feature coming soon!",
                toastLength: Toast.LENGTH_SHORT,
                gravity: ToastGravity.BOTTOM,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadCounselors,
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

          // Counselor list
          Expanded(
            child: _isLoading
                ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            )
                : filteredCounselors.isEmpty
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
              onRefresh: _loadCounselors,
              child: AnimationLimiter(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredCounselors.length,
                  itemBuilder: (context, index) {
                    final counselor = filteredCounselors[index];
                    final counselorId = counselor['user_id'];
                    final recentMessage = _recentMessages[counselorId];

                    // Get message details
                    String lastMessage = 'Start a conversation';
                    String time = '';
                    int unreadCount = 0;
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

                      // Check if message is unread
                      final currentUserId = _firebaseAuth.currentUser?.uid;
                      if (recentMessage['receiver_id'] == currentUserId &&
                          !(recentMessage['is_read'] ?? true)) {
                        unreadCount = 1;
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
                            onTap: () => _navigateToChatDetail(counselor),
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
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: unreadCount > 0 ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
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
                    color: AppColors.counselorColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.counselorColor.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 32),
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
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.w600,
                          fontSize: 16,
                          color: Colors.black87,
                        ),
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
                      Expanded(
                        child: Text(
                          lastMessage,
                          style: TextStyle(
                            color: unreadCount > 0
                                ? Colors.black87
                                : Colors.grey.shade600,
                            fontWeight: unreadCount > 0
                                ? FontWeight.w500
                                : FontWeight.normal,
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