#import "uYouPlus.h"

typedef struct {
    int version;
    NSString *appVersion;
} VersionMapping;

static VersionMapping versionMappings[] = {
    {0, @"21.26.4"},
    {1, @"21.25.5"},
    {2, @"21.24.3"},
    {3, @"21.22.4"},
    {4, @"21.21.3"},
    {5, @"21.20.4"},
    {6, @"21.19.2"},
    {7, @"21.18.4"},
    {8, @"21.17.3"},
    {9, @"21.16.2"},
    {10, @"21.15.5"},
    {11, @"21.15.4"},
    {12, @"21.14.4"},
    {13, @"21.13.6"},
    {14, @"21.12.4"},
    {15, @"21.11.4"},
    {16, @"21.10.2"},
    {17, @"21.09.3"},
    {18, @"21.09.2"},
    {19, @"21.08.3"},
    {20, @"21.07.4"},
    {21, @"21.06.2"},
    {22, @"21.05.3"},
    {23, @"21.04.2"},
    {24, @"21.03.2"},
    {25, @"21.02.3"},
    {26, @"20.50.10"},
    {27, @"20.50.9"},
    {28, @"20.50.6"},
    {29, @"20.49.5"},
    {30, @"20.47.3"},
    {31, @"20.46.3"},
    {32, @"20.46.2"},
    {33, @"20.45.3"},
    {34, @"20.44.2"},
    {35, @"20.43.3"},
    {36, @"20.42.3"},
    {37, @"20.41.5"},
    {38, @"20.41.4"},
    {39, @"20.40.4"},
    {40, @"20.39.6"},
    {41, @"20.39.5"},
    {42, @"20.39.4"},
    {43, @"20.38.4"},
    {44, @"20.38.3"},
    {45, @"20.37.5"},
    {46, @"20.37.3"},
    {47, @"20.36.3"},
    {48, @"20.35.2"},
    {49, @"20.34.2"},
    {50, @"20.33.2"},
    {51, @"20.32.5"},
    {52, @"20.32.4"},
    {53, @"20.31.6"},
    {54, @"20.31.5"},
    {55, @"20.30.5"},
    {56, @"20.29.3"},
    {57, @"20.28.2"},
    {58, @"20.26.7"},
    {59, @"20.25.4"},
    {60, @"20.24.5"},
    {61, @"20.24.4"},
    {62, @"20.23.3"},
    {63, @"20.22.1"},
    {64, @"20.21.6"},
    {65, @"20.20.7"},
    {66, @"20.20.5"},
    {67, @"20.19.3"},
    {68, @"20.19.2"},
    {69, @"20.18.5"},
    {70, @"20.18.4"},
    {71, @"20.16.7"},
    {72, @"20.15.1"},
    {73, @"20.14.2"},
    {74, @"20.13.5"},
    {75, @"20.12.4"},
    {76, @"20.11.6"},
    {77, @"20.10.4"},
    {78, @"20.10.3"},
    {79, @"20.09.3"},
    {80, @"20.08.3"},
    {81, @"20.07.6"},
    {82, @"20.06.03"},
    {83, @"20.05.4"},
    {84, @"20.03.1"},
    {85, @"20.03.02"},
    {86, @"20.02.3"}
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
