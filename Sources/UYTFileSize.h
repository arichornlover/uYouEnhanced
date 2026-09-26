
#import <Foundation/Foundation.h>

// NSDictionary has no -fileSize; the byte count lives under NSFileSize. Sends of
// -fileSize to the dictionary returned by -attributesOfItemAtPath: raise
// "unrecognized selector", which silently broke download finalization.
static inline unsigned long long UYTSizeOfAttrs(NSDictionary * _Nullable attrs) {
    if (![attrs isKindOfClass:[NSDictionary class]]) return 0;
    id value = attrs[NSFileSize];
    if (![value respondsToSelector:@selector(unsignedLongLongValue)]) return 0;
    return [value unsignedLongLongValue];
}

static inline unsigned long long UYTSizeOfFile(NSString * _Nullable path) {
    if (!path.length) return 0;
    return UYTSizeOfAttrs([[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil]);
}
