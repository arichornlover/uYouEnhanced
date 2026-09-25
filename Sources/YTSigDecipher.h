#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface UYTPlayerJSContext : NSObject
- (nullable NSString *)decipherSignature:(NSString *)s;
- (nullable NSString *)decipherN:(NSString *)n;
@end

@interface UYTSigDecipher : NSObject

+ (void)playerContextForVideoID:(NSString *)videoID
                      completion:(void (^)(UYTPlayerJSContext * _Nullable player, NSError * _Nullable error))completion;

+ (nullable NSString *)resolveURLFromSignatureCipher:(NSString *)signatureCipher
                                          usingPlayer:(UYTPlayerJSContext *)player;

+ (void)resolveCipheredURLForVideoID:(NSString *)videoID
                     signatureCipher:(NSString *)signatureCipher
                          completion:(void (^)(NSString * _Nullable resolvedURL, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

