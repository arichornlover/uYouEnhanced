// Extractor.xm was made by @LillieH1000 from https://github.com/LillieH1000/YouTube-Reborn/commit/bb858715235b1c2ce8793631bc34b51dfed491ef

#import "Extractor.h"

@implementation YouTubeExtractor

+ (NSDictionary *)youtubePlayerRequest :(NSString *)clientId :(NSString *)videoId {
    NSLocale *locale = [NSLocale currentLocale];
	NSString *countryCode = [locale objectForKey:NSLocaleCountryCode];
    
    NSString *innertubeKey;
    NSString *jsonBody;
    if ([clientId isEqual:@"mediaconnect"]) {
        innertubeKey = @"AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w";
        jsonBody = [NSString stringWithFormat:@"{\"context\":{\"client\":{\"hl\":\"en\",\"gl\":\"%@\",\"clientName\":\"MEDIA_CONNECT_FRONTEND\",\"clientVersion\":\"0.1\"}},\"contentCheckOk\":true,\"racyCheckOk\":true,\"videoId\":\"%@\"}", countryCode, videoId];
    }
    if ([clientId isEqual:@"ios"]) {
        innertubeKey = @"AAIzaSyB-63vPrdThhKuerbB2N_l7Kwwcxj6yUAc";
        jsonBody = [NSString stringWithFormat:@"{\"context\":{\"client\":{\"hl\":\"en\",\"gl\":\"%@\",\"clientName\":\"IOS\",\"clientVersion\":\"19.09.3\",\"deviceModel\":\"iPhone14,3\"}},\"contentCheckOk\":true,\"racyCheckOk\":true,\"videoId\":\"%@\"}", countryCode, videoId];
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://www.youtube.com/youtubei/v1/player?key=%@&prettyPrint=false", innertubeKey]]];
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:[jsonBody dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES]];
    
    __block NSData *requestData;
    __block BOOL requestFinished = NO;
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        requestData = data;
        requestFinished = YES;
    }] resume];

    while (!requestFinished) {
        [NSThread sleepForTimeInterval:0.02];
    }

    return [NSJSONSerialization JSONObjectWithData:requestData options:0 error:nil];
}

@end
