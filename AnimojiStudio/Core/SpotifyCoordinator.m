//
//  SpotifyCoordinator.m
//  AnimojiStudio
//
//  Created by Guilherme Rambo on 15/11/17.
//  Copyright © 2017 Guilherme Rambo. All rights reserved.
//

#import "SpotifyCoordinator.h"

#import <SpotifyAuthentication/SpotifyAuthentication.h>
#import <SpotifyAudioPlayback/SpotifyAudioPlayback.h>
#import <SpotifyMetadata/SpotifyMetadata.h>

@import SafariServices;
@import AVFoundation;

@interface SpotifyCoordinator () <SPTAudioStreamingDelegate>

@property (nonatomic, strong) SPTAuth *auth;
@property (nonatomic, strong) SPTAudioStreamingController *player;
@property (nonatomic, strong) SPTCoreAudioController *coreAudioController;

@property (nonatomic, strong) SFSafariViewController *safariController;

@property (nonatomic, assign) BOOL playerStarted;

@property (nonatomic, strong) AVPlayer *previewPlayer;
@property (nonatomic, strong) id<NSObject> previewObserver;

@end

@implementation SpotifyCoordinator

- (instancetype)init
{
    self = [super init];
    
    self.player = [SPTAudioStreamingController sharedInstance];
    self.player.delegate = self;
    
    self.coreAudioController = [SPTCoreAudioController new];
    
    self.auth = [SPTAuth defaultInstance];
    self.auth.clientID = @"7cc18ebcb302432b86abe6d2f3f65578";
    self.auth.redirectURL = [NSURL URLWithString:@"animojistudio://spotify"];
    self.auth.sessionUserDefaultsKey = @"SpotifySession";
    self.auth.requestedScopes = @[SPTAuthStreamingScope, SPTAuthUserReadPrivateScope];
    
    return self;
}

- (void)startAuthFlowFromViewController:(UIViewController *)presenter withError:(NSError **)outError
{
    if (!self.playerStarted) {
        if (![self.player startWithClientId:self.auth.clientID audioController:self.coreAudioController allowCaching:YES error:outError]) {
            return;
        }
        self.playerStarted = YES;
    }
    
    // not needed, already have a session
    if (self.auth.session.isValid) {
        [self.player loginWithAccessToken:self.auth.session.accessToken];
        return;
    }
    
    if ([SPTAuth supportsApplicationAuthentication]) {
        [[UIApplication sharedApplication] openURL:[self.auth spotifyAppAuthenticationURL] options:@{} completionHandler:^(BOOL success) {
            if (!success) {
                NSLog(@"Failed to open auth app");
            }
        }];
    } else {
        self.safariController = [[SFSafariViewController alloc] initWithURL:[self.auth spotifyWebAuthenticationURL]];
        [presenter presentViewController:self.safariController animated:YES completion:nil];
    }
}

- (BOOL)handleCallbackURL:(NSURL *)url
{
    if (![self.auth canHandleURL:url]) return NO;
    
    if (self.safariController.presentingViewController) {
        [self.safariController dismissViewControllerAnimated:YES completion:nil];
    }
    
    [self.auth handleAuthCallbackWithTriggeredAuthURL:url callback:^(NSError *error, SPTSession *session) {
        [self.player loginWithAccessToken:session.accessToken];
    }];
    
    return YES;
}

- (void)audioStreamingDidLogin:(SPTAudioStreamingController *)audioStreaming
{
    [self.delegate spotifyCoordinatorDidFinishLogin:self];
}

- (void)playTrackID:(NSString *)trackID
{
    [self.player playSpotifyURI:trackID startingWithIndex:0 startingWithPosition:0 callback:^(NSError *error) {
        if (error) {
            NSLog(@"Spotify playback error: %@", error);
        }
    }];
}

- (void)stop
{
    [self.player setIsPlaying:NO callback:^(NSError *error) {
        NSLog(@"setIsPlaying error: %@", error);
    }];
}

- (void)searchForTerm:(NSString *)term completion:(void(^)(NSError *error, id result))completionHandler
{
    [SPTSearch performSearchWithQuery:term queryType:SPTQueryTypeTrack accessToken:self.auth.session.accessToken callback:^(NSError *error, id object) {
        completionHandler(error, object);
    }];
}

- (void)playSongPreviewWithURL:(NSURL *)url
{
    self.previewPlayer = [AVPlayer playerWithURL:url];
    
    __weak typeof(self) weakSelf = self;
    self.previewObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:self.previewPlayer.currentItem queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        if (weakSelf.previewPlaybackDidFinish) weakSelf.previewPlaybackDidFinish();
    }];
    
    [self.previewPlayer play];
}

- (void)stopPreviewPlayback
{
    [[NSNotificationCenter defaultCenter] removeObserver:self.previewObserver];
    
    [self.previewPlayer pause];
    [self.previewPlayer cancelPendingPrerolls];
    self.previewPlayer = nil;
}

@end
