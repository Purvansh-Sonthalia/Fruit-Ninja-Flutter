import 'dart:io';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:developer';
import 'dart:convert'; // Import for jsonEncode/Decode

// Import models (adjust paths if necessary)
import '../models/post_model.dart';
import '../models/message_model.dart';
import '../models/conversation_summary_model.dart';

class DatabaseHelper {
  static const _databaseName = "AppCache.db";
  static const _databaseVersion = 1;

  // Table names
  static const tablePosts = 'posts';
  static const tableMessages = 'messages';
  static const tableConversationSummaries = 'conversation_summaries';

  // Post table columns
  static const columnPostId = 'post_id'; // TEXT PRIMARY KEY
  static const columnPostUserId = 'user_id'; // TEXT
  static const columnPostTextContent = 'text_content'; // TEXT
  static const columnPostCreatedAt = 'created_at'; // TEXT (ISO 8601)
  static const columnPostMediaContent = 'media_content'; // TEXT (JSON String)
  static const columnPostReported = 'reported'; // INTEGER (0 or 1)
  static const columnPostLikeCount = 'like_count'; // INTEGER
  static const columnPostCommentCount = 'comment_count'; // INTEGER
  static const columnPostUserDisplayName = 'user_display_name'; // TEXT NULLABLE

  // Message table columns
  static const columnMessageId = 'message_id'; // TEXT PRIMARY KEY
  static const columnMessageCreatedAt = 'created_at'; // TEXT (ISO 8601)
  static const columnMessageFromUserId = 'from_user_id'; // TEXT
  static const columnMessageToUserId = 'to_user_id'; // TEXT
  static const columnMessageText = 'message_text'; // TEXT NULLABLE
  static const columnMessageMedia =
      'message_media'; // TEXT (JSON String) NULLABLE
  static const columnMessageParentId = 'parent_message_id'; // TEXT NULLABLE
  // Display names are not stored in the message table directly, fetched separately

  // Conversation Summary table columns (using otherUserId as primary key)
  static const columnConvOtherUserId = 'other_user_id'; // TEXT PRIMARY KEY
  static const columnConvOtherUserDisplayName =
      'other_user_display_name'; // TEXT
  static const columnConvLastMessageText = 'last_message_text'; // TEXT
  static const columnConvLastMessageTimestamp =
      'last_message_timestamp'; // TEXT (ISO 8601)
  static const columnConvLastMessageFromUserId =
      'last_message_from_user_id'; // TEXT

  // Make this a singleton class.
  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  // Only have a single app-wide reference to the database.
  static Database? _database;
  Future<Database> get database async {
    if (_database != null) return _database!;
    // Lazily instantiate the db the first time it is accessed
    _database = await _initDatabase();
    return _database!;
  }

  // This opens the database (and creates it if it doesn't exist)
  _initDatabase() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, _databaseName);
    log('[DatabaseHelper] Database path: $path');
    return await openDatabase(path,
        version: _databaseVersion, onCreate: _onCreate);
  }

  // SQL code to create the database tables
  Future _onCreate(Database db, int version) async {
    log('[DatabaseHelper] Creating database tables...');
    await db.execute('''
          CREATE TABLE $tablePosts (
            $columnPostId TEXT PRIMARY KEY,
            $columnPostUserId TEXT NOT NULL,
            $columnPostTextContent TEXT,
            $columnPostCreatedAt TEXT NOT NULL,
            $columnPostMediaContent TEXT,
            $columnPostReported INTEGER NOT NULL DEFAULT 0,
            $columnPostLikeCount INTEGER NOT NULL DEFAULT 0,
            $columnPostCommentCount INTEGER NOT NULL DEFAULT 0,
            $columnPostUserDisplayName TEXT
          )
          ''');
    log('[DatabaseHelper] Created table: $tablePosts');

    await db.execute('''
          CREATE TABLE $tableMessages (
            $columnMessageId TEXT PRIMARY KEY,
            $columnMessageCreatedAt TEXT NOT NULL,
            $columnMessageFromUserId TEXT NOT NULL,
            $columnMessageToUserId TEXT NOT NULL,
            $columnMessageText TEXT,
            $columnMessageMedia TEXT,
            $columnMessageParentId TEXT
          )
          ''');
    log('[DatabaseHelper] Created table: $tableMessages');

    await db.execute('''
          CREATE TABLE $tableConversationSummaries (
            $columnConvOtherUserId TEXT PRIMARY KEY,
            $columnConvOtherUserDisplayName TEXT NOT NULL,
            $columnConvLastMessageText TEXT NOT NULL,
            $columnConvLastMessageTimestamp TEXT NOT NULL,
            $columnConvLastMessageFromUserId TEXT NOT NULL
          )
          ''');
    log('[DatabaseHelper] Created table: $tableConversationSummaries');
  }

  // --- CRUD operations ---

  // Insert/Update a list of posts (Upsert)
  Future<void> batchUpsertPosts(List<Post> posts) async {
    if (posts.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final post in posts) {
      batch.insert(
        tablePosts,
        _postToDbMap(post),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    // log('[DatabaseHelper] Batch upserted ${posts.length} posts.'); // Can be verbose
  }

  // Get cached posts, ordered by creation time descending
  Future<List<Post>> getCachedPosts({int limit = 20, int offset = 0}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tablePosts,
      orderBy: '$columnPostCreatedAt DESC',
      limit: limit,
      offset: offset,
    );
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) {
      return _dbMapToPost(maps[i]);
    });
  }

  // Insert/Update a list of messages (Upsert)
  Future<void> batchUpsertMessages(List<Message> messages) async {
    if (messages.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final message in messages) {
      batch.insert(
        tableMessages,
        _messageToDbMap(message),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    //  log('[DatabaseHelper] Batch upserted ${messages.length} messages.');
  }

  // Get cached messages for a chat, ordered by creation time descending
  Future<List<Message>> getCachedMessagesForChat(
      String otherUserId, String currentUserId,
      {int limit = 50}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableMessages,
      where:
          '(($columnMessageFromUserId = ? AND $columnMessageToUserId = ?) OR ($columnMessageFromUserId = ? AND $columnMessageToUserId = ?))',
      whereArgs: [currentUserId, otherUserId, otherUserId, currentUserId],
      orderBy: '$columnMessageCreatedAt DESC',
      limit: limit,
    );
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) {
      return _dbMapToMessage(maps[i]);
    });
  }

  // Insert/Update a list of conversation summaries (Upsert)
  Future<void> batchUpsertConversationSummaries(
      List<ConversationSummary> summaries) async {
    if (summaries.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final summary in summaries) {
      batch.insert(
        tableConversationSummaries,
        _summaryToDbMap(summary),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    //  log('[DatabaseHelper] Batch upserted ${summaries.length} summaries.');
  }

  // Get cached conversation summaries, ordered by last message time descending
  Future<List<ConversationSummary>> getCachedConversationSummaries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      tableConversationSummaries,
      orderBy: '$columnConvLastMessageTimestamp DESC',
    );
    if (maps.isEmpty) {
      return [];
    }
    return List.generate(maps.length, (i) {
      return _dbMapToSummary(maps[i]);
    });
  }

  // --- Delete Operations (Optional but Recommended) ---

  Future<void> deletePost(String postId) async {
    final db = await database;
    await db
        .delete(tablePosts, where: '$columnPostId = ?', whereArgs: [postId]);
    log('[DatabaseHelper] Deleted post $postId');
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    await db.delete(tableMessages,
        where: '$columnMessageId = ?', whereArgs: [messageId]);
    log('[DatabaseHelper] Deleted message $messageId');
  }

  // Deleting summaries might be less common, depends on logic
  Future<void> deleteConversationSummary(String otherUserId) async {
    final db = await database;
    await db.delete(tableConversationSummaries,
        where: '$columnConvOtherUserId = ?', whereArgs: [otherUserId]);
    log('[DatabaseHelper] Deleted conversation summary for $otherUserId');
  }

  // Added method to clear only conversation summaries
  Future<void> clearConversationSummaries() async {
    final db = await database;
    await db.delete(tableConversationSummaries);
    log('[DatabaseHelper] Cleared table: $tableConversationSummaries');
  }

  // Clear all data (useful for logout or debugging)
  Future<void> clearAllTables() async {
    final db = await database;
    await db.delete(tablePosts);
    await db.delete(tableMessages);
    await db.delete(tableConversationSummaries);
    log('[DatabaseHelper] Cleared all cache tables.');
  }

  // --- Model to Map Conversion Helpers ---

  Map<String, dynamic> _postToDbMap(Post post) {
    return {
      columnPostId: post.id,
      columnPostUserId: post.userId,
      columnPostTextContent: post.textContent,
      columnPostCreatedAt: post.createdAt.toIso8601String(),
      columnPostMediaContent:
          post.imageList != null ? jsonEncode(post.imageList) : null,
      columnPostReported: post.reported ? 1 : 0,
      columnPostLikeCount: post.likeCount,
      columnPostCommentCount: post.commentCount,
      columnPostUserDisplayName: post.displayName,
    };
  }

  Map<String, dynamic> _messageToDbMap(Message message) {
    return {
      columnMessageId: message.messageId,
      columnMessageCreatedAt: message.createdAt.toIso8601String(),
      columnMessageFromUserId: message.fromUserId,
      columnMessageToUserId: message.toUserId,
      columnMessageText: message.messageText,
      columnMessageMedia: message.messageMedia != null
          ? jsonEncode(message.messageMedia)
          : null,
      columnMessageParentId: message.parentMessageId,
    };
  }

  Map<String, dynamic> _summaryToDbMap(ConversationSummary summary) {
    return {
      columnConvOtherUserId: summary.otherUserId,
      columnConvOtherUserDisplayName: summary.otherUserDisplayName,
      columnConvLastMessageText: summary.lastMessageText,
      columnConvLastMessageTimestamp:
          summary.lastMessageTimestamp.toIso8601String(),
      columnConvLastMessageFromUserId: summary.lastMessageFromUserId,
    };
  }

  // --- Map to Model Conversion Helpers ---

  Post _dbMapToPost(Map<String, dynamic> map) {
    List<Map<String, dynamic>>? imageList;
    if (map[columnPostMediaContent] != null) {
      try {
        final decoded = jsonDecode(map[columnPostMediaContent]);
        if (decoded is List) {
          imageList = decoded.cast<Map<String, dynamic>>();
        } else {
          log('[DatabaseHelper] Warning: Failed to decode imageList for post ${map[columnPostId]}, expected List but got ${decoded.runtimeType}');
        }
      } catch (e) {
        log('[DatabaseHelper] Error decoding imageList JSON for post ${map[columnPostId]}: $e');
      }
    }

    return Post(
      id: map[columnPostId] as String,
      userId: map[columnPostUserId] as String,
      textContent: map[columnPostTextContent] as String? ?? '',
      createdAt: DateTime.parse(map[columnPostCreatedAt] as String),
      imageList: imageList,
      reported: (map[columnPostReported] as int? ?? 0) == 1,
      likeCount: map[columnPostLikeCount] as int? ?? 0,
      commentCount: map[columnPostCommentCount] as int? ?? 0,
      displayName: map[columnPostUserDisplayName] as String?,
    );
  }

  Message _dbMapToMessage(Map<String, dynamic> map) {
    Map<String, dynamic>? messageMedia;
    if (map[columnMessageMedia] != null) {
      try {
        messageMedia =
            jsonDecode(map[columnMessageMedia]) as Map<String, dynamic>?;
      } catch (e) {
        log('[DatabaseHelper] Error decoding messageMedia JSON for message ${map[columnMessageId]}: $e');
      }
    }

    return Message(
      messageId: map[columnMessageId] as String,
      createdAt: DateTime.parse(map[columnMessageCreatedAt] as String),
      fromUserId: map[columnMessageFromUserId] as String,
      toUserId: map[columnMessageToUserId] as String,
      messageText: map[columnMessageText] as String?,
      messageMedia: messageMedia,
      parentMessageId: map[columnMessageParentId] as String?,
      // Display names are not stored in the DB, will be fetched/added later by Provider
    );
  }

  ConversationSummary _dbMapToSummary(Map<String, dynamic> map) {
    return ConversationSummary(
      otherUserId: map[columnConvOtherUserId] as String,
      otherUserDisplayName: map[columnConvOtherUserDisplayName] as String,
      lastMessageText: map[columnConvLastMessageText] as String,
      lastMessageTimestamp:
          DateTime.parse(map[columnConvLastMessageTimestamp] as String),
      lastMessageFromUserId: map[columnConvLastMessageFromUserId] as String,
    );
  }
}
