// Pont vers le framework privé MediaRemote (« À l'écoute » de macOS).
// Depuis macOS 15.4, mediaremoted refuse les apps tierces ; /usr/bin/perl, binaire
// Apple, y a toujours droit. Ce dylib est donc chargé dans perl (voir mediaremote.pl) :
//  - stdout : une ligne JSON par changement d'état ;
//  - stdin  : « cmd <n> » (lecteur actuel), « app <n> <bundle id> » (app précise),
//             « seek <secondes> », « refresh » ; EOF => fin du processus.
#import <Foundation/Foundation.h>
#include <dlfcn.h>

typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*GetBoolFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*GetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef NSString *(*ClientStringFn)(id);
typedef Boolean (*SendCommandFn)(int, NSDictionary *);
typedef void (*SetElapsedFn)(double);
typedef void (*GetClientsFn)(dispatch_queue_t, void (^)(NSArray *));
typedef void *(*GetOriginFn)(void);
typedef void (*SendToAppFn)(int, NSDictionary *, void *, NSString *, int, dispatch_queue_t, void (^)(int, NSArray *));

static GetInfoFn getInfo;
static GetBoolFn getIsPlaying;
static GetClientFn getClient;
static GetPIDFn getPID;
static ClientStringFn clientBundleID, clientParentBundleID;
static SendCommandFn sendCommand;
static SetElapsedFn setElapsed;
static GetClientsFn getClients;
static GetOriginFn getLocalOrigin;
static SendToAppFn sendToApp;

static NSUInteger lastArtworkHash;
static BOOL refreshPending;

static void emit(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json) return;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static id value(NSDictionary *info, NSString *suffix) {
    return info[[@"kMRMediaRemoteNowPlayingInfo" stringByAppendingString:suffix]];
}

static void refresh(void) {
    dispatch_queue_t q = dispatch_get_main_queue();
    getInfo(q, ^(NSDictionary *info) {
        getIsPlaying(q, ^(Boolean playing) {
            getPID(q, ^(int pid) {
                void (^finish)(id) = ^(id client) {
                    NSMutableDictionary *out = [NSMutableDictionary dictionary];
                    out[@"playing"] = @(playing);
                    out[@"pid"] = @(pid);
                    NSString *title = value(info, @"Title");
                    out[@"title"] = title ?: @"";
                    out[@"artist"] = value(info, @"Artist") ?: @"";
                    out[@"album"] = value(info, @"Album") ?: @"";
                    out[@"duration"] = value(info, @"Duration") ?: @0;
                    out[@"elapsed"] = value(info, @"ElapsedTime") ?: @0;
                    out[@"rate"] = value(info, @"PlaybackRate") ?: @(playing ? 1 : 0);
                    NSDate *ts = value(info, @"Timestamp");
                    out[@"timestamp"] = @((ts ?: [NSDate date]).timeIntervalSince1970);
                    if (client && clientBundleID) {
                        NSString *parent = clientParentBundleID ? clientParentBundleID(client) : nil;
                        NSString *bundle = clientBundleID(client);
                        if (parent.length) out[@"bundle"] = parent;
                        else if (bundle.length) out[@"bundle"] = bundle;
                    }
                    NSData *art = value(info, @"ArtworkData");
                    NSUInteger h = art ? (art.length ^ art.hash) : 0;
                    if (h != lastArtworkHash) {
                        lastArtworkHash = h;
                        out[@"artwork"] = art ? [art base64EncodedStringWithOptions:0] : @"";
                    }
                    if (!getClients) { emit(out); return; }
                    // Tous les lecteurs connus du système, pour pouvoir passer de l'un à l'autre.
                    getClients(q, ^(NSArray *clients) {
                        NSMutableArray *ids = [NSMutableArray array];
                        for (id c in clients) {
                            NSString *parent = clientParentBundleID ? clientParentBundleID(c) : nil;
                            NSString *bundle = parent.length ? parent : (clientBundleID ? clientBundleID(c) : nil);
                            if (bundle.length && ![ids containsObject:bundle]) [ids addObject:bundle];
                        }
                        out[@"clients"] = ids;
                        emit(out);
                    });
                };
                if (getClient) getClient(q, finish); else finish(nil);
            });
        });
    });
}

static void scheduleRefresh(void) {
    if (refreshPending) return;
    refreshPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        refreshPending = NO;
        refresh();
    });
}

static void handleLine(NSString *line) {
    NSArray *parts = [line componentsSeparatedByString:@" "];
    if (parts.count < 2) return;
    if ([parts[0] isEqualToString:@"cmd"]) {
        sendCommand([parts[1] intValue], nil);
    } else if ([parts[0] isEqualToString:@"app"] && parts.count >= 3 && sendToApp) {
        void *origin = getLocalOrigin ? getLocalOrigin() : NULL;
        sendToApp([parts[1] intValue], nil, origin, parts[2], 0, dispatch_get_main_queue(), ^(int err, NSArray *st) {
            scheduleRefresh();
        });
    } else if ([parts[0] isEqualToString:@"seek"] && setElapsed) {
        setElapsed([parts[1] doubleValue]);
        scheduleRefresh();
    } else if ([parts[0] isEqualToString:@"refresh"]) {
        scheduleRefresh();
    }
}

static BOOL loadSymbols(void) {
    void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (!mr) return NO;
    RegisterFn reg = dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    getInfo = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getClient = dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    getPID = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
    clientBundleID = dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParentBundleID = dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    sendCommand = dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = dlsym(mr, "MRMediaRemoteSetElapsedTime");
    getClients = dlsym(mr, "MRMediaRemoteGetNowPlayingClients");
    getLocalOrigin = dlsym(mr, "MRMediaRemoteGetLocalOrigin");
    sendToApp = dlsym(mr, "MRMediaRemoteSendCommandToApp");
    if (!reg || !getInfo || !getIsPlaying || !getPID || !sendCommand) return NO;
    reg(dispatch_get_main_queue());
    return YES;
}

// Appelée par perl comme une XSUB : (PerlInterpreter *, CV *), arguments ignorés.
void adapter_stream(void *interp, void *cv) {
    @autoreleasepool {
        if (!loadSymbols()) {
            emit(@{@"error": @"MediaRemote indisponible"});
            exit(1);
        }
        for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                                 @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange"]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                                                        usingBlock:^(NSNotification *n) { scheduleRefresh(); }];
        }

        // Lecture de stdin : commandes, et arrêt quand l'app parente disparaît.
        dispatch_source_t src = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, STDIN_FILENO, 0,
                                                       dispatch_get_main_queue());
        __block NSMutableString *buffer = [NSMutableString string];
        dispatch_source_set_event_handler(src, ^{
            char buf[1024];
            ssize_t n = read(STDIN_FILENO, buf, sizeof buf);
            if (n <= 0) exit(0);
            [buffer appendString:[[NSString alloc] initWithBytes:buf length:n encoding:NSUTF8StringEncoding] ?: @""];
            NSRange r;
            while ((r = [buffer rangeOfString:@"\n"]).location != NSNotFound) {
                NSString *line = [buffer substringToIndex:r.location];
                [buffer deleteCharactersInRange:NSMakeRange(0, r.location + 1)];
                handleLine(line);
            }
        });
        dispatch_resume(src);

        refresh();
        // Filet de sécurité : certaines apps ne notifient pas tous les changements.
        dispatch_source_t tick = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(tick, dispatch_time(DISPATCH_TIME_NOW, 0), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(tick, ^{ scheduleRefresh(); });
        dispatch_resume(tick);

        CFRunLoopRun();
    }
    exit(0);
}
