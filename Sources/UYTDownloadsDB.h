#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Inserts a completed-download row into uYou's own uyoudb.sqlite so a file
// we placed on disk ourselves (the SABR fallback in UYTSABR.xm) actually
// shows up in uYou's native "Downloaded" tab, instead of existing on disk
// with nothing in the app aware of it.
//
// Schema and exact INSERT statement are not guessed - both were extracted
// via `strings` directly from the real (closed-source) uYou.dylib binary
// inside our own built IPA:
//   CREATE TABLE IF NOT EXISTS downloads (id TEXT PRIMARY KEY, videoID TEXT,
//     title TEXT, channel TEXT, channelURL TEXT, qualityLabel TEXT,
//     typeAndQuality TEXT, size TEXT, duration TEXT, type TEXT, path TEXT,
//     lyrics TEXT, timestamp DATETIME)
//   INSERT OR IGNORE INTO downloads (id, videoID, title, channel,
//     channelURL, qualityLabel, typeAndQuality, size, duration, type, path,
//     lyrics, timestamp) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
// DB path (also confirmed via strings): Documents/uyoudb.sqlite.
//
// Known caveat, also confirmed via strings (an NSMutableArray ivar named
// _allDownloaded, populated by a `loadDownloaded` method): uYou's
// "Downloaded" tab caches its list in memory, loaded once at launch/tab
// access, not re-queried live. A row inserted here will not appear until
// the app is fully relaunched - that's expected, not a bug in this insert.
//
// UYTDownloadsDB.m compiles as plain Objective-C (unmangled C symbol name),
// while .xm callers (DownloadPipeline.xm) compile as Objective-C++ (mangled
// symbols) - extern "C" makes both sides agree on the symbol name. Without
// this, linking fails with "Undefined symbols ... declaration possibly
// missing 'extern \"C\"'" - which is exactly what happened before this was
// added.
#ifdef __cplusplus
extern "C" {
#endif

BOOL UYTDownloadsDBInsertCompleted(NSString *rowID,
                                   NSString *videoID,
                                   NSString * _Nullable title,
                                   NSString * _Nullable channel,
                                   NSString * _Nullable channelURL,
                                   NSString * _Nullable qualityLabel,
                                   NSString * _Nullable typeAndQuality,
                                   unsigned long long size,
                                   NSTimeInterval duration,
                                   NSString *type, // integer as string - uYou queries `type` LIKE '%lu'
                                   NSString *path);

#ifdef __cplusplus
} // extern "C"
#endif

NS_ASSUME_NONNULL_END
