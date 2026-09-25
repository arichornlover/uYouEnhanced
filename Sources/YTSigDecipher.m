#import "YTSigDecipher.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <HBLog.h>

#pragma mark - Balanced-bracket extraction

// Given `source` and the index of an opening bracket (openChar), returns the
// range from that index through its matching closeChar, tracking nesting depth
// and skipping over bracket characters that appear inside "..."/'...' string
// literals (player.js source can and does contain "}" inside strings).
static NSRange UYTBalancedRange(NSString *source, NSUInteger openIndex, unichar openChar, unichar closeChar) {
    NSUInteger len = source.length;
    if (openIndex >= len) return NSMakeRange(NSNotFound, 0);
    NSInteger depth = 0;
    unichar inString = 0; // 0, '"', or '\''
    BOOL escaped = NO;
    for (NSUInteger i = openIndex; i < len; i++) {
        unichar c = [source characterAtIndex:i];
        if (inString) {
            if (escaped) { escaped = NO; }
            else if (c == '\\') { escaped = YES; }
            else if (c == inString) { inString = 0; }
            continue;
        }
        if (c == '"' || c == '\'') { inString = c; continue; }
        if (c == openChar) depth++;
        else if (c == closeChar) {
            depth--;
            if (depth == 0) return NSMakeRange(openIndex, i - openIndex + 1);
        }
    }
    return NSMakeRange(NSNotFound, 0);
}

// Finds `identifier={` or `identifier=[` (optionally preceded by "var "/"const "/"let ")
// anywhere in `source` and returns the full "identifier=<balanced literal>" text,
// e.g. "Yz={qB:function(a,b){...},Fp:function(a){...}}". Tries object form first,
// then array form. Returns nil if not found.
static NSString *UYTExtractContainerLiteral(NSString *source, NSString *identifier) {
    NSString *escaped = [NSRegularExpression escapedPatternForString:identifier];
    for (NSString *bracket in @[@"{", @"["]) {
        NSString *closeBracket = [bracket isEqualToString:@"{"] ? @"}" : @"]";
        NSString *pattern = [NSString stringWithFormat:@"(?:var|const|let)?\\s*\\b%@\\s*=\\s*%@",
                              escaped, [NSRegularExpression escapedPatternForString:bracket]];
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:source options:0 range:NSMakeRange(0, source.length)];
        if (!m) continue;
        NSUInteger openIdx = NSMaxRange(m.range) - 1; // position of the bracket itself
        NSRange body = UYTBalancedRange(source, openIdx, [bracket characterAtIndex:0], [closeBracket characterAtIndex:0]);
        if (body.location == NSNotFound) continue;
        return [NSString stringWithFormat:@"var %@=%@;", identifier, [source substringWithRange:NSMakeRange(openIdx, body.length)]];
    }
    return nil;
}

// Scans `functionBody` for calls of the form `IDENT.method(` and returns the
// distinct short (<=4 char) identifiers found - these are the helper
// objects/arrays the transform function delegates array-shuffling to.
static NSArray<NSString *> *UYTFindHelperIdentifiers(NSString *functionBody) {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\b([a-zA-Z_$][a-zA-Z0-9_$]{0,4})\\.[a-zA-Z0-9_$]+\\("
                                                                          options:0 error:nil];
    NSMutableOrderedSet<NSString *> *found = [NSMutableOrderedSet orderedSet];
    [re enumerateMatchesInString:functionBody options:0 range:NSMakeRange(0, functionBody.length)
                       usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags flags, BOOL *stop) {
        [found addObject:[functionBody substringWithRange:[m rangeAtIndex:1]]];
    }];
    return found.array;
}

#pragma mark - Locating the signature transform function

// Returns @[functionName, standaloneJSSourceDefiningIt] or nil.
static NSArray<NSString *> *UYTLocateSigFunction(NSString *js) {
    NSArray<NSString *> *patterns = @[
        // NAME=function(a){a=a.split("");...;return a.join("")}
        @"([a-zA-Z_$][a-zA-Z0-9_$]{0,3})\\s*=\\s*function\\(\\s*a\\s*\\)\\s*\\{\\s*a\\s*=\\s*a\\.split\\(\\s*\"\"\\s*\\)",
        // function NAME(a){a=a.split("");...;return a.join("")}
        @"function\\s+([a-zA-Z_$][a-zA-Z0-9_$]{0,3})\\s*\\(\\s*a\\s*\\)\\s*\\{\\s*a\\s*=\\s*a\\.split\\(\\s*\"\"\\s*\\)",
        // NAME=function(a){a=a.split(String.fromCharCode(...));...}  (rarer variant)
        @"([a-zA-Z_$][a-zA-Z0-9_$]{0,3})\\s*=\\s*function\\(\\s*a\\s*\\)\\s*\\{\\s*a\\s*=\\s*a\\.split\\(\\s*[a-zA-Z0-9_$.\\(\\)\"]+\\)\\s*;\\s*[a-zA-Z0-9_$.\\[\\]]+\\(a,",
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:js options:0 range:NSMakeRange(0, js.length)];
        if (!m) continue;
        NSString *name = [js substringWithRange:[m rangeAtIndex:1]];
        // Find the opening "{" of the function body (end of this match, minus the
        // already-consumed "a=a.split(...)" prefix - just balance-scan from the
        // first "{" at/after the match start).
        NSRange searchRange = NSMakeRange(m.range.location, js.length - m.range.location);
        NSRange braceSearch = [js rangeOfString:@"{" options:0 range:searchRange];
        if (braceSearch.location == NSNotFound) continue;
        NSRange bodyRange = UYTBalancedRange(js, braceSearch.location, '{', '}');
        if (bodyRange.location == NSNotFound) continue;
        NSString *bodyOnly = [js substringWithRange:bodyRange];

        NSMutableString *standalone = [NSMutableString string];
        for (NSString *helper in UYTFindHelperIdentifiers(bodyOnly)) {
            NSString *literal = UYTExtractContainerLiteral(js, helper);
            if (literal) [standalone appendString:literal];
        }
        // Normalize to a plain named function declaration regardless of which
        // pattern matched (assignment form vs. declaration form).
        [standalone appendFormat:@"function %@(a)%@", name, bodyOnly];
        return @[name, standalone];
    }
    return nil;
}

// Best-effort: locate the "n" throttling parameter transform. Structure has
// shifted across YouTube player releases more than the sig function has, so
// this is tried but never required - decipherN: returning nil just means we
// skip the n-fix (may cost download speed, shouldn't cost correctness).
static NSArray<NSString *> *UYTLocateNFunction(NSString *js) {
    NSArray<NSString *> *patterns = @[
        // ...&&(b=a.get("n"))&&(b=NAME[0](b)) or (b=NAME(b))
        @"&&\\(b=a\\.get\\(\"n\"\\)\\)&&\\(b=([a-zA-Z_$][a-zA-Z0-9_$]{0,6})(?:\\[(\\d+)\\])?\\(b\\)",
        // c=NAME(decodeURIComponent(c)) style seen in some releases
        @"[;,]\\s*([a-zA-Z_$][a-zA-Z0-9_$]{0,6})=function\\(\\s*a\\s*\\)\\s*\\{\\s*var\\s+b\\s*=\\s*a\\.split\\(\\s*\"\"\\s*\\)",
    ];
    for (NSString *pattern in patterns) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
        NSTextCheckingResult *m = [re firstMatchInString:js options:0 range:NSMakeRange(0, js.length)];
        if (!m) continue;
        NSString *name = [js substringWithRange:[m rangeAtIndex:1]];
        BOOL isArray = (m.numberOfRanges > 2 && [m rangeAtIndex:2].location != NSNotFound);
        NSString *fnSource;
        if (isArray) {
            NSString *literal = UYTExtractContainerLiteral(js, name);
            if (!literal) continue;
            NSString *idx = [js substringWithRange:[m rangeAtIndex:2]];
            fnSource = [NSString stringWithFormat:@"%@function __n(a){return (%@)[%@](a);}", literal, name, idx];
        } else {
            // Find `NAME=function(a){...}` and balance-extract its body.
            NSString *declPattern = [NSString stringWithFormat:@"\\b%@\\s*=\\s*function\\(\\s*a\\s*\\)\\s*\\{",
                                      [NSRegularExpression escapedPatternForString:name]];
            NSRegularExpression *declRe = [NSRegularExpression regularExpressionWithPattern:declPattern options:0 error:nil];
            NSTextCheckingResult *declM = [declRe firstMatchInString:js options:0 range:NSMakeRange(0, js.length)];
            if (!declM) continue;
            NSRange braceSearch = [js rangeOfString:@"{" options:0 range:NSMakeRange(declM.range.location, js.length - declM.range.location)];
            if (braceSearch.location == NSNotFound) continue;
            NSRange bodyRange = UYTBalancedRange(js, braceSearch.location, '{', '}');
            if (bodyRange.location == NSNotFound) continue;
            NSString *bodyOnly = [js substringWithRange:bodyRange];
            NSMutableString *standalone = [NSMutableString string];
            for (NSString *helper in UYTFindHelperIdentifiers(bodyOnly)) {
                NSString *literal = UYTExtractContainerLiteral(js, helper);
                if (literal) [standalone appendString:literal];
            }
            [standalone appendFormat:@"function __n(a)%@", bodyOnly];
            fnSource = standalone;
        }
        return @[name, fnSource];
    }
    return nil;
}

#pragma mark - UYTPlayerJSContext

@interface UYTPlayerJSContext ()
@property (nonatomic, strong) JSContext *sigContext;
@property (nonatomic, strong, nullable) JSContext *nContext;
@property (nonatomic, copy) NSString *sigFunctionName;
@end

@implementation UYTPlayerJSContext

- (nullable NSString *)decipherSignature:(NSString *)s {
    if (!self.sigContext || !s.length) return nil;
    @try {
        JSValue *fn = self.sigContext[self.sigFunctionName];
        if (!fn || fn.isUndefined) return nil;
        JSValue *result = [fn callWithArguments:@[s]];
        NSString *out = result.toString;
        return out.length ? out : nil;
    } @catch (NSException *e) {
        HBLogWarn(@"[YTSigDecipher] decipherSignature threw: %@", e);
        return nil;
    }
}

- (nullable NSString *)decipherN:(NSString *)n {
    if (!self.nContext || !n.length) return nil;
    @try {
        JSValue *fn = self.nContext[@"__n"];
        if (!fn || fn.isUndefined) return nil;
        JSValue *result = [fn callWithArguments:@[n]];
        NSString *out = result.toString;
        return out.length ? out : nil;
    } @catch (NSException *e) {
        HBLogWarn(@"[YTSigDecipher] decipherN threw: %@", e);
        return nil;
    }
}

@end

#pragma mark - UYTSigDecipher

@implementation UYTSigDecipher

+ (NSString *)cacheDirectory {
    NSString *caches = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [caches stringByAppendingPathComponent:@"UYTPlayerJS"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

+ (nullable NSString *)playerJSVersionFromPath:(NSString *)path {
    // .../s/player/<hash>/player_ios.js or .../s/player/<hash>/base.js
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"/s/player/([a-zA-Z0-9_-]+)/" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    if (!m) return nil;
    return [path substringWithRange:[m rangeAtIndex:1]];
}

+ (void)playerContextForVideoID:(NSString *)videoID
                      completion:(void (^)(UYTPlayerJSContext * _Nullable, NSError * _Nullable))completion {
    NSURL *watchURL = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@&bpctr=9999999999&has_verified=1", videoID]];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:watchURL];
    [req setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15" forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:req
        completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        if (err || !data) {
            HBLogWarn(@"[YTSigDecipher] watch page fetch failed: %@", err);
            completion(nil, err);
            return;
        }
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSRegularExpression *jsUrlRe = [NSRegularExpression regularExpressionWithPattern:@"\"jsUrl\"\\s*:\\s*\"([^\"]+)\"" options:0 error:nil];
        NSTextCheckingResult *m = [jsUrlRe firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
        if (!m) {
            HBLogWarn(@"[YTSigDecipher] jsUrl not found in watch page for %@", videoID);
            completion(nil, [NSError errorWithDomain:@"UYTSigDecipher" code:1 userInfo:@{NSLocalizedDescriptionKey: @"jsUrl not found"}]);
            return;
        }
        NSString *jsPath = [html substringWithRange:[m rangeAtIndex:1]];
        jsPath = [jsPath stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
        NSString *version = [self playerJSVersionFromPath:jsPath];
        NSString *cachePath = version ? [[self cacheDirectory] stringByAppendingPathComponent:[version stringByAppendingPathExtension:@"json"]] : nil;

        if (cachePath && [[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
            NSDictionary *cached = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:cachePath] options:0 error:nil];
            UYTPlayerJSContext *player = [self playerFromCachedDictionary:cached];
            if (player) {
                HBLogInfo(@"[YTSigDecipher] using cached player.js functions (version %@)", version);
                completion(player, nil);
                return;
            }
        }

        NSString *jsAbsolute = [jsPath hasPrefix:@"http"] ? jsPath : [@"https://www.youtube.com" stringByAppendingString:jsPath];
        NSURL *jsURL = [NSURL URLWithString:jsAbsolute];
        NSURLSessionDataTask *jsTask = [[NSURLSession sharedSession] dataTaskWithURL:jsURL
            completionHandler:^(NSData *jsData, NSURLResponse *jsResp, NSError *jsErr) {
            if (jsErr || !jsData) {
                HBLogWarn(@"[YTSigDecipher] player.js fetch failed: %@", jsErr);
                completion(nil, jsErr);
                return;
            }
            NSString *js = [[NSString alloc] initWithData:jsData encoding:NSUTF8StringEncoding];
            NSArray<NSString *> *sig = UYTLocateSigFunction(js);
            if (!sig) {
                HBLogWarn(@"[YTSigDecipher] could not locate signature function in player.js (version %@)", version);
                completion(nil, [NSError errorWithDomain:@"UYTSigDecipher" code:2 userInfo:@{NSLocalizedDescriptionKey: @"sig function not found"}]);
                return;
            }
            NSArray<NSString *> *nFn = UYTLocateNFunction(js);
            HBLogInfo(@"[YTSigDecipher] resolved player.js %@: sigFn=%@ nFn=%@", version, sig[0], nFn ? nFn[0] : @"(none)");

            UYTPlayerJSContext *player = [self playerFromSigSource:sig[1] sigFunctionName:sig[0] nSource:nFn ? nFn[1] : nil];
            if (cachePath) {
                NSDictionary *toCache = @{@"sigFunctionName": sig[0], @"sigSource": sig[1], @"nSource": nFn ? nFn[1] : @""};
                NSData *out = [NSJSONSerialization dataWithJSONObject:toCache options:0 error:nil];
                [out writeToFile:cachePath atomically:YES];
            }
            completion(player, nil);
        }];
        [jsTask resume];
    }];
    [task resume];
}

+ (nullable UYTPlayerJSContext *)playerFromCachedDictionary:(NSDictionary *)cached {
    NSString *sigSource = cached[@"sigSource"];
    NSString *sigFunctionName = cached[@"sigFunctionName"];
    if (!sigSource.length || !sigFunctionName.length) return nil;
    NSString *nSource = cached[@"nSource"];
    return [self playerFromSigSource:sigSource sigFunctionName:sigFunctionName nSource:nSource.length ? nSource : nil];
}

+ (UYTPlayerJSContext *)playerFromSigSource:(NSString *)sigSource sigFunctionName:(NSString *)sigFunctionName nSource:(nullable NSString *)nSource {
    UYTPlayerJSContext *player = [UYTPlayerJSContext new];
    player.sigFunctionName = sigFunctionName;

    JSContext *sigCtx = [JSContext new];
    sigCtx.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
        HBLogWarn(@"[YTSigDecipher] sig JSContext exception: %@", exception);
    };
    [sigCtx evaluateScript:sigSource];
    player.sigContext = sigCtx;

    if (nSource.length) {
        JSContext *nCtx = [JSContext new];
        nCtx.exceptionHandler = ^(JSContext *ctx, JSValue *exception) {
            HBLogWarn(@"[YTSigDecipher] n JSContext exception: %@", exception);
        };
        [nCtx evaluateScript:nSource];
        if (![nCtx[@"__n"] isUndefined]) {
            player.nContext = nCtx;
        }
    }
    return player;
}

+ (nullable NSString *)resolveURLFromSignatureCipher:(NSString *)signatureCipher usingPlayer:(UYTPlayerJSContext *)player {
    NSMutableDictionary<NSString *, NSString *> *parts = [NSMutableDictionary dictionary];
    for (NSString *pair in [signatureCipher componentsSeparatedByString:@"&"]) {
        NSRange eq = [pair rangeOfString:@"="];
        if (eq.location == NSNotFound) continue;
        NSString *key = [pair substringToIndex:eq.location];
        NSString *value = [pair substringFromIndex:eq.location + 1];
        parts[key] = [value stringByRemovingPercentEncoding] ?: value;
    }
    NSString *s = parts[@"s"];
    NSString *sp = parts[@"sp"].length ? parts[@"sp"] : @"signature";
    NSString *baseURL = parts[@"url"];
    if (!s.length || !baseURL.length) {
        HBLogWarn(@"[YTSigDecipher] signatureCipher missing s/url: %@", signatureCipher);
        return nil;
    }

    NSString *decipheredSig = [player decipherSignature:s];
    if (!decipheredSig.length) {
        HBLogWarn(@"[YTSigDecipher] failed to decipher signature");
        return nil;
    }

    // Best-effort "n" parameter fix - if it fails or isn't present, we still
    // return a valid (if possibly throttled) URL rather than failing outright.
    NSURLComponents *comps = [NSURLComponents componentsWithString:baseURL];
    NSMutableArray<NSURLQueryItem *> *items = [comps.queryItems mutableCopy] ?: [NSMutableArray array];
    for (NSUInteger i = 0; i < items.count; i++) {
        if ([items[i].name isEqualToString:@"n"]) {
            NSString *newN = [player decipherN:items[i].value];
            if (newN.length) {
                items[i] = [NSURLQueryItem queryItemWithName:@"n" value:newN];
            }
            break;
        }
    }
    // NSURLComponents percent-encodes queryItems values itself when building
    // .URL below - pass the raw deciphered signature, not a pre-encoded one,
    // or it gets double-encoded (a literal "%" in the signature would become
    // "%25", corrupting it).
    [items addObject:[NSURLQueryItem queryItemWithName:sp value:decipheredSig]];
    comps.queryItems = items;
    NSString *finalURL = comps.URL.absoluteString;
    if (!finalURL.length) {
        HBLogWarn(@"[YTSigDecipher] failed to rebuild final URL from components");
        return nil;
    }
    return finalURL;
}

+ (void)resolveCipheredURLForVideoID:(NSString *)videoID
                     signatureCipher:(NSString *)signatureCipher
                          completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    [self playerContextForVideoID:videoID completion:^(UYTPlayerJSContext *player, NSError *err) {
        if (!player) {
            completion(nil, err);
            return;
        }
        completion([self resolveURLFromSignatureCipher:signatureCipher usingPlayer:player], nil);
    }];
}

@end
