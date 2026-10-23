//
//  ServerInfoResponse.h
//  Moonlight
//
//  Created by Diego Waxemberg on 2/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "HttpResponse.h"
#import "TemporaryHost.h"

#define TAG_HOSTNAME @"hostname"
#define TAG_EXTERNAL_IP @"ExternalIP"
#define TAG_HTTPS_PORT @"HttpsPort"
#define TAG_LOCAL_IP @"LocalIP"
#define TAG_UNIQUE_ID @"uniqueid"
#define TAG_MAC_ADDRESS @"mac"
#define TAG_PAIR_STATUS @"PairStatus"
#define TAG_STATE @"state"
#define TAG_CURRENT_GAME @"currentgame"

// Sunshine extension
#define TAG_EXTERNAL_PORT @"ExternalPort"

@interface ServerInfoResponse : HttpResponse <Response>

/// The answer came over HTTPS from the PC whose certificate was pinned at pairing (HttpManager
/// sets it). A plain HTTP answer can't tell whether this client is paired: its PairStatus is
/// always 0, and Sunshine and Apollo hide the MAC address there.
@property (nonatomic) BOOL authenticated;

- (void) populateWithData:(NSData *)data;
- (void) populateHost:(TemporaryHost*)host;

@end

