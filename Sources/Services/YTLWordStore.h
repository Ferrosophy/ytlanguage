#import <Foundation/Foundation.h>

// Local SQLite store (Application Support/YTLanguage/ytlanguage.sqlite), schema_version 1.
// M1 writes saved_words; saved_sentences is created now for M2. All calls are serialized on one queue.
@interface YTLWordStore : NSObject
+ (instancetype)shared;
// Upserts by (language, normalized key). Returns NO and sets *error on failure.
- (BOOL)saveWord:(NSString *)surface definition:(NSString *)definition language:(NSString *)language
         videoID:(NSString *)videoID timeMs:(long long)timeMs error:(NSString **)error;
- (BOOL)hasWord:(NSString *)surface language:(NSString *)language;
- (NSInteger)wordCount;

// Inserts into saved_sentences (original text as selected/edited by the user, optional translation).
- (BOOL)saveSentence:(NSString *)text translation:(NSString *)translation language:(NSString *)language
             videoID:(NSString *)videoID title:(NSString *)title startMs:(long long)startMs endMs:(long long)endMs
               error:(NSString **)error;
- (NSInteger)sentenceCount;

// Newest first. Keys: id (NSNumber), text, translation (may be missing); sentences also videoID, title, startMs.
- (NSArray <NSDictionary *> *)allWords;
- (NSArray <NSDictionary *> *)allSentences;
- (BOOL)deleteWordWithID:(long long)rowID;
- (BOOL)deleteSentenceWithID:(long long)rowID;
@end
