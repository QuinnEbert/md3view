#import "PK3Archive.h"
#import "minizip/unzip.h"

@implementation PK3Archive {
    NSString *_archivePath;
    NSMutableArray<NSString *> *_fileList;
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (!self) return nil;

    _archivePath = [path copy];
    _fileList = [NSMutableArray new];

    unzFile uf = unzOpen([path fileSystemRepresentation]);
    if (!uf) return nil;

    int err = unzGoToFirstFile(uf);
    while (err == UNZ_OK) {
        char filename[512];
        unz_file_info fileInfo;
        unzGetCurrentFileInfo(uf, &fileInfo, filename, sizeof(filename), NULL, 0, NULL, 0);
        [_fileList addObject:[NSString stringWithUTF8String:filename]];
        err = unzGoToNextFile(uf);
    }
    unzClose(uf);

    return self;
}

- (NSArray<NSString *> *)allFiles {
    return [_fileList copy];
}

- (NSArray<NSString *> *)playerModelPaths {
    // Player models live under models/players/<name>/
    // Identified by having lower.md3, upper.md3, head.md3
    NSMutableSet<NSString *> *playerDirs = [NSMutableSet new];

    for (NSString *file in _fileList) {
        NSString *lower = [file lowercaseString];
        if ([lower hasSuffix:@"lower.md3"] || [lower hasSuffix:@"upper.md3"] || [lower hasSuffix:@"head.md3"]) {
            NSString *dir = [file stringByDeletingLastPathComponent];
            [playerDirs addObject:dir];
        }
    }

    // Filter to directories that have all three parts
    NSMutableArray<NSString *> *valid = [NSMutableArray new];
    for (NSString *dir in playerDirs) {
        NSString *lowerPath = [dir stringByAppendingPathComponent:@"lower.md3"];
        NSString *upperPath = [dir stringByAppendingPathComponent:@"upper.md3"];
        NSString *headPath = [dir stringByAppendingPathComponent:@"head.md3"];

        BOOL hasLower = NO, hasUpper = NO, hasHead = NO;
        for (NSString *file in _fileList) {
            if ([[file lowercaseString] isEqualToString:[lowerPath lowercaseString]]) hasLower = YES;
            if ([[file lowercaseString] isEqualToString:[upperPath lowercaseString]]) hasUpper = YES;
            if ([[file lowercaseString] isEqualToString:[headPath lowercaseString]]) hasHead = YES;
        }
        if (hasLower && hasUpper && hasHead) {
            [valid addObject:dir];
        }
    }

    return [valid sortedArrayUsingSelector:@selector(compare:)];
}

- (NSData *)readFile:(NSString *)filePath {
    unzFile uf = unzOpen([_archivePath fileSystemRepresentation]);
    if (!uf) return nil;

    // Try exact match first
    if (unzLocateFile(uf, [filePath UTF8String], 2) != UNZ_OK) {
        unzClose(uf);
        return nil;
    }

    unz_file_info fileInfo;
    unzGetCurrentFileInfo(uf, &fileInfo, NULL, 0, NULL, 0, NULL, 0);

    if (unzOpenCurrentFile(uf) != UNZ_OK) {
        unzClose(uf);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:fileInfo.uncompressed_size];
    int bytesRead = unzReadCurrentFile(uf, [data mutableBytes], (unsigned int)fileInfo.uncompressed_size);
    unzCloseCurrentFile(uf);
    unzClose(uf);

    if (bytesRead < 0) return nil;
    [data setLength:bytesRead];
    return data;
}

@end
