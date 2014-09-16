#import "IonicUpdate.h"
#import <Cordova/CDV.h>
#import "UNIRest.h"
#import "SSZipArchive.h"

@interface IonicUpdate()

@property (nonatomic) NSURLConnection *connectionManager;
@property (nonatomic) NSMutableData *downloadedMutableData;
@property (nonatomic) NSURLResponse *urlResponse;

@property int progress;
@property NSString *callbackId;
@property NSString *appId;

@end

static NSOperationQueue *delegateQueue;

@implementation IonicUpdate

- (void) initialize:(CDVInvokedUrlCommand *)command {
    CDVPluginResult* pluginResult = nil;
    
    self.appId = [command.arguments objectAtIndex:0];
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) check:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* pluginResult = nil;
        
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        
        NSString *our_version = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
        
        NSString *endpoint = [NSString stringWithFormat:@"/api/v1/app/%@/updates/check", self.appId];
        
        NSDictionary *result = [self httpRequest:endpoint];
        
        if (result != nil && [result objectForKey:@"uuid"]) {
            NSString *uuid = [result objectForKey:@"uuid"];
            
            // Save the "deployed" UUID so we can fetch it later
            [prefs setObject: uuid forKey: @"upstream_uuid"];
            [prefs synchronize];
            
            NSString *updatesAvailable = ![uuid isEqualToString:our_version] ? @"true" : @"false";
            
            NSLog(@"UUID: %@ OUR_UUID: %@", uuid, our_version);
            NSLog(@"Updates Available: %@", updatesAvailable);
            
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:updatesAvailable];
        } else {
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR];
        }
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
    }];
}

- (void) download:(CDVInvokedUrlCommand *)command {
    //[self.commandDelegate runInBackground:^{
        // Save this to a property so we can have the download progress delegate thing send
        // progress update callbacks
        self.callbackId = command.callbackId;
    
        NSString *endpoint = [NSString stringWithFormat:@"/api/v1/app/%@/updates/download", self.appId];
    
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        
        NSString *upstream_uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"upstream_uuid"];
        
        NSLog(@"Upstream UUID: %@", upstream_uuid);
        
        if (upstream_uuid != nil && [self hasVersion:upstream_uuid]) {
            // Set the current version to the upstream version (we already have this version)
            [prefs setObject:upstream_uuid forKey:@"uuid"];
            [prefs synchronize];
            
            [self doRedirect];
        } else {
            NSDictionary *result = [self httpRequest:endpoint];
            
            NSString *download_url = [result objectForKey:@"download_url"];
            
            //[self downloadUpdate:download_url];
            
            self.downloadedMutableData = [[NSMutableData alloc] init];
            
            NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:download_url]
                                                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                    timeoutInterval:60.0];
            
            //self.connectionManager = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self startImmediately:NO];
            //[self.connectionManager setDelegateQueue:delegateQueue];
            //[self.commandDelegate runInBackground:^{
                //[self.connectionManager start];
            //}];
        }
    //}];
}

- (void) extract:(CDVInvokedUrlCommand *)command {
    [self.commandDelegate runInBackground:^{
        self.callbackId = command.callbackId;
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        
        NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
        
        NSString *filePath = [NSString stringWithFormat:@"%@/%@", documentsDirectory, @"www.zip"];
        NSString *extractPath = [NSString stringWithFormat:@"%@/%@/", documentsDirectory, uuid];
        
        NSLog(@"Path for zip file: %@", filePath);
        
        NSLog(@"Unzipping...");
        
        [SSZipArchive unzipFileAtPath:filePath toDestination:extractPath delegate:self];
        
        NSLog(@"Unzipped...");
    }];
}

- (void) redirect:(CDVInvokedUrlCommand *)command {
    CDVPluginResult* pluginResult = nil;
    
    [self doRedirect];
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void) doRedirect {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
    
    NSString *indexPath = [NSString stringWithFormat:@"%@/%@/index.html", documentsDirectory, uuid];
    
    NSURL *urlOverwrite = [NSURL fileURLWithPath:indexPath];
    NSURLRequest *request = [NSURLRequest requestWithURL:urlOverwrite];
    
    NSLog(@"Redirecting to: %@", indexPath);
    [self.webView loadRequest:request];
}

- (NSDictionary *) httpRequest:(NSString *) endpoint {
    NSString *baseUrl = @"http://ionic-dash-local.ngrok.com";
    NSString *url = [NSString stringWithFormat:@"%@%@", baseUrl, endpoint];
    
    NSDictionary* headers = @{@"accept": @"application/json"};
    
    UNIHTTPJsonResponse *result = [[UNIRest get:^(UNISimpleRequest *request) {
        [request setUrl: url];
        [request setHeaders:headers];
    }] asJson];
    
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:result.rawBody options:kNilOptions error:nil];
    
    return json;
}

- (NSMutableArray *) getMyVersions {
    NSMutableArray *versions;
    NSArray *versionsLoaded = [[NSUserDefaults standardUserDefaults] arrayForKey:@"my_versions"];
    if (versionsLoaded != nil) {
        versions = [versionsLoaded mutableCopy];
    } else {
        versions = [[NSMutableArray alloc] initWithCapacity:5];
    }
    
    return versions;
}

- (bool) hasVersion:(NSString *) uuid {
    NSArray *versions = [self getMyVersions];
    
    NSLog(@"Versions: %@", versions);
    
    for (id version in versions) {
        NSArray *version_parts = [version componentsSeparatedByString:@"|"];
        NSString *version_uuid = version_parts[1];
        
        NSLog(@"version_uuid: %@, uuid: %@", version_uuid, uuid);
        if ([version_uuid isEqualToString:uuid]) {
            return true;
        }
    }
    
    return false;
}

- (void) saveVersion:(NSString *) uuid {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSMutableArray *versions = [self getMyVersions];
    
    int versionCount = [[NSUserDefaults standardUserDefaults] integerForKey:@"version_count"];
    
    if (versionCount) {
        versionCount += 1;
    } else {
        versionCount = 1;
    }
    
    [prefs setInteger:versionCount forKey:@"version_count"];
    [prefs synchronize];
    
    NSString *versionString = [NSString stringWithFormat:@"%i|%@", versionCount, uuid];
    
    [versions addObject:versionString];
    
    [prefs setObject:versions forKey:@"my_versions"];
    [prefs synchronize];
    
    [self cleanupVersions];
}

- (void) cleanupVersions {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSMutableArray *versions = [self getMyVersions];
    
    int versionCount = [[NSUserDefaults standardUserDefaults] integerForKey:@"version_count"];
    
    if (versionCount && versionCount > 3) {
        NSInteger threshold = versionCount - 3;
        
        NSInteger count = [versions count];
        for (NSInteger index = (count - 1); index >= 0; index--) {
            NSString *versionString = versions[index];
            NSArray *version_parts = [versionString componentsSeparatedByString:@"|"];
            NSInteger version_number = [version_parts[0] intValue];
            if (version_number < threshold) {
                [versions removeObjectAtIndex:index];
                [self removeVersion:version_parts[1]];
            }
        }
        
        NSLog(@"Version Count: %i", [versions count]);
        [prefs setObject:versions forKey:@"my_versions"];
        [prefs synchronize];
    }
}

- (void) removeVersion:(NSString *) uuid {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    
    NSString *pathToFolder = [NSString stringWithFormat:@"%@/%@/", documentsDirectory, uuid];
    
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:pathToFolder error:nil];
    
    NSLog(@"Removed Version %@ success? %d", uuid, success);
}

- (void) downloadUpdate:(NSString *) download_url {
    self.downloadedMutableData = [[NSMutableData alloc] init];
    
    NSURLRequest *urlRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:download_url]
                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                timeoutInterval:60.0];
    
    self.connectionManager = [[NSURLConnection alloc] initWithRequest:urlRequest delegate:self];
    
}

/* Delegate Methods for the NSURL thing */

-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    NSLog(@"%lld", response.expectedContentLength);
    self.urlResponse = response;
}

-(void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.downloadedMutableData appendData:data];
    self.progress = ((100.0 / self.urlResponse.expectedContentLength) * self.downloadedMutableData.length) / 100;
    
    NSLog(@"%.0f%%", ((100.0 / self.urlResponse.expectedContentLength) * self.downloadedMutableData.length));
    
    CDVPluginResult* pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:self.progress];
    [pluginResult setKeepCallbackAsBool:TRUE];
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection {
    NSLog(@"Finished");
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *filePath = [NSString stringWithFormat:@"%@/%@", documentsDirectory,@"www.zip"];

    [self.downloadedMutableData writeToFile:filePath atomically:YES];
    
    // Save the upstream_uuid (what we just downloaded) to the uuid preference
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    NSString *uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"uuid"];
    NSString *upstream_uuid = [[NSUserDefaults standardUserDefaults] objectForKey:@"upstream_uuid"];
    
    [prefs setObject: upstream_uuid forKey: @"uuid"];
    [prefs synchronize];
    
    NSLog(@"UUID is: %@ and upstream_uuid is: %@", uuid, upstream_uuid);
    
    [self saveVersion:upstream_uuid];
    
    CDVPluginResult* pluginResult = nil;
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"true"];
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

/* Delegate Methods for SSZipArchive */

- (void)zipArchiveProgressEvent:(NSInteger)loaded total:(NSInteger)total {
    float progress = ((100.0 / total) * loaded);
    NSLog(@"Zip Extraction: %.0f%%", progress);
    
    CDVPluginResult* pluginResult = nil;
    
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsInt:progress];
    [pluginResult setKeepCallbackAsBool:TRUE];
    
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    
    if (progress == 100) {
        CDVPluginResult* pluginResult = nil;
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"done"];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
    }
}

@end