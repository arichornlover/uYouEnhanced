// Extractor.h was made by @LillieH1000 from https://github.com/LillieH1000/YouTube-Reborn/commit/bb858715235b1c2ce8793631bc34b51dfed491ef

#import <Foundation/Foundation.h>

@interface YouTubeExtractor : NSObject
+ (NSDictionary *)youtubePlayerRequest :(NSString *)clientId :(NSString *)videoId;
@end
