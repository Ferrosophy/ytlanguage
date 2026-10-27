#import "YTLWordStore.h"
#import "../Core/YTLTextKit.h"
#import <sqlite3.h>

static const int kSchemaVersion = 1;

@implementation YTLWordStore {
    sqlite3 *_db;
    dispatch_queue_t _queue;
    NSString *_openError;
}

+ (instancetype)shared {
    static YTLWordStore *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [self new]; });
    return shared;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.ytlanguage.wordstore", DISPATCH_QUEUE_SERIAL);
        dispatch_sync(_queue, ^{ [self open]; });
    }
    return self;
}

- (BOOL)exec:(const char *)sql {
    char *message = NULL;
    if (sqlite3_exec(_db, sql, NULL, NULL, &message) == SQLITE_OK) return YES;
    _openError = message ? @(message) : @"sqlite error";
    sqlite3_free(message);
    return NO;
}

- (void)open {
    NSURL *dir = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject
                  URLByAppendingPathComponent:@"YTLanguage" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir URLByAppendingPathComponent:@"ytlanguage.sqlite"].path;
    if (sqlite3_open(path.fileSystemRepresentation, &_db) != SQLITE_OK) {
        _openError = @"无法打开数据库";
        sqlite3_close(_db);
        _db = NULL;
        return;
    }
    [self exec:"PRAGMA journal_mode=WAL;"];

    sqlite3_stmt *stmt = NULL;
    int version = 0;
    if (sqlite3_prepare_v2(_db, "PRAGMA user_version;", -1, &stmt, NULL) == SQLITE_OK && sqlite3_step(stmt) == SQLITE_ROW) {
        version = sqlite3_column_int(stmt, 0);
    }
    sqlite3_finalize(stmt);
    if (version >= kSchemaVersion) return;

    BOOL ok = [self exec:"BEGIN;"] &&
        [self exec:"CREATE TABLE IF NOT EXISTS saved_words ("
                    "id INTEGER PRIMARY KEY, normalized_key TEXT NOT NULL, surface TEXT NOT NULL, lemma TEXT, "
                    "language TEXT NOT NULL, definition TEXT, video_id TEXT, video_time_ms INTEGER, "
                    "created_at REAL NOT NULL, updated_at REAL NOT NULL);"] &&
        [self exec:"CREATE UNIQUE INDEX IF NOT EXISTS saved_words_key ON saved_words(language, normalized_key);"] &&
        [self exec:"CREATE TABLE IF NOT EXISTS saved_sentences ("
                    "id INTEGER PRIMARY KEY, source_text TEXT NOT NULL, translated_text TEXT, source_language TEXT NOT NULL, "
                    "target_language TEXT, video_id TEXT NOT NULL, video_title TEXT, start_ms INTEGER NOT NULL, end_ms INTEGER, "
                    "created_at REAL NOT NULL, updated_at REAL NOT NULL);"] &&
        [self exec:"PRAGMA user_version = 1;"];
    [self exec:ok ? "COMMIT;" : "ROLLBACK;"];
}

static void YTLBindText(sqlite3_stmt *stmt, int index, NSString *text) {
    if (text) sqlite3_bind_text(stmt, index, text.UTF8String, -1, SQLITE_TRANSIENT);
    else sqlite3_bind_null(stmt, index);
}

- (BOOL)saveWord:(NSString *)surface definition:(NSString *)definition language:(NSString *)language
         videoID:(NSString *)videoID timeMs:(long long)timeMs error:(NSString **)error {
    NSString *key = [YTLTextKit normalizedWord:surface];
    if (!key.length) {
        if (error) *error = @"空单词";
        return NO;
    }
    __block BOOL ok = NO;
    __block NSString *failure = nil;
    dispatch_sync(_queue, ^{
        if (!self->_db) { failure = self->_openError; return; }
        const char *sql = "INSERT INTO saved_words (normalized_key, surface, language, definition, video_id, video_time_ms, created_at, updated_at) "
                          "VALUES (?, ?, ?, ?, ?, ?, ?, ?) "
                          "ON CONFLICT(language, normalized_key) DO UPDATE SET surface = excluded.surface, "
                          "definition = COALESCE(excluded.definition, definition), video_id = excluded.video_id, "
                          "video_time_ms = excluded.video_time_ms, updated_at = excluded.updated_at;";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            failure = @(sqlite3_errmsg(self->_db));
            return;
        }
        double now = NSDate.date.timeIntervalSince1970;
        YTLBindText(stmt, 1, key);
        YTLBindText(stmt, 2, surface);
        YTLBindText(stmt, 3, language ?: @"en");
        YTLBindText(stmt, 4, definition.length ? definition : nil);
        YTLBindText(stmt, 5, videoID);
        if (timeMs >= 0) sqlite3_bind_int64(stmt, 6, timeMs); else sqlite3_bind_null(stmt, 6);
        sqlite3_bind_double(stmt, 7, now);
        sqlite3_bind_double(stmt, 8, now);
        ok = sqlite3_step(stmt) == SQLITE_DONE;
        if (!ok) failure = @(sqlite3_errmsg(self->_db));
        sqlite3_finalize(stmt);
    });
    if (!ok && error) *error = failure ?: @"保存失败";
    return ok;
}

- (BOOL)hasWord:(NSString *)surface language:(NSString *)language {
    NSString *key = [YTLTextKit normalizedWord:surface];
    __block BOOL found = NO;
    dispatch_sync(_queue, ^{
        if (!self->_db) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, "SELECT 1 FROM saved_words WHERE language = ? AND normalized_key = ?;", -1, &stmt, NULL) != SQLITE_OK) return;
        YTLBindText(stmt, 1, language ?: @"en");
        YTLBindText(stmt, 2, key);
        found = sqlite3_step(stmt) == SQLITE_ROW;
        sqlite3_finalize(stmt);
    });
    return found;
}

- (NSInteger)countRows:(const char *)sql {
    __block NSInteger count = 0;
    dispatch_sync(_queue, ^{
        if (!self->_db) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) == SQLITE_OK && sqlite3_step(stmt) == SQLITE_ROW) {
            count = sqlite3_column_int(stmt, 0);
        }
        sqlite3_finalize(stmt);
    });
    return count;
}

- (NSInteger)wordCount {
    return [self countRows:"SELECT COUNT(*) FROM saved_words;"];
}

- (NSInteger)sentenceCount {
    return [self countRows:"SELECT COUNT(*) FROM saved_sentences;"];
}

- (BOOL)saveSentence:(NSString *)text translation:(NSString *)translation language:(NSString *)language
             videoID:(NSString *)videoID title:(NSString *)title startMs:(long long)startMs endMs:(long long)endMs
               error:(NSString **)error {
    NSString *clean = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!clean.length || !videoID.length) {
        if (error) *error = clean.length ? @"没有视频 ID" : @"空句子";
        return NO;
    }
    __block BOOL ok = NO;
    __block NSString *failure = nil;
    dispatch_sync(_queue, ^{
        if (!self->_db) { failure = self->_openError; return; }
        const char *sql = "INSERT INTO saved_sentences (source_text, translated_text, source_language, target_language, video_id, "
                          "video_title, start_ms, end_ms, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);";
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) {
            failure = @(sqlite3_errmsg(self->_db));
            return;
        }
        double now = NSDate.date.timeIntervalSince1970;
        YTLBindText(stmt, 1, clean);
        YTLBindText(stmt, 2, translation.length ? translation : nil);
        YTLBindText(stmt, 3, language ?: @"en");
        YTLBindText(stmt, 4, translation.length ? @"zh-Hans" : nil);
        YTLBindText(stmt, 5, videoID);
        YTLBindText(stmt, 6, title.length ? title : nil);
        sqlite3_bind_int64(stmt, 7, MAX(0, startMs));
        if (endMs >= 0) sqlite3_bind_int64(stmt, 8, endMs); else sqlite3_bind_null(stmt, 8);
        sqlite3_bind_double(stmt, 9, now);
        sqlite3_bind_double(stmt, 10, now);
        ok = sqlite3_step(stmt) == SQLITE_DONE;
        if (!ok) failure = @(sqlite3_errmsg(self->_db));
        sqlite3_finalize(stmt);
    });
    if (!ok && error) *error = failure ?: @"保存失败";
    return ok;
}

- (NSArray <NSDictionary *> *)rows:(const char *)sql {
    NSMutableArray *rows = [NSMutableArray array];
    dispatch_sync(_queue, ^{
        if (!self->_db) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            row[@"id"] = @(sqlite3_column_int64(stmt, 0));
            const unsigned char *text = sqlite3_column_text(stmt, 1);
            const unsigned char *translation = sqlite3_column_text(stmt, 2);
            row[@"text"] = text ? @((const char *)text) : @"";
            if (translation) row[@"translation"] = @((const char *)translation);
            if (sqlite3_column_count(stmt) >= 6) {   // sentences: video_id, video_title, start_ms
                const unsigned char *videoID = sqlite3_column_text(stmt, 3);
                const unsigned char *title = sqlite3_column_text(stmt, 4);
                if (videoID) row[@"videoID"] = @((const char *)videoID);
                if (title) row[@"title"] = @((const char *)title);
                row[@"startMs"] = @(sqlite3_column_int64(stmt, 5));
            }
            [rows addObject:row];
        }
        sqlite3_finalize(stmt);
    });
    return rows;
}

- (NSArray <NSDictionary *> *)allWords {
    return [self rows:"SELECT id, surface, definition FROM saved_words ORDER BY updated_at DESC;"];
}

- (NSArray <NSDictionary *> *)allSentences {
    return [self rows:"SELECT id, source_text, translated_text, video_id, video_title, start_ms FROM saved_sentences ORDER BY created_at DESC;"];
}

- (BOOL)deleteRow:(long long)rowID sql:(const char *)sql {
    __block BOOL ok = NO;
    dispatch_sync(_queue, ^{
        if (!self->_db) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) return;
        sqlite3_bind_int64(stmt, 1, rowID);
        ok = sqlite3_step(stmt) == SQLITE_DONE;
        sqlite3_finalize(stmt);
    });
    return ok;
}

- (BOOL)deleteWordWithID:(long long)rowID {
    return [self deleteRow:rowID sql:"DELETE FROM saved_words WHERE id = ?;"];
}

- (BOOL)deleteSentenceWithID:(long long)rowID {
    return [self deleteRow:rowID sql:"DELETE FROM saved_sentences WHERE id = ?;"];
}

@end
