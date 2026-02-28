#import "SkinParser.h"

@implementation SkinParser

+ (NSDictionary<NSString *, NSString *> *)parseSkinData:(NSData *)data {
    NSMutableDictionary *result = [NSMutableDictionary new];
    if (!data) return result;

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        // Try Latin1
        text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (!text) return result;

    NSArray *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    for (NSString *line in lines) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (trimmed.length == 0) continue;

        // Format: surfaceName,texturePath
        NSRange commaRange = [trimmed rangeOfString:@","];
        if (commaRange.location == NSNotFound) continue;

        NSString *surfName = [[trimmed substringToIndex:commaRange.location]
                              stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *texPath = [[trimmed substringFromIndex:commaRange.location + 1]
                             stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // Skip tag_ entries
        if ([surfName.lowercaseString hasPrefix:@"tag_"]) continue;
        if (surfName.length == 0 || texPath.length == 0) continue;

        result[surfName.lowercaseString] = texPath;
    }

    return result;
}

@end
