#import "UYTDownloadsDB.h"
#import "UYTLog.h"
#import <sqlite3.h>

static NSString *UYTDownloadsDBPath(void) {
    NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [docs stringByAppendingPathComponent:@"uYou"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:@"uyoudb.sqlite"];
}

static BOOL UYTDownloadsDBInsertAtPath(NSString *dbPath,
                                       NSString *rowID,
                                       NSString *videoID,
                                       NSString *title,
                                       NSString *channel,
                                       NSString *channelURL,
                                       NSString *qualityLabel,
                                       NSString *typeAndQuality,
                                       unsigned long long size,
                                       NSTimeInterval duration,
                                       NSString *type,
                                       NSString *path) {
    sqlite3 *db = NULL;
    if (sqlite3_open([dbPath UTF8String], &db) != SQLITE_OK) {
        UYTDebugErr(@"[UYTPipeline] uyoudb.sqlite open failed at %@: %s", dbPath, sqlite3_errmsg(db));
        if (db) sqlite3_close(db);
        return NO;
    }

    const char *createSQL =
        "CREATE TABLE IF NOT EXISTS downloads ("
        "id TEXT PRIMARY KEY, videoID TEXT, title TEXT, channel TEXT, "
        "channelURL TEXT, qualityLabel TEXT, typeAndQuality TEXT, size TEXT, "
        "duration TEXT, type TEXT, path TEXT, lyrics TEXT, timestamp DATETIME)";
    char *createErr = NULL;
    if (sqlite3_exec(db, createSQL, NULL, NULL, &createErr) != SQLITE_OK) {
        UYTDebugErr(@"[UYTPipeline] uyoudb.sqlite CREATE TABLE failed: %s", createErr);
        sqlite3_free(createErr);
        sqlite3_close(db);
        return NO;
    }

    const char *insertSQL =
        "INSERT OR IGNORE INTO downloads "
        "(id, videoID, title, channel, channelURL, qualityLabel, typeAndQuality, "
        "size, duration, type, path, lyrics, timestamp) "
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
    sqlite3_stmt *stmt = NULL;
    if (sqlite3_prepare_v2(db, insertSQL, -1, &stmt, NULL) != SQLITE_OK) {
        UYTDebugErr(@"[UYTPipeline] uyoudb.sqlite prepare failed: %s", sqlite3_errmsg(db));
        sqlite3_close(db);
        return NO;
    }

    NSDateFormatter *fmt = [NSDateFormatter new];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm";
    NSString *timestamp = [fmt stringFromDate:[NSDate date]];

    NSArray<NSString *> *values = @[
        rowID.length ? rowID : videoID,
        videoID,
        title ?: @"",
        channel ?: @"",
        channelURL ?: @"",
        qualityLabel ?: @"",
        typeAndQuality ?: @"",
        [NSString stringWithFormat:@"%llu", size],
        [NSString stringWithFormat:@"%.0f", duration],
        type ?: @"0",
        path,
        @"",
        timestamp,
    ];
    for (NSUInteger i = 0; i < values.count; i++) {
        sqlite3_bind_text(stmt, (int)(i + 1), [values[i] UTF8String], -1, SQLITE_TRANSIENT);
    }

    BOOL ok = (sqlite3_step(stmt) == SQLITE_DONE);
    if (!ok) UYTDebugErr(@"[UYTPipeline] uyoudb.sqlite insert failed for %@ at %@: %s", videoID, dbPath, sqlite3_errmsg(db));
    else UYTDebugInfo(@"[UYTPipeline] uyoudb.sqlite insert OK for %@ at %@ -> %@", videoID, dbPath, path);

    sqlite3_finalize(stmt);
    sqlite3_close(db);
    return ok;
}

BOOL UYTDownloadsDBInsertCompleted(NSString *rowID,
                                   NSString *videoID,
                                   NSString *title,
                                   NSString *channel,
                                   NSString *channelURL,
                                   NSString *qualityLabel,
                                   NSString *typeAndQuality,
                                   unsigned long long size,
                                   NSTimeInterval duration,
                                   NSString *type,
                                   NSString *path) {
    if (!videoID.length) return NO;
    return UYTDownloadsDBInsertAtPath(UYTDownloadsDBPath(), rowID, videoID, title, channel, channelURL,
                                      qualityLabel, typeAndQuality, size, duration, type, path);
}

