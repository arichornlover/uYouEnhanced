#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Resolves a YouTube "signatureCipher" (a URL-encoded blob shaped like
// "s=<encrypted>&sp=<param name>&url=<base url missing the signature>") into a
// final, directly-playable URL.
//
// Why this exists: YouTube stopped returning plain `url` fields for most/all
// formats for the iOS innertube client context DownloadPipeline.xm uses.
// Instead it returns `signatureCipher`, whose `s` value must be run through a
// per-player-version obfuscated JS transform embedded in that day's player.js
// before it's usable. We don't hand-port that transform to Objective-C (it is
// re-obfuscated by YouTube on every player rollout, so a hand port breaks
// silently and constantly). Instead we fetch the real player.js, locate the
// transform function(s) by structural pattern (not by name - names change),
// and execute the *actual* YouTube code in a JSContext.
@interface UYTPlayerJSContext : NSObject
// nil if the corresponding function couldn't be located in this player.js.
- (nullable NSString *)decipherSignature:(NSString *)s;
- (nullable NSString *)decipherN:(NSString *)n; // throttling param; best-effort.
@end

@interface UYTSigDecipher : NSObject

// Resolves (fetching + caching player.js as needed) a decipher context usable
// for any number of signatureCipher values belonging to the same video (they
// all share the same player.js version). Completion runs on an arbitrary
// background queue.
+ (void)playerContextForVideoID:(NSString *)videoID
                      completion:(void (^)(UYTPlayerJSContext * _Nullable player, NSError * _Nullable error))completion;

// Synchronous - pure string/JS work, no I/O. Returns nil if the cipher blob
// can't be parsed or the signature function is missing from `player`.
+ (nullable NSString *)resolveURLFromSignatureCipher:(NSString *)signatureCipher
                                          usingPlayer:(UYTPlayerJSContext *)player;

// Convenience one-shot wrapper combining both of the above for a single
// signatureCipher value. Prefer the two-step API above when resolving many
// formats for the same video (one player.js fetch instead of one per format).
+ (void)resolveCipheredURLForVideoID:(NSString *)videoID
                     signatureCipher:(NSString *)signatureCipher
                          completion:(void (^)(NSString * _Nullable resolvedURL, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
