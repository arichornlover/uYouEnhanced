/*
 * Copyright (c) 2018-2022, 2026 Taner Sener
 *
 * This file is part of FFmpegKitNext.
 *
 * FFmpegKitNext is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * FFmpegKitNext is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General License for more details.
 *
 * You should have received a copy of the GNU Lesser General License
 * along with FFmpegKitNext. If not, see <http://www.gnu.org/licenses/>.
 */

#import "FFmpegKitConfig.h"
#import "ArchDetect.h"
#import "AtomicLong.h"
#import "FFmpegKit.h"
#import "FFmpegSession.h"
#import "FFprobeKit.h"
#import "FFprobeSession.h"
#import "Level.h"
#import "LogRedirectionStrategy.h"
#import "MediaInformationSession.h"
#import "SessionState.h"
#import "fftools/ffmpeg.h"
#import "libavformat/avio.h"
#import "libavutil/bprint.h"
#import "libavutil/common.h"
#import "libavutil/error.h"
#import "libavutil/ffversion.h"
#import "libavutil/mem.h"
#import <errno.h>
#import <limits.h>
#import <stdatomic.h>
#import <stdint.h>
#import <sys/stat.h>
#import <sys/time.h>
#import <sys/types.h>

/** Global library version */
NSString *const FFmpegKitVersion = @"9.0.0";

/**
 * Prefix of named pipes created by ffmpeg-kit.
 */
NSString *const FFmpegKitNamedPipePrefix = @"fk_pipe_";

/**
 * Generates ids for named ffmpeg kit pipes.
 */
static AtomicLong *pipeIndexGenerator;

/* Session history variables */
static int sessionHistorySize;
static volatile NSMutableDictionary *sessionHistoryMap;
static NSMutableArray *sessionHistoryList;
static NSRecursiveLock *sessionHistoryLock;
static NSHashTable *sessionDeleteListeners;
static NSRecursiveLock *sessionDeleteListenerLock;

/** Session control variables */
#define SESSION_MAP_SIZE 1000
static atomic_short sessionMap[SESSION_MAP_SIZE];
static atomic_int sessionInTransitMessageCountMap[SESSION_MAP_SIZE];

static dispatch_queue_t asyncDispatchQueue;

/** Holds callback defined to redirect logs */
static LogCallback logCallback;

/** Holds callback defined to redirect statistics */
static StatisticsCallback statisticsCallback;

/** Holds complete callbacks defined to redirect asynchronous execution results
 */
static FFmpegSessionCompleteCallback ffmpegSessionCompleteCallback;
static FFprobeSessionCompleteCallback ffprobeSessionCompleteCallback;
static MediaInformationSessionCompleteCallback
    mediaInformationSessionCompleteCallback;

static LogRedirectionStrategy globalLogRedirectionStrategy;

/** Redirection control variables */
static int redirectionEnabled;
static NSRecursiveLock *lock;
static dispatch_semaphore_t semaphore;
static NSMutableArray *callbackDataArray;

/** Fields that control the handling of SIGNALs */
volatile int handleSIGQUIT = 1;
volatile int handleSIGINT = 1;
volatile int handleSIGTERM = 1;
volatile int handleSIGXCPU = 1;
volatile int handleSIGPIPE = 1;

/** Holds the id of the current execution */
__thread long globalSessionId = 0;

/** Holds the default log level */
int configuredLogLevel = LevelAVLogInfo;

#define FFKIT_RESOURCE_INPUT 1
#define FFKIT_RESOURCE_OUTPUT 2
#define FFKIT_DEFAULT_OUTPUT_CAPACITY 4096
#define FFKIT_DEFAULT_STREAM_CAPACITY 1048576

/*
 * The two helpers below (ffkit_max_alloc_size and ffkit_int64_add_overflow)
 * are duplicated verbatim in the Android, Apple and Linux FFmpegKit sources
 * because there is no shared native layer between the platforms. Keep all
 * three copies in sync: any change here must be mirrored in the others.
 */
static int64_t ffkit_max_alloc_size(void) {
#if SIZE_MAX > INT64_MAX
    return INT64_MAX;
#else
    return (int64_t)SIZE_MAX;
#endif
}

static int ffkit_int64_add_overflow(int64_t left, int64_t right,
                                    int64_t *result) {
    if ((right > 0 && left > INT64_MAX - right) ||
        (right < 0 && left < INT64_MIN - right)) {
        return 1;
    }

    *result = left + right;
    return 0;
}

typedef struct FFKitMemoryResource {
    int64_t id;
    int type;
    uint8_t *data;
    int64_t size;
    int64_t capacity;
    int64_t maxCapacity;
    int ownsData;
    int unregistered;
    int openCount;
    pthread_mutex_t mutex;
    struct FFKitMemoryResource *next;
} FFKitMemoryResource;

typedef struct FFKitMemoryHandle {
    FFKitMemoryResource *resource;
    int64_t position;
    int flags;
} FFKitMemoryHandle;

typedef struct FFKitStreamResource {
    int64_t id;
    int type;
    uint8_t *data;
    int64_t capacity;
    int64_t size;
    int64_t readPosition;
    int64_t writePosition;
    int closed;
    int writeClosed;
    int unregistered;
    int openCount;
    pthread_mutex_t mutex;
    pthread_cond_t canRead;
    pthread_cond_t canWrite;
    struct FFKitStreamResource *next;
} FFKitStreamResource;

typedef struct FFKitStreamHandle {
    FFKitStreamResource *resource;
    int flags;
} FFKitStreamHandle;

static pthread_mutex_t ffkitMemoryRegistryMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t ffkitStreamRegistryMutex = PTHREAD_MUTEX_INITIALIZER;
static FFKitMemoryResource *ffkitMemoryResources = NULL;
static FFKitStreamResource *ffkitStreamResources = NULL;
static atomic_llong ffkitNextResourceId = 1;

#ifdef USES_FFMPEG_KIT_PROTOCOLS
typedef int (*ffkit_local_protocol_open_function)(int64_t, int, void **);
typedef int (*ffkit_local_protocol_read_function)(void *, unsigned char *, int);
typedef int (*ffkit_local_protocol_write_function)(void *, const unsigned char *,
                                                   int);
typedef int64_t (*ffkit_local_protocol_seek_function)(void *, int64_t, int);
typedef int (*ffkit_local_protocol_close_function)(void *);

extern void av_set_ffkitmem_functions(
    ffkit_local_protocol_open_function open_function,
    ffkit_local_protocol_read_function read_function,
    ffkit_local_protocol_write_function write_function,
    ffkit_local_protocol_seek_function seek_function,
    ffkit_local_protocol_close_function close_function);

extern void av_set_ffkitstream_functions(
    ffkit_local_protocol_open_function open_function,
    ffkit_local_protocol_read_function read_function,
    ffkit_local_protocol_write_function write_function,
    ffkit_local_protocol_seek_function seek_function,
    ffkit_local_protocol_close_function close_function);
#endif

/** Forward declaration for function defined in fftools/ffmpeg.c */
int ffmpeg_execute(int argc, char **argv);

/** Forward declaration for function defined in fftools/ffprobe.c */
int ffprobe_execute(int argc, char **argv);

/** Forward declaration for function defined in fftools/ffprobe.c */
void ffprobe_set_media_information_buffer(AVBPrint *buffer);

typedef NS_ENUM(NSUInteger, CallbackType) { LogType, StatisticsType };

NSArray *deleteExpiredSessionsLocked() {
    NSMutableArray *deletedSessionIds = [[NSMutableArray alloc] init];

    while ([sessionHistoryList count] > sessionHistorySize) {
        id<Session> first = [sessionHistoryList firstObject];
        if (first != nil) {
            long sessionId = [first getSessionId];
            [sessionHistoryList removeObjectAtIndex:0];
            [sessionHistoryMap
                removeObjectForKey:[NSNumber
                                       numberWithLong:sessionId]];
            [deletedSessionIds addObject:[NSNumber numberWithLong:sessionId]];
        }
    }

    return deletedSessionIds;
}

void notifySessionDeleted(long sessionId) {
    [sessionDeleteListenerLock lock];
    NSArray *listeners = [sessionDeleteListeners allObjects];
    [sessionDeleteListenerLock unlock];

    for (int i = 0; i < [listeners count]; i++) {
        id<SessionDeleteListener> listener = [listeners objectAtIndex:i];
        @try {
            [listener sessionDeleted:sessionId];
        } @catch (NSException *exception) {
            NSLog(@"Exception thrown inside session delete listener. %@",
                  [exception callStackSymbols]);
        }
    }
}

void notifySessionsDeleted(NSArray *sessionIds) {
    for (int i = 0; i < [sessionIds count]; i++) {
        NSNumber *sessionId = [sessionIds objectAtIndex:i];
        notifySessionDeleted([sessionId longValue]);
    }
}

void addSessionToSessionHistory(id<Session> session) {
    NSNumber *sessionIdNumber =
        [NSNumber numberWithLong:[session getSessionId]];
    NSArray *deletedSessionIds = @[];

    [sessionHistoryLock lock];

    /*
     * ASYNC SESSIONS CALL THIS METHOD TWICE
     * THIS CHECK PREVENTS ADDING THE SAME SESSION AGAIN
     */
    if ([sessionHistoryMap objectForKey:sessionIdNumber] == nil) {
        [sessionHistoryMap setObject:session forKey:sessionIdNumber];
        [sessionHistoryList addObject:session];
        deletedSessionIds = deleteExpiredSessionsLocked();
    }

    [sessionHistoryLock unlock];

    notifySessionsDeleted(deletedSessionIds);
}

/**
 * Callback data class.
 */
@interface CallbackData : NSObject

@end

@implementation CallbackData {
    CallbackType _type;
    long _sessionId; // session id

    int _logLevel;     // log level
    AVBPrint _logData; // log data

    int _statisticsFrameNumber; // statistics frame number
    float _statisticsFps;       // statistics fps
    float _statisticsQuality;   // statistics quality
    int64_t _statisticsSize;    // statistics size
    double _statisticsTime;     // statistics time
    double _statisticsBitrate;  // statistics bitrate
    double _statisticsSpeed;    // statistics speed
}

- (instancetype)init:(long)sessionId
            logLevel:(int)logLevel
                data:(AVBPrint *)data {
    self = [super init];
    if (self) {
        _type = LogType;
        _sessionId = sessionId;
        _logLevel = logLevel;
        av_bprint_init(&_logData, 0, AV_BPRINT_SIZE_UNLIMITED);
        av_bprintf(&_logData, "%s", data->str);
    }

    return self;
}

- (instancetype)init:(long)sessionId
    videoFrameNumber:(int)videoFrameNumber
                 fps:(float)videoFps
             quality:(float)videoQuality
                size:(int64_t)size
                time:(double)time
             bitrate:(double)bitrate
               speed:(double)speed {
    self = [super init];
    if (self) {
        _type = StatisticsType;
        _sessionId = sessionId;
        _statisticsFrameNumber = videoFrameNumber;
        _statisticsFps = videoFps;
        _statisticsQuality = videoQuality;
        _statisticsSize = size;
        _statisticsTime = time;
        _statisticsBitrate = bitrate;
        _statisticsSpeed = speed;
    }

    return self;
}

- (CallbackType)getType {
    return _type;
}

- (long)getSessionId {
    return _sessionId;
}

- (int)getLogLevel {
    return _logLevel;
}

- (AVBPrint *)getLogData {
    return &_logData;
}

- (int)getStatisticsFrameNumber {
    return _statisticsFrameNumber;
}

- (float)getStatisticsFps {
    return _statisticsFps;
}

- (float)getStatisticsQuality {
    return _statisticsQuality;
}

- (int64_t)getStatisticsSize {
    return _statisticsSize;
}

- (double)getStatisticsTime {
    return _statisticsTime;
}

- (double)getStatisticsBitrate {
    return _statisticsBitrate;
}

- (double)getStatisticsSpeed {
    return _statisticsSpeed;
}

@end

/**
 * Waits on the callback semaphore for the given time.
 *
 * @param milliSeconds wait time in milliseconds
 */
void callbackWait(int milliSeconds) {
    dispatch_semaphore_wait(
        semaphore, dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(milliSeconds * NSEC_PER_MSEC)));
}

/**
 * Notifies threads waiting on callback semaphore.
 */
void callbackNotify() { dispatch_semaphore_signal(semaphore); }

static const char *avutil_log_get_level_str(int level) {
    switch (level) {
    case AV_LOG_STDERR:
        return "stderr";
    case AV_LOG_QUIET:
        return "quiet";
    case AV_LOG_DEBUG:
        return "debug";
    case AV_LOG_VERBOSE:
        return "verbose";
    case AV_LOG_INFO:
        return "info";
    case AV_LOG_WARNING:
        return "warning";
    case AV_LOG_ERROR:
        return "error";
    case AV_LOG_FATAL:
        return "fatal";
    case AV_LOG_PANIC:
        return "panic";
    default:
        return "";
    }
}

static void avutil_log_format_line(void *avcl, int level, const char *fmt,
                                   va_list vl, AVBPrint part[4],
                                   int *print_prefix) {
    int flags = av_log_get_flags();
    AVClass *avc = avcl ? *(AVClass **)avcl : NULL;
    av_bprint_init(part + 0, 0, 1);
    av_bprint_init(part + 1, 0, 1);
    av_bprint_init(part + 2, 0, 1);
    av_bprint_init(part + 3, 0, 65536);

    if (*print_prefix && avc) {
        if (avc->parent_log_context_offset) {
            AVClass **parent = *(AVClass ***)(((uint8_t *)avcl) +
                                              avc->parent_log_context_offset);
            if (parent && *parent) {
                av_bprintf(part + 0, "[%s @ %p] ", (*parent)->item_name(parent),
                           parent);
            }
        }
        av_bprintf(part + 1, "[%s @ %p] ", avc->item_name(avcl), avcl);
    }

    if (*print_prefix && (level > AV_LOG_QUIET) && (flags & AV_LOG_PRINT_LEVEL))
        av_bprintf(part + 2, "[%s] ", avutil_log_get_level_str(level));

    av_vbprintf(part + 3, fmt, vl);

    if (*part[0].str || *part[1].str || *part[2].str || *part[3].str) {
        char lastc = part[3].len && part[3].len <= part[3].size
                         ? part[3].str[part[3].len - 1]
                         : 0;
        *print_prefix = lastc == '\n' || lastc == '\r';
    }
}

static void avutil_log_sanitize(uint8_t *line) {
    while (*line) {
        if (*line < 0x08 || (*line > 0x0D && *line < 0x20))
            *line = '?';
        line++;
    }
}

/**
 * Adds log data to the end of callback data list.
 *
 * @param level log level
 * @param data log data
 */
void logCallbackDataAdd(int level, AVBPrint *data) {
    CallbackData *callbackData = [[CallbackData alloc] init:globalSessionId
                                                   logLevel:level
                                                       data:data];

    [lock lock];
    [callbackDataArray addObject:callbackData];
    [lock unlock];

    callbackNotify();

    atomic_fetch_add(
        &sessionInTransitMessageCountMap[globalSessionId % SESSION_MAP_SIZE],
        1);
}

/**
 * Adds statistics data to the end of callback data list.
 */
void statisticsCallbackDataAdd(int frameNumber, float fps, float quality,
                               int64_t size, double time, double bitrate,
                               double speed) {
    CallbackData *callbackData = [[CallbackData alloc] init:globalSessionId
                                           videoFrameNumber:frameNumber
                                                        fps:fps
                                                    quality:quality
                                                       size:size
                                                       time:time
                                                    bitrate:bitrate
                                                      speed:speed];

    [lock lock];
    [callbackDataArray addObject:callbackData];
    [lock unlock];

    callbackNotify();

    atomic_fetch_add(
        &sessionInTransitMessageCountMap[globalSessionId % SESSION_MAP_SIZE],
        1);
}

/**
 * Removes head of callback data list.
 */
CallbackData *callbackDataRemove() {
    CallbackData *newData = nil;

    [lock lock];

    @try {
        if ([callbackDataArray count] > 0) {
            newData = [callbackDataArray objectAtIndex:0];
            [callbackDataArray removeObjectAtIndex:0];
        }
    } @catch (NSException *exception) {
        // DO NOTHING
    } @finally {
        [lock unlock];
    }

    return newData;
}

/**
 * Registers a session id to the session map.
 *
 * @param sessionId session id
 */
void registerSessionId(long sessionId) {
    atomic_store(&sessionMap[sessionId % SESSION_MAP_SIZE], 1);
}

/**
 * Removes a session id from the session map.
 *
 * @param sessionId session id
 */
void removeSession(long sessionId) {
    atomic_store(&sessionMap[sessionId % SESSION_MAP_SIZE], 0);
}

/**
 * Adds a cancel session request to the session map.
 *
 * @param sessionId session id
 */
void cancelSession(long sessionId) {
    atomic_store(&sessionMap[sessionId % SESSION_MAP_SIZE], 2);
}

/**
 * Adds a cancel session request for every running session to the session map.
 * Only sessions currently marked running (1) are switched to cancel (2); slots
 * that are idle (0) or already cancelling (2) are left untouched, and a session
 * that starts after this call claims its own slot and is therefore unaffected.
 */
void cancelAllSessions(void) {
    for (int i = 0; i < SESSION_MAP_SIZE; i++) {
        short running = 1;
        atomic_compare_exchange_strong(&sessionMap[i], &running, 2);
    }
}

/**
 * Checks whether a cancel request for the given session id exists in the
 * session map.
 *
 * @param sessionId session id
 * @return 1 if exists, false otherwise
 */
int cancelRequested(long sessionId) {
    if (atomic_load(&sessionMap[sessionId % SESSION_MAP_SIZE]) == 2) {
        return 1;
    } else {
        return 0;
    }
}

/**
 * Resets the number of messages in transmit for this session.
 *
 * @param sessionId session id
 */
void resetMessagesInTransmit(long sessionId) {
    atomic_store(&sessionInTransitMessageCountMap[sessionId % SESSION_MAP_SIZE],
                 0);
}

static int ffkit_cond_wait(pthread_cond_t *condition, pthread_mutex_t *mutex,
                           int timeoutMs) {
    if (timeoutMs < 0) {
        return pthread_cond_wait(condition, mutex);
    }

    if (timeoutMs == 0) {
        return ETIMEDOUT;
    }

    struct timeval tv;
    struct timespec ts;
    gettimeofday(&tv, NULL);
    ts.tv_sec = tv.tv_sec + timeoutMs / 1000;
    ts.tv_nsec = (tv.tv_usec * 1000) + ((timeoutMs % 1000) * 1000000);
    ts.tv_sec += ts.tv_nsec / 1000000000L;
    ts.tv_nsec %= 1000000000L;

    return pthread_cond_timedwait(condition, mutex, &ts);
}

static int64_t ffkit_next_resource_id() {
    return atomic_fetch_add(&ffkitNextResourceId, 1);
}

static FFKitMemoryResource *ffkit_memory_find_locked(int64_t id) {
    FFKitMemoryResource *current = ffkitMemoryResources;

    while (current != NULL) {
        if (current->id == id) {
            return current;
        }
        current = current->next;
    }

    return NULL;
}

static void ffkit_memory_free(FFKitMemoryResource *resource) {
    if (resource == NULL) {
        return;
    }

    if (resource->ownsData && resource->data != NULL) {
        av_free(resource->data);
    }

    pthread_mutex_destroy(&resource->mutex);
    av_free(resource);
}

static void ffkit_memory_add(FFKitMemoryResource *resource) {
    pthread_mutex_lock(&ffkitMemoryRegistryMutex);
    resource->next = ffkitMemoryResources;
    ffkitMemoryResources = resource;
    pthread_mutex_unlock(&ffkitMemoryRegistryMutex);
}

static FFKitStreamResource *ffkit_stream_find_locked(int64_t id) {
    FFKitStreamResource *current = ffkitStreamResources;

    while (current != NULL) {
        if (current->id == id) {
            return current;
        }
        current = current->next;
    }

    return NULL;
}

static void ffkit_stream_free(FFKitStreamResource *resource) {
    if (resource == NULL) {
        return;
    }

    if (resource->data != NULL) {
        av_free(resource->data);
    }

    pthread_cond_destroy(&resource->canRead);
    pthread_cond_destroy(&resource->canWrite);
    pthread_mutex_destroy(&resource->mutex);
    av_free(resource);
}

static void ffkit_stream_add(FFKitStreamResource *resource) {
    pthread_mutex_lock(&ffkitStreamRegistryMutex);
    resource->next = ffkitStreamResources;
    ffkitStreamResources = resource;
    pthread_mutex_unlock(&ffkitStreamRegistryMutex);
}

static int ffkit_memory_open(int64_t id, int flags, void **opaque) {
    FFKitMemoryResource *resource = NULL;
    FFKitMemoryHandle *handle = NULL;

    pthread_mutex_lock(&ffkitMemoryRegistryMutex);
    resource = ffkit_memory_find_locked(id);
    if (resource != NULL) {
        pthread_mutex_lock(&resource->mutex);
        if (resource->unregistered ||
            ((flags & AVIO_FLAG_WRITE) && resource->type != FFKIT_RESOURCE_OUTPUT) ||
            (!(flags & AVIO_FLAG_WRITE) && resource->type != FFKIT_RESOURCE_INPUT)) {
            pthread_mutex_unlock(&resource->mutex);
            pthread_mutex_unlock(&ffkitMemoryRegistryMutex);
            return AVERROR(ENOENT);
        }
        resource->openCount++;
        pthread_mutex_unlock(&resource->mutex);
    }
    pthread_mutex_unlock(&ffkitMemoryRegistryMutex);

    if (resource == NULL) {
        return AVERROR(ENOENT);
    }

    handle = av_mallocz(sizeof(FFKitMemoryHandle));
    if (handle == NULL) {
        pthread_mutex_lock(&resource->mutex);
        resource->openCount--;
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR(ENOMEM);
    }

    handle->resource = resource;
    handle->flags = flags;
    handle->position = 0;
    *opaque = handle;
    return 0;
}

static int ffkit_memory_read(void *opaque, unsigned char *buf, int size) {
    FFKitMemoryHandle *handle = opaque;
    FFKitMemoryResource *resource;
    int bytesToRead;

    if (handle == NULL || buf == NULL || size < 0) {
        return AVERROR(EINVAL);
    }

    resource = handle->resource;
    pthread_mutex_lock(&resource->mutex);
    if (resource->type != FFKIT_RESOURCE_INPUT) {
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR(EBADF);
    }

    if (handle->position >= resource->size) {
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR_EOF;
    }

    bytesToRead = (int)FFMIN((int64_t)size, resource->size - handle->position);
    memcpy(buf, resource->data + handle->position, bytesToRead);
    handle->position += bytesToRead;
    pthread_mutex_unlock(&resource->mutex);

    return bytesToRead;
}

static int ffkit_memory_ensure_capacity(FFKitMemoryResource *resource,
                                        int64_t requiredCapacity) {
    int64_t newCapacity;
    uint8_t *newData;

    if (requiredCapacity <= resource->capacity) {
        return 0;
    }

    if (requiredCapacity > resource->maxCapacity) {
        return AVERROR(ENOSPC);
    }

    newCapacity = resource->capacity > 0 ? resource->capacity
                                         : FFKIT_DEFAULT_OUTPUT_CAPACITY;
    while (newCapacity < requiredCapacity) {
        if (newCapacity > resource->maxCapacity / 2) {
            newCapacity = resource->maxCapacity;
        } else {
            newCapacity *= 2;
        }
    }

    newData = av_realloc(resource->data, newCapacity);
    if (newData == NULL) {
        return AVERROR(ENOMEM);
    }

    resource->data = newData;
    resource->capacity = newCapacity;
    return 0;
}

static int ffkit_memory_write(void *opaque, const unsigned char *buf, int size) {
    FFKitMemoryHandle *handle = opaque;
    FFKitMemoryResource *resource;
    int ret;
    int64_t requiredSize;

    if (handle == NULL || buf == NULL || size < 0) {
        return AVERROR(EINVAL);
    }

    resource = handle->resource;
    pthread_mutex_lock(&resource->mutex);
    if (resource->type != FFKIT_RESOURCE_OUTPUT) {
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR(EBADF);
    }

    if (ffkit_int64_add_overflow(handle->position, size, &requiredSize)) {
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR(EOVERFLOW);
    }

    ret = ffkit_memory_ensure_capacity(resource, requiredSize);
    if (ret < 0) {
        pthread_mutex_unlock(&resource->mutex);
        return ret;
    }

    if (handle->position > resource->size) {
        memset(resource->data + resource->size, 0,
               handle->position - resource->size);
    }

    memcpy(resource->data + handle->position, buf, size);
    handle->position = requiredSize;
    if (requiredSize > resource->size) {
        resource->size = requiredSize;
    }
    pthread_mutex_unlock(&resource->mutex);

    return size;
}

static int64_t ffkit_memory_seek(void *opaque, int64_t pos, int whence) {
    FFKitMemoryHandle *handle = opaque;
    FFKitMemoryResource *resource;
    int64_t newPosition;

    if (handle == NULL) {
        return AVERROR(EINVAL);
    }

    resource = handle->resource;
    pthread_mutex_lock(&resource->mutex);

    if (whence == AVSEEK_SIZE) {
        int64_t size = resource->size;
        pthread_mutex_unlock(&resource->mutex);
        return size;
    }

    if (whence == SEEK_SET) {
        newPosition = pos;
    } else if (whence == SEEK_CUR) {
        if (ffkit_int64_add_overflow(handle->position, pos, &newPosition)) {
            pthread_mutex_unlock(&resource->mutex);
            return AVERROR(EOVERFLOW);
        }
    } else if (whence == SEEK_END) {
        if (ffkit_int64_add_overflow(resource->size, pos, &newPosition)) {
            pthread_mutex_unlock(&resource->mutex);
            return AVERROR(EOVERFLOW);
        }
    } else {
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR(EINVAL);
    }

    if (newPosition < 0) {
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR(EINVAL);
    }

    handle->position = newPosition;
    pthread_mutex_unlock(&resource->mutex);

    return newPosition;
}

static int ffkit_memory_close(void *opaque) {
    FFKitMemoryHandle *handle = opaque;
    FFKitMemoryResource *resource;
    int freeResource = 0;

    if (handle == NULL) {
        return 0;
    }

    resource = handle->resource;
    pthread_mutex_lock(&resource->mutex);
    if (resource->openCount > 0) {
        resource->openCount--;
    }
    freeResource = resource->unregistered && resource->openCount == 0;
    pthread_mutex_unlock(&resource->mutex);

    av_free(handle);

    if (freeResource) {
        ffkit_memory_free(resource);
    }

    return 0;
}

static int ffkit_stream_open(int64_t id, int flags, void **opaque) {
    FFKitStreamResource *resource = NULL;
    FFKitStreamHandle *handle = NULL;

    pthread_mutex_lock(&ffkitStreamRegistryMutex);
    resource = ffkit_stream_find_locked(id);
    if (resource != NULL) {
        pthread_mutex_lock(&resource->mutex);
        if (resource->unregistered ||
            ((flags & AVIO_FLAG_WRITE) && resource->type != FFKIT_RESOURCE_OUTPUT) ||
            (!(flags & AVIO_FLAG_WRITE) && resource->type != FFKIT_RESOURCE_INPUT)) {
            pthread_mutex_unlock(&resource->mutex);
            pthread_mutex_unlock(&ffkitStreamRegistryMutex);
            return AVERROR(ENOENT);
        }
        resource->openCount++;
        pthread_mutex_unlock(&resource->mutex);
    }
    pthread_mutex_unlock(&ffkitStreamRegistryMutex);

    if (resource == NULL) {
        return AVERROR(ENOENT);
    }

    handle = av_mallocz(sizeof(FFKitStreamHandle));
    if (handle == NULL) {
        pthread_mutex_lock(&resource->mutex);
        resource->openCount--;
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR(ENOMEM);
    }

    handle->resource = resource;
    handle->flags = flags;
    *opaque = handle;
    return 0;
}

static int ffkit_stream_write_bytes(FFKitStreamResource *resource,
                                    const uint8_t *buf, int size,
                                    int timeoutMs) {
    int written = 0;

    if (resource == NULL || buf == NULL || size < 0) {
        return AVERROR(EINVAL);
    }

    pthread_mutex_lock(&resource->mutex);
    while (written < size) {
        while (resource->size == resource->capacity && !resource->closed &&
               !resource->writeClosed) {
            int waitRc =
                ffkit_cond_wait(&resource->canWrite, &resource->mutex,
                                timeoutMs);
            if (waitRc == ETIMEDOUT) {
                pthread_mutex_unlock(&resource->mutex);
                return written;
            }
        }

        if (resource->closed || resource->writeClosed) {
            pthread_mutex_unlock(&resource->mutex);
            return written > 0 ? written : AVERROR(EPIPE);
        }

        int64_t freeSize = resource->capacity - resource->size;
        int chunkSize = (int)FFMIN((int64_t)(size - written), freeSize);
        chunkSize =
            (int)FFMIN((int64_t)chunkSize, resource->capacity - resource->writePosition);

        memcpy(resource->data + resource->writePosition, buf + written,
               chunkSize);
        resource->writePosition =
            (resource->writePosition + chunkSize) % resource->capacity;
        resource->size += chunkSize;
        written += chunkSize;
        pthread_cond_broadcast(&resource->canRead);
    }
    pthread_mutex_unlock(&resource->mutex);

    return written;
}

static int ffkit_stream_read_bytes(FFKitStreamResource *resource, uint8_t *buf,
                                   int size, int timeoutMs, int *timedOut,
                                   int *eof) {
    int bytesRead = 0;

    if (timedOut != NULL) {
        *timedOut = 0;
    }
    if (eof != NULL) {
        *eof = 0;
    }

    if (resource == NULL || buf == NULL || size < 0) {
        return AVERROR(EINVAL);
    }

    pthread_mutex_lock(&resource->mutex);
    while (resource->size == 0 && !resource->writeClosed && !resource->closed) {
        int waitRc =
            ffkit_cond_wait(&resource->canRead, &resource->mutex, timeoutMs);
        if (waitRc == ETIMEDOUT) {
            if (timedOut != NULL) {
                *timedOut = 1;
            }
            pthread_mutex_unlock(&resource->mutex);
            return 0;
        }
    }

    if (resource->size == 0 && resource->writeClosed) {
        if (eof != NULL) {
            *eof = 1;
        }
        pthread_mutex_unlock(&resource->mutex);
        return 0;
    }

    if (resource->size == 0 && resource->closed) {
        pthread_mutex_unlock(&resource->mutex);
        return AVERROR(EPIPE);
    }

    while (bytesRead < size && resource->size > 0) {
        int chunkSize = (int)FFMIN((int64_t)(size - bytesRead), resource->size);
        chunkSize =
            (int)FFMIN((int64_t)chunkSize, resource->capacity - resource->readPosition);

        memcpy(buf + bytesRead, resource->data + resource->readPosition,
               chunkSize);
        resource->readPosition =
            (resource->readPosition + chunkSize) % resource->capacity;
        resource->size -= chunkSize;
        bytesRead += chunkSize;
        pthread_cond_broadcast(&resource->canWrite);
    }
    pthread_mutex_unlock(&resource->mutex);

    return bytesRead;
}

static int ffkit_stream_read(void *opaque, unsigned char *buf, int size) {
    FFKitStreamHandle *handle = opaque;
    int eof = 0;
    int ret;

    if (handle == NULL) {
        return AVERROR(EINVAL);
    }

    ret = ffkit_stream_read_bytes(handle->resource, buf, size, -1, NULL, &eof);
    return eof ? AVERROR_EOF : ret;
}

static int ffkit_stream_write(void *opaque, const unsigned char *buf, int size) {
    FFKitStreamHandle *handle = opaque;

    if (handle == NULL) {
        return AVERROR(EINVAL);
    }

    return ffkit_stream_write_bytes(handle->resource, buf, size, -1);
}

static int64_t ffkit_stream_seek(void *opaque, int64_t pos, int whence) {
    return AVERROR(ESPIPE);
}

static int ffkit_stream_close(void *opaque) {
    FFKitStreamHandle *handle = opaque;
    FFKitStreamResource *resource;
    int freeResource = 0;

    if (handle == NULL) {
        return 0;
    }

    resource = handle->resource;
    pthread_mutex_lock(&resource->mutex);
    if (resource->type == FFKIT_RESOURCE_OUTPUT) {
        resource->writeClosed = 1;
    } else {
        resource->closed = 1;
    }
    if (resource->openCount > 0) {
        resource->openCount--;
    }
    freeResource = resource->unregistered && resource->openCount == 0;
    pthread_cond_broadcast(&resource->canRead);
    pthread_cond_broadcast(&resource->canWrite);
    pthread_mutex_unlock(&resource->mutex);

    av_free(handle);

    if (freeResource) {
        ffkit_stream_free(resource);
    }

    return 0;
}

/*
 * FFmpegKitNext per-session log "duties".
 *
 * -report (ffmpeg) and -show_log (ffprobe) used to each install their own global
 * av_log callback, hijacking redirection and (for ffprobe) needing a manual
 * restore. Instead they now just leave a signal in place (report_file != NULL,
 * do_show_log != 0) and the single, always-installed FFmpegKit callback invokes
 * these passive duty routines for every log line. Each duty self-guards, so both
 * are cheap no-ops when their feature is inactive. A va_list is consumed once, so
 * each duty gets its own va_copy. Neither duty may call av_log() (it would recurse
 * back into the callback).
 */
extern void ffmpegkit_report_write(void *ptr, int level, const char *fmt, va_list vl);
extern void ffmpegkit_show_log_capture(void *ptr, int level, const char *fmt, va_list vl);

static void run_duties(void *ptr, int level, const char *format, va_list vargs) {
    va_list copy;

    va_copy(copy, vargs);
    ffmpegkit_report_write(ptr, level, format, copy);
    va_end(copy);

    va_copy(copy, vargs);
    ffmpegkit_show_log_capture(ptr, level, format, copy);
    va_end(copy);
}

/**
 * Callback function for FFmpeg/FFprobe logs.
 *
 * @param ptr pointer to AVClass struct
 * @param level log level
 * @param format format string
 * @param vargs arguments
 */
void ffmpegkit_log_callback_function(void *ptr, int level, const char *format,
                                     va_list vargs) {
    AVBPrint fullLine;
    AVBPrint part[4];
    int print_prefix = 1;

    // DO NOT PROCESS UNWANTED LOGS
    if (level >= 0) {
        level &= 0xff;
    }

    // Run -report / -show_log capture for every line, independent of the console
    // log-level filter below (the report keeps its own report_file_level threshold).
    run_duties(ptr, level, format, vargs);

    int activeLogLevel = av_log_get_level();

    // LevelAVLogStdErr logs are always redirected
    if ((activeLogLevel == LevelAVLogQuiet && level != LevelAVLogStdErr) ||
        (level > activeLogLevel)) {
        return;
    }

    av_bprint_init(&fullLine, 0, AV_BPRINT_SIZE_UNLIMITED);

    avutil_log_format_line(ptr, level, format, vargs, part, &print_prefix);
    avutil_log_sanitize(part[0].str);
    avutil_log_sanitize(part[1].str);
    avutil_log_sanitize(part[2].str);
    avutil_log_sanitize(part[3].str);

    // COMBINE ALL 4 LOG PARTS
    av_bprintf(&fullLine, "%s%s%s%s", part[0].str, part[1].str, part[2].str,
               part[3].str);

    if (fullLine.len > 0) {
        logCallbackDataAdd(level, &fullLine);
    }

    av_bprint_finalize(part, NULL);
    av_bprint_finalize(part + 1, NULL);
    av_bprint_finalize(part + 2, NULL);
    av_bprint_finalize(part + 3, NULL);
    av_bprint_finalize(&fullLine, NULL);
}

int ffmpegkit_redirection_enabled(void) { return redirectionEnabled; }

/*
 * FFmpegKitNext: av_log callback installed when redirection is DISABLED.
 * Reproduces stock ffmpeg logging (stderr) while still running the per-session
 * duties, so -report / -show_log keep working even with redirection off.
 */
static void ffmpegkit_log_callback_default(void *ptr, int level,
                                           const char *format, va_list vargs) {
    va_list copy;

    va_copy(copy, vargs);
    av_log_default_callback(ptr, level, format, copy);
    va_end(copy);

    run_duties(ptr, level, format, vargs);
}

/**
 * Callback function for FFmpeg statistics.
 *
 * @param frameNumber last processed frame number
 * @param fps frames processed per second
 * @param quality quality of the output stream (video only)
 * @param size size in bytes
 * @param time processed output duration
 * @param bitrate output bit rate in kbits/s
 * @param speed processing speed = processed duration / operation duration
 */
void ffmpegkit_statistics_callback_function(int frameNumber, float fps,
                                            float quality, int64_t size,
                                            double time, double bitrate,
                                            double speed) {
    statisticsCallbackDataAdd(frameNumber, fps, quality, size, time, bitrate,
                              speed);
}

void process_log(long sessionId, int levelValue, AVBPrint *logMessage) {
    int activeLogLevel = av_log_get_level();
    NSString *message = [NSString stringWithCString:logMessage->str
                                           encoding:NSUTF8StringEncoding];
    if (message == nil) {
        // WE DROP LOGS THAT WE CANNOT DISPLAY
        return;
    }
    Log *log = [[Log alloc] init:sessionId:levelValue:message];
    BOOL globalCallbackDefined = false;
    BOOL sessionCallbackDefined = false;
    LogRedirectionStrategy activeLogRedirectionStrategy =
        globalLogRedirectionStrategy;

    // LevelAVLogStdErr logs are always redirected
    if ((activeLogLevel == LevelAVLogQuiet && levelValue != LevelAVLogStdErr) ||
        (levelValue > activeLogLevel)) {
        // LOG NEITHER PRINTED NOR FORWARDED
        return;
    }

    id<Session> session = [FFmpegKitConfig getSession:sessionId];
    if (session != nil) {
        activeLogRedirectionStrategy = [session getLogRedirectionStrategy];
        [session addLog:log];

        LogCallback sessionLogCallback = [session getLogCallback];
        if (sessionLogCallback != nil) {
            sessionCallbackDefined = TRUE;

            @try {
                // NOTIFY SESSION CALLBACK DEFINED
                sessionLogCallback(log);
            } @catch (NSException *exception) {
                NSLog(@"Exception thrown inside session log callback. %@",
                      [exception callStackSymbols]);
            }
        }
    }

    LogCallback globalLogCallback = logCallback;
    if (globalLogCallback != nil) {
        globalCallbackDefined = TRUE;

        @try {
            // NOTIFY GLOBAL CALLBACK DEFINED
            globalLogCallback(log);
        } @catch (NSException *exception) {
            NSLog(@"Exception thrown inside global log callback. %@",
                  [exception callStackSymbols]);
        }
    }

    // EXECUTE THE LOG STRATEGY
    switch (activeLogRedirectionStrategy) {
    case LogRedirectionStrategyNeverPrintLogs: {
        return;
    }
    case LogRedirectionStrategyPrintLogsWhenGlobalCallbackNotDefined: {
        if (globalCallbackDefined) {
            return;
        }
    } break;
    case LogRedirectionStrategyPrintLogsWhenSessionCallbackNotDefined: {
        if (sessionCallbackDefined) {
            return;
        }
    } break;
    case LogRedirectionStrategyPrintLogsWhenNoCallbacksDefined: {
        if (globalCallbackDefined || sessionCallbackDefined) {
            return;
        }
    } break;
    case LogRedirectionStrategyAlwaysPrintLogs: {
    } break;
    }

    // PRINT LOGS
    switch (levelValue) {
    case LevelAVLogQuiet:
        // PRINT NO OUTPUT
        break;
    default:
        // WRITE TO NSLOG
        NSLog(@"%@: %@", [FFmpegKitConfig logLevelToString:levelValue],
              [NSString stringWithCString:logMessage->str
                                 encoding:NSUTF8StringEncoding]);
        break;
    }
}

void process_statistics(long sessionId, int videoFrameNumber, float videoFps,
                        float videoQuality, long size, double time,
                        double bitrate, double speed) {

    Statistics *statistics = [[Statistics alloc] init:sessionId
                                     videoFrameNumber:videoFrameNumber
                                             videoFps:videoFps
                                         videoQuality:videoQuality
                                                 size:size
                                                 time:time
                                              bitrate:bitrate
                                                speed:speed];

    id<Session> session = [FFmpegKitConfig getSession:sessionId];
    if (session != nil && [session isFFmpeg]) {
        FFmpegSession *ffmpegSession = (FFmpegSession *)session;
        [ffmpegSession addStatistics:statistics];

        StatisticsCallback sessionStatisticsCallback =
            [ffmpegSession getStatisticsCallback];
        if (sessionStatisticsCallback != nil) {
            @try {
                sessionStatisticsCallback(statistics);
            } @catch (NSException *exception) {
                NSLog(
                    @"Exception thrown inside session statistics callback. %@",
                    [exception callStackSymbols]);
            }
        }
    }

    StatisticsCallback globalStatisticsCallback = statisticsCallback;
    if (globalStatisticsCallback != nil) {
        @try {
            globalStatisticsCallback(statistics);
        } @catch (NSException *exception) {
            NSLog(@"Exception thrown inside global statistics callback. %@",
                  [exception callStackSymbols]);
        }
    }
}

/**
 * Forwards asynchronous messages to Callbacks.
 */
void callbackBlockFunction() {
    int activeLogLevel = av_log_get_level();
    if ((activeLogLevel != LevelAVLogQuiet) &&
        (LevelAVLogDebug <= activeLogLevel)) {
        NSLog(@"Async callback block started.\n");
    }

    while (redirectionEnabled) {
        @autoreleasepool {
            @try {

                CallbackData *callbackData = callbackDataRemove();
                if (callbackData != nil) {

                    if ([callbackData getType] == LogType) {
                        process_log([callbackData getSessionId],
                                    [callbackData getLogLevel],
                                    [callbackData getLogData]);
                        av_bprint_finalize([callbackData getLogData], NULL);
                    } else {
                        process_statistics(
                            [callbackData getSessionId],
                            [callbackData getStatisticsFrameNumber],
                            [callbackData getStatisticsFps],
                            [callbackData getStatisticsQuality],
                            [callbackData getStatisticsSize],
                            [callbackData getStatisticsTime],
                            [callbackData getStatisticsBitrate],
                            [callbackData getStatisticsSpeed]);
                    }

                    atomic_fetch_sub(
                        &sessionInTransitMessageCountMap[
                            [callbackData getSessionId] % SESSION_MAP_SIZE],
                        1);

                } else {
                    callbackWait(100);
                }

            } @catch (NSException *exception) {
                activeLogLevel = av_log_get_level();
                if ((activeLogLevel != LevelAVLogQuiet) &&
                    (LevelAVLogWarning <= activeLogLevel)) {
                    NSLog(@"Async callback block received error: %@n\n",
                          exception);
                    NSLog(@"%@", [exception callStackSymbols]);
                }
            }
        }
    }

    activeLogLevel = av_log_get_level();
    if ((activeLogLevel != LevelAVLogQuiet) &&
        (LevelAVLogDebug <= activeLogLevel)) {
        NSLog(@"Async callback block stopped.\n");
    }
}

int executeFFmpeg(long sessionId, NSArray *arguments) {
    NSString *const LIB_NAME = @"ffmpeg";

    // SETS DEFAULT LOG LEVEL BEFORE STARTING A NEW RUN
    av_log_set_level(configuredLogLevel);

    char **commandCharPArray =
        (char **)av_malloc(sizeof(char *) * ([arguments count] + 2));

    /* PRESERVE USAGE FORMAT
     *
     * ffmpeg <arguments>
     */
    commandCharPArray[0] =
        (char *)av_malloc(sizeof(char) * ([LIB_NAME length] + 1));
    strcpy(commandCharPArray[0], [LIB_NAME UTF8String]);

    // PREPARE ARRAY ELEMENTS
    for (int i = 0; i < [arguments count]; i++) {
        NSString *argument = [arguments objectAtIndex:i];
        commandCharPArray[i + 1] = (char *)[argument UTF8String];
    }
    commandCharPArray[[arguments count] + 1] = NULL;

    // REGISTER THE ID BEFORE STARTING THE SESSION
    globalSessionId = sessionId;
    registerSessionId(sessionId);

    resetMessagesInTransmit(sessionId);

    // RUN
    int returnCode = ffmpeg_execute(([arguments count] + 1), commandCharPArray);

    // ALWAYS REMOVE THE ID FROM THE MAP
    removeSession(sessionId);

    // CLEANUP
    av_free(commandCharPArray[0]);
    av_free(commandCharPArray);

    return returnCode;
}

int executeFFprobeToBuffer(long sessionId, NSArray *arguments, AVBPrint *outputBuffer) {
    NSString *const LIB_NAME = @"ffprobe";

    // SETS DEFAULT LOG LEVEL BEFORE STARTING A NEW RUN
    av_log_set_level(configuredLogLevel);

    char **commandCharPArray =
        (char **)av_malloc(sizeof(char *) * ([arguments count] + 2));

    /* PRESERVE USAGE FORMAT
     *
     * ffprobe <arguments>
     */
    commandCharPArray[0] =
        (char *)av_malloc(sizeof(char) * ([LIB_NAME length] + 1));
    strcpy(commandCharPArray[0], [LIB_NAME UTF8String]);

    // PREPARE ARRAY ELEMENTS
    for (int i = 0; i < [arguments count]; i++) {
        NSString *argument = [arguments objectAtIndex:i];
        commandCharPArray[i + 1] = (char *)[argument UTF8String];
    }
    commandCharPArray[[arguments count] + 1] = NULL;

    // REGISTER THE ID BEFORE STARTING THE SESSION
    globalSessionId = sessionId;
    registerSessionId(sessionId);

    resetMessagesInTransmit(sessionId);

    // WHEN A BUFFER IS PROVIDED, ffprobe WRITES ITS FORMATTED OUTPUT THERE
    // INSTEAD OF THE av_log/stdout PATH. THE POINTER IS THREAD-LOCAL INSIDE
    // ffprobe AND IS CLEARED IMMEDIATELY AFTER THE RUN SO A REUSED THREAD NEVER
    // SEES A STALE (FINALIZED) BUFFER ON A LATER ffprobe EXECUTION.
    ffprobe_set_media_information_buffer(outputBuffer);

    // RUN
    int returnCode =
        ffprobe_execute(([arguments count] + 1), commandCharPArray);

    ffprobe_set_media_information_buffer(NULL);

    // ALWAYS REMOVE THE ID FROM THE MAP
    removeSession(sessionId);

    // CLEANUP
    av_free(commandCharPArray[0]);
    av_free(commandCharPArray);

    return returnCode;
}

int executeFFprobe(long sessionId, NSArray *arguments) {
    return executeFFprobeToBuffer(sessionId, arguments, NULL);
}

@implementation FFmpegKitConfig

+ (void)initialize {
    [ArchDetect class];
    [FFmpegKit class];
    [FFprobeKit class];

    pipeIndexGenerator = [[AtomicLong alloc] initWithValue:1];

    sessionHistorySize = 10;
    sessionHistoryMap = [[NSMutableDictionary alloc] init];
    sessionHistoryList = [[NSMutableArray alloc] init];
    sessionHistoryLock = [[NSRecursiveLock alloc] init];
    sessionDeleteListeners = [NSHashTable weakObjectsHashTable];
    sessionDeleteListenerLock = [[NSRecursiveLock alloc] init];

    for (int i = 0; i < SESSION_MAP_SIZE; i++) {
        atomic_init(&sessionMap[i], 0);
        atomic_init(&sessionInTransitMessageCountMap[i], 0);
    }

    asyncDispatchQueue =
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    logCallback = nil;
    statisticsCallback = nil;
    ffmpegSessionCompleteCallback = nil;
    ffprobeSessionCompleteCallback = nil;
    mediaInformationSessionCompleteCallback = nil;

    globalLogRedirectionStrategy =
        LogRedirectionStrategyPrintLogsWhenNoCallbacksDefined;

    redirectionEnabled = 0;
    lock = [[NSRecursiveLock alloc] init];
    semaphore = dispatch_semaphore_create(0);
    callbackDataArray = [[NSMutableArray alloc] init];

#ifdef USES_FFMPEG_KIT_PROTOCOLS
    av_set_ffkitmem_functions(ffkit_memory_open, ffkit_memory_read,
                              ffkit_memory_write, ffkit_memory_seek,
                              ffkit_memory_close);
    av_set_ffkitstream_functions(ffkit_stream_open, ffkit_stream_read,
                                 ffkit_stream_write, ffkit_stream_seek,
                                 ffkit_stream_close);
#endif

    [FFmpegKitConfig enableRedirection];
}

+ (long)registerFFmpegKitInputBuffer:(NSData *)data {
    if (data == nil) {
        return 0;
    }

    return [FFmpegKitConfig registerFFmpegKitInputBufferWithBytes:[data bytes]
                                                           length:[data length]];
}

+ (long)registerFFmpegKitInputBufferWithBytes:(const void *)bytes
                                       length:(NSUInteger)length {
    int64_t id;
    FFKitMemoryResource *resource;

    if ((bytes == NULL && length > 0) ||
        length > (NSUInteger)ffkit_max_alloc_size()) {
        return 0;
    }

    resource = av_mallocz(sizeof(FFKitMemoryResource));
    if (resource == NULL) {
        return 0;
    }

    resource->data = av_malloc(length > 0 ? length : 1);
    if (resource->data == NULL) {
        av_free(resource);
        return 0;
    }

    if (length > 0) {
        memcpy(resource->data, bytes, length);
    }

    id = ffkit_next_resource_id();
    resource->id = id;
    resource->type = FFKIT_RESOURCE_INPUT;
    resource->size = (int64_t)length;
    resource->capacity = (int64_t)length;
    resource->maxCapacity = (int64_t)length;
    resource->ownsData = 1;
    pthread_mutex_init(&resource->mutex, NULL);
    ffkit_memory_add(resource);

    return (long)id;
}

+ (long)registerFFmpegKitOutputBuffer:(long)initialCapacity
                          maxCapacity:(long)maxCapacity {
    int64_t id;
    FFKitMemoryResource *resource;
    int64_t capacity = initialCapacity > 0 ? initialCapacity
                                           : FFKIT_DEFAULT_OUTPUT_CAPACITY;
    int64_t maximumCapacity =
        maxCapacity > 0 ? maxCapacity : ffkit_max_alloc_size();

    if (initialCapacity < 0 || maxCapacity < 0 ||
        capacity > maximumCapacity || capacity > ffkit_max_alloc_size() ||
        maximumCapacity > ffkit_max_alloc_size()) {
        return 0;
    }

    resource = av_mallocz(sizeof(FFKitMemoryResource));
    if (resource == NULL) {
        return 0;
    }

    resource->data = av_malloc(capacity);
    if (resource->data == NULL) {
        av_free(resource);
        return 0;
    }

    id = ffkit_next_resource_id();
    resource->id = id;
    resource->type = FFKIT_RESOURCE_OUTPUT;
    resource->capacity = capacity;
    resource->maxCapacity = maximumCapacity;
    resource->ownsData = 1;
    pthread_mutex_init(&resource->mutex, NULL);
    ffkit_memory_add(resource);

    return (long)id;
}

+ (long)getFFmpegKitBufferSize:(long)bufferId {
    FFKitMemoryResource *resource;
    int64_t size = -1;

    pthread_mutex_lock(&ffkitMemoryRegistryMutex);
    resource = ffkit_memory_find_locked(bufferId);
    if (resource != NULL) {
        pthread_mutex_lock(&resource->mutex);
        size = resource->size;
        pthread_mutex_unlock(&resource->mutex);
    }
    pthread_mutex_unlock(&ffkitMemoryRegistryMutex);

    return (long)size;
}

+ (NSData *)getFFmpegKitOutputBuffer:(long)bufferId {
    FFKitMemoryResource *resource;
    NSData *result = nil;

    pthread_mutex_lock(&ffkitMemoryRegistryMutex);
    resource = ffkit_memory_find_locked(bufferId);
    if (resource != NULL) {
        pthread_mutex_lock(&resource->mutex);
        if (resource->type == FFKIT_RESOURCE_OUTPUT &&
            resource->size >= 0 &&
            (uint64_t)resource->size <= (uint64_t)NSUIntegerMax) {
            result = [NSData dataWithBytes:resource->data
                                    length:(NSUInteger)resource->size];
        }
        pthread_mutex_unlock(&resource->mutex);
    }
    pthread_mutex_unlock(&ffkitMemoryRegistryMutex);

    return result;
}

+ (NSData *)getFFmpegKitOutputBufferNoCopy:(long)bufferId {
    FFKitMemoryResource *resource;
    NSData *result = nil;

    pthread_mutex_lock(&ffkitMemoryRegistryMutex);
    resource = ffkit_memory_find_locked(bufferId);
    if (resource != NULL) {
        pthread_mutex_lock(&resource->mutex);
        if (resource->type == FFKIT_RESOURCE_OUTPUT &&
            resource->size >= 0 &&
            (uint64_t)resource->size <= (uint64_t)NSUIntegerMax) {
            result = [NSData dataWithBytesNoCopy:resource->data
                                          length:(NSUInteger)resource->size
                                    freeWhenDone:NO];
        }
        pthread_mutex_unlock(&resource->mutex);
    }
    pthread_mutex_unlock(&ffkitMemoryRegistryMutex);

    return result;
}

+ (void)unregisterFFmpegKitBuffer:(long)bufferId {
    FFKitMemoryResource *current;
    FFKitMemoryResource *previous = NULL;
    FFKitMemoryResource *resource = NULL;
    int freeResource = 0;

    pthread_mutex_lock(&ffkitMemoryRegistryMutex);
    current = ffkitMemoryResources;
    while (current != NULL) {
        if (current->id == bufferId) {
            resource = current;
            if (previous == NULL) {
                ffkitMemoryResources = current->next;
            } else {
                previous->next = current->next;
            }
            break;
        }
        previous = current;
        current = current->next;
    }
    pthread_mutex_unlock(&ffkitMemoryRegistryMutex);

    if (resource != NULL) {
        pthread_mutex_lock(&resource->mutex);
        resource->unregistered = 1;
        freeResource = resource->openCount == 0;
        pthread_mutex_unlock(&resource->mutex);

        if (freeResource) {
            ffkit_memory_free(resource);
        }
    }
}

+ (long)registerFFmpegKitStream:(long)capacity type:(int)type {
    int64_t id;
    FFKitStreamResource *resource;
    int64_t streamCapacity = capacity > 0 ? capacity
                                          : FFKIT_DEFAULT_STREAM_CAPACITY;

    if (capacity < 0 || streamCapacity > ffkit_max_alloc_size() ||
        (type != FFKIT_RESOURCE_INPUT && type != FFKIT_RESOURCE_OUTPUT)) {
        return 0;
    }

    resource = av_mallocz(sizeof(FFKitStreamResource));
    if (resource == NULL) {
        return 0;
    }

    resource->data = av_malloc(streamCapacity);
    if (resource->data == NULL) {
        av_free(resource);
        return 0;
    }

    id = ffkit_next_resource_id();
    resource->id = id;
    resource->type = type;
    resource->capacity = streamCapacity;
    pthread_mutex_init(&resource->mutex, NULL);
    pthread_cond_init(&resource->canRead, NULL);
    pthread_cond_init(&resource->canWrite, NULL);
    ffkit_stream_add(resource);

    return (long)id;
}

+ (int)writeFFmpegKitStream:(long)streamId
                       data:(NSData *)data
                     offset:(NSUInteger)offset
                     length:(NSUInteger)length
                    timeout:(int)timeoutMs {
    FFKitStreamResource *resource;
    int ret = AVERROR(ENOENT);
    int freeResource = 0;

    if (data == nil || offset > [data length] ||
        length > ([data length] - offset) || length > INT_MAX) {
        return AVERROR(EINVAL);
    }

    pthread_mutex_lock(&ffkitStreamRegistryMutex);
    resource = ffkit_stream_find_locked(streamId);
    if (resource != NULL && resource->type == FFKIT_RESOURCE_INPUT) {
        pthread_mutex_lock(&resource->mutex);
        if (!resource->unregistered) {
            resource->openCount++;
            ret = 0;
        }
        pthread_mutex_unlock(&resource->mutex);
    }
    pthread_mutex_unlock(&ffkitStreamRegistryMutex);

    if (ret == 0) {
        ret = ffkit_stream_write_bytes(
            resource, ((const uint8_t *)[data bytes]) + offset, (int)length,
            timeoutMs);

        pthread_mutex_lock(&resource->mutex);
        if (resource->openCount > 0) {
            resource->openCount--;
        }
        freeResource = resource->unregistered && resource->openCount == 0;
        pthread_mutex_unlock(&resource->mutex);

        if (freeResource) {
            ffkit_stream_free(resource);
        }
    }

    return ret;
}

+ (NSData *)readFFmpegKitStream:(long)streamId
                       maxBytes:(int)maxBytes
                        timeout:(int)timeoutMs {
    FFKitStreamResource *resource;
    uint8_t *buffer;
    int ret = AVERROR(ENOENT);
    int timedOut = 0;
    int eof = 0;
    int freeResource = 0;
    NSData *result = nil;

    if (maxBytes < 0) {
        return nil;
    }

    buffer = av_malloc(maxBytes > 0 ? maxBytes : 1);
    if (buffer == NULL) {
        return nil;
    }

    pthread_mutex_lock(&ffkitStreamRegistryMutex);
    resource = ffkit_stream_find_locked(streamId);
    if (resource != NULL && resource->type == FFKIT_RESOURCE_OUTPUT) {
        pthread_mutex_lock(&resource->mutex);
        if (!resource->unregistered) {
            resource->openCount++;
            ret = 0;
        }
        pthread_mutex_unlock(&resource->mutex);
    }
    pthread_mutex_unlock(&ffkitStreamRegistryMutex);

    if (ret == 0) {
        ret = ffkit_stream_read_bytes(resource, buffer, maxBytes, timeoutMs,
                                      &timedOut, &eof);

        pthread_mutex_lock(&resource->mutex);
        if (resource->openCount > 0) {
            resource->openCount--;
        }
        freeResource = resource->unregistered && resource->openCount == 0;
        pthread_mutex_unlock(&resource->mutex);

        if (freeResource) {
            ffkit_stream_free(resource);
        }
    }

    if (ret > 0 || eof) {
        result = [NSData dataWithBytes:buffer length:(NSUInteger)ret];
    } else if (timedOut) {
        result = nil;
    }

    av_free(buffer);
    return result;
}

+ (void)closeFFmpegKitStreamInput:(long)streamId {
    FFKitStreamResource *resource;

    pthread_mutex_lock(&ffkitStreamRegistryMutex);
    resource = ffkit_stream_find_locked(streamId);
    if (resource != NULL) {
        pthread_mutex_lock(&resource->mutex);
        resource->writeClosed = 1;
        pthread_cond_broadcast(&resource->canRead);
        pthread_cond_broadcast(&resource->canWrite);
        pthread_mutex_unlock(&resource->mutex);
    }
    pthread_mutex_unlock(&ffkitStreamRegistryMutex);
}

+ (void)unregisterFFmpegKitStream:(long)streamId {
    FFKitStreamResource *current;
    FFKitStreamResource *previous = NULL;
    FFKitStreamResource *resource = NULL;
    int freeResource = 0;

    pthread_mutex_lock(&ffkitStreamRegistryMutex);
    current = ffkitStreamResources;
    while (current != NULL) {
        if (current->id == streamId) {
            resource = current;
            if (previous == NULL) {
                ffkitStreamResources = current->next;
            } else {
                previous->next = current->next;
            }
            break;
        }
        previous = current;
        current = current->next;
    }
    pthread_mutex_unlock(&ffkitStreamRegistryMutex);

    if (resource != NULL) {
        pthread_mutex_lock(&resource->mutex);
        resource->unregistered = 1;
        resource->closed = 1;
        resource->writeClosed = 1;
        freeResource = resource->openCount == 0;
        pthread_cond_broadcast(&resource->canRead);
        pthread_cond_broadcast(&resource->canWrite);
        pthread_mutex_unlock(&resource->mutex);

        if (freeResource) {
            ffkit_stream_free(resource);
        }
    }
}

+ (void)enableRedirection {
    [lock lock];

    if (redirectionEnabled != 0) {
        [lock unlock];
        return;
    }
    redirectionEnabled = 1;

    [lock unlock];

    dispatch_async(
        dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
          callbackBlockFunction();
        });

    av_log_set_callback(ffmpegkit_log_callback_function);
    set_report_callback(ffmpegkit_statistics_callback_function);
}

+ (void)disableRedirection {
    [lock lock];

    if (redirectionEnabled != 1) {
        [lock unlock];
        return;
    }
    redirectionEnabled = 0;

    [lock unlock];

    av_log_set_callback(ffmpegkit_log_callback_default);
    set_report_callback(nil);

    callbackNotify();
}

+ (int)setFontconfigConfigurationPath:(NSString *)path {
    return [FFmpegKitConfig setEnvironmentVariable:@"FONTCONFIG_PATH"
                                             value:path];
}

+ (void)setFontDirectory:(NSString *)fontDirectoryPath
                    with:(NSDictionary *)fontNameMapping {
    [FFmpegKitConfig
        setFontDirectoryList:[NSArray arrayWithObject:fontDirectoryPath]
                        with:fontNameMapping];
}

+ (void)setFontDirectoryList:(NSArray *)fontDirectoryArray
                        with:(NSDictionary *)fontNameMapping {
    NSError *error = nil;
    BOOL isDirectory = YES;
    BOOL isCacheDirectory = YES;
    BOOL isFile = NO;
    int validFontNameMappingCount = 0;
    NSString *tempConfigurationDirectory =
        [NSTemporaryDirectory() stringByAppendingPathComponent:@"fontconfig"];
    NSString *fontConfigurationFile = [tempConfigurationDirectory
        stringByAppendingPathComponent:@"fonts.conf"];
    NSString *fontConfigurationCacheDirectory = [tempConfigurationDirectory
        stringByAppendingPathComponent:@"cache"];

    if (![[NSFileManager defaultManager]
            fileExistsAtPath:tempConfigurationDirectory
                 isDirectory:&isDirectory]) {
        if (![[NSFileManager defaultManager]
                      createDirectoryAtPath:tempConfigurationDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&error]) {
            NSLog(@"Failed to set font directory. Error received while "
                  @"creating temp "
                  @"conf directory: %@.",
                  error);
            return;
        }
        NSLog(@"Created temporary font conf directory: TRUE.");
    }

    if (![[NSFileManager defaultManager]
            fileExistsAtPath:fontConfigurationCacheDirectory
                 isDirectory:&isCacheDirectory] ||
        !isCacheDirectory) {
        if (![[NSFileManager defaultManager]
                      createDirectoryAtPath:fontConfigurationCacheDirectory
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&error]) {
            NSLog(@"Failed to set font directory. Error received while "
                  @"creating temp "
                  @"cache directory: %@.",
                  error);
            return;
        }
        NSLog(@"Created temporary font cache directory: TRUE.");
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:fontConfigurationFile
                                             isDirectory:&isFile]) {
        BOOL fontConfigurationDeleted = [[NSFileManager defaultManager]
            removeItemAtPath:fontConfigurationFile
                       error:nil];
        NSLog(@"Deleted old temporary font configuration: %s.",
              fontConfigurationDeleted ? "TRUE" : "FALSE");
    }

    /* PROCESS MAPPINGS FIRST */
    NSString *fontNameMappingBlock = @"";
    for (NSString *fontName in [fontNameMapping allKeys]) {
        NSString *mappedFontName = [fontNameMapping objectForKey:fontName];

        if ((fontName != nil) && (mappedFontName != nil) &&
            ([fontName length] > 0) && ([mappedFontName length] > 0)) {

            fontNameMappingBlock = [NSString
                stringWithFormat:
                    @"%@\n%@\n%@%@%@\n%@\n%@\n%@%@%@\n%@\n%@\n",
                    @"    <match target=\"pattern\">",
                    @"        <test qual=\"any\" name=\"family\">",
                    @"            <string>", fontName, @"</string>",
                    @"        </test>",
                    @"        <edit name=\"family\" mode=\"assign\" "
                    @"binding=\"same\">",
                    @"            <string>", mappedFontName, @"</string>",
                    @"        </edit>", @"    </match>"];

            validFontNameMappingCount++;
        }
    }

    NSMutableString *fontConfiguration = [NSMutableString
        stringWithFormat:@"%@\n%@\n%@\n%@\n", @"<?xml version=\"1.0\"?>",
                         @"<!DOCTYPE fontconfig SYSTEM \"fonts.dtd\">",
                         @"<fontconfig>", @"    <dir prefix=\"cwd\">.</dir>"];
    for (int i = 0; i < [fontDirectoryArray count]; i++) {
        NSString *fontDirectoryPath = [fontDirectoryArray objectAtIndex:i];
        [fontConfiguration appendString:@"    <dir>"];
        [fontConfiguration appendString:fontDirectoryPath];
        [fontConfiguration appendString:@"</dir>\n"];
    }
    [fontConfiguration appendString:@"    <cachedir>"];
    [fontConfiguration appendString:fontConfigurationCacheDirectory];
    [fontConfiguration appendString:@"</cachedir>\n"];
    [fontConfiguration appendString:fontNameMappingBlock];
    [fontConfiguration appendString:@"</fontconfig>\n"];

    if (![fontConfiguration writeToFile:fontConfigurationFile
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:&error]) {
        NSLog(@"Failed to set font directory. Error received while saving font "
              @"configuration: %@.",
              error);
        return;
    }

    NSLog(@"Saved new temporary font configuration with %d font name mappings.",
          validFontNameMappingCount);

    [FFmpegKitConfig setFontconfigConfigurationPath:tempConfigurationDirectory];

    for (int i = 0; i < [fontDirectoryArray count]; i++) {
        NSString *fontDirectoryPath = [fontDirectoryArray objectAtIndex:i];
        NSLog(@"Font directory %@ registered successfully.", fontDirectoryPath);
    }
}

+ (NSString *)registerNewFFmpegPipe {
    NSError *error = nil;
    BOOL isDirectory;

    // PIPES ARE CREATED UNDER THE PIPES DIRECTORY
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(
        NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *pipesDir = [cacheDir stringByAppendingPathComponent:@"pipes"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:pipesDir
                                              isDirectory:&isDirectory]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:pipesDir
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&error]) {
            NSLog(@"Failed to create pipes directory: %@. Operation failed "
                  @"with %@.",
                  pipesDir, error);
            return nil;
        }
    }

    NSString *newFFmpegPipePath = [NSString
        stringWithFormat:@"%@/%@%ld", pipesDir, FFmpegKitNamedPipePrefix,
                         [pipeIndexGenerator getAndIncrement]];

    // FIRST CLOSE OLD PIPES WITH THE SAME NAME
    [FFmpegKitConfig closeFFmpegPipe:newFFmpegPipePath];

    int rc =
        mkfifo([newFFmpegPipePath UTF8String], S_IRWXU | S_IRWXG | S_IROTH);
    if (rc == 0) {
        return newFFmpegPipePath;
    } else {
        NSLog(@"Failed to register new FFmpeg pipe %@. Operation failed with "
              @"rc=%d.",
              newFFmpegPipePath, rc);
        return nil;
    }
}

+ (void)closeFFmpegPipe:(NSString *)ffmpegPipePath {
    NSFileManager *fileManager = [NSFileManager defaultManager];

    if ([fileManager fileExistsAtPath:ffmpegPipePath]) {
        [fileManager removeItemAtPath:ffmpegPipePath error:nil];
    }
}

+ (NSString *)getFFmpegVersion {
    return [NSString stringWithUTF8String:FFMPEG_VERSION];
}

+ (NSString *)getVersion {
    return FFmpegKitVersion;
}

+ (int)isLTSBuild {
    return 0;
}

+ (NSString *)getBuildDate {
    char buildDate[10];
    sprintf(buildDate, "%d", FFMPEG_KIT_BUILD_DATE);
    return [NSString stringWithUTF8String:buildDate];
}

+ (int)setEnvironmentVariable:(NSString *)variableName
                        value:(NSString *)variableValue {
    return setenv([variableName UTF8String], [variableValue UTF8String], true);
}

+ (void)ignoreSignal:(Signal)signal {
    if (signal == SignalQuit) {
        handleSIGQUIT = 0;
    } else if (signal == SignalInt) {
        handleSIGINT = 0;
    } else if (signal == SignalTerm) {
        handleSIGTERM = 0;
    } else if (signal == SignalXcpu) {
        handleSIGXCPU = 0;
    } else if (signal == SignalPipe) {
        handleSIGPIPE = 0;
    }
}

+ (void)ffmpegExecute:(FFmpegSession *)ffmpegSession {
    [ffmpegSession startRunning];

    @try {
        int returnCode = executeFFmpeg([ffmpegSession getSessionId],
                                       [ffmpegSession getArguments]);
        [ffmpegSession complete:[[ReturnCode alloc] init:returnCode]];
    } @catch (NSException *exception) {
        [ffmpegSession fail:exception];
        NSLog(@"FFmpeg execute failed: %@.%@",
              [FFmpegKitConfig argumentsToString:[ffmpegSession getArguments]],
              [NSString stringWithFormat:@"%@", [exception callStackSymbols]]);
    }
}

+ (void)ffprobeExecute:(FFprobeSession *)ffprobeSession {
    [ffprobeSession startRunning];

    @try {
        int returnCode = executeFFprobe([ffprobeSession getSessionId],
                                        [ffprobeSession getArguments]);
        [ffprobeSession complete:[[ReturnCode alloc] init:returnCode]];
    } @catch (NSException *exception) {
        [ffprobeSession fail:exception];
        NSLog(@"FFprobe execute failed: %@.%@",
              [FFmpegKitConfig argumentsToString:[ffprobeSession getArguments]],
              [NSString stringWithFormat:@"%@", [exception callStackSymbols]]);
    }
}

+ (void)getMediaInformationExecute:
            (MediaInformationSession *)mediaInformationSession
                       withTimeout:(int)waitTimeout {
    [mediaInformationSession startRunning];

    @try {
        AVBPrint mediaInformationBuffer;
        av_bprint_init(&mediaInformationBuffer, 0, AV_BPRINT_SIZE_UNLIMITED);
        @try {
            int returnCodeValue = executeFFprobeToBuffer(
                [mediaInformationSession getSessionId],
                [mediaInformationSession getArguments], &mediaInformationBuffer);
            ReturnCode *returnCode = [[ReturnCode alloc] init:returnCodeValue];
            [mediaInformationSession complete:returnCode];

            // NOTE: waitTimeout is retained for API compatibility but is no
            // longer used here. ffprobe writes the JSON synchronously into the
            // buffer below, so it is already complete and does not depend on
            // async log delivery. Callers that read the session logs afterwards
            // still get the wait, because getAllLogs applies the timeout itself.
            if ([returnCode isValueSuccess]) {
                NSString *ffprobeJsonOutput =
                    [NSString stringWithCString:mediaInformationBuffer.str
                                       encoding:NSUTF8StringEncoding];
                MediaInformation *mediaInformation = [MediaInformationJsonParser
                    fromWithError:ffprobeJsonOutput];
                [mediaInformationSession setMediaInformation:mediaInformation];
            }
        } @finally {
            av_bprint_finalize(&mediaInformationBuffer, NULL);
        }
    } @catch (NSException *exception) {
        [mediaInformationSession fail:exception];
        NSLog(@"Get media information execute failed: %@.%@",
              [FFmpegKitConfig
                  argumentsToString:[mediaInformationSession getArguments]],
              [NSString stringWithFormat:@"\n%@\n%@", [exception userInfo],
                                         [exception callStackSymbols]]);
    }
}

+ (void)asyncFFmpegExecute:(FFmpegSession *)ffmpegSession {
    [FFmpegKitConfig asyncFFmpegExecute:ffmpegSession
                        onDispatchQueue:asyncDispatchQueue];
}

+ (void)asyncFFmpegExecute:(FFmpegSession *)ffmpegSession
           onDispatchQueue:(dispatch_queue_t)queue {
    dispatch_async(queue, ^{
      [FFmpegKitConfig ffmpegExecute:ffmpegSession];

      FFmpegSessionCompleteCallback completeCallback =
          [ffmpegSession getCompleteCallback];
      if (completeCallback != nil) {
          @try {
              // NOTIFY SESSION CALLBACK DEFINED
              completeCallback(ffmpegSession);
          } @catch (NSException *exception) {
              NSLog(@"Exception thrown inside session complete callback. %@",
                    [exception callStackSymbols]);
          }
      }

      FFmpegSessionCompleteCallback globalFFmpegSessionCompleteCallback =
          [FFmpegKitConfig getFFmpegSessionCompleteCallback];
      if (globalFFmpegSessionCompleteCallback != nil) {
          @try {
              // NOTIFY SESSION CALLBACK DEFINED
              globalFFmpegSessionCompleteCallback(ffmpegSession);
          } @catch (NSException *exception) {
              NSLog(@"Exception thrown inside global complete callback. %@",
                    [exception callStackSymbols]);
          }
      }
    });
}

+ (void)asyncFFprobeExecute:(FFprobeSession *)ffprobeSession {
    [FFmpegKitConfig asyncFFprobeExecute:ffprobeSession
                         onDispatchQueue:asyncDispatchQueue];
}

+ (void)asyncFFprobeExecute:(FFprobeSession *)ffprobeSession
            onDispatchQueue:(dispatch_queue_t)queue {
    dispatch_async(queue, ^{
      [FFmpegKitConfig ffprobeExecute:ffprobeSession];

      FFprobeSessionCompleteCallback completeCallback =
          [ffprobeSession getCompleteCallback];
      if (completeCallback != nil) {
          @try {
              // NOTIFY SESSION CALLBACK DEFINED
              completeCallback(ffprobeSession);
          } @catch (NSException *exception) {
              NSLog(@"Exception thrown inside session complete callback. %@",
                    [exception callStackSymbols]);
          }
      }

      FFprobeSessionCompleteCallback globalFFprobeSessionCompleteCallback =
          [FFmpegKitConfig getFFprobeSessionCompleteCallback];
      if (globalFFprobeSessionCompleteCallback != nil) {
          @try {
              // NOTIFY SESSION CALLBACK DEFINED
              globalFFprobeSessionCompleteCallback(ffprobeSession);
          } @catch (NSException *exception) {
              NSLog(@"Exception thrown inside global complete callback. %@",
                    [exception callStackSymbols]);
          }
      }
    });
}

+ (void)asyncGetMediaInformationExecute:
            (MediaInformationSession *)mediaInformationSession
                            withTimeout:(int)waitTimeout {
    [FFmpegKitConfig asyncGetMediaInformationExecute:mediaInformationSession
                                     onDispatchQueue:asyncDispatchQueue
                                         withTimeout:waitTimeout];
}

+ (void)asyncGetMediaInformationExecute:
            (MediaInformationSession *)mediaInformationSession
                        onDispatchQueue:(dispatch_queue_t)queue
                            withTimeout:(int)waitTimeout {
    dispatch_async(queue, ^{
      [FFmpegKitConfig getMediaInformationExecute:mediaInformationSession
                                      withTimeout:waitTimeout];

      MediaInformationSessionCompleteCallback completeCallback =
          [mediaInformationSession getCompleteCallback];
      if (completeCallback != nil) {
          @try {
              // NOTIFY SESSION CALLBACK DEFINED
              completeCallback(mediaInformationSession);
          } @catch (NSException *exception) {
              NSLog(@"Exception thrown inside session complete callback. %@",
                    [exception callStackSymbols]);
          }
      }

      MediaInformationSessionCompleteCallback
          globalMediaInformationSessionCompleteCallback =
              [FFmpegKitConfig getMediaInformationSessionCompleteCallback];
      if (globalMediaInformationSessionCompleteCallback != nil) {
          @try {
              // NOTIFY SESSION CALLBACK DEFINED
              globalMediaInformationSessionCompleteCallback(
                  mediaInformationSession);
          } @catch (NSException *exception) {
              NSLog(@"Exception thrown inside global complete callback. %@",
                    [exception callStackSymbols]);
          }
      }
    });
}

+ (void)enableLogCallback:(LogCallback)callback {
    logCallback = callback;
}

+ (void)enableStatisticsCallback:(StatisticsCallback)callback {
    statisticsCallback = callback;
}

+ (void)enableFFmpegSessionCompleteCallback:
    (FFmpegSessionCompleteCallback)completeCallback {
    ffmpegSessionCompleteCallback = completeCallback;
}

+ (FFmpegSessionCompleteCallback)getFFmpegSessionCompleteCallback {
    return ffmpegSessionCompleteCallback;
}

+ (void)enableFFprobeSessionCompleteCallback:
    (FFprobeSessionCompleteCallback)completeCallback {
    ffprobeSessionCompleteCallback = completeCallback;
}

+ (FFprobeSessionCompleteCallback)getFFprobeSessionCompleteCallback {
    return ffprobeSessionCompleteCallback;
}

+ (void)enableMediaInformationSessionCompleteCallback:
    (MediaInformationSessionCompleteCallback)completeCallback {
    mediaInformationSessionCompleteCallback = completeCallback;
}

+ (MediaInformationSessionCompleteCallback)
    getMediaInformationSessionCompleteCallback {
    return mediaInformationSessionCompleteCallback;
}

+ (int)getLogLevel {
    return configuredLogLevel;
}

+ (void)setLogLevel:(int)level {
    configuredLogLevel = level;
}

+ (NSString *)logLevelToString:(int)level {
    switch (level) {
    case LevelAVLogStdErr:
        return @"STDERR";
    case LevelAVLogTrace:
        return @"TRACE";
    case LevelAVLogDebug:
        return @"DEBUG";
    case LevelAVLogVerbose:
        return @"VERBOSE";
    case LevelAVLogInfo:
        return @"INFO";
    case LevelAVLogWarning:
        return @"WARNING";
    case LevelAVLogError:
        return @"ERROR";
    case LevelAVLogFatal:
        return @"FATAL";
    case LevelAVLogPanic:
        return @"PANIC";
    case LevelAVLogQuiet:
        return @"QUIET";
    default:
        return @"";
    }
}

+ (int)getSessionHistorySize {
    return sessionHistorySize;
}

+ (void)setSessionHistorySize:(int)pSessionHistorySize {
    if (pSessionHistorySize >= SESSION_MAP_SIZE) {

        /*
         * THERE IS A HARD LIMIT ON THE NATIVE SIDE. HISTORY SIZE MUST BE
         * SMALLER THAN SESSION_MAP_SIZE
         */
        @throw([NSException exceptionWithName:NSInvalidArgumentException
                                       reason:@"Session history size must not "
                                              @"exceed the hard limit!"
                                     userInfo:nil]);
    } else if (pSessionHistorySize > 0) {
        NSArray *deletedSessionIds;

        [sessionHistoryLock lock];
        sessionHistorySize = pSessionHistorySize;
        deletedSessionIds = deleteExpiredSessionsLocked();
        [sessionHistoryLock unlock];

        notifySessionsDeleted(deletedSessionIds);
    }
}

+ (id<Session>)getSession:(long)sessionId {
    [sessionHistoryLock lock];

    id<Session> session =
        [sessionHistoryMap objectForKey:[NSNumber numberWithLong:sessionId]];

    [sessionHistoryLock unlock];

    return session;
}

+ (void)deleteSession:(long)sessionId {
    NSNumber *deletedSessionId = nil;

    [sessionHistoryLock lock];

    id<Session> session = [sessionHistoryMap objectForKey:[NSNumber numberWithLong:sessionId]];
    if (session != nil) {
        [sessionHistoryMap removeObjectForKey:[NSNumber numberWithLong:sessionId]];
        [sessionHistoryList removeObject:session];
        deletedSessionId = [NSNumber numberWithLong:[session getSessionId]];
    }

    [sessionHistoryLock unlock];

    if (deletedSessionId != nil) {
        notifySessionDeleted([deletedSessionId longValue]);
    }
}

+ (void)addSessionDeleteListener:(id<SessionDeleteListener>)listener {
    if (listener == nil) {
        return;
    }

    [sessionDeleteListenerLock lock];
    [sessionDeleteListeners addObject:listener];
    [sessionDeleteListenerLock unlock];
}

+ (void)removeSessionDeleteListener:(id<SessionDeleteListener>)listener {
    if (listener == nil) {
        return;
    }

    [sessionDeleteListenerLock lock];
    [sessionDeleteListeners removeObject:listener];
    [sessionDeleteListenerLock unlock];
}

+ (id<Session>)getLastSession {
    [sessionHistoryLock lock];

    id<Session> lastSession = [sessionHistoryList lastObject];

    [sessionHistoryLock unlock];

    return lastSession;
}

+ (id<Session>)getLastCompletedSession {
    id<Session> lastCompletedSession = nil;

    [sessionHistoryLock lock];

    for (int i = [sessionHistoryList count] - 1; i >= 0; i--) {
        id<Session> session = [sessionHistoryList objectAtIndex:i];
        if ([session getState] == SessionStateCompleted) {
            lastCompletedSession = session;
            break;
        }
    }

    [sessionHistoryLock unlock];

    return lastCompletedSession;
}

+ (NSArray *)getSessions {
    [sessionHistoryLock lock];

    NSArray *sessionsCopy = [sessionHistoryList copy];

    [sessionHistoryLock unlock];

    return sessionsCopy;
}

+ (void)clearSessions {
    NSMutableArray *deletedSessionIds = [[NSMutableArray alloc] init];

    [sessionHistoryLock lock];

    for (int i = 0; i < [sessionHistoryList count]; i++) {
        id<Session> session = [sessionHistoryList objectAtIndex:i];
        [deletedSessionIds addObject:[NSNumber numberWithLong:[session getSessionId]]];
    }

    [sessionHistoryList removeAllObjects];
    [sessionHistoryMap removeAllObjects];

    [sessionHistoryLock unlock];

    notifySessionsDeleted(deletedSessionIds);
}

+ (NSArray *)getFFmpegSessions {
    NSMutableArray *ffmpegSessions = [[NSMutableArray alloc] init];

    [sessionHistoryLock lock];

    for (int i = 0; i < [sessionHistoryList count]; i++) {
        id<Session> session = [sessionHistoryList objectAtIndex:i];
        if ([session isFFmpeg]) {
            [ffmpegSessions addObject:session];
        }
    }

    [sessionHistoryLock unlock];

    return ffmpegSessions;
}

+ (NSArray *)getFFprobeSessions {
    NSMutableArray *ffprobeSessions = [[NSMutableArray alloc] init];

    [sessionHistoryLock lock];

    for (int i = 0; i < [sessionHistoryList count]; i++) {
        id<Session> session = [sessionHistoryList objectAtIndex:i];
        if ([session isFFprobe]) {
            [ffprobeSessions addObject:session];
        }
    }

    [sessionHistoryLock unlock];

    return ffprobeSessions;
}

+ (NSArray *)getMediaInformationSessions {
    NSMutableArray *mediaInformationSessions = [[NSMutableArray alloc] init];

    [sessionHistoryLock lock];

    for (int i = 0; i < [sessionHistoryList count]; i++) {
        id<Session> session = [sessionHistoryList objectAtIndex:i];
        if ([session isMediaInformation]) {
            [mediaInformationSessions addObject:session];
        }
    }

    [sessionHistoryLock unlock];

    return mediaInformationSessions;
}

+ (NSArray *)getSessionsByState:(SessionState)state {
    NSMutableArray *sessions = [[NSMutableArray alloc] init];

    [sessionHistoryLock lock];

    for (int i = 0; i < [sessionHistoryList count]; i++) {
        id<Session> session = [sessionHistoryList objectAtIndex:i];
        if ([session getState] == state) {
            [sessions addObject:session];
        }
    }

    [sessionHistoryLock unlock];

    return sessions;
}

+ (LogRedirectionStrategy)getLogRedirectionStrategy {
    return globalLogRedirectionStrategy;
}

+ (void)setLogRedirectionStrategy:
    (LogRedirectionStrategy)logRedirectionStrategy {
    globalLogRedirectionStrategy = logRedirectionStrategy;
}

+ (int)messagesInTransmit:(long)sessionId {
    return atomic_load(
        &sessionInTransitMessageCountMap[sessionId % SESSION_MAP_SIZE]);
}

+ (NSString *)sessionStateToString:(SessionState)state {
    switch (state) {
    case SessionStateCreated:
        return @"CREATED";
    case SessionStateRunning:
        return @"RUNNING";
    case SessionStateFailed:
        return @"FAILED";
    case SessionStateCompleted:
        return @"COMPLETED";
    default:
        return @"";
    }
}

+ (NSArray *)parseArguments:(NSString *)command {
    NSMutableArray *argumentArray = [[NSMutableArray alloc] init];
    NSMutableString *currentArgument = [[NSMutableString alloc] init];

    bool singleQuoteStarted = false;
    bool doubleQuoteStarted = false;

    for (int i = 0; i < command.length; i++) {
        unichar previousChar;
        if (i > 0) {
            previousChar = [command characterAtIndex:(i - 1)];
        } else {
            previousChar = 0;
        }
        unichar currentChar = [command characterAtIndex:i];

        if (currentChar == ' ') {
            if (singleQuoteStarted || doubleQuoteStarted) {
                [currentArgument appendFormat:@"%C", currentChar];
            } else if ([currentArgument length] > 0) {
                [argumentArray addObject:currentArgument];
                currentArgument = [[NSMutableString alloc] init];
            }
        } else if (currentChar == '\'' &&
                   (previousChar == 0 || previousChar != '\\')) {
            if (singleQuoteStarted) {
                singleQuoteStarted = false;
            } else if (doubleQuoteStarted) {
                [currentArgument appendFormat:@"%C", currentChar];
            } else {
                singleQuoteStarted = true;
            }
        } else if (currentChar == '\"' &&
                   (previousChar == 0 || previousChar != '\\')) {
            if (doubleQuoteStarted) {
                doubleQuoteStarted = false;
            } else if (singleQuoteStarted) {
                [currentArgument appendFormat:@"%C", currentChar];
            } else {
                doubleQuoteStarted = true;
            }
        } else {
            [currentArgument appendFormat:@"%C", currentChar];
        }
    }

    if ([currentArgument length] > 0) {
        [argumentArray addObject:currentArgument];
    }

    return argumentArray;
}

+ (NSString *)argumentsToString:(NSArray *)arguments {
    if (arguments == nil) {
        return @"nil";
    }

    NSMutableString *string = [NSMutableString stringWithString:@""];
    for (int i = 0; i < [arguments count]; i++) {
        NSString *argument = [arguments objectAtIndex:i];
        if (i > 0) {
            [string appendString:@" "];
        }
        [string appendString:argument];
    }

    return string;
}

@end
