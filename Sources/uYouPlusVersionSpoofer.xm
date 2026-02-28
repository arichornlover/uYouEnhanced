#import "uYouPlus.h"

typedef struct {
    int version;
    NSString *appVersion;
} VersionMapping;

static VersionMapping versionMappings[] = {
    {0, @"21.08.3"},
    {1, @"21.07.4"},
    {2, @"21.06.2"},
    {3, @"21.05.3"},
    {4, @"21.04.2"},
    {5, @"21.03.2"},
    {6, @"21.02.3"},
    {7, @"20.50.10"},
    {8, @"20.50.9"},
    {9, @"20.50.6"},
    {10, @"20.49.5"},
    {11, @"20.47.3"},
    {12, @"20.46.3"},
    {13, @"20.46.2"},
    {14, @"20.45.3"},
    {15, @"20.44.2"},
    {16, @"20.43.3"},
    {17, @"20.42.3"},
    {18, @"20.41.5"},
    {19, @"20.41.4"},
    {20, @"20.40.4"},
    {21, @"20.39.6"},
    {22, @"20.39.5"},
    {23, @"20.39.4"},
    {24, @"20.38.4"},
    {25, @"20.38.3"},
    {26, @"20.37.5"},
    {27, @"20.37.3"},
    {28, @"20.36.3"},
    {29, @"20.35.2"},
    {30, @"20.34.2"},
    {31, @"20.33.2"},
    {32, @"20.32.5"},
    {33, @"20.32.4"},
    {34, @"20.31.6"},
    {35, @"20.31.5"},
    {36, @"20.30.5"},
    {37, @"20.29.3"},
    {38, @"20.28.2"},
    {39, @"20.26.7"},
    {40, @"20.25.4"},
    {41, @"20.24.5"},
    {42, @"20.24.4"},
    {43, @"20.23.3 (Deprecated)"},
    {44, @"20.22.1 (Deprecated)"},
    {45, @"20.21.6 (Deprecated)"},
    {46, @"20.20.7 (Deprecated)"},
    {47, @"20.20.5 (Deprecated)"},
    {48, @"20.19.3 (Deprecated)"},
    {49, @"20.19.2 (Deprecated)"},
    {50, @"20.18.5 (Deprecated)"},
    {51, @"20.18.4 (Deprecated)"},
    {52, @"20.16.7 (Deprecated)"},
    {53, @"20.15.1 (Deprecated)"},
    {54, @"20.14.2 (Deprecated)"},
    {55, @"20.13.5 (Deprecated)"},
    {56, @"20.12.4 (Deprecated)"},
    {57, @"20.11.6 (Deprecated)"},
    {58, @"20.10.4 (Deprecated)"},
    {59, @"20.10.3 (Deprecated)"},
    {60, @"20.09.3 (Deprecated)"},
    {61, @"20.08.3 (Deprecated)"},
    {62, @"20.07.6 (Deprecated)"},
    {63, @"20.06.03 (Deprecated)"},
    {64, @"20.05.4 (Deprecated)"},
    {65, @"20.03.1 (Deprecated)"},
    {66, @"20.03.02 (Deprecated)"},
    {67, @"20.02.3 (Deprecated)"}
};

static int appVersionSpoofer() {
    return [[NSUserDefaults standardUserDefaults] integerForKey:@"versionSpoofer"];
}

static BOOL isVersionSpooferEnabled() {
    return IS_ENABLED(@"enableVersionSpoofer_enabled");
}

static NSString* getAppVersionForSpoofedVersion(int spoofedVersion) {
    for (int i = 0; i < sizeof(versionMappings) / sizeof(versionMappings[0]); i++) {
        if (versionMappings[i].version == spoofedVersion) {
            return versionMappings[i].appVersion;
        }
    }
    return nil;
}

%hook YTVersionUtils
+ (NSString *)appVersion {
    if (!isVersionSpooferEnabled()) {
        return %orig;
    }
    int spoofedVersion = appVersionSpoofer();
    NSString *appVersion = getAppVersionForSpoofedVersion(spoofedVersion);
    return appVersion ? appVersion : %orig;
}
%end
